#!/bin/sh
set -eu

. /usr/local/lib/campus/wait-for-interface.sh

interface="${DHCP_INTERFACE:-eth1}"
wait_seconds="${INTERFACE_WAIT_SECONDS:-30}"
wait_for_interface "$interface" "$wait_seconds" campus-endpoint

ip link set "$interface" up
# Containerlab's management interface supplies a Docker default route. The
# endpoint's data-plane default must instead come from campus DHCP on eth1.
ip -4 route flush default
exec dhclient -4 -d -v "$interface"
