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

  alias QMI.{DeviceManagement, NetworkAccess, WirelessData, WirelessDataAdmin}
  alias QMI.Codec.WirelessData, as: WirelessDataCodec
  alias VintageNetQMI.Connection.Configuration
  alias VintageNetQMI.Profiles
  alias VintageNetQMI.ServiceProvider

  require Logger

  @configuration_retry 60_000
  @start_network_timeout 30_000
  @reattach_online_delay 2_000
  @attach_fallback_delay 1_000
  @pdn_already_on_apn 55

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
    initial_eps_bearer = Keyword.get(args, :initial_eps_bearer)
    profile_index = Keyword.get(args, :profile_index)

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
        initial_eps_bearer: initial_eps_bearer,
        profile_index: profile_index,
        prefer_attach?: false,
        reattached?: false,
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

  defp try_run_configuration(:initial_eps_bearer_set, %{initial_eps_bearer: nil}), do: :ok

  defp try_run_configuration(:initial_eps_bearer_set, state) do
    bearer = state.initial_eps_bearer

    with {:ok, index} <- initial_eps_bearer_profile(state.qmi),
         {:ok, profile} <- WirelessData.get_profile_settings(state.qmi, index) do
      if Profiles.up_to_date?(profile, bearer) do
        :ok
      else
        Logger.info(
          "[VintageNetQMI] setting the initial EPS bearer (profile #{index}) to APN #{inspect(bearer.apn)}"
        )

        set_initial_eps_bearer(state.qmi, index, bearer)
      end
    end
  end

  defp try_run_configuration(:reporting_connection_stats, state) do
    WirelessData.set_event_report(state.qmi)
  end

  # The LTE attach profile, or the default profile on modems without an
  # attach PDN list
  defp initial_eps_bearer_profile(qmi) do
    case attach_profile_index(qmi) do
      nil -> WirelessData.get_default_profile_number(qmi)
      index -> {:ok, index}
    end
  end

  defp attach_profile_index(qmi) do
    case WirelessData.get_lte_attach_pdn_list(qmi) do
      {:ok, [index | _]} -> index
      _ -> nil
    end
  end

  # As ModemManager does: leave the network, change the attach profile and
  # register again, so the next attach uses the new settings.
  defp set_initial_eps_bearer(qmi, index, bearer) do
    with :ok <- DeviceManagement.set_operating_mode(qmi, :low_power) do
      result = write_profile(qmi, index, bearer)

      case DeviceManagement.set_operating_mode(qmi, :online) do
        :ok -> result
        error -> error
      end
    end
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

  def handle_info(:reattach_online, state) do
    case DeviceManagement.set_operating_mode(state.qmi, :online) do
      :ok ->
        :ok

      error ->
        Logger.warning("[VintageNetQMI] could not put the modem back online: #{inspect(error)}")
    end

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp try_to_connect(%{registration_state: reg} = state)
       when reg != :registered do
    state
  end

  defp try_to_connect(state) do
    iccid = state.iccid
    providers = state.service_providers

    with :ok <- validate_iccid(iccid),
         {:ok, provider} <- ServiceProvider.select_provider_by_iccid(providers, iccid),
         PropertyTable.put(VintageNet, mobile_prop(state.ifname, "apn"), provider.apn),
         {:ok, profile_index, kind} <- data_profile(provider, state),
         PropertyTable.put(VintageNet, mobile_prop(state.ifname, "profile_index"), profile_index),
         :ok <- ensure_data_format(state),
         {:ok, _} <- start_network(provider, profile_index, kind, state) do
      Logger.info(
        "[VintageNetQMI]: network started on profile #{profile_index} (#{kind}), waiting for IP configuration"
      )

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

      {:error, {:call_failed, reason, kind}} ->
        handle_call_failure(reason, kind, state)

      {:error, reason} ->
        Logger.warning(
          "[VintageNetQMI]: could not connect for #{inspect(reason)}. " <>
            "Retrying in #{inspect(state.connect_retry_interval)} ms."
        )

        start_try_to_connect_timer(state)
    end
  end

  defp validate_iccid(iccid) when is_binary(iccid), do: :ok
  defp validate_iccid(_iccid), do: {:error, :invalid_iccid}

  # Pick the profile for the data call and make it hold the provider's
  # settings (see VintageNetQMI.Profiles). The attach profile is never
  # written here: its settings come from the initial EPS bearer.
  defp data_profile(provider, state) do
    attach_index = attach_profile_index(state.qmi)

    with {:ok, profiles} <- WirelessData.get_profile_list(state.qmi) do
      choice =
        Profiles.select(provider.apn, profiles, attach_index,
          profile_index: state.profile_index,
          prefer_attach?: state.prefer_attach?
        )

      use_profile(choice, profiles, provider, state.qmi)
    end
  end

  defp use_profile({:attach, index}, _profiles, _provider, _qmi), do: {:ok, index, :attach}

  defp use_profile({kind, index}, profiles, provider, qmi) do
    profile = Enum.find(profiles, &(&1.index == index))

    with :ok <- ensure_profile(qmi, index, profile, provider) do
      {:ok, index, kind}
    end
  end

  defp use_profile(:create, _profiles, provider, qmi) do
    with {:ok, %{index: index}} <- WirelessData.create_profile(qmi, Profiles.settings(provider)) do
      Logger.info("[VintageNetQMI] created profile #{index} for APN #{inspect(provider.apn)}")
      {:ok, index, :created}
    end
  end

  defp ensure_profile(qmi, index, profile, wanted) do
    if Profiles.up_to_date?(profile, wanted) do
      :ok
    else
      write_profile(qmi, index, wanted)
    end
  end

  defp write_profile(qmi, index, wanted) do
    case WirelessData.modify_profile_settings(qmi, index, Profiles.settings(wanted)) do
      {:ok, %{extended_error_code: nil}} ->
        :ok

      {:ok, error} ->
        Logger.warning("[VintageNetQMI] writing profile #{index} failed: #{inspect(error)}")
        {:error, error}

      error ->
        Logger.warning("[VintageNetQMI] writing profile #{index} failed: #{inspect(error)}")
        error
    end
  end

  # The profile holds the APN, so it is not passed again: with the APN the
  # modem may ask for a new PDN instead of using the attach bearer.
  defp start_network(provider, profile_index, kind, state) do
    case WirelessData.start_network_interface(state.qmi,
           profile_3gpp_index: profile_index,
           ip_family: Profiles.ip_family(provider),
           timeout: @start_network_timeout
         ) do
      {:error, {:call_failed, reason}} -> {:error, {:call_failed, reason, kind}}
      other -> other
    end
  end

  defp handle_call_failure(
         %{
           call_end_reason_type: :three_gpp_specification_defined,
           verbose_call_end_reason: @pdn_already_on_apn
         },
         kind,
         %{prefer_attach?: false} = state
       )
       when kind != :attach do
    # The attach bearer already runs on this APN: use the attach profile.
    Logger.info(
      "[VintageNetQMI] the network already has a PDN on this APN, using the attach profile"
    )

    _ = Process.send_after(self(), :try_to_connect, @attach_fallback_delay)
    %{state | prefer_attach?: true}
  end

  defp handle_call_failure(
         %{
           call_end_reason_type: :three_gpp_specification_defined,
           verbose_call_end_reason: @pdn_already_on_apn
         },
         :attach,
         %{reattached?: false} = state
       ) do
    # The attach still runs with settings the attach profile no longer holds.
    Logger.info("[VintageNetQMI] the attach bearer is stale, registering again")

    _ = DeviceManagement.set_operating_mode(state.qmi, :low_power)
    _ = Process.send_after(self(), :reattach_online, @reattach_online_delay)
    start_try_to_connect_timer(%{state | reattached?: true})
  end

  defp handle_call_failure(reason, kind, state) do
    Logger.warning(
      "[VintageNetQMI]: could not connect on the #{kind} profile: #{inspect(reason)}. " <>
        "Retrying in #{inspect(state.connect_retry_interval)} ms."
    )

    start_try_to_connect_timer(state)
  end

  defp ensure_data_format(state) do
    # If the driver has a sysfs raw_ip knob, QMI.configure_linux/1 already
    # handled it.  Otherwise, use the WDA service to tell the modem to send
    # raw-IP packets so they match the ARPHRD_NONE / ARPHRD_RAWIP driver.
    sysfs_path = "/sys/class/net/#{state.ifname}/qmi/raw_ip"

    if File.exists?(sysfs_path) do
      :ok
    else
      case WirelessDataAdmin.set_data_format(state.qmi,
             link_layer_protocol: :raw_ip,
             ul_aggregation_protocol: :disabled,
             dl_aggregation_protocol: :disabled,
             qos_format: false
           ) do
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
