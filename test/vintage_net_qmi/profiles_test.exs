# SPDX-FileCopyrightText: 2026 Marc Lainez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.ProfilesTest do
  use ExUnit.Case, async: true

  alias VintageNetQMI.Profiles

  # The profiles of a Qualcomm MSM8974 modem: 3 is its LTE attach profile
  @profiles [
    %{index: 1, profile_name: "profile1", apn: "", pdp_type: :ipv4v6},
    %{index: 2, profile_name: "profile2", apn: "", pdp_type: :ipv4v6},
    %{index: 3, profile_name: "qdp_profile_ia", apn: "fixedip.m2m", pdp_type: :ipv4}
  ]

  describe "select/4" do
    test "uses the attach profile when it holds the APN" do
      assert {:attach, 3} == Profiles.select("fixedip.m2m", @profiles, 3)
    end

    test "matches APNs case-insensitively" do
      assert {:attach, 3} == Profiles.select("FixedIP.M2M", @profiles, 3)
    end

    test "uses another profile that holds the APN" do
      profiles = @profiles ++ [%{index: 4, apn: "simbase"}]

      assert {:existing, 4} == Profiles.select("simbase", profiles, 3)
    end

    test "creates a profile when none holds the APN" do
      assert :create == Profiles.select("simbase", @profiles, 3)
    end

    test "does not reuse a profile with an empty APN" do
      assert :create == Profiles.select("", @profiles, nil)
    end

    test "prefers the attach profile when asked, whatever its APN" do
      assert {:attach, 3} == Profiles.select("simbase", @profiles, 3, prefer_attach?: true)
    end

    test "ignores prefer_attach? without an attach profile" do
      assert :create == Profiles.select("simbase", @profiles, nil, prefer_attach?: true)
    end

    test "a configured profile index wins" do
      assert {:configured, 2} == Profiles.select("fixedip.m2m", @profiles, 3, profile_index: 2)
    end

    test "works without an attach profile" do
      profiles = [%{index: 1, apn: "fixedip.m2m"}]

      assert {:existing, 1} == Profiles.select("fixedip.m2m", profiles, nil)
    end
  end

  describe "up_to_date?/2" do
    test "true when the given settings match" do
      assert Profiles.up_to_date?(Enum.at(@profiles, 2), %{apn: "fixedip.m2m", pdp_type: :ipv4})
    end

    test "false when the PDP type differs" do
      refute Profiles.up_to_date?(Enum.at(@profiles, 2), %{apn: "fixedip.m2m", pdp_type: :ipv4v6})
    end

    test "false when the roaming flag differs" do
      profile = %{apn: "fixedip.m2m", roaming_disallowed: true}

      refute Profiles.up_to_date?(profile, %{apn: "fixedip.m2m", roaming_allowed?: true})
      assert Profiles.up_to_date?(profile, %{apn: "fixedip.m2m", roaming_allowed?: false})
    end

    test "false for a missing profile or another APN" do
      refute Profiles.up_to_date?(nil, %{apn: "a"})
      refute Profiles.up_to_date?(%{apn: "b"}, %{apn: "a"})
    end
  end

  describe "settings/1" do
    test "APN only" do
      assert [apn: "simbase"] == Profiles.settings(%{apn: "simbase"})
    end

    test "everything" do
      wanted = %{
        apn: "a",
        username: "u",
        password: "p",
        pdp_type: :ipv4,
        roaming_allowed?: true
      }

      assert [
               apn: "a",
               username: "u",
               password: "p",
               auth_method: :pap_or_chap,
               pdp_type: :ipv4,
               roaming_disallowed: false
             ] == Profiles.settings(wanted)
    end
  end

  test "ip_family/1" do
    assert 6 == Profiles.ip_family(%{apn: "a", pdp_type: :ipv6})
    assert 4 == Profiles.ip_family(%{apn: "a", pdp_type: :ipv4v6})
    assert 4 == Profiles.ip_family(%{apn: "a"})
  end
end
