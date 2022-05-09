#!/usr/bin/env bash

set -Ceuo pipefail

function error_handler() {
  set +x
  echo "something went wrong" >&2
  exit 1
}

: "start" && {
  echo "start building..."
  trap error_handler ERR
  set -x
}

: "add-netns" && {
  sudo ip netns add ns1
  sudo ip netns add ns2
  sudo ip netns add router
  sudo ip netns add bridge
}

# bridgeにipv6アドレスが割り当てられないようにする
: "disable-bridge-IPv6" && {
  sudo ip netns exec bridge sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sudo ip netns exec bridge sysctl -w net.ipv6.conf.default.disable_ipv6=1
}

: "add-veth" && {
  sudo ip link add ns1-veth0 type veth peer name ns1-br0
  sudo ip link add ns2-veth0 type veth peer name ns2-br0
  sudo ip link add gw-veth0 type veth peer name gw-br0
}

: "set-veth" && {
  sudo ip link set ns1-veth0 netns ns1
  sudo ip link set ns2-veth0 netns ns2
  sudo ip link set gw-veth0 netns router
  sudo ip link set ns1-br0 netns bridge
  sudo ip link set ns2-br0 netns bridge
  sudo ip link set gw-br0 netns bridge
}

: "change-MAC" && {
  sudo ip netns exec ns1 ip link set dev ns1-veth0 address 00:00:5E:00:53:01
  sudo ip netns exec ns2 ip link set dev ns2-veth0 address 00:00:5E:00:53:02
  sudo ip netns exec router ip link set dev gw-veth0 address 00:00:5E:00:53:0F
}

: "add-ip" && {
  sudo ip netns exec router ip address add fe80::1/64 dev gw-veth0
  sudo ip netns exec router ip address add 2001:db8::1/64 dev gw-veth0
}

: "to-be-router" && {
  sudo ip netns exec router sysctl -w net.ipv6.conf.all.forwarding=1
  sudo ip netns exec router sysctl -w net.ipv6.conf.all.autoconf=0
}

: "link-up" && {
  sudo ip netns exec ns1 ip link set ns1-veth0 up
  sudo ip netns exec ns2 ip link set ns2-veth0 up
  sudo ip netns exec router ip link set gw-veth0 up
  sudo ip netns exec bridge ip link set ns1-br0 up
  sudo ip netns exec bridge ip link set ns2-br0 up
  sudo ip netns exec bridge ip link set gw-br0 up
}

: "set-bridge" && {
  sudo ip netns exec bridge ip link add dev br0 type bridge
  sudo ip netns exec bridge ip link set br0 up
}

: "connect-bridge" && {
  sudo ip netns exec bridge ip link set ns1-br0 master br0
  sudo ip netns exec bridge ip link set ns2-br0 master br0
  sudo ip netns exec bridge ip link set gw-br0 master br0
}

: "router-autoip-del" && {
  sudo ip netns exec router ip addr del fe80::200:5eff:fe00:530f/64 dev gw-veth0
}

: "router-send-ra" && {
  sudo ip netns exec router radvd -C ./radvd.conf
}

: "done" && {
  set +x
  echo "successful"
}
