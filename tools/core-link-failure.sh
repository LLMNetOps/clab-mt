#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

path_attempts=${CORE_PATH_ATTEMPTS:-25}
path_interval=${CORE_PATH_INTERVAL:-2}
r2_data_interface=${R2_R3_CONTAINER_INTERFACE:-eth2}
link_disabled=false

LAB_CONTEXT="core-link failure"
source tools/lib/lab.sh

trace_hops() {
    local destination=$1
    docker exec "$h1" traceroute -n -q 1 -w 1 -m 8 "$destination" \
        | awk '
            /^[[:space:]]*[0-9]+[[:space:]]/ {
                for (field = 2; field <= NF; field++) {
                    if ($field ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                        hops = hops (hops == "" ? "" : " ") $field
                        break
                    }
                }
            }
            END { print hops }
        '
}

assert_path() {
    local label=$1
    local expected=$2
    local actual=""
    local attempt

    for attempt in $(seq 1 "$path_attempts"); do
        actual=$(trace_hops "$h2_ip")
        if [[ "$actual" == "$expected" ]]; then
            echo "$label path verified: $actual"
            return
        fi
        sleep "$path_interval"
    done

    echo "$label path mismatch after $path_attempts attempts" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
}

assert_ping() {
    local label=$1
    echo "$label ping:"
    docker exec "$h1" ping -c 3 -W 1 "$h2_ip"
}

restore_link() {
    if [[ "$link_disabled" == true ]]; then
        echo "Restoring the R2-R3 link during cleanup..." >&2
        docker exec "$r2" ip link set "$r2_data_interface" up >/dev/null 2>&1 || true
        link_disabled=false
    fi
}
trap restore_link EXIT

r2=$(lab_require_running R2)
h1=$(lab_require_running H1)
h2=$(lab_require_running H2)

if ! docker exec "$r2" ip link show dev "$r2_data_interface" >/dev/null 2>&1; then
    echo "core-link failure: $r2_data_interface is not present on $r2" >&2
    exit 1
fi

h2_ip=""
for _attempt in $(seq 1 30); do
    h2_ip=$(lab_interface_ip "$h2")
    [[ -n "$h2_ip" ]] && break
    sleep 1
done
if [[ -z "$h2_ip" ]]; then
    echo "core-link failure: H2 has no DHCP address on eth1" >&2
    exit 1
fi

normal_path="10.255.10.1 10.255.1.6 $h2_ip"
rerouted_path="10.255.10.1 10.255.1.1 10.255.1.10 $h2_ip"

assert_ping "Normal R2-R3"
assert_path "Normal R2-R3" "$normal_path"

echo "Disabling the R2-R3 link ($r2:$r2_data_interface / RouterOS ether3)..."
docker exec "$r2" ip link set "$r2_data_interface" down
link_disabled=true

assert_path "Rerouted R2-R1-R3" "$rerouted_path"
assert_ping "Rerouted R2-R1-R3"

echo "Restoring the R2-R3 link..."
docker exec "$r2" ip link set "$r2_data_interface" up
link_disabled=false

assert_path "Restored R2-R3" "$normal_path"
assert_ping "Restored R2-R3"

echo "Core-link failure scenario passed."
