# SPDX-FileCopyrightText: 2026 Marc Lainez
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.RmnetLink do
  @moduledoc """
  Create / configure rmnet child netdevs over an IPA base netdev.

  On Qualcomm SoCs that ship the Citronics `ipa2-lite` driver
  (msm8953 / sdm632 — Fairphone 3+), the base IPA netdev
  (`rmnet_ipa0`) is QMAP-only: `ndo_start_xmit` drops anything
  whose protocol isn't `ETH_P_MAP`. Plain IP packets have to be
  encapsulated. The kernel's `rmnet` driver (`CONFIG_RMNET=y`)
  provides an upper-layer netdev that does the QMAP encap/decap
  for a single PDP context — you create it with:

      ip link add link rmnet_ipa0 name rmnet0 type rmnet mux_id N

  …except busybox `ip` doesn't have `link add`. So this module
  sends the equivalent `RTM_NEWLINK` netlink request directly via
  an `AF_NETLINK` socket using the `:socket` OTP module.

  Public API mirrors what we'd want from iproute2:

    * `ensure_child/3` — idempotent: create the child if missing,
      no-op if it already exists.
    * `set_up/1` / `set_down/1` — toggle the `IFF_UP` flag.
    * `delete/1` — remove the child netdev.
  """

  require Logger
  import Bitwise

  # AF_NETLINK on Linux. OTP's `:socket` accepts arbitrary integer domains
  # but doesn't expose a `:netlink` atom — pass the raw `16` instead.
  @af_netlink 16
  @netlink_route 0

  # rtnetlink message types (uapi/linux/rtnetlink.h)
  @rtm_newlink 16
  @rtm_dellink 17

  # netlink message flags (uapi/linux/netlink.h)
  @nlm_f_request 0x0001
  @nlm_f_ack 0x0004
  @nlm_f_excl 0x0200
  @nlm_f_create 0x0400

  # ifinfomsg attribute ids (uapi/linux/if_link.h)
  @ifla_ifname 3
  @ifla_link 5
  @ifla_linkinfo 18

  # IFLA_LINKINFO children
  @ifla_info_kind 1
  @ifla_info_data 2

  # IFLA_INFO_DATA children for rmnet (uapi/linux/if_link.h)
  @ifla_rmnet_mux_id 1
  @ifla_rmnet_flags 2

  # rmnet flag bits (uapi/linux/if_link.h). libqmi's default behaviour
  # is to always enable INGRESS_DEAGGREGATION even for single-PDP setups
  # — without it the in-kernel rmnet handler silently fails to deliver
  # received QMAP frames up the stack.
  @rmnet_flags_ingress_deaggregation 0x01
  @rmnet_flags_ingress_map_cksumv4 0x04
  @rmnet_flags_egress_map_cksumv4 0x08
  @rmnet_flags_ingress_map_cksumv5 0x10
  @rmnet_flags_egress_map_cksumv5 0x20

  # Default = INGRESS_DEAGGREGATION only — matches what ModemManager
  # configures on IPA modems where `/sys/.../ipa/feature/{rx,tx}_offload`
  # doesn't exist (which is the case on FP3+/msm8953). MM only enables
  # the CKSUMv4/v5 bits when the sysfs offload features advertise them.
  # Setting CKSUM flags unconditionally caused the kernel rmnet ingress
  # handler to expect checksum trailers the modem doesn't send.
  @default_rmnet_flags @rmnet_flags_ingress_deaggregation

  # Mask covers all bits libqmi touches when creating an rmnet child —
  # we pin the cksum bits to 0 so the kernel doesn't carry over stale
  # ingress/egress settings from a previous link config.
  @default_rmnet_mask @rmnet_flags_ingress_deaggregation +
                        @rmnet_flags_ingress_map_cksumv4 +
                        @rmnet_flags_egress_map_cksumv4 +
                        @rmnet_flags_ingress_map_cksumv5 +
                        @rmnet_flags_egress_map_cksumv5

  # Interface flags (uapi/linux/if.h)
  @iff_up 0x1

  # rtgenmsg / ifinfomsg constants
  @af_unspec 0

  @doc """
  Create `child_name` as an rmnet child netdev over `parent_name`
  with QMAP `mux_id`. Idempotent — returns `:ok` if the child
  already exists, regardless of its `mux_id`.
  """
  @spec ensure_child(String.t(), String.t(), 1..255, keyword()) :: :ok | {:error, term()}
  def ensure_child(parent_name, child_name, mux_id, opts \\ []) do
    if interface_exists?(child_name) do
      :ok
    else
      create_child(parent_name, child_name, mux_id, opts)
    end
  end

  @doc """
  Create `child_name` as a fresh rmnet child netdev. Fails with
  `{:error, :eexist}` if the interface already exists.

  Options:

    * `:flags` — `IFLA_RMNET_FLAGS.flags` (defaults to
      `RMNET_FLAGS_INGRESS_DEAGGREGATION`, matching libqmi).
    * `:mask` — `IFLA_RMNET_FLAGS.mask` (defaults to all the
      deaggregation / cksum bits libqmi explicitly manages, so
      unset bits get pinned to 0).
  """
  @spec create_child(String.t(), String.t(), 1..255, keyword()) :: :ok | {:error, term()}
  def create_child(parent_name, child_name, mux_id, opts \\ []) do
    rmnet_flags = Keyword.get(opts, :flags, @default_rmnet_flags)
    rmnet_mask = Keyword.get(opts, :mask, @default_rmnet_mask)

    with {:ok, parent_index} <- ifindex(parent_name) do
      info_data =
        IO.iodata_to_binary([
          nla(@ifla_rmnet_mux_id, <<mux_id::little-16>>),
          nla(@ifla_rmnet_flags, <<rmnet_flags::little-32, rmnet_mask::little-32>>)
        ])

      attrs = [
        nla(@ifla_link, <<parent_index::little-32>>),
        nla(@ifla_ifname, child_name <> <<0>>),
        nla(
          @ifla_linkinfo,
          IO.iodata_to_binary([
            nla(@ifla_info_kind, "rmnet" <> <<0>>),
            nla(@ifla_info_data, info_data)
          ])
        )
      ]

      header = ifinfomsg(0, 0, 0, 0)
      payload = IO.iodata_to_binary([header | attrs])
      flags = @nlm_f_request ||| @nlm_f_ack ||| @nlm_f_create ||| @nlm_f_excl
      send_rtnetlink(@rtm_newlink, flags, payload)
    end
  end

  @doc "Bring `ifname` up (IFF_UP)."
  @spec set_up(String.t()) :: :ok | {:error, term()}
  def set_up(ifname), do: set_flags(ifname, @iff_up, @iff_up)

  @doc "Bring `ifname` down (clear IFF_UP)."
  @spec set_down(String.t()) :: :ok | {:error, term()}
  def set_down(ifname), do: set_flags(ifname, 0, @iff_up)

  defp set_flags(ifname, value, mask) do
    with {:ok, idx} <- ifindex(ifname) do
      header = ifinfomsg(@af_unspec, 0, idx, value, mask)
      flags = @nlm_f_request ||| @nlm_f_ack
      send_rtnetlink(@rtm_newlink, flags, header)
    end
  end

  @doc "Delete `ifname`."
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(ifname) do
    with {:ok, idx} <- ifindex(ifname) do
      header = ifinfomsg(@af_unspec, 0, idx, 0)
      flags = @nlm_f_request ||| @nlm_f_ack
      send_rtnetlink(@rtm_dellink, flags, header)
    end
  end

  # ---- ifindex lookup ------------------------------------------------------

  @spec interface_exists?(String.t()) :: boolean()
  def interface_exists?(ifname), do: File.dir?("/sys/class/net/#{ifname}")

  @spec ifindex(String.t()) :: {:ok, pos_integer()} | {:error, term()}
  def ifindex(ifname) do
    case File.read("/sys/class/net/#{ifname}/ifindex") do
      {:ok, s} ->
        case Integer.parse(String.trim(s)) do
          {n, _} -> {:ok, n}
          :error -> {:error, :bad_ifindex}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---- low-level encoders / send loop --------------------------------------

  # struct ifinfomsg { __u8 family; __u8 _pad; __u16 type; __s32 index; __u32 flags; __u32 change; }
  defp ifinfomsg(family, type, index, flags, change \\ 0xFFFFFFFF) do
    <<family::8, 0::8, type::little-16, index::little-32, flags::little-32, change::little-32>>
  end

  # Pack a single NLA: <<u16 len, u16 type, payload, padding to 4-byte boundary>>
  defp nla(type, value) when is_binary(value) do
    len = 4 + byte_size(value)
    pad = padding(len)
    <<len::little-16, type::little-16>> <> value <> :binary.copy(<<0>>, pad)
  end

  defp padding(len), do: rem(4 - rem(len, 4), 4)

  # Send a single netlink request and wait for the ACK / error reply.
  defp send_rtnetlink(msg_type, flags, payload) do
    body = IO.iodata_to_binary([payload])

    case :socket.open(@af_netlink, :raw, @netlink_route) do
      {:ok, sock} ->
        try do
          do_send(sock, msg_type, flags, body)
        after
          :socket.close(sock)
        end

      {:error, reason} ->
        {:error, {:open, reason}}
    end
  end

  defp do_send(sock, msg_type, flags, body) do
    seq = :erlang.unique_integer([:positive]) |> rem(0xFFFFFFFF)
    pid = 0
    total_len = 16 + byte_size(body)

    hdr = <<total_len::little-32, msg_type::little-16, flags::little-16, seq::little-32,
            pid::little-32>>

    msg = hdr <> body

    case :socket.sendto(sock, msg, %{family: @af_netlink, addr: <<0::16, 0::16, 0::32, 0::32>>}) do
      :ok -> wait_ack(sock, seq)
      err -> {:error, {:sendto, err}}
    end
  end

  defp wait_ack(sock, seq) do
    case :socket.recv(sock, 0, 2_000) do
      {:ok, data} -> parse_ack(data, seq)
      {:error, :timeout} -> {:error, :timeout}
      {:error, reason} -> {:error, {:recv, reason}}
    end
  end

  # Parse netlink message looking for our seq + NLMSG_ERROR (type=2).
  # NLMSG_ERROR payload is `<<errno::little-32, original_header(16)::binary>>`
  # where errno == 0 means ACK.
  defp parse_ack(
         <<len::little-32, type::little-16, _flags::little-16, seq::little-32, _pid::little-32,
           rest::binary>>,
         expected_seq
       )
       when type == 2 and seq == expected_seq do
    payload_len = len - 16
    <<errno::little-signed-32, _rest::binary>> = binary_part(rest, 0, payload_len)

    case errno do
      0 -> :ok
      n when n < 0 -> {:error, :inet.format_error(-n) |> List.to_string() |> String.to_atom()}
      n -> {:error, :inet.format_error(n) |> List.to_string() |> String.to_atom()}
    end
  end

  defp parse_ack(<<len::little-32, _rest::binary>> = msg, expected_seq) when byte_size(msg) > len do
    <<_first::binary-size(len), rest::binary>> = msg
    parse_ack(rest, expected_seq)
  end

  defp parse_ack(_unexpected, _seq), do: {:error, :no_ack}
end
