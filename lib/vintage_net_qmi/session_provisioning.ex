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

  def init(args) do
    ifname = Keyword.fetch!(args, :ifname)

    state = %{
      ifname: ifname,
      qmi: VintageNetQMI.qmi_name(ifname),
      slot_id: nil,
      application_id: nil,
      active: false
    }

    card_status = UserIdentity.get_cards_status(state.qmi)
    Logger.warning("[VintageNetQMI] Card status: #{inspect(card_status, limit: :infinity)}")
    {slot_id, application_id} = extract_slot_id_and_application_id(card_status)
    Logger.warning("[VintageNetQMI] SlotID and ApplicationID: #{inspect({slot_id, application_id})}")
    {:ok} = UserIdentity.provision_uim_session(state.qmi, slot_id, application_id)
    {:ok, %{state | active: true, slot_id: slot_id, application_id: application_id}}
  end

  defp extract_slot_id_and_application_id(%{cards: cards}) when is_list(cards) do
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
