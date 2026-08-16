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
        actual=$(received_route_count "$peer_address" 2>/dev/null || true)
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

ospf_default_present() {
    local node=$1
    local output

    output=$(lab_routeros_command "$node" "/routing/route/print detail where dst-address=0.0.0.0/0" | tr -d '\r')
    grep -Eq '^[[:space:]]*Ao[[:space:]]' <<<"$output" \
        && grep -Fq '.type=ext-type-1' <<<"$output"
}

assert_ospf_default_state() {
    local label=$1
    local expected=$2
    local attempts=${3:-$bgp_attempts}
    local actual=""
    local attempt matches node state

    for attempt in $(seq 1 "$attempts"); do
        actual=""
        matches=true
        for node in R2 R3; do
            if ospf_default_present "$node"; then
                state="present"
            else
                state="absent"
            fi
            actual="${actual:+$actual, }$node=$state"
            if [[ "$state" != "$expected" ]]; then
                matches=false
            fi
        done
        if [[ "$matches" == true ]]; then
            echo "$label OSPF default state verified: $actual"
            return
        fi
        sleep "$bgp_interval"
    done

    echo "$label OSPF default state mismatch after $attempts attempts" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
}

assert_full_ospf_neighbors() {
    local label=$1
    local actual=""
    local attempt node

    for node in R1 R2 R3; do
        for attempt in $(seq 1 "$bgp_recovery_attempts"); do
            actual=$(lab_routeros_numeric_output "$node" "/routing/ospf/neighbor/print count-only where state=Full" 2>/dev/null || true)
            if [[ "$actual" == 2 ]]; then
                echo "$label $node full-neighbor count verified: $actual"
                break
            fi
            sleep "$bgp_interval"
        done
        if [[ "$actual" != 2 ]]; then
            echo "$label $node full-neighbor count mismatch" >&2
            echo "  expected: 2" >&2
            echo "  actual:   ${actual:-unavailable}" >&2
            exit 1
        fi
    done
}

assert_routeros_unavailable() {
    local label=$1
    local attempt

    for attempt in $(seq 1 "$bgp_attempts"); do
        if ! lab_routeros_command R1 "/system/identity/print" >/dev/null 2>&1; then
            echo "$label RouterOS unavailability verified."
            return
        fi
        sleep "$bgp_interval"
    done

    echo "$label did not make RouterOS unavailable" >&2
    exit 1
}

external_peer_scenario() {
    case $1 in
        ISP)
            printf '%s\n' 'isp|10.255.2.2|REN|10.255.2.6'
            ;;
        REN)
            printf '%s\n' 'ren|10.255.2.6|ISP|10.255.2.2'
            ;;
        *)
            return 1
            ;;
    esac
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

test_r1_restart_without_isp() {
    local ren_prefixes

    lab_require_running ISP >/dev/null
    lab_require_running R1 >/dev/null
    ren_prefixes=$(lab_manifest_count ren)

    bash tools/link-state.sh down isp
    disabled_link=isp
    assert_received_route_count "ISP before R1 restart" 10.255.2.2 0
    assert_ospf_default_state "ISP before R1 restart" absent

    bash tools/restart-router.sh R1
    assert_routeros_unavailable "R1 restart"

    assert_received_route_count \
        "REN after R1 restart" 10.255.2.6 "$ren_prefixes" \
        "$bgp_recovery_attempts"
    assert_full_ospf_neighbors "R1 restart"
    assert_ospf_default_state "R1 restart without ISP" absent

    bash tools/link-state.sh up isp
    disabled_link=""
    assert_received_route_count \
        "ISP after R1 restart" 10.255.2.2 "$(lab_manifest_count isp)" \
        "$bgp_recovery_attempts"
    assert_ospf_default_state \
        "ISP recovery after R1 restart" present "$bgp_recovery_attempts"
}

test_peer_failure() {
    local node=$1
    local failed_default_state=$2
    local link peer_address surviving_node surviving_peer_address
    local expected_prefixes surviving_prefixes
    local pid_before pid_after

    IFS='|' read -r link peer_address surviving_node surviving_peer_address \
        <<<"$(external_peer_scenario "$node")"
    expected_prefixes=$(lab_manifest_count "${node,,}")
    surviving_prefixes=$(lab_manifest_count "${surviving_node,,}")

    lab_require_running "$node" >/dev/null
    assert_received_route_count "$node baseline" "$peer_address" "$expected_prefixes"
    assert_received_route_count "$surviving_node baseline" "$surviving_peer_address" "$surviving_prefixes"
    assert_ospf_default_state "$node baseline" present
    pid_before=$(speaker_pid "$node")
    if [[ -z "$pid_before" ]]; then
        echo "$node ExaBGP process is not running before the link failure" >&2
        exit 1
    fi

    bash tools/link-state.sh down "$link"
    disabled_link=$link

    assert_received_route_count "$node withdrawal" "$peer_address" 0
    assert_received_route_count "$surviving_node while $node is down" "$surviving_peer_address" "$surviving_prefixes"
    assert_ospf_default_state "$node withdrawal" "$failed_default_state"
    bash tools/validate.sh reachability-only

    bash tools/link-state.sh up "$link"
    disabled_link=""

    assert_received_route_count "$node recovery" "$peer_address" "$expected_prefixes" "$bgp_recovery_attempts"
    assert_ospf_default_state "$node recovery" present "$bgp_recovery_attempts"
    pid_after=$(speaker_pid "$node")
    if [[ "$pid_after" != "$pid_before" ]]; then
        echo "$node ExaBGP process restarted during link recovery (before $pid_before, after ${pid_after:-missing})" >&2
        exit 1
    fi
    echo "$node ExaBGP process continuity verified."
    bash tools/validate.sh reachability-only
}

lab_require_running R1 >/dev/null
test_peer_failure ISP absent
test_peer_failure REN present
test_r1_restart_without_isp

echo "External-link failure tests passed."
