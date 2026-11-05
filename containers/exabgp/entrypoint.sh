#!/bin/sh
set -eu

. /usr/local/lib/campus/wait-for-interface.sh

interface="${DATA_INTERFACE:-eth1}"
address="${DATA_ADDRESS:?DATA_ADDRESS must contain the data-interface address/prefix}"
gateway="${DATA_GATEWAY:?DATA_GATEWAY must contain the R1 data-interface address}"
wait_seconds="${INTERFACE_WAIT_SECONDS:-30}"
wait_for_interface "$interface" "$wait_seconds" campus-exabgp

ip link set "$interface" up
ip addr replace "$address" dev "$interface"
ip route replace default via "$gateway" dev "$interface"

exec exabgp server "$@"
