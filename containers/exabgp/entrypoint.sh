#!/bin/sh
set -eu

. /usr/local/lib/campus/wait-for-interface.sh

interface="${DATA_INTERFACE:-eth1}"
address="${DATA_ADDRESS:?DATA_ADDRESS must contain the data-interface address/prefix}"
wait_seconds="${INTERFACE_WAIT_SECONDS:-30}"
wait_for_interface "$interface" "$wait_seconds" campus-exabgp

ip link set "$interface" up
ip addr replace "$address" dev "$interface"

exec exabgp server "$@"
