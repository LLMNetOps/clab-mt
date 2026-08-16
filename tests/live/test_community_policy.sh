#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root_dir"

LAB_CONTEXT="community-policy live fixture"
source tools/lib/lab.sh

peer_container=$(lab_require_running ISP)
lab_require_running R1 >/dev/null
peer_address=10.255.2.2
fixture_prefixes=()

mapfile -t fixture_prefixes < <(python3 - "$LAB_MANIFEST_PATH" <<'PY'
import json
import sys
from ipaddress import IPv4Network
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
pool = IPv4Network("10.64.0.0/10")
used = [
    IPv4Network(route["prefix"])
    for routes in manifest["routes"].values()
    for route in routes
]
selected = []
for candidate in reversed(tuple(pool.subnets(new_prefix=24))):
    if any(candidate.overlaps(route) for route in [*used, *selected]):
        continue
    selected.append(candidate)
    if len(selected) == 5:
        break

if len(selected) != 5:
    raise SystemExit("could not allocate five unused community-policy fixture prefixes")
for prefix in selected:
    print(prefix)
PY
)

if [[ "${#fixture_prefixes[@]}" -ne 5 ]]; then
    echo "${LAB_CONTEXT}: expected five fixture prefixes" >&2
    exit 1
fi

route_count() {
    local prefix=$1
    lab_routeros_numeric_output R1 \
        "/routing/route/print count-only where dst-address=$prefix and belongs-to=bgp-IP-$peer_address" \
        2>/dev/null || true
}

route_detail() {
    local prefix=$1
    lab_routeros_command R1 \
        "/routing/route/print detail where dst-address=$prefix and belongs-to=bgp-IP-$peer_address" \
        | tr -d '\r'
}

speaker_route_present() {
    local prefix=$1
    docker exec "$peer_container" /opt/exabgp/bin/exabgp-cli \
        show adj-rib out 2>/dev/null | grep -F " $prefix " >/dev/null
}

wait_for_speaker_route() {
    local prefix=$1
    local expected=$2
    local attempts=${3:-30}
    local actual=false

    for _attempt in $(seq 1 "$attempts"); do
        if speaker_route_present "$prefix"; then
            actual=true
        else
            actual=false
        fi
        if [[ "$actual" == "$expected" ]]; then
            return 0
        fi
        sleep 2
    done

    echo "${LAB_CONTEXT}: ExaBGP Adj-RIB-Out state mismatch for $prefix" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    return 1
}

wait_for_route_count() {
    local prefix=$1
    local expected=$2
    local attempts=${3:-30}
    local actual=""

    for _attempt in $(seq 1 "$attempts"); do
        actual=$(route_count "$prefix")
        if [[ "$actual" == "$expected" ]]; then
            return 0
        fi
        sleep 2
    done

    echo "${LAB_CONTEXT}: route count mismatch for $prefix" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   ${actual:-unavailable}" >&2
    return 1
}

wait_for_filtered_route() {
    local prefix=$1
    local attempts=${2:-30}
    local detail=""

    for _attempt in $(seq 1 "$attempts"); do
        detail=$(route_detail "$prefix")
        if grep -Fq 'contribution=filtered' <<<"$detail"; then
            return 0
        fi
        sleep 2
    done

    echo "${LAB_CONTEXT}: expected a filtered route for $prefix" >&2
    echo "$detail" >&2
    return 1
}

wait_for_accepted_route() {
    local prefix=$1
    local attempts=${2:-30}
    local detail=""

    for _attempt in $(seq 1 "$attempts"); do
        detail=$(route_detail "$prefix")
        if grep -Eq 'contribution=(active|candidate)' <<<"$detail" \
            && grep -Fq '.local-pref=100' <<<"$detail"; then
            return 0
        fi
        sleep 2
    done

    echo \
        "${LAB_CONTEXT}: expected an accepted route with local preference 100 for $prefix" \
        >&2
    echo "$detail" >&2
    return 1
}

announce_route() {
    local prefix=$1
    shift
    docker exec "$peer_container" /opt/exabgp/bin/exabgp-cli \
        announce route "$prefix" next-hop self "$@" >/dev/null
}

withdraw_route() {
    local prefix=$1
    docker exec "$peer_container" /opt/exabgp/bin/exabgp-cli \
        withdraw route "$prefix" next-hop self >/dev/null 2>&1 || true
}

cleanup() {
    local prefix
    for prefix in "${fixture_prefixes[@]}"; do
        withdraw_route "$prefix"
    done
    for prefix in "${fixture_prefixes[@]}"; do
        wait_for_speaker_route "$prefix" false 15 >/dev/null 2>&1 || true
        wait_for_route_count "$prefix" 0 15 >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT
cleanup

for _attempt in $(seq 1 30); do
    bgp_sessions=$(lab_routeros_command R1 "/routing/bgp/session/print terse" 2>/dev/null | tr -d '\r' || true)
    if grep -Eq "^[[:space:]]*[0-9]+ E .*remote.address=${peer_address//./\\.}([[:space:]]|$)" <<<"$bgp_sessions"; then
        break
    fi
    if [[ "$_attempt" == 30 ]]; then
        echo "${LAB_CONTEXT}: ISP BGP session is not established" >&2
        exit 1
    fi
    sleep 2
done

empty_prefix=${fixture_prefixes[0]}
mismatched_prefix=${fixture_prefixes[1]}
extra_prefix=${fixture_prefixes[2]}
missing_path_prefix=${fixture_prefixes[3]}
contradictory_prefix=${fixture_prefixes[4]}

announce_route "$empty_prefix"
wait_for_speaker_route "$empty_prefix" true
wait_for_accepted_route "$empty_prefix"
echo \
    "Empty community attribute accepted with default local preference 100: $empty_prefix"

announce_route "$mismatched_prefix" community "[" 65000:20 65000:0 "]"
wait_for_speaker_route "$mismatched_prefix" true
wait_for_filtered_route "$mismatched_prefix"
echo "Peer-mismatched source community rejected: $mismatched_prefix"

announce_route "$extra_prefix" community "[" 65000:10 65000:0 65000:123 "]"
wait_for_speaker_route "$extra_prefix" true
wait_for_filtered_route "$extra_prefix"
echo "Unexpected extra community rejected: $extra_prefix"

announce_route "$missing_path_prefix" community "[" 65000:10 "]"
wait_for_speaker_route "$missing_path_prefix" true
wait_for_filtered_route "$missing_path_prefix"
echo "Missing path-class community rejected: $missing_path_prefix"

announce_route \
    "$contradictory_prefix" community "[" 65000:10 65000:20 65000:0 "]"
wait_for_speaker_route "$contradictory_prefix" true
wait_for_filtered_route "$contradictory_prefix"
echo "Contradictory source communities rejected: $contradictory_prefix"

cleanup
trap - EXIT
echo "Community-policy live fixture passed."
