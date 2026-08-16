#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

fixture_dir=$(mktemp -d)
cleanup() {
    rm -rf "$fixture_dir"
}
trap cleanup EXIT

manifest_fixture="$fixture_dir/manifest.json"
routes_fixture="$fixture_dir/routes.conf"
printf '%s\n' '{"counts":{"isp":7,"ren":3}}' >"$manifest_fixture"
printf '%s\n' \
    '        route 10.64.0.0/16 next-hop self;' \
    '        route 10.65.0.0/16 {' \
    '            next-hop self;' \
    '        }' >"$routes_fixture"

LAB_MANIFEST_PATH=$manifest_fixture
source tools/lib/lab.sh

[[ "$(lab_manifest_count isp)" == 7 ]]
[[ "$(lab_manifest_count ren)" == 3 ]]
[[ "$(lab_generated_route_count "$routes_fixture")" == 2 ]]

address_attempt_file="$fixture_dir/address-attempt"
printf '%s\n' 0 >"$address_attempt_file"
lab_interface_ip() {
    address_attempt=$(cat "$address_attempt_file")
    address_attempt=$((address_attempt + 1))
    printf '%s\n' "$address_attempt" >"$address_attempt_file"
    if [[ "$address_attempt" == 3 ]]; then
        printf '%s\n' 10.255.20.101
    fi
}
sleep() {
    :
}

[[ "$(lab_wait_for_interface_ip clab-campus-ebgp-H2 eth1 3 0)" == 10.255.20.101 ]]

lab_interface_ip() {
    :
}
wait_error="$fixture_dir/wait-error"
if lab_wait_for_interface_ip clab-campus-ebgp-H2 eth1 2 0 2>"$wait_error"; then
    echo "Address wait unexpectedly succeeded without an address" >&2
    exit 1
fi
grep -F "lab: clab-campus-ebgp-H2:eth1 has no IPv4 address after 2 attempts" \
    "$wait_error" >/dev/null

echo "Generated route metadata and address waits passed."
