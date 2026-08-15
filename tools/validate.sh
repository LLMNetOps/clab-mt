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
    local bgp_sessions expected_isp expected_idren shared_prefix route_output lsa_output

    lab_require_running R1 >/dev/null
    lab_require_running R2 >/dev/null
    lab_require_running R3 >/dev/null

    bgp_sessions=$(lab_routeros_command R1 "/routing/bgp/session/print terse" | tr -d '\r')
    for peer_address in 10.255.2.2 10.255.2.6; do
        if ! grep -Eq "^[[:space:]]*[0-9]+ E .*remote.address=${peer_address//./\\.}([[:space:]]|$)" <<<"$bgp_sessions"; then
            echo "validation: BGP peer $peer_address is not established" >&2
            exit 1
        fi
    done
    expected_isp=$(lab_manifest_count isp)
    expected_idren=$(lab_manifest_count idren)
    assert_equal "ISP received routes" "$expected_isp" "$(lab_routeros_numeric_output R1 "/routing/route/print count-only where belongs-to=bgp-IP-10.255.2.2")"
    assert_equal "IDREN received routes" "$expected_idren" "$(lab_routeros_numeric_output R1 "/routing/route/print count-only where belongs-to=bgp-IP-10.255.2.6")"
    echo "BGP sessions and received-route counts verified."

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

    route_output=$(lab_routeros_command R1 "/routing/route/print detail where dst-address=$shared_prefix and belongs-to=bgp-IP-10.255.2.6" | tr -d '\r')
    grep -Eq '^[[:space:]]*Ab[[:space:]]' <<<"$route_output" || {
        echo "validation: IDREN route for $shared_prefix is not active" >&2
        exit 1
    }
    grep -Fq '.local-pref=200' <<<"$route_output" || {
        echo "validation: IDREN route for $shared_prefix does not have local preference 200" >&2
        exit 1
    }

    route_output=$(lab_routeros_command R1 "/routing/route/print detail where dst-address=$shared_prefix and belongs-to=bgp-IP-10.255.2.2" | tr -d '\r')
    grep -Fq 'contribution=candidate' <<<"$route_output" || {
        echo "validation: ISP route for $shared_prefix is not the candidate path" >&2
        exit 1
    }
    grep -Fq '.local-pref=100' <<<"$route_output" || {
        echo "validation: ISP route for $shared_prefix does not have local preference 100" >&2
        exit 1
    }
    echo "IDREN local preference verified for shared prefix $shared_prefix."

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
        idren=$(lab_require_running IDREN)
        echo "ISP data address:"
        docker exec "$isp" ip -4 -br addr show dev eth1
        echo "IDREN data address:"
        docker exec "$idren" ip -4 -br addr show dev eth1
        echo "Generated route line counts:"
        printf '  ISP:   '
        lab_generated_route_count generated/isp.conf
        printf '  IDREN: '
        lab_generated_route_count generated/idren.conf
        validate_control_plane
        ;;
    reachability-only)
        validate_endpoints
        ;;
    control-plane-only)
        validate_control_plane
        ;;
    *)
        echo "usage: $0 [full|reachability-only|control-plane-only]" >&2
        exit 2
        ;;
esac
