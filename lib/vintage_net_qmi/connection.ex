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

  alias QMI.{NetworkAccess, WirelessData, WirelessDataAdmin}
  alias QMI.Codec.WirelessData, as: WirelessDataCodec
  alias VintageNetQMI.Connection.Configuration
  alias VintageNetQMI.ServiceProvider

  require Logger

  @configuration_retry 30_000

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

    iccid_property = mobile_prop(ifname, "iccid")
    VintageNet.subscribe(iccid_property)
    iccid = VintageNet.get(iccid_property)

    state =
      %{
        ifname: ifname,
        qmi: VintageNetQMI.qmi_name(ifname),
        service_providers: providers,
        iccid: iccid,
        connect_retry_interval: 30_000,
        radio_technologies: radio_technologies,
        configuration: Configuration.new()
      }
      |> try_to_configure_modem()
      |> maybe_start_try_to_connect_timer()

    {:ok, state}
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

  def handle_info(:try_to_configure, state) do
    new_state = try_to_configure_modem(state)

    _ =
      if Configuration.completely_configured?(new_state.configuration) do
        Process.send_after(self(), :try_to_connect, 1_000)
      end

    {:noreply, new_state}
  end

  def handle_info(:try_to_connect, state) do
    {:noreply, try_to_connect(state)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp try_to_connect(state) do
    three_3gpp_profile_index = 1
    iccid = state.iccid
    providers = state.service_providers

    with :ok <- validate_iccid(iccid),
         {:ok, provider} <- ServiceProvider.select_provider_by_iccid(providers, iccid),
         PropertyTable.put(VintageNet, mobile_prop(state.ifname, "apn"), provider.apn),
         :ok <- configure_profile_for_provider(provider, three_3gpp_profile_index, state),
         {:ok, _} <-
           WirelessData.start_network_interface(state.qmi,
             apn: provider.apn,
             profile_3gpp_index: three_3gpp_profile_index
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
          "[VintageNetQMI]: could not connect for #{inspect(reason)}. Retrying in #{inspect(state.connect_retry_interval)} ms."
        )

        start_try_to_connect_timer(state)
    end
  end

  defp validate_iccid(iccid) when is_binary(iccid), do: :ok
  defp validate_iccid(_iccid), do: {:error, :invalid_iccid}

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
