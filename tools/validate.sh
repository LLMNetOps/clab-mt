#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

mode=${1:-full}
LAB_CONTEXT="validation"
source tools/lib/lab.sh

assert_equal() {
    local label=$1
    local expected=$2
    local actual=$3
    if [[ "$actual" != "$expected" ]]; then
        echo "validation: $label mismatch (expected $expected, got ${actual:-empty})" >&2
        exit 1
    fi
}

manifest_route_profile() {
    local speaker=$1
    local category=$2
    local shared=${3:-any}
    python3 - "$LAB_MANIFEST_PATH" "$speaker" "$category" "$shared" <<'PY'
import json
import sys
from pathlib import Path

manifest_path, speaker, category, shared = sys.argv[1:]
manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
for route in manifest["routes"][speaker]:
    if route["source_category"] != category:
        continue
    if shared == "shared" and not route["shared"]:
        continue
    if shared == "unique" and route["shared"]:
        continue
    if shared == "shared-isp-shorter":
        if not route["shared"] or route["path_class"] != "transit-learned":
            continue
        other_speaker = "ren" if speaker == "isp" else "isp"
        other_route = next(
            candidate
            for candidate in manifest["routes"][other_speaker]
            if candidate["prefix"] == route["prefix"]
        )
        isp_route = route if speaker == "isp" else other_route
        ren_route = route if speaker == "ren" else other_route
        if isp_route["path_depth"] >= ren_route["path_depth"]:
            continue
    path = route["expected_as_path"]
    path_depth = route["path_depth"]
    transit_neighbor = route["transit_neighbor"]
    path_class = route["path_class"]
    if path_depth != len(path):
        raise SystemExit(f"manifest path depth disagrees with AS path: {route}")
    if path_class == "adjacent-origin":
        if path_depth != 2 or transit_neighbor is not None:
            raise SystemExit(f"invalid adjacent-origin profile: {route}")
    elif path_class == "transit-learned":
        expected_neighbors = set(
            manifest["asns"][f"{speaker}_transit_neighbors"]
        )
        if not 3 <= path_depth <= 6:
            raise SystemExit(f"invalid transit-learned path depth: {route}")
        if transit_neighbor not in expected_neighbors or path[1] != transit_neighbor:
            raise SystemExit(f"invalid transit-learned neighbor: {route}")
    else:
        raise SystemExit(f"unknown path class: {route}")
    print(
        route["prefix"],
        path_depth,
        transit_neighbor if transit_neighbor is not None else "none",
        ",".join(str(asn) for asn in path),
        sep="|",
    )
    break
else:
    raise SystemExit(
        f"no {shared} {category} route found in {speaker} manifest"
    )
PY
}

assert_bgp_route_policy() {
    local label=$1
    local peer_address=$2
    local prefix=$3
    local expected_local_pref=$4
    local source_community=$5
    local category_community=$6
    local expected_path_depth=$7
    local expected_transit_neighbor=$8
    local expected_as_path=$9
    local route_output

    route_output=$(lab_routeros_command R1 \
        "/routing/route/print detail where dst-address=$prefix and belongs-to=bgp-IP-$peer_address" \
        | tr -d '\r')
    grep -Fq "$source_community" <<<"$route_output" || {
        echo "validation: $label is missing community $source_community" >&2
        exit 1
    }
    grep -Fq "$category_community" <<<"$route_output" || {
        echo "validation: $label is missing community $category_community" >&2
        exit 1
    }
    grep -Fq ".local-pref=$expected_local_pref" <<<"$route_output" || {
        echo "validation: $label has unexpected local preference" >&2
        echo "$route_output" >&2
        exit 1
    }
    grep -Fq ".as-path=\"$expected_as_path\"" <<<"$route_output" || {
        echo "validation: $label AS path does not match the manifest" >&2
        echo "  expected: $expected_as_path" >&2
        echo "$route_output" >&2
        exit 1
    }
    echo \
        "$label verified: path-depth=$expected_path_depth " \
        "transit-neighbor=$expected_transit_neighbor as-path=$expected_as_path " \
        "local-pref=$expected_local_pref"
}

validate_filter_contract() {
    local config=configs/routeros/r1.rsc

    for required in \
        "bgp-communities-empty) { accept }" \
        "bgp-communities equal-list community-isp-adjacent-origin) { set bgp-local-pref 200; accept }" \
        "bgp-communities equal-list community-ren-adjacent-origin) { set bgp-local-pref 200; accept }" \
        "bgp-communities equal-list community-isp-transit-learned) { set bgp-local-pref 160; accept }" \
        "bgp-communities equal-list community-ren-transit-learned) { set bgp-local-pref 180; accept }" \
        'add chain=bgp-in-isp rule="reject"' \
        'add chain=bgp-in-ren rule="reject"'; do
        grep -Fq "$required" "$config" || {
            echo "validation: R1 community filter contract is missing: $required" >&2
            exit 1
        }
    done
    python3 tests/check_community_policy.py
    echo "R1 exact community policy and empty-community fallback verified."
}

validate_endpoints() {
    local h1 h2 h1_ip h2_ip
    h1=$(lab_require_running H1)
    h2=$(lab_require_running H2)

    echo "Waiting for DHCP leases on H1 and H2..."
    h1_ip=""
    h2_ip=""
    for _attempt in $(seq 1 60); do
        h1_ip=$(lab_interface_ip "$h1")
        h2_ip=$(lab_interface_ip "$h2")
        if [[ -n "$h1_ip" && -n "$h2_ip" ]]; then
            break
        fi
        sleep 1
    done

    if [[ -z "$h1_ip" || -z "$h2_ip" ]]; then
        echo "validation: DHCP lease missing (H1='$h1_ip', H2='$h2_ip')" >&2
        exit 1
    fi

    echo "H1 address: $h1_ip"
    echo "H2 address: $h2_ip"
    echo "Waiting for campus routing convergence..."
    for _attempt in $(seq 1 60); do
        if docker exec "$h1" ping -c 1 -W 1 "$h2_ip" >/dev/null 2>&1; then
            break
        fi
        if [[ "$_attempt" == 60 ]]; then
            echo "validation: H1 cannot reach H2 after routing convergence timeout" >&2
            exit 1
        fi
        sleep 1
    done
    echo "H1 -> H2 ping:"
    docker exec "$h1" ping -c 3 -W 1 "$h2_ip"
    echo "H1 -> H2 traceroute:"
    docker exec "$h1" traceroute -n -q 1 -w 1 -m 8 "$h2_ip"
}

validate_control_plane() {
    local bgp_sessions expected_isp expected_ren shared_prefix route_output lsa_output
    local isp_adjacent_origin_prefix isp_transit_learned_prefix ren_adjacent_origin_prefix ren_transit_learned_prefix
    local isp_adjacent_origin_depth isp_transit_learned_depth ren_adjacent_origin_depth ren_transit_learned_depth
    local isp_adjacent_origin_neighbor isp_transit_learned_neighbor ren_adjacent_origin_neighbor ren_transit_learned_neighbor
    local isp_adjacent_origin_path isp_transit_learned_path ren_adjacent_origin_path ren_transit_learned_path
    local shared_adjacent_origin_prefix shared_ren_adjacent_origin_prefix
    local shared_transit_learned_prefix shared_ren_transit_learned_prefix
    local shared_isp_adjacent_origin_depth shared_ren_adjacent_origin_depth
    local shared_isp_adjacent_origin_neighbor shared_ren_adjacent_origin_neighbor
    local shared_isp_adjacent_origin_path shared_ren_adjacent_origin_path
    local shared_isp_transit_learned_depth shared_ren_transit_learned_depth
    local shared_isp_transit_learned_neighbor shared_ren_transit_learned_neighbor
    local shared_isp_transit_learned_path shared_ren_transit_learned_path
    local adjacent_origin_active_count adjacent_origin_candidate_count

    lab_require_running R1 >/dev/null
    lab_require_running R2 >/dev/null
    lab_require_running R3 >/dev/null
    validate_filter_contract

    bgp_sessions=$(lab_routeros_command R1 "/routing/bgp/session/print terse" | tr -d '\r')
    for peer_address in 10.255.2.2 10.255.2.6; do
        if ! grep -Eq "^[[:space:]]*[0-9]+ E .*remote.address=${peer_address//./\\.}([[:space:]]|$)" <<<"$bgp_sessions"; then
            echo "validation: BGP peer $peer_address is not established" >&2
            exit 1
        fi
    done
    expected_isp=$(lab_manifest_count isp)
    expected_ren=$(lab_manifest_count ren)
    assert_equal "ISP received routes" "$expected_isp" "$(lab_routeros_numeric_output R1 "/routing/route/print count-only where belongs-to=bgp-IP-10.255.2.2")"
    assert_equal "REN received routes" "$expected_ren" "$(lab_routeros_numeric_output R1 "/routing/route/print count-only where belongs-to=bgp-IP-10.255.2.6")"
    echo "BGP sessions and received-route counts verified."

    IFS='|' read -r isp_adjacent_origin_prefix isp_adjacent_origin_depth \
        isp_adjacent_origin_neighbor isp_adjacent_origin_path \
        < <(manifest_route_profile isp isp-adjacent-origin)
    IFS='|' read -r isp_transit_learned_prefix isp_transit_learned_depth \
        isp_transit_learned_neighbor isp_transit_learned_path \
        < <(manifest_route_profile isp isp-transit-learned)
    IFS='|' read -r ren_adjacent_origin_prefix ren_adjacent_origin_depth \
        ren_adjacent_origin_neighbor ren_adjacent_origin_path \
        < <(manifest_route_profile ren ren-adjacent-origin)
    IFS='|' read -r ren_transit_learned_prefix ren_transit_learned_depth \
        ren_transit_learned_neighbor ren_transit_learned_path \
        < <(manifest_route_profile ren ren-transit-learned)
    assert_bgp_route_policy \
        "ISP adjacent-origin $isp_adjacent_origin_prefix" 10.255.2.2 "$isp_adjacent_origin_prefix" \
        200 65000:10 65000:0 "$isp_adjacent_origin_depth" \
        "$isp_adjacent_origin_neighbor" "$isp_adjacent_origin_path"
    assert_bgp_route_policy \
        "ISP transit-learned $isp_transit_learned_prefix" 10.255.2.2 "$isp_transit_learned_prefix" \
        160 65000:10 65000:99 "$isp_transit_learned_depth" \
        "$isp_transit_learned_neighbor" "$isp_transit_learned_path"
    assert_bgp_route_policy \
        "REN adjacent-origin $ren_adjacent_origin_prefix" 10.255.2.6 "$ren_adjacent_origin_prefix" \
        200 65000:20 65000:0 "$ren_adjacent_origin_depth" \
        "$ren_adjacent_origin_neighbor" "$ren_adjacent_origin_path"
    assert_bgp_route_policy \
        "REN transit-learned $ren_transit_learned_prefix" 10.255.2.6 "$ren_transit_learned_prefix" \
        180 65000:20 65000:99 "$ren_transit_learned_depth" \
        "$ren_transit_learned_neighbor" "$ren_transit_learned_path"
    echo "Adjacent-origin and transit-learned communities plus local preferences verified."

    IFS='|' read -r shared_adjacent_origin_prefix \
        shared_isp_adjacent_origin_depth shared_isp_adjacent_origin_neighbor \
        shared_isp_adjacent_origin_path \
        < <(manifest_route_profile isp isp-adjacent-origin shared)
    IFS='|' read -r shared_ren_adjacent_origin_prefix \
        shared_ren_adjacent_origin_depth shared_ren_adjacent_origin_neighbor \
        shared_ren_adjacent_origin_path \
        < <(manifest_route_profile ren ren-adjacent-origin shared)
    if [[ "$shared_adjacent_origin_prefix" != "$shared_ren_adjacent_origin_prefix" ]]; then
        echo "validation: shared adjacent-origin prefix differs between ISP and REN" >&2
        exit 1
    fi
    assert_bgp_route_policy \
        "shared ISP adjacent-origin $shared_adjacent_origin_prefix" 10.255.2.2 \
        "$shared_adjacent_origin_prefix" 200 65000:10 65000:0 \
        "$shared_isp_adjacent_origin_depth" \
        "$shared_isp_adjacent_origin_neighbor" "$shared_isp_adjacent_origin_path"
    assert_bgp_route_policy \
        "shared REN adjacent-origin $shared_adjacent_origin_prefix" 10.255.2.6 \
        "$shared_adjacent_origin_prefix" 200 65000:20 65000:0 \
        "$shared_ren_adjacent_origin_depth" \
        "$shared_ren_adjacent_origin_neighbor" "$shared_ren_adjacent_origin_path"
    adjacent_origin_active_count=0
    adjacent_origin_candidate_count=0
    for peer_address in 10.255.2.2 10.255.2.6; do
        route_output=$(lab_routeros_command R1 \
            "/routing/route/print detail where dst-address=$shared_adjacent_origin_prefix and belongs-to=bgp-IP-$peer_address" \
            | tr -d '\r')
        if grep -Fq 'contribution=active' <<<"$route_output"; then
            adjacent_origin_active_count=$((adjacent_origin_active_count + 1))
        elif grep -Fq 'contribution=candidate' <<<"$route_output"; then
            adjacent_origin_candidate_count=$((adjacent_origin_candidate_count + 1))
        else
            echo "validation: adjacent-origin path from $peer_address is neither active nor a candidate" >&2
            exit 1
        fi
    done
    assert_equal "shared adjacent-origin active path count" 1 "$adjacent_origin_active_count"
    assert_equal "shared adjacent-origin candidate path count" 1 "$adjacent_origin_candidate_count"

    IFS='|' read -r shared_transit_learned_prefix \
        shared_isp_transit_learned_depth shared_isp_transit_learned_neighbor \
        shared_isp_transit_learned_path \
        < <(manifest_route_profile isp isp-transit-learned shared-isp-shorter)
    IFS='|' read -r shared_ren_transit_learned_prefix \
        shared_ren_transit_learned_depth shared_ren_transit_learned_neighbor \
        shared_ren_transit_learned_path \
        < <(manifest_route_profile ren ren-transit-learned shared-isp-shorter)
    if [[ "$shared_transit_learned_prefix" != "$shared_ren_transit_learned_prefix" ]]; then
        echo "validation: shared transit-learned prefix differs between ISP and REN" >&2
        exit 1
    fi
    if ((shared_isp_transit_learned_depth >= shared_ren_transit_learned_depth)); then
        echo "validation: shared transit proof requires ISP's AS path to be shorter" >&2
        exit 1
    fi
    assert_bgp_route_policy \
        "shared ISP transit-learned $shared_transit_learned_prefix" 10.255.2.2 \
        "$shared_transit_learned_prefix" 160 65000:10 65000:99 \
        "$shared_isp_transit_learned_depth" \
        "$shared_isp_transit_learned_neighbor" "$shared_isp_transit_learned_path"
    assert_bgp_route_policy \
        "shared REN transit-learned $shared_transit_learned_prefix" 10.255.2.6 \
        "$shared_transit_learned_prefix" 180 65000:20 65000:99 \
        "$shared_ren_transit_learned_depth" \
        "$shared_ren_transit_learned_neighbor" "$shared_ren_transit_learned_path"
    route_output=$(lab_routeros_command R1 \
        "/routing/route/print detail where dst-address=$shared_transit_learned_prefix and belongs-to=bgp-IP-10.255.2.6" \
        | tr -d '\r')
    grep -Eq '^[[:space:]]*Ab[[:space:]]' <<<"$route_output" || {
        echo "validation: REN transit-learned route for $shared_transit_learned_prefix is not active" >&2
        exit 1
    }
    route_output=$(lab_routeros_command R1 \
        "/routing/route/print detail where dst-address=$shared_transit_learned_prefix and belongs-to=bgp-IP-10.255.2.2" \
        | tr -d '\r')
    grep -Fq 'contribution=candidate' <<<"$route_output" || {
        echo "validation: ISP transit-learned route for $shared_transit_learned_prefix is not the candidate path" >&2
        exit 1
    }
    echo \
        "Shared adjacent-origin equality verified; REN transit-learned wins " \
        "despite ISP's shorter AS path."

    for node in R1 R2 R3; do
        assert_equal "$node full OSPF neighbors" 2 "$(lab_routeros_numeric_output "$node" "/routing/ospf/neighbor/print count-only where state=Full")"
    done
    echo "OSPF full-neighbor counts verified."

    shared_prefix=$(python3 -c '
import json
from pathlib import Path

manifest = json.loads(Path("generated/manifest.json").read_text(encoding="utf-8"))
print(next(route["prefix"] for route in manifest["routes"]["isp"] if route["shared"]))
')

    echo "Shared-prefix route containment verified for $shared_prefix; adjacent-origin winner is intentionally unspecified."

    for node in R2 R3; do
        route_output=$(lab_routeros_command "$node" "/routing/route/print detail where dst-address=0.0.0.0/0" | tr -d '\r')
        grep -Eq '^[[:space:]]*Ao[[:space:]]' <<<"$route_output" || {
            echo "validation: $node has no active OSPF default route" >&2
            exit 1
        }
        grep -Fq '.type=ext-type-1' <<<"$route_output" || {
            echo "validation: $node default route is not OSPF external type 1" >&2
            exit 1
        }
        assert_equal "$node external OSPF route count" 1 "$(lab_routeros_numeric_output "$node" "/routing/route/print count-only where belongs-to=campus-ospf and (ospf.type=ext-type-1 or ospf.type=ext-type-2)")"
        assert_equal "$node exact route for generated prefix" 0 "$(lab_routeros_numeric_output "$node" "/routing/route/print count-only where dst-address=$shared_prefix")"
    done

    for node in R1 R2 R3; do
        assert_equal "$node external OSPF LSA count" 1 "$(lab_routeros_numeric_output "$node" "/routing/ospf/lsa/print count-only where type=external")"
        lsa_output=$(lab_routeros_command "$node" "/routing/ospf/lsa/print detail where type=external and id=0.0.0.0" | tr -d '\r')
        grep -Fq 'metric=20 type-1' <<<"$lsa_output" || {
            echo "validation: $node has no OSPF external type 1 default LSA with metric 20" >&2
            exit 1
        }
    done
    echo "ISP-gated OSPF external type 1 default metric 20 verified."
}

case "$mode" in
    full)
        validate_endpoints
        isp=$(lab_require_running ISP)
        ren=$(lab_require_running REN)
        echo "ISP data address:"
        docker exec "$isp" ip -4 -br addr show dev eth1
        echo "REN data address:"
        docker exec "$ren" ip -4 -br addr show dev eth1
        echo "Generated route line counts:"
        printf '  ISP:   '
        lab_generated_route_count generated/isp.conf
        printf '  REN:   '
        lab_generated_route_count generated/ren.conf
        validate_control_plane
        ;;
    reachability-only)
        validate_endpoints
        ;;
    control-plane-only)
        validate_control_plane
        ;;
    filter-contract-only)
        validate_filter_contract
        ;;
    *)
        echo "usage: $0 [full|reachability-only|control-plane-only|filter-contract-only]" >&2
        exit 2
        ;;
esac
