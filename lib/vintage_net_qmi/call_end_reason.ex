# SPDX-FileCopyrightText: 2025 Marc Laínez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.CallEndReason do
  @moduledoc """
  Lookup tables for QMI verbose call end reasons.

  Translates raw `call_end_reason` integers into human-readable descriptions,
  organized by `call_end_reason_type`. The descriptions are derived from the
  libqmi C header enums (`qmi-enums-wds.h`).

  ## Usage

      iex> VintageNetQMI.CallEndReason.describe(:three_gpp_specification_defined, 36)
      "Regular deactivation"

      iex> VintageNetQMI.CallEndReason.describe(:internal, 206)
      "Network initiated termination"

  """

  @doc """
  Returns a human-readable description for a call end reason.

  Takes the `call_end_reason_type` atom and the `call_end_reason` integer
  as parsed by the QMI codec, and returns a descriptive string.

  Returns `"Unknown (<type> <code>)"` for unrecognized type/code combinations.
  """
  @spec describe(atom(), integer()) :: String.t()
  def describe(type, code)

  # ── Unspecified (generic call end reasons) ──────────────────────────────────

  def describe(:unspecified, 1), do: "Unspecified"
  def describe(:unspecified, 2), do: "Client end"
  def describe(:unspecified, 3), do: "No service"
  def describe(:unspecified, 4), do: "Fade"
  def describe(:unspecified, 5), do: "Release normal"
  def describe(:unspecified, 6), do: "Access attempt in progress"
  def describe(:unspecified, 7), do: "Access failure"
  def describe(:unspecified, 8), do: "Redirection or handoff"
  def describe(:unspecified, 9), do: "Close in progress"
  def describe(:unspecified, 10), do: "Authentication failed"
  def describe(:unspecified, 11), do: "Internal error"

  # CDMA-specific (part of the generic/unspecified enum)
  def describe(:unspecified, 500), do: "CDMA lock"
  def describe(:unspecified, 501), do: "CDMA intercept"
  def describe(:unspecified, 502), do: "CDMA reorder"
  def describe(:unspecified, 503), do: "CDMA release SO reject"
  def describe(:unspecified, 504), do: "CDMA incoming call"
  def describe(:unspecified, 505), do: "CDMA alert stop"
  def describe(:unspecified, 506), do: "CDMA activation"
  def describe(:unspecified, 507), do: "CDMA max access probes"
  def describe(:unspecified, 508), do: "CDMA CCS not supported by BS"
  def describe(:unspecified, 509), do: "CDMA no response from BS"
  def describe(:unspecified, 510), do: "CDMA rejected by BS"
  def describe(:unspecified, 511), do: "CDMA incompatible"
  def describe(:unspecified, 512), do: "CDMA already in TC"
  def describe(:unspecified, 513), do: "CDMA user call originated during GPS"
  def describe(:unspecified, 514), do: "CDMA user call originated during SMS"
  def describe(:unspecified, 515), do: "CDMA no service"

  # GSM/WCDMA-specific (part of the generic/unspecified enum)
  def describe(:unspecified, 1000), do: "GSM/WCDMA conference failed"
  def describe(:unspecified, 1001), do: "GSM/WCDMA incoming rejected"
  def describe(:unspecified, 1002), do: "GSM/WCDMA no service"
  def describe(:unspecified, 1003), do: "GSM/WCDMA network end"
  def describe(:unspecified, 1004), do: "GSM/WCDMA LLC SNDCP failure"
  def describe(:unspecified, 1005), do: "GSM/WCDMA insufficient resources"
  def describe(:unspecified, 1006), do: "GSM/WCDMA option temporarily out of order"
  def describe(:unspecified, 1007), do: "GSM/WCDMA NSAPI already used"
  def describe(:unspecified, 1008), do: "GSM/WCDMA regular deactivation"
  def describe(:unspecified, 1009), do: "GSM/WCDMA network failure"
  def describe(:unspecified, 1010), do: "GSM/WCDMA reattach required"
  def describe(:unspecified, 1011), do: "GSM/WCDMA protocol error"
  def describe(:unspecified, 1012), do: "GSM/WCDMA operator-determined barring"
  def describe(:unspecified, 1013), do: "GSM/WCDMA unknown APN"
  def describe(:unspecified, 1014), do: "GSM/WCDMA unknown PDP"
  def describe(:unspecified, 1015), do: "GSM/WCDMA GGSN reject"
  def describe(:unspecified, 1016), do: "GSM/WCDMA activation reject"
  def describe(:unspecified, 1017), do: "GSM/WCDMA option not supported"
  def describe(:unspecified, 1018), do: "GSM/WCDMA option unsubscribed"
  def describe(:unspecified, 1019), do: "GSM/WCDMA QoS not accepted"
  def describe(:unspecified, 1020), do: "GSM/WCDMA TFT semantic error"
  def describe(:unspecified, 1021), do: "GSM/WCDMA TFT syntax error"
  def describe(:unspecified, 1022), do: "GSM/WCDMA unknown PDP context"
  def describe(:unspecified, 1023), do: "GSM/WCDMA filter semantic error"
  def describe(:unspecified, 1024), do: "GSM/WCDMA filter syntax error"
  def describe(:unspecified, 1025), do: "GSM/WCDMA PDP without active TFT"
  def describe(:unspecified, 1026), do: "GSM/WCDMA invalid transaction ID"
  def describe(:unspecified, 1027), do: "GSM/WCDMA message incorrect semantic"
  def describe(:unspecified, 1028), do: "GSM/WCDMA invalid mandatory info"
  def describe(:unspecified, 1029), do: "GSM/WCDMA message type unsupported"
  def describe(:unspecified, 1030), do: "GSM/WCDMA message type noncompatible state"
  def describe(:unspecified, 1031), do: "GSM/WCDMA unknown info element"
  def describe(:unspecified, 1032), do: "GSM/WCDMA conditional IE error"
  def describe(:unspecified, 1033), do: "GSM/WCDMA message and protocol state uncompatible"
  def describe(:unspecified, 1034), do: "GSM/WCDMA APN type conflict"
  def describe(:unspecified, 1035), do: "GSM/WCDMA no GPRS context"
  def describe(:unspecified, 1036), do: "GSM/WCDMA feature not supported"

  # EVDO-specific (part of the generic/unspecified enum)
  def describe(:unspecified, 1500), do: "EVDO connection deny: general or busy"
  def describe(:unspecified, 1501), do: "EVDO connection deny: billing or authentication failure"
  def describe(:unspecified, 1502), do: "EVDO HDR change"
  def describe(:unspecified, 1503), do: "EVDO HDR exit"
  def describe(:unspecified, 1504), do: "EVDO HDR no session"
  def describe(:unspecified, 1505), do: "EVDO HDR origination during GPS fix"
  def describe(:unspecified, 1506), do: "EVDO HDR connection setup timeout"
  def describe(:unspecified, 1507), do: "EVDO HDR released by CM"

  # ── Mobile IP (MIP) ────────────────────────────────────────────────────────

  def describe(:mobile_ip, -1), do: "Unknown reason"

  def describe(:mobile_ip, 64), do: "FA error: reason unspecified"
  def describe(:mobile_ip, 65), do: "FA error: administratively prohibited"
  def describe(:mobile_ip, 66), do: "FA error: insufficient resources"
  def describe(:mobile_ip, 67), do: "FA error: mobile node authentication failure"
  def describe(:mobile_ip, 68), do: "FA error: HA authentication failure"
  def describe(:mobile_ip, 69), do: "FA error: requested lifetime too long"
  def describe(:mobile_ip, 70), do: "FA error: malformed request"
  def describe(:mobile_ip, 71), do: "FA error: malformed reply"
  def describe(:mobile_ip, 72), do: "FA error: encapsulation unavailable"
  def describe(:mobile_ip, 73), do: "FA error: VJHC unavailable"
  def describe(:mobile_ip, 74), do: "FA error: reverse tunnel unavailable"
  def describe(:mobile_ip, 75), do: "FA error: reverse tunnel mandatory and T bit not set"
  def describe(:mobile_ip, 79), do: "FA error: delivery style not supported"
  def describe(:mobile_ip, 97), do: "FA error: missing NAI"
  def describe(:mobile_ip, 98), do: "FA error: missing HA"
  def describe(:mobile_ip, 99), do: "FA error: missing home address"
  def describe(:mobile_ip, 104), do: "FA error: unknown challenge"
  def describe(:mobile_ip, 105), do: "FA error: missing challenge"
  def describe(:mobile_ip, 106), do: "FA error: stale challenge"

  def describe(:mobile_ip, 128), do: "HA error: reason unspecified"
  def describe(:mobile_ip, 129), do: "HA error: administratively prohibited"
  def describe(:mobile_ip, 130), do: "HA error: insufficient resources"
  def describe(:mobile_ip, 131), do: "HA error: mobile node authentication failure"
  def describe(:mobile_ip, 132), do: "HA error: FA authentication failure"
  def describe(:mobile_ip, 133), do: "HA error: registration ID mismatch"
  def describe(:mobile_ip, 134), do: "HA error: malformed request"
  def describe(:mobile_ip, 136), do: "HA error: unknown HA address"
  def describe(:mobile_ip, 137), do: "HA error: reverse tunnel unavailable"
  def describe(:mobile_ip, 138), do: "HA error: reverse tunnel mandatory and T bit not set"
  def describe(:mobile_ip, 139), do: "HA error: encapsulation unavailable"

  # ── Internal ────────────────────────────────────────────────────────────────

  def describe(:internal, 201), do: "Internal error"
  def describe(:internal, 202), do: "Call ended"
  def describe(:internal, 203), do: "Unknown internal cause"
  def describe(:internal, 204), do: "Unknown cause"
  def describe(:internal, 205), do: "Close in progress"
  def describe(:internal, 206), do: "Network initiated termination"
  def describe(:internal, 207), do: "App preempted"
  def describe(:internal, 208), do: "PDN IPv4 call disallowed"
  def describe(:internal, 209), do: "PDN IPv4 call throttled"
  def describe(:internal, 210), do: "PDN IPv6 call disallowed"
  def describe(:internal, 211), do: "PDN IPv6 call throttled"
  def describe(:internal, 212), do: "Modem restart"
  def describe(:internal, 213), do: "PDP PPP not supported"
  def describe(:internal, 214), do: "Unpreferred RAT"
  def describe(:internal, 215), do: "Physical link close in progress"
  def describe(:internal, 216), do: "APN pending handover"
  def describe(:internal, 217), do: "Profile bearer incompatible"
  def describe(:internal, 218), do: "MMGDSI card event"
  def describe(:internal, 219), do: "LPM or power down"
  def describe(:internal, 220), do: "APN disabled"
  def describe(:internal, 221), do: "MPIT expired"
  def describe(:internal, 222), do: "IPv6 address transfer failed"
  def describe(:internal, 223), do: "TRAT swap failed"
  def describe(:internal, 224), do: "eHRPD to HRPD fallback"
  def describe(:internal, 225), do: "Mandatory APN disabled"
  def describe(:internal, 226), do: "MIP config failure"
  def describe(:internal, 227), do: "PDN inactivity timer expired"
  def describe(:internal, 228), do: "Max IPv4 connections"
  def describe(:internal, 229), do: "Max IPv6 connections"
  def describe(:internal, 230), do: "APN mismatch"
  def describe(:internal, 231), do: "IP version mismatch"
  def describe(:internal, 232), do: "DUN call disallowed"
  def describe(:internal, 233), do: "Invalid profile"
  def describe(:internal, 234), do: "EPC to non-EPC transition"
  def describe(:internal, 235), do: "Invalid profile ID"
  def describe(:internal, 236), do: "Call already present"
  def describe(:internal, 237), do: "Interface in use"
  def describe(:internal, 238), do: "IP PDP mismatch"
  def describe(:internal, 239), do: "APN disallowed on roaming"
  def describe(:internal, 240), do: "APN parameter change"
  def describe(:internal, 241), do: "Interface in use config match"
  def describe(:internal, 242), do: "NULL APN disallowed"
  def describe(:internal, 243), do: "Thermal mitigation"
  def describe(:internal, 244), do: "Subs ID mismatch"
  def describe(:internal, 245), do: "Data settings disabled"
  def describe(:internal, 246), do: "Data roaming settings disabled"
  def describe(:internal, 247), do: "APN format invalid"
  def describe(:internal, 248), do: "DDS call abort"
  def describe(:internal, 249), do: "Validation failure"
  def describe(:internal, 251), do: "Profiles not compatible"
  def describe(:internal, 252), do: "Null resolved APN no match"
  def describe(:internal, 253), do: "Invalid APN name"
  def describe(:internal, 254), do: "DDS switch in progress"
  def describe(:internal, 255), do: "Call disallowed in roaming"
  def describe(:internal, 256), do: "MO exceptional not supported"
  def describe(:internal, 257), do: "Non-IP not supported"
  def describe(:internal, 258), do: "PDN non-IP call throttled"
  def describe(:internal, 259), do: "PDN non-IP call disallowed"
  def describe(:internal, 261), do: "Non-IP type mismatch"
  def describe(:internal, 262), do: "Max NB PDN reached"
  def describe(:internal, 263), do: "Invalid APN"
  def describe(:internal, 264), do: "Slice not allowed"
  def describe(:internal, 265), do: "Routing failure"
  def describe(:internal, 266), do: "Routing changed"
  def describe(:internal, 267), do: "LADN DNN not available"
  def describe(:internal, 268), do: "APN type mismatch"

  # ── Call Manager (CM) ───────────────────────────────────────────────────────

  # CDMA-specific CM reasons
  def describe(:call_manager_defined, 500), do: "CDMA lock"
  def describe(:call_manager_defined, 501), do: "Intercept"
  def describe(:call_manager_defined, 502), do: "Reorder"
  def describe(:call_manager_defined, 503), do: "Release SO reject"
  def describe(:call_manager_defined, 504), do: "Incoming call"
  def describe(:call_manager_defined, 505), do: "Alert stop"
  def describe(:call_manager_defined, 506), do: "Activation"
  def describe(:call_manager_defined, 507), do: "Max access probes"
  def describe(:call_manager_defined, 508), do: "CCS not supported by BS"
  def describe(:call_manager_defined, 509), do: "No response from BS"
  def describe(:call_manager_defined, 510), do: "Rejected by BS"
  def describe(:call_manager_defined, 511), do: "Incompatible"
  def describe(:call_manager_defined, 512), do: "Already in TC"
  def describe(:call_manager_defined, 513), do: "User call originated during GPS"
  def describe(:call_manager_defined, 514), do: "User call originated during SMS"
  def describe(:call_manager_defined, 515), do: "No CDMA service"
  def describe(:call_manager_defined, 516), do: "MC abort"
  def describe(:call_manager_defined, 517), do: "Persistence test failure"
  def describe(:call_manager_defined, 518), do: "UIM not present"
  def describe(:call_manager_defined, 519), do: "Retry order"
  def describe(:call_manager_defined, 520), do: "Access block"
  def describe(:call_manager_defined, 521), do: "Access block all"
  def describe(:call_manager_defined, 522), do: "IS-707B max access probes"
  def describe(:call_manager_defined, 523), do: "Thermal emergency"
  def describe(:call_manager_defined, 524), do: "Call origination throttled"
  def describe(:call_manager_defined, 525), do: "User call originated"

  # GW-specific CM reasons
  def describe(:call_manager_defined, 1000), do: "Conference failed"
  def describe(:call_manager_defined, 1001), do: "Incoming rejected"
  def describe(:call_manager_defined, 1002), do: "No gateway service"
  def describe(:call_manager_defined, 1003), do: "No GPRS context"
  def describe(:call_manager_defined, 1004), do: "Illegal MS"
  def describe(:call_manager_defined, 1005), do: "Illegal ME"
  def describe(:call_manager_defined, 1006), do: "GPRS and non-GPRS services not allowed"
  def describe(:call_manager_defined, 1007), do: "GPRS services not allowed"
  def describe(:call_manager_defined, 1008), do: "MS identity not derived by the network"
  def describe(:call_manager_defined, 1009), do: "Implicitly detached"
  def describe(:call_manager_defined, 1010), do: "PLMN not allowed"
  def describe(:call_manager_defined, 1011), do: "LA not allowed"
  def describe(:call_manager_defined, 1012), do: "GPRS services not allowed in PLMN"
  def describe(:call_manager_defined, 1013), do: "PDP duplicate"
  def describe(:call_manager_defined, 1014), do: "UE RAT change"
  def describe(:call_manager_defined, 1015), do: "Congestion"
  def describe(:call_manager_defined, 1016), do: "No PDP context activated"
  def describe(:call_manager_defined, 1017), do: "Access class DSAC rejection"
  def describe(:call_manager_defined, 1018), do: "PDP activate max retry failed"
  def describe(:call_manager_defined, 1019), do: "RAB failure"
  def describe(:call_manager_defined, 1020), do: "EPS service not allowed"
  def describe(:call_manager_defined, 1021), do: "Tracking area not allowed"
  def describe(:call_manager_defined, 1022), do: "Roaming not allowed in tracking area"
  def describe(:call_manager_defined, 1023), do: "No suitable cells in tracking area"
  def describe(:call_manager_defined, 1024), do: "Not authorized closed subscriber group"
  def describe(:call_manager_defined, 1025), do: "ESM unknown EPS bearer context"
  def describe(:call_manager_defined, 1026), do: "DRB released at RRC"
  def describe(:call_manager_defined, 1027), do: "NAS signal connection released"
  def describe(:call_manager_defined, 1028), do: "EMM detached"
  def describe(:call_manager_defined, 1029), do: "EMM attach failed"
  def describe(:call_manager_defined, 1030), do: "EMM attach started"
  def describe(:call_manager_defined, 1031), do: "LTE NAS service request failed"
  def describe(:call_manager_defined, 1032), do: "ESM active dedicated bearer reactivated by NW"
  def describe(:call_manager_defined, 1033), do: "ESM lower layer failure"
  def describe(:call_manager_defined, 1034), do: "ESM sync up with NW"

  def describe(:call_manager_defined, 1035),
    do: "ESM NW activated dedicated bearer with ID of default bearer"

  def describe(:call_manager_defined, 1036), do: "ESM bad OTA message"
  def describe(:call_manager_defined, 1037), do: "ESM DS rejected call"
  def describe(:call_manager_defined, 1038), do: "ESM context transferred due to IRAT"
  def describe(:call_manager_defined, 1039), do: "DS explicit deactivation"
  def describe(:call_manager_defined, 1040), do: "ESM local cause none"
  def describe(:call_manager_defined, 1041), do: "LTE NAS service request failed, no throttle"
  def describe(:call_manager_defined, 1042), do: "ACL failure"
  def describe(:call_manager_defined, 1043), do: "LTE NAS service request failed, DS disallow"
  def describe(:call_manager_defined, 1044), do: "EMM T3417 expired"
  def describe(:call_manager_defined, 1045), do: "EMM T3417 ext expired"

  def describe(:call_manager_defined, 1046),
    do: "LRRC UL data confirmation failure: transaction"

  def describe(:call_manager_defined, 1047), do: "LRRC UL data confirmation failure: handover"

  def describe(:call_manager_defined, 1048),
    do: "LRRC UL data confirmation failure: connection release"

  def describe(:call_manager_defined, 1049), do: "LRRC UL data confirmation failure: RLF"

  def describe(:call_manager_defined, 1050),
    do: "LRRC UL data confirmation failure: ctrl not connected"

  def describe(:call_manager_defined, 1051), do: "LRRC connection establishment failure"
  def describe(:call_manager_defined, 1052), do: "LRRC connection establishment failure: aborted"

  def describe(:call_manager_defined, 1053),
    do: "LRRC connection establishment failure: access barred"

  def describe(:call_manager_defined, 1054),
    do: "LRRC connection establishment failure: cell reselection"

  def describe(:call_manager_defined, 1055),
    do: "LRRC connection establishment failure: config failure"

  def describe(:call_manager_defined, 1056),
    do: "LRRC connection establishment failure: timer expired"

  def describe(:call_manager_defined, 1057),
    do: "LRRC connection establishment failure: link failure"

  def describe(:call_manager_defined, 1058),
    do: "LRRC connection establishment failure: not camped"

  def describe(:call_manager_defined, 1059),
    do: "LRRC connection establishment failure: SI failure"

  def describe(:call_manager_defined, 1060),
    do: "LRRC connection establishment failure: rejected"

  def describe(:call_manager_defined, 1061), do: "LRRC connection release: normal"
  def describe(:call_manager_defined, 1062), do: "LRRC connection release: RLF"
  def describe(:call_manager_defined, 1063), do: "LRRC connection release: CRE failure"

  def describe(:call_manager_defined, 1064),
    do: "LRRC connection release: OOS during CRE"

  def describe(:call_manager_defined, 1065), do: "LRRC connection release: aborted"
  def describe(:call_manager_defined, 1066), do: "LRRC connection release: SIB read error"
  def describe(:call_manager_defined, 1067), do: "Detach with reattach LTE NW detach"
  def describe(:call_manager_defined, 1068), do: "Detach without reattach LTE NW detach"
  def describe(:call_manager_defined, 1069), do: "ESM proc timeout"

  def describe(:call_manager_defined, 1070), do: "Invalid connection ID"
  def describe(:call_manager_defined, 1071), do: "Invalid NSAPI"
  def describe(:call_manager_defined, 1072), do: "Invalid primary NSAPI"
  def describe(:call_manager_defined, 1073), do: "Invalid field"
  def describe(:call_manager_defined, 1074), do: "Radio access bearer setup failure"
  def describe(:call_manager_defined, 1075), do: "PDP establish max timeout"
  def describe(:call_manager_defined, 1076), do: "PDP modify max timeout"
  def describe(:call_manager_defined, 1077), do: "PDP inactive max timeout"
  def describe(:call_manager_defined, 1078), do: "PDP lower layer error"
  def describe(:call_manager_defined, 1079), do: "PPD unknown reason"
  def describe(:call_manager_defined, 1080), do: "PDP modify collision"
  def describe(:call_manager_defined, 1081), do: "PDP MBMS request collision"
  def describe(:call_manager_defined, 1082), do: "MBMS duplicate"
  def describe(:call_manager_defined, 1083), do: "SM PS detached"
  def describe(:call_manager_defined, 1084), do: "SM no radio available"
  def describe(:call_manager_defined, 1085), do: "SM abort service not available"
  def describe(:call_manager_defined, 1086), do: "Message exceeds max L2 limit"
  def describe(:call_manager_defined, 1087), do: "SM NAS service request failure"

  def describe(:call_manager_defined, 1088),
    do: "RRC connection establishment failure: request error"

  def describe(:call_manager_defined, 1089),
    do: "RRC connection establishment failure: TAI change"

  def describe(:call_manager_defined, 1090),
    do: "RRC connection establishment failure: RF unavailable"

  def describe(:call_manager_defined, 1091),
    do: "RRC connection release: aborted inter-RAT success"

  def describe(:call_manager_defined, 1092),
    do: "RRC connection release: RLF security not active"

  def describe(:call_manager_defined, 1093),
    do: "RRC connection release: inter-RAT to LTE aborted"

  def describe(:call_manager_defined, 1094),
    do: "RRC connection release: inter-RAT from LTE to GERAN CCO success"

  def describe(:call_manager_defined, 1095),
    do: "RRC connection release: inter-RAT from LTE to GERAN CCO aborted"

  def describe(:call_manager_defined, 1096), do: "IMSI unknown in home subscriber server"
  def describe(:call_manager_defined, 1097), do: "IMEI not accepted"

  def describe(:call_manager_defined, 1098),
    do: "EPS services and non-EPS services not allowed"

  def describe(:call_manager_defined, 1099), do: "EPS services not allowed in PLMN"
  def describe(:call_manager_defined, 1100), do: "MSC temporarily not reachable"
  def describe(:call_manager_defined, 1101), do: "CS domain not available"
  def describe(:call_manager_defined, 1102), do: "ESM failure"
  def describe(:call_manager_defined, 1103), do: "MAC failure"
  def describe(:call_manager_defined, 1104), do: "Synchronization failure"
  def describe(:call_manager_defined, 1105), do: "UE security capabilities mismatch"
  def describe(:call_manager_defined, 1106), do: "Security mode reject unspecified"
  def describe(:call_manager_defined, 1107), do: "Non-EPS auth unacceptable"

  def describe(:call_manager_defined, 1108),
    do: "CS fallback call establishment not allowed"

  def describe(:call_manager_defined, 1109), do: "No EPS bearer context activated"
  def describe(:call_manager_defined, 1110), do: "EMM invalid state"
  def describe(:call_manager_defined, 1111), do: "NAS layer failure"
  def describe(:call_manager_defined, 1112), do: "Multi-PDN not allowed"
  def describe(:call_manager_defined, 1113), do: "eMBMS not enabled"
  def describe(:call_manager_defined, 1114), do: "Pending redial call cleanup"
  def describe(:call_manager_defined, 1115), do: "eMBMS regular deactivation"
  def describe(:call_manager_defined, 1116), do: "TLB regular deactivation"
  def describe(:call_manager_defined, 1117), do: "Lower layer registration failure"
  def describe(:call_manager_defined, 1118), do: "Detach EPS services not allowed"
  def describe(:call_manager_defined, 1119), do: "SM internal PDP deactivation"

  # HDR-specific CM reasons
  def describe(:call_manager_defined, 1500), do: "Connection deny: general or busy"

  def describe(:call_manager_defined, 1501),
    do: "Connection deny: billing or authentication failure"

  def describe(:call_manager_defined, 1502), do: "HDR change"
  def describe(:call_manager_defined, 1503), do: "HDR exit"
  def describe(:call_manager_defined, 1504), do: "HDR no session"
  def describe(:call_manager_defined, 1505), do: "HDR origination during GPS fix"
  def describe(:call_manager_defined, 1506), do: "HDR connection setup timeout"
  def describe(:call_manager_defined, 1507), do: "HDR released by CM"
  def describe(:call_manager_defined, 1508), do: "HDR collocated acquisition failed"
  def describe(:call_manager_defined, 1509), do: "OTASP commit in progress"
  def describe(:call_manager_defined, 1510), do: "HDR no hybrid service"
  def describe(:call_manager_defined, 1511), do: "HDR no lock granted"
  def describe(:call_manager_defined, 1512), do: "Hold other in progress"
  def describe(:call_manager_defined, 1513), do: "HDR fade"
  def describe(:call_manager_defined, 1514), do: "HDR access failure"
  def describe(:call_manager_defined, 1515), do: "Unsupported 1X prev"

  # Generic CM reasons
  def describe(:call_manager_defined, 2000), do: "Client end"
  def describe(:call_manager_defined, 2001), do: "No service"
  def describe(:call_manager_defined, 2002), do: "Fade"
  def describe(:call_manager_defined, 2003), do: "Release normal"
  def describe(:call_manager_defined, 2004), do: "Access attempt in progress"
  def describe(:call_manager_defined, 2005), do: "Access failure"
  def describe(:call_manager_defined, 2006), do: "Redirection or handoff"

  # Other CM reasons
  def describe(:call_manager_defined, 2500), do: "Offline"
  def describe(:call_manager_defined, 2501), do: "Emergency mode"
  def describe(:call_manager_defined, 2502), do: "Phone in use"
  def describe(:call_manager_defined, 2503), do: "Invalid mode"
  def describe(:call_manager_defined, 2504), do: "Invalid SIM state"
  def describe(:call_manager_defined, 2505), do: "No collocated HDR"
  def describe(:call_manager_defined, 2506), do: "Call control rejected"
  def describe(:call_manager_defined, 2507), do: "EMM detached PSM"
  def describe(:call_manager_defined, 2508), do: "Dual switch"
  def describe(:call_manager_defined, 2509), do: "Call manager"
  def describe(:call_manager_defined, 2510), do: "Invalid class 3 APN"
  def describe(:call_manager_defined, 2511), do: "MPLMN in progress"

  # ── 3GPP specification defined ──────────────────────────────────────────────

  def describe(:three_gpp_specification_defined, 8), do: "Operator-determined barring"
  def describe(:three_gpp_specification_defined, 25), do: "LLC or SNDCP failure"
  def describe(:three_gpp_specification_defined, 26), do: "Insufficient resources"
  def describe(:three_gpp_specification_defined, 27), do: "Unknown or missing APN"
  def describe(:three_gpp_specification_defined, 28), do: "Unknown PDP address or type"
  def describe(:three_gpp_specification_defined, 29), do: "Authentication failed"
  def describe(:three_gpp_specification_defined, 30), do: "Activation rejected by GGSN"
  def describe(:three_gpp_specification_defined, 31), do: "Activation rejected"
  def describe(:three_gpp_specification_defined, 32), do: "Service option not supported"
  def describe(:three_gpp_specification_defined, 33), do: "Service option not subscribed"

  def describe(:three_gpp_specification_defined, 34),
    do: "Service option temporarily out of order"

  def describe(:three_gpp_specification_defined, 35), do: "NSAPI already used"
  def describe(:three_gpp_specification_defined, 36), do: "Regular deactivation"
  def describe(:three_gpp_specification_defined, 37), do: "QoS not accepted"
  def describe(:three_gpp_specification_defined, 38), do: "Network failure"
  def describe(:three_gpp_specification_defined, 39), do: "Reattach required"
  def describe(:three_gpp_specification_defined, 40), do: "Feature not supported"
  def describe(:three_gpp_specification_defined, 41), do: "TFT semantic error"
  def describe(:three_gpp_specification_defined, 42), do: "TFT syntax error"
  def describe(:three_gpp_specification_defined, 43), do: "Unknown PDP context"
  def describe(:three_gpp_specification_defined, 44), do: "Filter semantic error"
  def describe(:three_gpp_specification_defined, 45), do: "Filter syntax error"
  def describe(:three_gpp_specification_defined, 46), do: "PDP without active TFT"
  def describe(:three_gpp_specification_defined, 50), do: "IPv4 only allowed"
  def describe(:three_gpp_specification_defined, 51), do: "IPv6 only allowed"
  def describe(:three_gpp_specification_defined, 52), do: "Single address bearer only"
  def describe(:three_gpp_specification_defined, 53), do: "ESM info not received"
  def describe(:three_gpp_specification_defined, 54), do: "PDN connection does not exist"

  def describe(:three_gpp_specification_defined, 55),
    do: "Multiple connection to same PDN not allowed"

  def describe(:three_gpp_specification_defined, 81), do: "Invalid transaction ID"
  def describe(:three_gpp_specification_defined, 95), do: "Message incorrect semantic"
  def describe(:three_gpp_specification_defined, 96), do: "Invalid mandatory info"
  def describe(:three_gpp_specification_defined, 97), do: "Message type unsupported"
  def describe(:three_gpp_specification_defined, 98), do: "Message type noncompatible state"
  def describe(:three_gpp_specification_defined, 99), do: "Unknown info element"
  def describe(:three_gpp_specification_defined, 100), do: "Conditional IE error"

  def describe(:three_gpp_specification_defined, 101),
    do: "Message and protocol state uncompatible"

  def describe(:three_gpp_specification_defined, 111), do: "Protocol error"
  def describe(:three_gpp_specification_defined, 112), do: "APN type conflict"

  def describe(:three_gpp_specification_defined, 113),
    do: "Invalid proxy call session control function address"

  def describe(:three_gpp_specification_defined, 114),
    do: "Internal call preempted by high priority APN"

  def describe(:three_gpp_specification_defined, 115), do: "EMM access barred"
  def describe(:three_gpp_specification_defined, 116), do: "Emergency interface only"
  def describe(:three_gpp_specification_defined, 117), do: "Interface mismatch"
  def describe(:three_gpp_specification_defined, 118), do: "Companion interface in use"
  def describe(:three_gpp_specification_defined, 119), do: "IP address mismatch"

  def describe(:three_gpp_specification_defined, 120),
    do: "Interface and policy family mismatch"

  def describe(:three_gpp_specification_defined, 121), do: "EMM access barred infinite retry"

  def describe(:three_gpp_specification_defined, 122),
    do: "Authentication failure on emergency call"

  def describe(:three_gpp_specification_defined, 123), do: "Invalid DNS address"

  def describe(:three_gpp_specification_defined, 124),
    do: "Invalid proxy call session control function DNS address"

  def describe(:three_gpp_specification_defined, 125), do: "Test loopback mode A or B enabled"
  def describe(:three_gpp_specification_defined, 126), do: "EMM access barred EAB"
  def describe(:three_gpp_specification_defined, 127), do: "Call preempted by emergency APN"
  def describe(:three_gpp_specification_defined, 128), do: "UE initiated detach or disconnect"

  # ── PPP ─────────────────────────────────────────────────────────────────────

  def describe(:ppp, -1), do: "Unknown"
  def describe(:ppp, 1), do: "Timeout"
  def describe(:ppp, 2), do: "Authentication failure"
  def describe(:ppp, 3), do: "Option mismatch"
  def describe(:ppp, 31), do: "PAP failure"
  def describe(:ppp, 32), do: "CHAP failure"
  def describe(:ppp, 33), do: "Close in progress"

  # ── eHRPD ───────────────────────────────────────────────────────────────────

  def describe(:ehrpd, 1), do: "Subscription limited to IPv4"
  def describe(:ehrpd, 2), do: "Subscription limited to IPv6"
  def describe(:ehrpd, 4), do: "VSNCP timeout"
  def describe(:ehrpd, 5), do: "VSNCP failure"
  def describe(:ehrpd, 6), do: "VSNCP 3GPP2 general error"
  def describe(:ehrpd, 7), do: "VSNCP 3GPP2 unauthenticated APN"
  def describe(:ehrpd, 8), do: "VSNCP 3GPP2 PDN limit exceeded"
  def describe(:ehrpd, 9), do: "VSNCP 3GPP2 no PDN gateway"
  def describe(:ehrpd, 10), do: "VSNCP 3GPP2 PDN gateway unreachable"
  def describe(:ehrpd, 11), do: "VSNCP 3GPP2 PDN gateway rejected"
  def describe(:ehrpd, 12), do: "VSNCP 3GPP2 insufficient parameters"
  def describe(:ehrpd, 13), do: "VSNCP 3GPP2 resource unavailable"
  def describe(:ehrpd, 14), do: "VSNCP 3GPP2 administratively prohibited"
  def describe(:ehrpd, 15), do: "VSNCP 3GPP2 PDN ID in use"
  def describe(:ehrpd, 16), do: "VSNCP 3GPP2 subscription limitation"
  def describe(:ehrpd, 17), do: "VSNCP 3GPP2 PDN exists for this APN"

  # ── IPv6 ────────────────────────────────────────────────────────────────────

  def describe(:ipv6, 1), do: "Prefix unavailable"
  def describe(:ipv6, 2), do: "HRPD IPv6 disabled"
  def describe(:ipv6, 3), do: "IPv6 disabled"

  # ── Handoff ─────────────────────────────────────────────────────────────────
  # The handoff type (0x0C) is recognized by the QMI codec but has no
  # sub-enum defined in the libqmi specification.

  # ── Catch-all ───────────────────────────────────────────────────────────────

  def describe(type, code) do
    "Unknown (#{inspect(type)} #{code})"
  end

  @doc """
  Returns the human-readable name for a `call_end_reason_type` atom.
  """
  @spec type_name(atom()) :: String.t()
  def type_name(:unspecified), do: "Unspecified"
  def type_name(:mobile_ip), do: "Mobile IP"
  def type_name(:internal), do: "Internal"
  def type_name(:call_manager_defined), do: "Call Manager"
  def type_name(:three_gpp_specification_defined), do: "3GPP"
  def type_name(:ppp), do: "PPP"
  def type_name(:ehrpd), do: "eHRPD"
  def type_name(:ipv6), do: "IPv6"
  def type_name(:handoff), do: "Handoff"
  def type_name({:unknown, id}), do: "Unknown type (#{id})"
  def type_name(other), do: inspect(other)

  @doc """
  Returns a formatted single-line summary of a call end reason.

  ## Example

      iex> VintageNetQMI.CallEndReason.format(:three_gpp_specification_defined, 36)
      "3GPP: Regular deactivation (36)"

  """
  @spec format(atom(), integer()) :: String.t()
  def format(type, code) do
    "#{type_name(type)}: #{describe(type, code)} (#{code})"
  end
end
