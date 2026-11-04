# SPDX-FileCopyrightText: 2026 Marc Lainez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.LteAttachTest do
  use ExUnit.Case, async: true

  alias VintageNetQMI.LteAttach

  doctest LteAttach

  test "uses the first profile of a multi-profile attach list" do
    tlvs = <<2, 4::little-16, 0::32, 0x10, 5::little-16, 2, 7::little-16, 3::little-16>>

    assert LteAttach.parse_response(<<0x94::little-16, byte_size(tlvs)::little-16, tlvs::binary>>) ==
             {:ok, 7}
  end

  test "finds the list after other TLVs" do
    tlvs = <<2, 4::little-16, 0::32, 0x11, 1::little-16, 9, 0x10, 3::little-16, 1, 2::little-16>>

    assert LteAttach.parse_response(<<0x94::little-16, byte_size(tlvs)::little-16, tlvs::binary>>) ==
             {:ok, 2}
  end

  test "rejects a response without the list" do
    tlvs = <<2, 4::little-16, 0::32>>

    assert LteAttach.parse_response(<<0x94::little-16, byte_size(tlvs)::little-16, tlvs::binary>>) ==
             {:error, :no_attach_profile}
  end

  test "rejects another message" do
    assert LteAttach.parse_response(<<0x2B, 0, 0, 0>>) == {:error, :no_attach_profile}
  end
end
