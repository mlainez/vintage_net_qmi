# SPDX-FileCopyrightText: 2021 Frank Hunleth
# SPDX-FileCopyrightText: 2021 Jon Carstens
# SPDX-FileCopyrightText: 2021 Matt Ludwigs
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMITest do
  use ExUnit.Case
  import Mock
  alias VintageNet.Interface.RawConfig

  test "create a simple qmi configuration" do
    input = %{
      type: VintageNetQMI,
      vintage_net_qmi: %{service_providers: [%{apn: "super"}]},
      hostname: "unit_test"
    }

    expected = %RawConfig{
      ifname: "wwan0",
      type: VintageNetQMI,
      source_config: input,
      required_ifnames: ["wwan0"],
      child_specs: [
        {VintageNetQMI.Indications, [ifname: "wwan0"]},
        {QMI.Supervisor,
         [
           ifname: "wwan0",
           device_path: nil,
           name: :"Elixir.VintageNetQMI.QMI.wwan0",
           indication_callback: VintageNetQMI.indication_callback("wwan0")
         ]},
        {VintageNetQMI.Connectivity, [ifname: "wwan0"]},
        {VintageNetQMI.Connection,
         [{:ifname, "wwan0"}, service_providers: [%{apn: "super"}], radio_technologies: nil]},
        {VintageNetQMI.CellMonitor, [ifname: "wwan0"]},
        {VintageNetQMI.SignalMonitor, [ifname: "wwan0"]},
        {VintageNetQMI.ModemInfo, [ifname: "wwan0"]},
        Utils.udhcpc_child_spec("wwan0", "unit_test")
      ],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wwan0", "label", "wwan0"]},
        {:run, "ip", ["link", "set", "wwan0", "down"]}
      ],
      up_cmds: [
        {:fun, QMI, :configure_linux, ["wwan0"]},
        {:run, "ip", ["link", "set", "wwan0", "up"]}
      ]
    }

    created = VintageNetQMI.to_raw_config("wwan0", input, Utils.default_opts())

    assert created == expected
  end

  test "quick_configure_with_auth creates proper configuration" do
    # Mock VintageNet.configure to capture the call
    pid = self()

    config_capture = fn ifname, config ->
      send(pid, {:configure_called, ifname, config})
      :ok
    end

    # Test with minimal options
    with_mock VintageNet, configure: config_capture do
      VintageNetQMI.quick_configure_with_auth("test.apn")

      assert_received {:configure_called, "wwan0",
                       %{
                         type: VintageNetQMI,
                         vintage_net_qmi: %{
                           service_providers: [%{apn: "test.apn"}]
                         }
                       }}
    end

    # Test with full options
    with_mock VintageNet, configure: config_capture do
      VintageNetQMI.quick_configure_with_auth("test.apn",
        username: "testuser",
        password: "testpass",
        auth_method: :pap_or_chap,
        pdp_type: :ipv4v6,
        roaming_allowed?: false
      )

      assert_received {:configure_called, "wwan0",
                       %{
                         type: VintageNetQMI,
                         vintage_net_qmi: %{
                           service_providers: [
                             %{
                               apn: "test.apn",
                               username: "testuser",
                               password: "testpass",
                               auth_method: :pap_or_chap,
                               pdp_type: :ipv4v6,
                               roaming_allowed?: false
                             }
                           ]
                         }
                       }}
    end
  end
end
