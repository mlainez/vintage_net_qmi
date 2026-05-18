# SPDX-FileCopyrightText: 2025 Marc Lainez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.SessionProvisioning do
  @moduledoc false
  require Logger

  use GenServer
  alias QMI.UserIdentity

  def start_link(args) do
    ifname = Keyword.fetch!(args, :ifname)
    GenServer.start_link(__MODULE__, args, name: name(ifname))
  end

  defp name(ifname) do
    Module.concat(__MODULE__, ifname)
  end

  @impl GenServer
  def init(args) do
    ifname = Keyword.fetch!(args, :ifname)

    state = %{
      ifname: ifname,
      qmi: VintageNetQMI.qmi_name(ifname),
      slot_id: nil,
      application_id: nil,
      active: false
    }

    {:ok, state, {:continue, :provision}}
  end

  # On a cold boot some Qualcomm modems (FP3+/msm8953) need 10-30 s
  # after `SET_OPERATING_MODE=ONLINE` before the UIM service can read
  # the SIM. `GET_CARD_STATUS` returns `card_state=0` (absent) the
  # whole time. Retry until a card with at least one application
  # actually shows up, otherwise we permanently lose the boot race
  # and `READ_TRANSPARENT` keeps failing with `:internal` because no
  # session was ever provisioned.
  @retry_after_ms 3_000

  @impl GenServer
  def handle_continue(:provision, state) do
    do_provision(state)
  end

  @impl GenServer
  def handle_info(:retry_provision, state) do
    do_provision(state)
  end

  defp do_provision(state) do
    card_status = UserIdentity.get_cards_status(state.qmi)
    Logger.debug("[VintageNetQMI] Card status: #{inspect(card_status, limit: :infinity)}")

    case extract_slot_id_and_application_id(card_status) do
      {nil, nil} ->
        Logger.warning("[VintageNetQMI] No SIM card found, retrying")
        Process.send_after(self(), :retry_provision, @retry_after_ms)
        {:noreply, state}

      {_slot_id, nil} ->
        Logger.warning("[VintageNetQMI] No application found, retrying")
        Process.send_after(self(), :retry_provision, @retry_after_ms)
        {:noreply, state}

      {slot_id, application_id} ->
        :ok = UserIdentity.provision_uim_session(state.qmi, slot_id, application_id)
        {:noreply, %{state | slot_id: slot_id, application_id: application_id, active: true}}
    end
  end

  defp extract_slot_id_and_application_id({:ok, %{cards: cards}}) when is_list(cards) do
    case Enum.find(cards, fn card -> card.card_state == 1 end) do
      nil ->
        {nil, nil}

      %{slot_id: slot_id, applications: [%{aid: aid} | _]} ->
        {slot_id, aid}

      %{slot_id: slot_id} ->
        {slot_id, nil}
    end
  end

  defp extract_slot_id_and_application_id(_), do: {nil, nil}
end
