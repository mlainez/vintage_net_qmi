# SPDX-FileCopyrightText: 2026 Marc Lainez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.LteAttach do
  @moduledoc """
  Find the profile the modem uses for the LTE initial attach.

  On LTE the attach itself brings up the default bearer with the APN of this
  profile. A data call has to be started on the same profile to reuse that
  bearer: starting it on another profile with the same APN asks the network
  for a second PDN connection, which networks reject (3GPP cause #55).
  """

  @wds_service 0x01
  @get_lte_attach_pdn_list 0x0094
  @tlv_current_pdn_list 0x10

  @doc """
  Return the first profile index of the modem's LTE attach PDN list
  """
  @spec attach_profile_index(QMI.name()) :: {:ok, pos_integer()} | {:error, term()}
  def attach_profile_index(qmi) do
    request = %{
      service_id: @wds_service,
      payload: <<@get_lte_attach_pdn_list::little-16, 0::little-16>>,
      decode: &parse_response/1
    }

    QMI.call(request, qmi)
  end

  @doc """
  Parse a "Get LTE Attach PDN List" response

      iex> VintageNetQMI.LteAttach.parse_response(<<0x94, 0, 13, 0, 2, 4, 0, 0, 0, 0, 0, 16, 3, 0, 1, 3, 0>>)
      {:ok, 3}

      iex> VintageNetQMI.LteAttach.parse_response(<<0x94, 0, 11, 0, 2, 4, 0, 0, 0, 0, 0, 16, 1, 0, 0>>)
      {:error, :no_attach_profile}
  """
  @spec parse_response(binary()) :: {:ok, pos_integer()} | {:error, :no_attach_profile}
  def parse_response(
        <<@get_lte_attach_pdn_list::little-16, size::little-16, tlvs::binary-size(size)>>
      ) do
    case find_tlv(tlvs, @tlv_current_pdn_list) do
      <<count, indexes::binary-size(count * 2), _::binary>> when count > 0 ->
        <<first::little-16, _::binary>> = indexes
        {:ok, first}

      _ ->
        {:error, :no_attach_profile}
    end
  end

  def parse_response(_other), do: {:error, :no_attach_profile}

  defp find_tlv(<<type, len::little-16, value::binary-size(len), _::binary>>, type), do: value

  defp find_tlv(<<_type, len::little-16, _value::binary-size(len), rest::binary>>, type),
    do: find_tlv(rest, type)

  defp find_tlv(_, _type), do: nil
end
