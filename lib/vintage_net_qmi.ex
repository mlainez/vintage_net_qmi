# SPDX-FileCopyrightText: 2021 Frank Hunleth
# SPDX-FileCopyrightText: 2021 Matt Ludwigs
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI do
  @moduledoc """
  Use a QMI-enabled cellular modem with VintageNet

  This module is not intended to be called directly but via calls to `VintageNet`. Here's an
  example:

  ```elixir
  VintageNet.configure(
    "wwan0",
    %{
      type: VintageNetQMI,
      vintage_net_qmi: %{
        service_providers: [
          %{apn: "favorite_apn", only_iccid_prefixes: ["1234"]},
          %{apn: "second_favorite_apn", only_iccid_prefixes: ["56789"]},
          %{apn: "last_resort_apn"}
        ],
        only_radio_technologies: [:lte]
      }
    }
  )
  ```

  The following keys are supported in the `:vintage_net_qmi` map:

  * `:service_providers` (required) - a list of service provider information
  * `:only_radio_technologies` (optional) - e.g., `[:lte]`
  * `:device_path` (optional) - path to the QMI device (cdc-wdm /
    `wwan*qmi*` chardev). Only used by the `:qmux` transport.
  * `:transport` (optional) - which QMI wire transport to use. Either
    `:qmux` for the cdc-wdm-style chardev path (USB modems, some
    in-kernel modems) or `:qrtr` for `AF_QIPCRTR` (in-kernel Qualcomm
    modems whose firmware publishes QMI services on the IPC Router —
    msm8953 / sdm632, e.g. Fairphone 3+). When omitted, the
    transport is auto-detected from `:device_path`: a cdc-wdm-style
    path picks `:qmux`; anything else picks `:qrtr`.
  * `:ip_method` (optional) - how to obtain the IP address. Defaults to `:dhcp`.
    Set to `:qmi_profile` to fetch IP settings directly from the modem's QMI
    wireless data service instead of running a DHCP client. This is needed for
    modems that don't support DHCP (e.g., Qualcomm MSM8974).
  * `:provision_uim` (optional) - when `true`, explicitly provisions a UIM
    session and sets the modem to online mode at startup. Required for modems
    that need manual SIM session provisioning (e.g., Qualcomm MSM8974).
    Defaults to `false`.
  * `:rmnet_child` (optional) - declare that the configured `ifname` is an
    `rmnet` upper-layer netdev that should be created over a QMAP-only base
    IPA netdev. Required on platforms whose data path is exposed only as a
    QMAP-protocol netdev (Citronics' `ipa2-lite` driver on msm8953/sdm632 —
    Fairphone 3+). Map keys:

      * `:parent` (required) - the underlying QMAP netdev (e.g.
        `"rmnet_ipa0"`).
      * `:mux_id` (required) - the QMAP mux id (1..255) used by both the
        kernel rmnet child and the WDS `bind_mux_data_port` call.

    When set, `VintageNetQMI.Application` creates the child netdev via
    netlink before VintageNet's interface state machine activates, and the
    WDS bring-up sequence binds the QMI client to the same mux id.

  The `:service_providers` key should be set to information provided by each of
  your service providers.

  Information for each service provider is a map with some or all of the following
  fields:

  * `:apn` (required) - e.g., `"access_point_name"`
  * `:only_iccid_prefixes` (optional) - only use this APN if the one of the strings
    in the list is a prefix of the ICCID. E.g, `["1234"]`
  * `:username` (optional) - authentication username, e.g., `"user@provider.com"`
  * `:password` (optional) - authentication password
  * `:auth_method` (optional) - authentication method: `:none`, `:pap`, `:chap`, `:pap_or_chap`
  * `:pdp_type` (optional) - PDP type: `:ipv4`, `:ipv6`, `:ipv4v6`, `:ppp`
  * `:roaming_allowed?` (optional) - whether roaming is allowed

  When multiple entries are specified, the first allowed service provider is used.

  Your service provider should provide you with the information that you need to
  connect. Often it is just an APN. The Gnome project provides a database of
  [service provider
  information](https://wiki.gnome.org/Projects/NetworkManager/MobileBroadband/ServiceProviders)
  that may also be useful.
  """

  @behaviour VintageNet.Technology

  alias VintageNet.Interface.RawConfig
  alias VintageNet.IP.IPv4Config
  alias VintageNetQMI.Cookbook

  @doc """
  Name of the the QMI server that VintageNetQMI uses
  """
  @spec qmi_name(VintageNet.ifname()) :: atom()
  def qmi_name(ifname), do: Module.concat(__MODULE__.QMI, ifname)

  @impl VintageNet.Technology
  def normalize(%{type: __MODULE__, vintage_net_qmi: _qmi} = config) do
    require_a_service_provider(config)
  end

  def normalize(_config) do
    raise ArgumentError,
          "specify vintage_net_qmi options (e.g., %{vintage_net_qmi: %{service_providers: [%{apn: \"super\"}]}})"
  end

  defp require_a_service_provider(
         %{type: __MODULE__, vintage_net_qmi: qmi} = config,
         required_fields \\ [:apn]
       ) do
    case Map.get(qmi, :service_providers, []) do
      [] ->
        service_provider =
          for field <- required_fields, into: %{} do
            {field, to_string(field)}
          end

        new_qmi = Map.put(qmi, :service_providers, [service_provider])

        new_config = %{config | vintage_net_qmi: new_qmi}

        raise ArgumentError,
              """
              At least one service provider is required for #{__MODULE__}.

              For example:

              #{inspect(new_config)}
              """

      [service_provider | _rest] ->
        missing =
          Enum.find(required_fields, fn field -> not Map.has_key?(service_provider, field) end)

        if missing do
          raise ArgumentError,
                """
                The service provider '#{inspect(service_provider)}' is missing the `inspect(missing)' field.
                """
        end

        config
    end
  end

  @impl VintageNet.Technology
  def to_raw_config(
        ifname,
        %{type: __MODULE__} = config,
        _opts
      ) do
    normalized_config = normalize(config)
    qmi_opts = normalized_config.vintage_net_qmi
    radio_technologies_preference = qmi_opts[:only_radio_technologies]
    device_path = qmi_opts[:device_path]
    transport = resolve_transport(qmi_opts[:transport], device_path)
    ip_method = qmi_opts[:ip_method] || :dhcp
    provision_uim? = qmi_opts[:provision_uim] || false

    # QMI.configure_linux/1 only matters for cdc-wdm/wwan-chardev
    # backed modems (it sets `qmi/raw_ip` in sysfs). In-kernel modems
    # reached via QRTR don't expose a netdev at the same path and the
    # call is a no-op there anyway, but skip it explicitly to keep the
    # ifup output clean.
    up_cmds =
      if transport == :qrtr,
        do: [],
        else: [{:fun, QMI, :configure_linux, [ifname]}]

    qmi_supervisor_opts =
      [
        ifname: ifname,
        device_path: device_path,
        name: qmi_name(ifname),
        indication_callback: indication_callback(ifname),
        transport: transport
      ]

    child_specs =
      [
        {VintageNetQMI.Indications, ifname: ifname},
        {QMI.Supervisor, qmi_supervisor_opts},
        if(provision_uim?, do: {VintageNetQMI.SessionProvisioning, ifname: ifname}),
        {VintageNetQMI.Connectivity, ifname: ifname},
        {VintageNetQMI.Connection,
         [
           ifname: ifname,
           service_providers: qmi_opts.service_providers,
           radio_technologies: radio_technologies_preference,
           transport: transport,
           rmnet_child: qmi_opts[:rmnet_child]
         ]},
        if(ip_method == :qmi_profile, do: {VintageNetQMI.IPManager, ifname: ifname}),
        {VintageNetQMI.CellMonitor, [ifname: ifname]},
        {VintageNetQMI.SignalMonitor, [ifname: ifname]},
        {VintageNetQMI.ModemInfo, ifname: ifname}
      ]
      |> Enum.reject(&is_nil/1)

    raw =
      %RawConfig{
        ifname: ifname,
        type: __MODULE__,
        source_config: config,
        required_ifnames: [ifname],
        up_cmds: up_cmds,
        child_specs: child_specs
      }

    raw =
      case ip_method do
        :qmi_profile ->
          # IP will be configured by IPManager from QMI profile settings.
          # No DHCP client needed.
          raw

        _dhcp ->
          ipv4_config = %{
            ipv4: %{method: :dhcp},
            hostname: Map.get(config, :hostname)
          }

          IPv4Config.add_config(raw, ipv4_config, [])
      end

    raw |> remove_connectivity_detector()
  end

  # Pick the wire transport up-front so downstream child specs all see
  # the same concrete value. Mirrors `QMI.Supervisor.derive_transport/1`:
  # an explicit `:transport` wins; otherwise a cdc-wdm-style
  # `:device_path` means QMUX, anything else (including no path) means
  # QRTR.
  defp resolve_transport(nil, device_path), do: detect_transport(device_path)
  defp resolve_transport(transport, _device_path), do: transport

  defp detect_transport(nil), do: :qrtr

  defp detect_transport(path) do
    cond do
      String.starts_with?(path, "/dev/cdc-wdm") -> :qmux
      String.match?(path, ~r"^/dev/wwan\d+qmi\d+$") -> :qmux
      true -> :qrtr
    end
  end

  defp remove_connectivity_detector(raw_config) do
    new_child_specs =
      Enum.reject(raw_config.child_specs, fn
        # Old internet connectivity checker module
        {VintageNet.Interface.InternetConnectivityChecker, _ifname} -> true
        # New internet connectivity checker module
        {VintageNet.Connectivity.InternetChecker, _ifname} -> true
        _ -> false
      end)

    %{raw_config | child_specs: new_child_specs}
  end

  @impl VintageNet.Technology
  def check_system(_), do: {:error, "unimplemented"}

  @impl VintageNet.Technology
  def ioctl(_ifname, _command, _args), do: {:error, :unsupported}

  @doc """
  Configure a cellular modem using an APN

  ```
  iex> VintageNetQMI.quick_configure("an_apn")
  :ok
  ```
  """
  @spec quick_configure(String.t()) :: :ok | {:error, term()}
  def quick_configure(apn) do
    with {:ok, config} <- Cookbook.simple(apn) do
      VintageNet.configure("wwan0", config)
    end
  end

  @doc """
  Configure a cellular modem with extended options

  This function allows you to quickly configure a cellular modem with
  authentication credentials and PDP type settings.

  ## Examples

      # Basic APN configuration
      VintageNetQMI.quick_configure_with_auth("internet.provider.com")

      # With username and password
      VintageNetQMI.quick_configure_with_auth("internet.provider.com",
        username: "user@provider.com",
        password: "secret")

      # With full configuration
      VintageNetQMI.quick_configure_with_auth("internet.provider.com",
        username: "user@provider.com",
        password: "secret",
        auth_method: :pap_or_chap,
        pdp_type: :ipv4v6,
        roaming_allowed?: false)

  ## Options

  * `:username` - Authentication username (optional)
  * `:password` - Authentication password (optional)
  * `:auth_method` - Authentication method: `:none`, `:pap`, `:chap`, `:pap_or_chap` (optional)
  * `:pdp_type` - PDP type: `:ipv4`, `:ipv6`, `:ipv4v6`, `:ppp` (optional)
  * `:roaming_allowed?` - Whether roaming is allowed (optional)
  """
  @spec quick_configure_with_auth(String.t(), keyword()) :: :ok | {:error, term()}
  def quick_configure_with_auth(apn, opts \\ []) do
    provider_config =
      opts
      |> Keyword.put(:apn, apn)
      |> Enum.into(%{})

    config = %{
      type: __MODULE__,
      vintage_net_qmi: %{
        service_providers: [provider_config]
      }
    }

    VintageNet.configure("wwan0", config)
  end

  # For unit test purposes
  @doc false
  @spec indication_callback(VintageNet.ifname()) :: function()
  def indication_callback(ifname) do
    &VintageNetQMI.Indications.handle(ifname, &1)
  end
end
