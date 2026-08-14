#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root_dir"

bgp_attempts=${BGP_STATE_ATTEMPTS:-25}
bgp_recovery_attempts=${BGP_RECOVERY_ATTEMPTS:-90}
bgp_interval=${BGP_STATE_INTERVAL:-2}
disabled_link=""

LAB_CONTEXT="external-link failure test"
source tools/lib/lab.sh

received_route_count() {
    local peer_address=$1
    local output
    output=$(lab_routeros_command R1 "/routing/route/print count-only where belongs-to=bgp-IP-$peer_address")
    printf '%s\n' "$output" | tr -d '\r' | awk '/^[0-9]+$/ { count=$0 } END { print count }'
}

assert_received_route_count() {
    local label=$1
    local peer_address=$2
    local expected=$3
    local attempts=${4:-$bgp_attempts}
    local actual=""
    local attempt

    for attempt in $(seq 1 "$attempts"); do
        actual=$(received_route_count "$peer_address")
        if [[ "$actual" == "$expected" ]]; then
            echo "$label received-route count verified: $actual"
            return
        fi
        sleep "$bgp_interval"
    done

    echo "$label received-route count mismatch after $attempts attempts" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
}

speaker_pid() {
    local node=$1
    local container
    container=$(lab_container_for "$node")
    docker top "$container" -eo pid,comm | awk '$2 == "exabgp" { print $1; exit }'
}

restore_external_link() {
    if [[ -n "$disabled_link" ]]; then
        echo "Restoring $disabled_link during cleanup..." >&2
        bash tools/link-state.sh up "$disabled_link" >/dev/null 2>&1 || true
        disabled_link=""
    fi
}
trap restore_external_link EXIT

test_peer_failure() {
    local node=$1
    local link=$2
    local peer_address=$3
    local expected_prefixes=$4
    local pid_before pid_after

    lab_require_running "$node" >/dev/null
    assert_received_route_count "$node baseline" "$peer_address" "$expected_prefixes"
    pid_before=$(speaker_pid "$node")
    if [[ -z "$pid_before" ]]; then
        echo "$node ExaBGP process is not running before the link failure" >&2
        exit 1
    fi

    bash tools/link-state.sh down "$link"
    disabled_link=$link

    assert_received_route_count "$node withdrawal" "$peer_address" 0
    bash tools/validate.sh reachability-only

    bash tools/link-state.sh up "$link"
    disabled_link=""

    assert_received_route_count "$node recovery" "$peer_address" "$expected_prefixes" "$bgp_recovery_attempts"
    pid_after=$(speaker_pid "$node")
    if [[ "$pid_after" != "$pid_before" ]]; then
        echo "$node ExaBGP process restarted during link recovery (before $pid_before, after ${pid_after:-missing})" >&2
        exit 1
    fi
    echo "$node ExaBGP process continuity verified."
    bash tools/validate.sh reachability-only
}

lab_require_running R1 >/dev/null
test_peer_failure ISP isp 10.255.2.2 "$(lab_manifest_count isp)"
test_peer_failure IDREN idren 10.255.2.6 "$(lab_manifest_count idren)"

echo "External-link failure tests passed."
