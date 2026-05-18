# SPDX-FileCopyrightText: 2026 Marc Lainez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children =
      case configured_rmnet_children() do
        [] -> []
        specs -> [{VintageNetQMI.RmnetChildSpawner, specs}]
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: VintageNetQMI.Supervisor)
  end

  # Scan the runtime VintageNet config for any VintageNetQMI-typed
  # interfaces that declare a `:rmnet_child` block. Returns a list of
  # `{child_ifname, parent_ifname, mux_id}` tuples ready to be created
  # by `RmnetLink`.
  defp configured_rmnet_children do
    Application.get_env(:vintage_net, :config, [])
    |> Enum.flat_map(fn
      {ifname, %{type: VintageNetQMI, vintage_net_qmi: %{rmnet_child: %{} = rc}}} ->
        with parent when is_binary(parent) <- Map.get(rc, :parent),
             mux_id when is_integer(mux_id) <- Map.get(rc, :mux_id) do
          [{ifname, parent, mux_id}]
        else
          _ -> []
        end

      _ ->
        []
    end)
  end
end
