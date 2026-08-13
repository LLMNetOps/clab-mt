#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source "$root_dir/tests/lib/delayed_interface.sh"

image=${EXABGP_IMAGE:-local/campus-exabgp:5.0.9}
container="campus-exabgp-startup-test-$$"

cleanup() {
    cleanup_test_container "$container"
}
trap cleanup EXIT

docker run -d \
    --name "$container" \
    --network none \
    --cap-add NET_ADMIN \
    --env DATA_INTERFACE=eth1 \
    --env DATA_ADDRESS=10.255.2.2/30 \
    --volume "$root_dir/generated/isp.conf:/etc/exabgp/exabgp.conf:ro" \
    "$image" >/dev/null

verify_delayed_interface_startup "$container" ExaBGP 2

echo "ExaBGP startup test: delayed eth1 attachment passed"
