#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source "$root_dir/tests/lib/delayed_interface.sh"

image=${ENDPOINT_IMAGE:-local/campus-endpoint:12}
container="campus-endpoint-startup-test-$$"

cleanup() {
    cleanup_test_container "$container"
}
trap cleanup EXIT

docker run -d \
    --name "$container" \
    --cap-add NET_ADMIN \
    "$image" >/dev/null

verify_delayed_interface_startup "$container" endpoint 1

if docker exec "$container" ip -4 route show default | grep -q 'dev eth0'; then
    echo "endpoint startup test: management default route remained after eth1 appeared" >&2
    docker exec "$container" ip -4 route show >&2
    exit 1
fi

echo "endpoint startup test: delayed eth1 attachment passed"
