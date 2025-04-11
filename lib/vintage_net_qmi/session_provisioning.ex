defmodule VintageNetQMI.SessionProvisioning do
  @moduledoc false

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
    state = %__MODULE__{
      ifname: ifname,
      qmi: VintageNetQMI.qmi_name(ifname),
      slot_id: nil,
      application_id: nil,
      active: false
    }

    card_status = UserIdentity.get_card_status(stat.qmi)
    {slot_id, application_id} = extract_slot_id_and_application_id(card_status)
    {:ok} = UserIdentity.provision_uim_session(slot_id, application_id)
    {:ok, state | %{active: true, slot_id: slot_id, application_id: application_id}}
  end

  defp extract_slot_id_and_application_id(card_status) do
    case Enum.find(card_status.cards, fn card -> card.card_state == 1 end) do
      nil ->
        {nil, nil}

      %{slot_id: slot_id, applications: [%{aid: aid} | _]} ->
        {slot_id, aid}

      %{slot_id: slot_id} ->
        {slot_id, nil}
    end
  end
end
