# SPDX-FileCopyrightText: 2026 Marc Lainez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.Profiles do
  @moduledoc false

  # Choosing and filling 3GPP profiles, following ModemManager.
  #
  # On LTE the attach brings up the default bearer with the settings of the
  # attach profile (the "initial EPS bearer"). A data call for the same APN
  # has to run on that profile to reuse the bearer: on any other profile the
  # modem asks the network for a second PDN on the same APN, which networks
  # reject (ESM cause 55). A data call for another APN gets a profile of its
  # own, so the attach profile and the modem's other profiles stay untouched.

  @typedoc """
  The settings a profile should hold: a service provider or the initial EPS
  bearer configuration
  """
  @type wanted() :: %{
          required(:apn) => String.t(),
          optional(:pdp_type) => atom(),
          optional(:username) => String.t(),
          optional(:password) => String.t(),
          optional(:auth_method) => atom(),
          optional(:roaming_allowed?) => boolean(),
          optional(atom()) => any()
        }

  @typedoc "A profile as read from the modem, with its index"
  @type profile() :: %{required(:index) => pos_integer(), optional(atom()) => any()}

  @type kind() :: :configured | :attach | :existing
  @type choice() :: {kind(), pos_integer()} | :create

  @doc """
  Pick the profile for a data call on `apn`

  In order: the configured `:profile_index`; the attach profile when it holds
  the same APN, or when `:prefer_attach?` is set; another profile that holds
  the APN; otherwise a profile has to be created.
  """
  @spec select(String.t(), [profile()], pos_integer() | nil, keyword()) :: choice()
  def select(apn, profiles, attach_index, opts \\ []) do
    attach = find(profiles, attach_index)
    existing = Enum.find(profiles, &(&1.index != attach_index and apn_matches?(&1, apn)))

    cond do
      is_integer(opts[:profile_index]) -> {:configured, opts[:profile_index]}
      attach_index != nil and opts[:prefer_attach?] == true -> {:attach, attach_index}
      apn_matches?(attach, apn) -> {:attach, attach_index}
      existing != nil -> {:existing, existing.index}
      true -> :create
    end
  end

  @doc """
  Whether a profile already holds the wanted settings

  APNs compare case-insensitively, as networks treat them. Only the settings
  that are given are compared.
  """
  @spec up_to_date?(profile() | map() | nil, wanted()) :: boolean()
  def up_to_date?(nil, _wanted), do: false

  def up_to_date?(profile, wanted) do
    apn_matches?(profile, wanted.apn) and
      Enum.all?(settings(wanted), fn
        {:apn, _} -> true
        {key, value} -> Map.get(profile, key) == value
      end)
  end

  @doc """
  The profile settings to write for the wanted settings
  """
  @spec settings(wanted()) :: keyword()
  def settings(wanted) do
    roaming =
      case Map.get(wanted, :roaming_allowed?) do
        nil -> []
        allowed? -> [roaming_disallowed: !allowed?]
      end

    pdp =
      case Map.get(wanted, :pdp_type) do
        nil -> []
        pdp_type -> [pdp_type: pdp_type]
      end

    [apn: wanted.apn] ++ auth_settings(wanted) ++ pdp ++ roaming
  end

  defp auth_settings(wanted) do
    username = Map.get(wanted, :username)
    password = Map.get(wanted, :password)
    auth_method = Map.get(wanted, :auth_method)

    cond do
      is_binary(username) and is_binary(password) ->
        [username: username, password: password, auth_method: auth_method || :pap_or_chap]

      is_binary(username) ->
        [username: username, auth_method: auth_method || :none]

      is_binary(password) ->
        [password: password, auth_method: auth_method || :none]

      auth_method != nil ->
        [auth_method: auth_method]

      true ->
        []
    end
  end

  @doc """
  The IP family to request for a PDP type
  """
  @spec ip_family(wanted()) :: 4 | 6
  def ip_family(%{pdp_type: :ipv6}), do: 6
  def ip_family(_wanted), do: 4

  defp find(_profiles, nil), do: nil
  defp find(profiles, index), do: Enum.find(profiles, &(&1.index == index))

  defp apn_matches?(%{apn: apn}, wanted)
       when is_binary(apn) and is_binary(wanted) and apn != "" do
    String.downcase(apn) == String.downcase(wanted)
  end

  defp apn_matches?(_profile, _wanted), do: false
end
