# SPDX-FileCopyrightText: 2021 Frank Hunleth
# SPDX-FileCopyrightText: 2021 Matt Ludwigs
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.Connection do
  @moduledoc """
  Establish an connection with the QMI device
  """

  use GenServer

  alias QMI.{DataPortMapper, NetworkAccess, WirelessData, WirelessDataAdmin}
  alias QMI.Codec.WirelessData, as: WirelessDataCodec
  alias VintageNetQMI.Connection.Configuration
  alias VintageNetQMI.ServiceProvider

  require Logger

  @configuration_retry 60_000
  @start_network_timeout 30_000

  @typedoc """
  Options for to establish the connection

  `:service_provider` - The service provider configuration containing:
    - `:apn` - The Access Point Name of the service provider
    - `:username` - Optional username for authentication
    - `:password` - Optional password for authentication
    - `:pdp_type` - Optional PDP type (:ipv4, :ppp, :ipv6, :ipv4v6)
    - `:auth_method` - Optional authentication method (:none, :pap, :chap, :pap_or_chap)
    - `:roaming_allowed?` - Optional roaming configuration
  """
  @type arg() :: {:service_provider, String.t()}

  @doc """
  Start the Connection server
  """
  @spec start_link([arg()]) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: name(args[:ifname]))
  end

  defp name(ifname) do
    Module.concat(__MODULE__, ifname)
  end

  @doc """
  Process connection stats

  This will post the updated stats as properties.
  """
  @spec process_stats(VintageNet.ifname(), map()) :: :ok
  def process_stats(ifname, event_report_indication) do
    stats = Map.drop(event_report_indication, [:name])
    GenServer.cast(name(ifname), {:process_stats, stats})
  end

  defp mobile_prop(ifname, key), do: ["interface", ifname, "mobile", key]

  @impl GenServer
  def init(args) do
    ifname = Keyword.fetch!(args, :ifname)
    providers = Keyword.fetch!(args, :service_providers)
    radio_technologies = Keyword.get(args, :radio_technologies)
    transport = Keyword.get(args, :transport, :qmux)
    rmnet_child = Keyword.get(args, :rmnet_child)
    qmap_mux_id = (rmnet_child && rmnet_child[:mux_id]) || 0x81

    iccid_property = mobile_prop(ifname, "iccid")
    VintageNet.subscribe(iccid_property)
    iccid = VintageNet.get(iccid_property)

    registration_property = mobile_prop(ifname, "registration_state")
    VintageNet.subscribe(registration_property)
    registration_state = VintageNet.get(registration_property) || :unregistered

    state =
      %{
        ifname: ifname,
        qmi: VintageNetQMI.qmi_name(ifname),
        service_providers: providers,
        iccid: iccid,
        registration_state: registration_state,
        connect_retry_interval: 30_000,
        radio_technologies: radio_technologies,
        transport: transport,
        qmap_mux_id: qmap_mux_id,
        configuration: Configuration.new()
      }
      |> try_to_configure_modem()
      |> maybe_start_try_to_connect_timer()

    bootstrap_serving_system(state)

    {:ok, state}
  end

  # The modem typically emits its first `serving_system_indication`
  # very early in its own boot, often before our `Indications`
  # GenServer is alive to receive it. After that the modem only
  # re-emits on state changes, so without this bootstrap call
  # `registration_state` would stay `nil` even though the modem is
  # already attached to the network. Query NAS once on init and feed
  # the result into `Connectivity` as if it were a fresh indication.
  defp bootstrap_serving_system(state) do
    case NetworkAccess.get_serving_system(state.qmi) do
      {:ok, serving_system} ->
        VintageNetQMI.Connectivity.serving_system_change(state.ifname, serving_system)

      {:error, _reason} ->
        :ok
    end
  end

  defp try_to_configure_modem(state) do
    case Configuration.run_configurations(state.configuration, &try_run_configuration(&1, state)) do
      {:ok, updated_configuration} ->
        %{state | configuration: updated_configuration}

      {:error, reason, config_item, updated_config} ->
        Logger.warning(
          "[VintageNetQMI] Failed configuring modem: #{inspect(config_item)} for reason: #{inspect(reason)}"
        )

        _ = Process.send_after(self(), :try_to_configure, @configuration_retry)

        %{state | configuration: updated_config}
    end
  end

  defp try_run_configuration(:radio_technologies_set, %{radio_technologies: rts})
       when rts in [nil, []] do
    :ok
  end

  defp try_run_configuration(:radio_technologies_set, state) do
    NetworkAccess.set_system_selection_preference(state.qmi,
      mode_preference: state.radio_technologies
    )
  end

  defp try_run_configuration(:reporting_connection_stats, state) do
    WirelessData.set_event_report(state.qmi)
  end

  defp try_run_configuration(:profile_settings_configured, _state) do
    # This is a placeholder for future profile configuration verification
    :ok
  end

  @impl GenServer
  def handle_cast({:process_stats, stats}, state) do
    timestamp = System.monotonic_time()
    stats_with_timestamp = Map.put(stats, :timestamp, timestamp)

    PropertyTable.put(VintageNet, mobile_prop(state.ifname, "statistics"), stats_with_timestamp)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {VintageNet, ["interface", ifname, "mobile", "iccid"], _, new_iccid, _meta},
        %{ifname: ifname, iccid: old_iccid} = state
      )
      when new_iccid != old_iccid do
    new_state = %{state | iccid: new_iccid}

    {:noreply, try_to_connect(new_state)}
  end

  def handle_info(
        {VintageNet, ["interface", ifname, "mobile", "registration_state"], _, new_reg_state,
         _meta},
        %{ifname: ifname} = state
      ) do
    new_state = %{state | registration_state: new_reg_state}

    if new_reg_state == :registered do
      Logger.info("[VintageNetQMI] Modem registered on network, attempting to connect")
      {:noreply, try_to_connect(new_state)}
    else
      {:noreply, new_state}
    end
  end

  def handle_info(:try_to_configure, state) do
    new_state = try_to_configure_modem(state)

    _ =
      if Configuration.completely_configured?(new_state.configuration) do
        Process.send_after(self(), :try_to_connect, 10_000)
      end

    {:noreply, new_state}
  end

  def handle_info(:try_to_connect, state) do
    {:noreply, try_to_connect(state)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp try_to_connect(%{registration_state: reg} = state)
       when reg != :registered do
    state
  end

  defp try_to_connect(state) do
    three_3gpp_profile_index = 1
    iccid = state.iccid
    providers = state.service_providers

    with :ok <- validate_iccid(iccid),
         {:ok, provider} <- ServiceProvider.select_provider_by_iccid(providers, iccid),
         PropertyTable.put(VintageNet, mobile_prop(state.ifname, "apn"), provider.apn),
         :ok <- configure_profile_for_provider(provider, three_3gpp_profile_index, state),
         :ok <- ensure_dpm_open_port(state),
         :ok <- ensure_data_format(state),
         :ok <- ensure_qrtr_data_binding(state),
         {:ok, _} <-
           WirelessData.start_network_interface(state.qmi,
             # ModemManager sends EITHER profile_index_3gpp OR (apn + auth);
             # never both. Sending both confuses the modem firmware and
             # makes WDS Start Network return :call_failed (3GPP verbose 29).
             apn: provider.apn,
             timeout: @start_network_timeout
           ) do
      Logger.info("[VintageNetQMI]: network started, waiting for IP configuration")
      state
    else
      {:error, :no_provider} ->
        Logger.warning(
          "[VintageNetQMI]: cannot select an APN to use from the configured service providers, check your configuration for VintageNet."
        )

        state

      {:error, :invalid_iccid} ->
        Logger.warning(
          "[VintageNetQMI] ICCID, #{inspect(iccid)}, is invalid. Waiting for a valid one."
        )

        state

      {:error, :no_effect} ->
        # no effect means that a network connection as already be established
        # so we don't need to try to connect again.
        state

      {:error, reason} ->
        Logger.warning(
          "[VintageNetQMI]: could not connect for #{inspect(reason)}. " <>
            "Check QMI.Driver logs for verbose call end reason. " <>
            "Retrying in #{inspect(state.connect_retry_interval)} ms."
        )

        start_try_to_connect_timer(state)
    end
  end

  defp validate_iccid(iccid) when is_binary(iccid), do: :ok
  defp validate_iccid(_iccid), do: {:error, :invalid_iccid}

  defp ensure_data_format(state) do
    # If the driver has a sysfs raw_ip knob, QMI.configure_linux/1 already
    # handled it.  Otherwise, use the WDA service to tell the modem to send
    # raw-IP packets so they match the ARPHRD_NONE / ARPHRD_RAWIP driver.
    sysfs_path = "/sys/class/net/#{state.ifname}/qmi/raw_ip"

    if File.exists?(sysfs_path) do
      :ok
    else
      # On QRTR-backed in-kernel modems (msm8953/sdm632, FP3+) the data
      # endpoint is the embedded IPA-backed link, not an HSUSB port,
      # and the modem must agree with the kernel rmnet child on the
      # QMAP wire format. MM picks the aggregation protocol from the
      # rmnet child's `feature/{rx,tx}_offload` sysfs entries; the
      # `ipa2-lite` driver doesn't expose `feature/`, so MM and we both
      # use QMAPv1 (libqmi `QMI_WDA_DATA_AGGREGATION_PROTOCOL_QMAP =
      # 0x05`) with the rmnet child set to `INGRESS_DEAGGREGATION` only.
      # Mismatch with `:qmap_v5` makes `rmnet_map_deaggregate` drop
      # every downlink frame because it doesn't strip the v5 csum
      # header — rmnet0 RX stays at zero forever.
      # MM also doesn't send TLV 0x10 (qos_format) — omit it to match.
      opts =
        case state.transport do
          :qrtr ->
            [
              link_layer_protocol: :raw_ip,
              ul_aggregation_protocol: :qmap,
              dl_aggregation_protocol: :qmap,
              dl_max_datagrams: 32,
              dl_max_size: 32_768,
              endpoint_type: 4,
              endpoint_iface_number: 1
            ]

          _ ->
            [
              link_layer_protocol: :raw_ip,
              ul_aggregation_protocol: :disabled,
              dl_aggregation_protocol: :disabled
            ]
        end

      case WirelessDataAdmin.set_data_format(state.qmi, opts) do
        {:ok, _result} ->
          :ok

        {:error, reason} ->
          Logger.warning("[VintageNetQMI] WDA Set Data Format failed: #{inspect(reason)}")
          # Don't block connection — the modem may not support WDA, or may
          # already be in the correct mode.
          :ok
      end
    end
  end

  # On QRTR-backed in-kernel modems with an IPA hardware data path
  # (msm8953/sdm632), the modem firmware refuses every subsequent
  # `WDS`/`WDA` data-plane call until the AP has registered its
  # hardware data port with the modem via DPM `Open Port`. The
  # endpoint id pair is the IPA driver's modem-side RX/TX endpoint
  # ids, exposed under `/sys/devices/platform/.../ipa/modem/{rx,tx}_endpoint_id`.
  # We attempt to read those from sysfs and fall back to (5, 4),
  # which is what `ipa2-lite` reports on msm8953.
  defp ensure_dpm_open_port(%{transport: :qrtr} = state) do
    {ap_rx, ap_tx} = ipa_endpoint_ids()
    # IMPORTANT: DPM Open Port expects modem-side endpoint perspective.
    # sysfs `rx_endpoint_id`/`tx_endpoint_id` is AP-side. The modem's RX is
    # the AP's TX and vice-versa, so we pass them swapped (matching MM's
    # mm-port-qmi.c::dpm_open_port). Without the swap the modem firmware
    # sets up the IPA pipes in the wrong direction and TX from the AP
    # never reaches the modem's WDS data plane.
    modem_rx = ap_tx
    modem_tx = ap_rx

    case DataPortMapper.open_hardware_port(state.qmi, 4, 1, modem_rx, modem_tx) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[VintageNetQMI] DPM Open Port returned #{inspect(reason)} — continuing"
        )

        :ok
    end
  end

  defp ensure_dpm_open_port(_state), do: :ok

  defp ipa_endpoint_ids do
    case Path.wildcard("/sys/devices/platform/*/*.ipa/modem") do
      [path | _] ->
        {read_int!(path, "rx_endpoint_id", 5), read_int!(path, "tx_endpoint_id", 4)}

      _ ->
        {5, 4}
    end
  end

  defp read_int!(dir, file, default) do
    case File.read(Path.join(dir, file)) do
      {:ok, s} ->
        case Integer.parse(String.trim(s)) do
          {n, _} -> n
          :error -> default
        end

      _ ->
        default
    end
  end

  # Extra WDS bring-up steps needed for in-kernel Qualcomm modems
  # (msm8953/sdm632 — FP3+) before `start_network_interface/2` will
  # succeed:
  #
  #   * Bind the WDS client to the embedded data endpoint (mux id 0x81)
  #     so the modem knows where the rmnet/IPA path lives.
  #   * Bind to the primary SIM subscription.
  #   * Pin IPv4 as the IP family preference.
  #
  # Each step is best-effort: older firmwares may not implement
  # `bind_subscription` (msg 0x00AF was introduced in libqmi 1.37) so a
  # `:not_supported`/`:invalid_arg` here shouldn't block the connection
  # attempt. Hard failures bubble up so we don't silently retry a
  # `start_network_interface` that's guaranteed to keep failing.
  defp ensure_qrtr_data_binding(%{transport: :qrtr} = state) do
    # Note: ModemManager only sends Endpoint Info + Mux ID TLVs on bind_mux;
    # it does NOT send Client Type. We match that here (omit `:client_type`).
    # Passing `client_type: :tethered` makes the modem firmware reject the
    # WDS Start Network that follows with `:call_failed` (verbose end reason
    # 29) on FP3+/msm8953. See [[feedback-fp3-modem-debugging]].
    with :ok <-
           best_effort(
             WirelessData.bind_mux_data_port(state.qmi,
               endpoint_type: :embedded,
               interface_number: 1,
               mux_id: state.qmap_mux_id
             ),
             "bind_mux_data_port"
           ),
         :ok <- best_effort(WirelessData.bind_subscription(state.qmi, :primary), "bind_subscription"),
         :ok <- best_effort(WirelessData.set_ip_family(state.qmi, :ipv4), "set_ip_family") do
      :ok
    end
  end

  defp ensure_qrtr_data_binding(_state), do: :ok

  defp best_effort({:ok, _}, _step), do: :ok

  defp best_effort({:error, reason}, step) do
    Logger.warning(
      "[VintageNetQMI] WDS #{step} returned #{inspect(reason)} — continuing"
    )

    :ok
  end

  defp configure_profile_for_provider(provider, profile_index, state) do
    profile_settings = build_profile_settings(provider)

    case WirelessData.modify_profile_settings(state.qmi, profile_index, profile_settings) do
      {:ok, %{extended_error_code: nil}} ->
        :ok

      {:ok, has_error} ->
        Logger.warning(
          "[VintageNetQMI] Profile configuration returned error: #{inspect(has_error)}"
        )

        {:error, has_error}

      error ->
        Logger.warning("[VintageNetQMI] Failed to configure profile: #{inspect(error)}")
        error
    end
  end

  defp build_profile_settings(provider) do
    base_settings = []

    # Add roaming configuration (keep the inverted logic for compatibility)
    roaming_settings =
      case Map.get(provider, :roaming_allowed?) do
        nil -> []
        roaming_allowed? -> [roaming_disallowed: !roaming_allowed?]
      end

    # Add APN (always required)
    apn_settings = [apn: provider.apn]

    # Add optional authentication settings
    auth_settings =
      [
        Map.get(provider, :username),
        Map.get(provider, :password),
        Map.get(provider, :auth_method)
      ]
      |> case do
        [username, password, auth_method] when is_binary(username) and is_binary(password) ->
          auth_method = auth_method || :pap_or_chap
          [username: username, password: password, auth_method: auth_method]

        [username, nil, _] when is_binary(username) ->
          [username: username, auth_method: Map.get(provider, :auth_method) || :none]

        [nil, password, _] when is_binary(password) ->
          [password: password, auth_method: Map.get(provider, :auth_method) || :none]

        _ ->
          case Map.get(provider, :auth_method) do
            nil -> []
            auth_method -> [auth_method: auth_method]
          end
      end

    # Add PDP type if specified
    pdp_settings =
      case Map.get(provider, :pdp_type) do
        nil -> []
        pdp_type -> [pdp_type: pdp_type]
      end

    base_settings ++ roaming_settings ++ apn_settings ++ auth_settings ++ pdp_settings
  end

  @doc """
  Get current profile settings for debugging purposes

  This function can be called to retrieve the current configuration
  of a profile for debugging or verification purposes.
  """
  @spec get_profile_settings(VintageNet.ifname(), integer()) ::
          {:ok, WirelessDataCodec.profile_settings()} | {:error, atom()}
  def get_profile_settings(ifname, profile_index \\ 1) do
    qmi_name = VintageNetQMI.qmi_name(ifname)
    WirelessData.get_profile_settings(qmi_name, profile_index, :profile_type_3gpp)
  end

  @doc """
  Get current connection settings for debugging purposes

  This function retrieves current connection settings including MTU information.
  """
  @spec get_current_settings(VintageNet.ifname(), 4 | 6, keyword()) ::
          {:ok, WirelessDataCodec.current_settings()} | {:error, atom()}
  def get_current_settings(ifname, ip_family \\ 4, opts \\ []) do
    qmi_name = VintageNetQMI.qmi_name(ifname)
    WirelessData.get_current_settings(qmi_name, ip_family, opts)
  end

  defp maybe_start_try_to_connect_timer(%{iccid: nil} = state), do: state

  defp maybe_start_try_to_connect_timer(state) do
    if Configuration.required_configured?(state.configuration) do
      start_try_to_connect_timer(state)
    else
      state
    end
  end

  defp start_try_to_connect_timer(state) do
    _ = Process.send_after(self(), :try_to_connect, state.connect_retry_interval)
    state
  end
end
