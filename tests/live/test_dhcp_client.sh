#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root_dir"

LAB_CONTEXT="DHCP client test"
source tools/lib/lab.sh

released_endpoint=""
restore_endpoint() {
    if [[ -n "$released_endpoint" ]]; then
        echo "Renewing DHCP on $released_endpoint during cleanup..." >&2
        bash tools/dhcp-client.sh renew "$released_endpoint" >/dev/null 2>&1 || true
        released_endpoint=""
    fi
}
trap restore_endpoint EXIT

assert_lease() {
    local endpoint=$1
    local expected_prefix=$2
    local expected_gateway=$3
    local container address gateway

    container=$(lab_require_running "$endpoint")
    address=$(lab_interface_ip "$container")
    gateway=$(docker exec "$container" sh -c \
        "ip -4 route show default dev eth1 | awk '/^default/ {print \$3; exit}'")

    if [[ "$address" != "$expected_prefix"* ]]; then
        echo "DHCP client test: $endpoint address '$address' is not in ${expected_prefix}0/24" >&2
        exit 1
    fi
    if [[ "$gateway" != "$expected_gateway" ]]; then
        echo "DHCP client test: $endpoint gateway '$gateway' is not $expected_gateway" >&2
        exit 1
    fi
    echo "$endpoint lease verified: $address via $gateway"
}

test_endpoint() {
    local endpoint=$1
    local expected_prefix=$2
    local expected_gateway=$3
    local container

    bash tools/dhcp-client.sh renew "$endpoint" >/dev/null
    assert_lease "$endpoint" "$expected_prefix" "$expected_gateway"

    bash tools/dhcp-client.sh release "$endpoint" >/dev/null
    released_endpoint=$endpoint
    container=$(lab_require_running "$endpoint")

    if [[ -n "$(lab_interface_ip "$container")" ]]; then
        echo "DHCP client test: $endpoint kept an address after release" >&2
        exit 1
    fi
    if docker exec "$container" ip -4 route show default dev eth1 | grep -q .; then
        echo "DHCP client test: $endpoint kept a default route after release" >&2
        exit 1
    fi
    echo "$endpoint release verified; the endpoint container remains running."

    bash tools/dhcp-client.sh renew "$endpoint" >/dev/null
    released_endpoint=""
    assert_lease "$endpoint" "$expected_prefix" "$expected_gateway"
}

test_endpoint H1 10.255.10. 10.255.10.1
test_endpoint H2 10.255.20. 10.255.20.1

echo "DHCP client release and renewal tests passed."
