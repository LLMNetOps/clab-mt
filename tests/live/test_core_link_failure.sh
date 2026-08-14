#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root_dir"

path_attempts=${CORE_PATH_ATTEMPTS:-25}
path_interval=${CORE_PATH_INTERVAL:-2}
link_disabled=false

LAB_CONTEXT="core-link failure test"
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
        echo "Restoring r2-r3 during cleanup..." >&2
        bash tools/link-state.sh up r2-r3 >/dev/null 2>&1 || true
        link_disabled=false
    fi
}
trap restore_link EXIT

bash tools/link-state.sh status r2-r3 >/dev/null
h1=$(lab_require_running H1)
h2=$(lab_require_running H2)
h2_ip=$(lab_wait_for_interface_ip "$h2" eth1 30 1)

normal_path="10.255.10.1 10.255.1.6 $h2_ip"
rerouted_path="10.255.10.1 10.255.1.1 10.255.1.10 $h2_ip"

assert_ping "Normal R2-R3"
assert_path "Normal R2-R3" "$normal_path"

bash tools/link-state.sh down r2-r3
link_disabled=true

assert_path "Rerouted R2-R1-R3" "$rerouted_path"
assert_ping "Rerouted R2-R1-R3"

bash tools/link-state.sh up r2-r3
link_disabled=false

assert_path "Restored R2-R3" "$normal_path"
assert_ping "Restored R2-R3"

echo "Core-link failure test passed."
