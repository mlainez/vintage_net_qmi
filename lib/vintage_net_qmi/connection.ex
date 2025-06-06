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

  alias QMI.{NetworkAccess, WirelessData}
  alias VintageNetQMI.Connection.Configuration
  alias VintageNetQMI.ServiceProvider

  require Logger

  @configuration_retry 60_000

  @typedoc """
  Options for to establish the connection

  `:apn` - The Access Point Name of the service provider
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
        connect_retry_interval: 60_000,
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

  defp try_to_connect(state) do
    three_3gpp_profile_index = 3
    iccid = state.iccid
    providers = state.service_providers

    with :ok <- validate_iccid(iccid),
         Logger.warning("[VintageNetQMI]: Trying to connect with ICCID: #{inspect(iccid)}"),
         {:ok, provider} <- ServiceProvider.select_provider_by_iccid(providers, iccid),
         PropertyTable.put(VintageNet, mobile_prop(state.ifname, "apn"), provider.apn),
         :ok <- set_roaming_allowed_for_provider(provider, three_3gpp_profile_index, state),
         {:ok, _} <-
           WirelessData.start_network_interface(state.qmi,
             apn: provider.apn,
             profile_3gpp_index: three_3gpp_profile_index
           ) do
      Logger.info("[VintageNetQMI]: network started. Waiting on DHCP")
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

  defp set_roaming_allowed_for_provider(
         %{roaming_allowed?: roaming_allowed?},
         profile_index,
         state
       ) do
    case WirelessData.modify_profile_settings(state.qmi, profile_index,
           # We have to set the opposite of what was passed in because QMI
           # configures if roaming is disallowed whereas our public
           # configuration API configures if roaming is allowed.
           roaming_disallowed: !roaming_allowed?
         ) do
      {:ok, %{extended_error_code: nil}} ->
        :ok

      {:ok, has_error} ->
        {:error, has_error}

      error ->
        error
    end
  end

  defp set_roaming_allowed_for_provider(_, _, _) do
    :ok
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
