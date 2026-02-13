# SPDX-FileCopyrightText: 2025 Marc Lainez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.IPManager do
  @moduledoc false

  # Replaces CurrentSettingsMonitor + IPConfigurator.
  #
  # Listens for QMI connection-status changes, fetches IP settings from the
  # modem, and applies them directly with ifconfig / RouteManager / NameResolver.
  # This avoids calling VintageNet.configure() which would tear down and
  # restart the entire supervision tree.

  use GenServer
  require Logger

  alias VintageNet.Command
  alias VintageNet.NameResolver
  alias VintageNet.RouteManager
  alias QMI.WirelessData

  @initial_fetch_delay 500
  @retry_fetch_delay 2_000

  def start_link(args) do
    ifname = Keyword.fetch!(args, :ifname)
    GenServer.start_link(__MODULE__, args, name: name(ifname))
  end

  defp name(ifname), do: Module.concat(__MODULE__, ifname)

  @impl GenServer
  def init(args) do
    ifname = Keyword.fetch!(args, :ifname)

    VintageNet.subscribe(["interface", ifname, "qmi_connection_status"])

    state = %{
      ifname: ifname,
      qmi: VintageNetQMI.qmi_name(ifname),
      configured?: false
    }

    {:ok, state}
  end

  # --- QMI connection status changes ----------------------------------------

  @impl GenServer
  def handle_info(
        {VintageNet, ["interface", ifname, "qmi_connection_status"], _old, :connected, _meta},
        %{ifname: ifname} = state
      ) do
    Logger.info("[IPManager] #{ifname} connected, will fetch IP settings")
    Process.send_after(self(), :fetch_settings, @initial_fetch_delay)
    {:noreply, state}
  end

  def handle_info(
        {VintageNet, ["interface", ifname, "qmi_connection_status"], _old, :disconnected, _meta},
        %{ifname: ifname} = state
      ) do
    Logger.info("[IPManager] #{ifname} disconnected, tearing down IP")
    tear_down(ifname)
    {:noreply, %{state | configured?: false}}
  end

  def handle_info(
        {VintageNet, ["interface", _ifname, "qmi_connection_status"], _old, _other, _meta},
        state
      ) do
    {:noreply, state}
  end

  # --- Fetch & apply --------------------------------------------------------

  def handle_info(:fetch_settings, state) do
    case fetch_ip_settings(state.qmi) do
      {:ok, settings} when map_size(settings) > 0 ->
        apply_settings(state.ifname, settings)
        {:noreply, %{state | configured?: true}}

      _ ->
        Process.send_after(self(), :fetch_settings, @retry_fetch_delay)
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp fetch_ip_settings(qmi) do
    ipv4 =
      case WirelessData.get_current_settings(qmi, 4) do
        {:ok, data} -> data
        {:error, _} -> %{}
      end

    ipv6 =
      case WirelessData.get_current_settings(qmi, 6) do
        {:ok, data} -> data
        {:error, _} -> %{}
      end

    {:ok, Map.merge(ipv4, ipv6)}
  rescue
    e ->
      Logger.warning("[IPManager] Exception fetching settings: #{inspect(e)}")
      {:error, :exception}
  end

  # -- Apply -----------------------------------------------------------------

  defp apply_settings(ifname, settings) do
    with {:ok, addr, prefix} <- extract_ipv4_address(settings) do
      # 1. Assign the IP address via ifconfig
      apply_ipv4_address(ifname, addr, prefix, settings)

      # 2. Set default route through RouteManager
      apply_route(ifname, addr, prefix, settings)

      # 3. Set DNS through NameResolver
      apply_dns(ifname, settings)

      Logger.info("[IPManager] IP configuration applied to #{ifname}")
    else
      {:error, reason} ->
        Logger.warning("[IPManager] Cannot apply IP to #{ifname}: #{inspect(reason)}")
    end
  end

  defp extract_ipv4_address(settings) do
    with address when is_binary(address) <- settings[:ipv4_address],
         subnet when is_binary(subnet) <- settings[:ipv4_subnet_mask],
         {:ok, _addr_tuple} <- parse_ip(address) do
      prefix = subnet_mask_to_prefix(subnet)
      {:ok, address, prefix}
    else
      nil -> {:error, :missing_ipv4}
      {:error, _} = err -> err
    end
  end

  defp apply_ipv4_address(ifname, address, _prefix, settings) do
    netmask = settings[:ipv4_subnet_mask]
    args = [ifname, address, "netmask", netmask]

    # For raw-IP / point-to-point interfaces (type != 1/Ethernet), set the
    # peer address so the kernel knows how to deliver packets on the link.
    # ARPHRD_NONE (519) and ARPHRD_RAWIP (530) both need this.
    args =
      case {settings[:ipv4_gateway], pointopoint_interface?(ifname)} do
        {gateway, true} when gateway != nil -> args ++ ["pointopoint", gateway]
        _ -> args
      end

    args =
      case settings[:ipv4_mtu] do
        nil -> args
        mtu -> args ++ ["mtu", to_string(mtu)]
      end

    case Command.cmd("ifconfig", args, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, code} ->
        Logger.warning("[IPManager] ifconfig failed (#{code}): #{output}")
        {:error, :ifconfig_failed}
    end
  end

  defp apply_route(ifname, address, prefix, settings) do
    with gateway when is_binary(gateway) <- settings[:ipv4_gateway],
         {:ok, addr_tuple} <- parse_ip(address),
         {:ok, gw_tuple} <- parse_ip(gateway) do
      RouteManager.set_route(ifname, [{addr_tuple, prefix}], gw_tuple)
    else
      nil ->
        :ok

      {:error, _} = err ->
        Logger.warning("[IPManager] Failed to parse route IPs for #{ifname}")
        err
    end
  end

  defp apply_dns(ifname, settings) do
    dns_strings =
      [settings[:ipv4_primary_dns], settings[:ipv4_secondary_dns]]
      |> Enum.reject(&is_nil/1)

    dns_tuples =
      Enum.flat_map(dns_strings, fn s ->
        case parse_ip(s) do
          {:ok, t} -> [t]
          _ -> []
        end
      end)

    if dns_tuples != [] do
      NameResolver.setup(ifname, nil, dns_tuples)
    end

    :ok
  end

  # -- Tear down -------------------------------------------------------------

  defp tear_down(ifname) do
    _ = Command.cmd("ifconfig", [ifname, "0.0.0.0"], stderr_to_stdout: true)
    RouteManager.clear_route(ifname)
    NameResolver.clear(ifname)
    :ok
  end

  # -- Helpers ---------------------------------------------------------------

  @arphrd_ether 1

  # Returns true when the network interface is NOT an Ethernet-type device,
  # i.e. raw-IP (ARPHRD_NONE=519, ARPHRD_RAWIP=530, etc.).  These interfaces
  # require a point-to-point peer address to deliver packets.
  defp pointopoint_interface?(ifname) do
    path = "/sys/class/net/#{ifname}/type"

    case File.read(path) do
      {:ok, contents} ->
        case Integer.parse(String.trim(contents)) do
          {type, _} -> type != @arphrd_ether
          :error -> false
        end

      {:error, _} ->
        false
    end
  end

  defp parse_ip(str) when is_binary(str) do
    str |> String.to_charlist() |> :inet.parse_address()
  end

  defp subnet_mask_to_prefix(mask) when is_binary(mask) do
    {:ok, {a, b, c, d}} = parse_ip(mask)

    <<bits::32>> = <<a, b, c, d>>

    count_leading_ones(bits, 0)
  end

  defp count_leading_ones(0, acc), do: acc

  defp count_leading_ones(bits, acc) when bits > 0 do
    if Bitwise.band(bits, 0x80000000) != 0 do
      count_leading_ones(Bitwise.bsl(Bitwise.band(bits, 0x7FFFFFFF), 1), acc + 1)
    else
      acc
    end
  end
end
