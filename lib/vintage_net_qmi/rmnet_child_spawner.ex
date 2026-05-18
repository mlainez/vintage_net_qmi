# SPDX-FileCopyrightText: 2026 Marc Lainez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.RmnetChildSpawner do
  @moduledoc """
  Polls for the parent IPA netdev and creates the configured rmnet
  child netdev once the parent appears.

  Lives under `VintageNetQMI.Application` so the child netdev exists
  by the time `VintageNet`'s interface state machine starts handling
  it. Idempotent across reboots — `RmnetLink.ensure_child/3` is a
  no-op when the child already exists.
  """

  use GenServer
  require Logger

  alias VintageNetQMI.RmnetLink

  @poll_interval 1_000
  @max_attempts 30

  def start_link(specs) do
    GenServer.start_link(__MODULE__, specs, name: __MODULE__)
  end

  @impl GenServer
  def init(specs) do
    state = %{
      pending:
        Enum.map(specs, fn {child, parent, mux_id} ->
          %{child: child, parent: parent, mux_id: mux_id, attempts: 0}
        end)
    }

    send(self(), :tick)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    still_pending =
      Enum.flat_map(state.pending, fn entry ->
        case try_create(entry) do
          :done -> []
          {:retry, updated} -> [updated]
        end
      end)

    if still_pending != [], do: Process.send_after(self(), :tick, @poll_interval)
    {:noreply, %{state | pending: still_pending}}
  end

  defp try_create(%{child: child, parent: parent, mux_id: mux_id, attempts: n} = entry) do
    cond do
      not RmnetLink.interface_exists?(parent) and n >= @max_attempts ->
        Logger.warning(
          "[VintageNetQMI] giving up on rmnet child #{child}: parent #{parent} never appeared"
        )

        :done

      not RmnetLink.interface_exists?(parent) ->
        {:retry, %{entry | attempts: n + 1}}

      RmnetLink.interface_exists?(child) ->
        :done

      true ->
        case RmnetLink.ensure_child(parent, child, mux_id) do
          :ok ->
            Logger.info(
              "[VintageNetQMI] created rmnet child #{child} over #{parent} (mux_id=#{mux_id})"
            )

            ensure_parent_up(parent)

            :done

          {:error, reason} ->
            Logger.warning(
              "[VintageNetQMI] failed to create rmnet child #{child}: #{inspect(reason)}"
            )

            {:retry, %{entry | attempts: n + 1}}
        end
    end
  end

  # Without this the parent IPA netdev's operstate sits at DOWN even
  # though `flags & IFF_UP` is set — the kernel rmnet driver then
  # marks every newly created child `M-DOWN`, and every outgoing QMAP
  # frame is dropped at rmnet_ipa0's tx queue (visible as `tx_drop` in
  # `/proc/net/dev`). `ip link` doesn't expose `add` on busybox, but
  # `RTM_NEWLINK` with `IFF_UP` does the job.
  defp ensure_parent_up(parent) do
    case RmnetLink.set_up(parent) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("[VintageNetQMI] failed to bring up #{parent}: #{inspect(reason)}")
        :ok
    end
  end
end
