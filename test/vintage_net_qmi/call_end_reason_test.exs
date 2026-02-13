# SPDX-FileCopyrightText: 2025 Marc Laínez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.CallEndReasonTest do
  use ExUnit.Case, async: true

  alias VintageNetQMI.CallEndReason

  describe "describe/2" do
    test "returns description for 3GPP regular deactivation" do
      assert CallEndReason.describe(:three_gpp_specification_defined, 36) ==
               "Regular deactivation"
    end

    test "returns description for 3GPP unknown APN" do
      assert CallEndReason.describe(:three_gpp_specification_defined, 27) ==
               "Unknown or missing APN"
    end

    test "returns description for 3GPP authentication failed" do
      assert CallEndReason.describe(:three_gpp_specification_defined, 29) ==
               "Authentication failed"
    end

    test "returns description for internal network initiated termination" do
      assert CallEndReason.describe(:internal, 206) == "Network initiated termination"
    end

    test "returns description for internal modem restart" do
      assert CallEndReason.describe(:internal, 212) == "Modem restart"
    end

    test "returns description for internal APN disabled" do
      assert CallEndReason.describe(:internal, 220) == "APN disabled"
    end

    test "returns description for unspecified generic reasons" do
      assert CallEndReason.describe(:unspecified, 1) == "Unspecified"
      assert CallEndReason.describe(:unspecified, 3) == "No service"
      assert CallEndReason.describe(:unspecified, 10) == "Authentication failed"
    end

    test "returns description for mobile IP reasons" do
      assert CallEndReason.describe(:mobile_ip, -1) == "Unknown reason"
      assert CallEndReason.describe(:mobile_ip, 65) == "FA error: administratively prohibited"

      assert CallEndReason.describe(:mobile_ip, 131) ==
               "HA error: mobile node authentication failure"
    end

    test "returns description for call manager reasons" do
      assert CallEndReason.describe(:call_manager_defined, 2001) == "No service"
      assert CallEndReason.describe(:call_manager_defined, 1029) == "EMM attach failed"
      assert CallEndReason.describe(:call_manager_defined, 2504) == "Invalid SIM state"
    end

    test "returns description for PPP reasons" do
      assert CallEndReason.describe(:ppp, 1) == "Timeout"
      assert CallEndReason.describe(:ppp, 2) == "Authentication failure"
      assert CallEndReason.describe(:ppp, 32) == "CHAP failure"
    end

    test "returns description for eHRPD reasons" do
      assert CallEndReason.describe(:ehrpd, 1) == "Subscription limited to IPv4"
      assert CallEndReason.describe(:ehrpd, 7) == "VSNCP 3GPP2 unauthenticated APN"
    end

    test "returns description for IPv6 reasons" do
      assert CallEndReason.describe(:ipv6, 1) == "Prefix unavailable"
      assert CallEndReason.describe(:ipv6, 3) == "IPv6 disabled"
    end

    test "returns unknown for unrecognized type/code" do
      assert CallEndReason.describe(:handoff, 42) == "Unknown (:handoff 42)"
      assert CallEndReason.describe(:internal, 9999) == "Unknown (:internal 9999)"
    end

    test "handles {:unknown, id} tuples from driver catch-all" do
      assert CallEndReason.describe({:unknown, 0xFF}, 123) ==
               "Unknown ({:unknown, 255} 123)"
    end
  end

  describe "type_name/1" do
    test "returns human-readable names for all known types" do
      assert CallEndReason.type_name(:unspecified) == "Unspecified"
      assert CallEndReason.type_name(:mobile_ip) == "Mobile IP"
      assert CallEndReason.type_name(:internal) == "Internal"
      assert CallEndReason.type_name(:call_manager_defined) == "Call Manager"
      assert CallEndReason.type_name(:three_gpp_specification_defined) == "3GPP"
      assert CallEndReason.type_name(:ppp) == "PPP"
      assert CallEndReason.type_name(:ehrpd) == "eHRPD"
      assert CallEndReason.type_name(:ipv6) == "IPv6"
      assert CallEndReason.type_name(:handoff) == "Handoff"
    end

    test "handles {:unknown, id} tuples" do
      assert CallEndReason.type_name({:unknown, 0xFF}) == "Unknown type (255)"
    end
  end

  describe "format/2" do
    test "returns formatted string with type name, description, and code" do
      assert CallEndReason.format(:three_gpp_specification_defined, 36) ==
               "3GPP: Regular deactivation (36)"
    end

    test "format includes code for internal reasons" do
      assert CallEndReason.format(:internal, 206) ==
               "Internal: Network initiated termination (206)"
    end

    test "format works for unknown codes" do
      assert CallEndReason.format(:ppp, 999) ==
               "PPP: Unknown (:ppp 999) (999)"
    end
  end
end
