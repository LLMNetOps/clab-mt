#!/usr/bin/env bash
set -euo pipefail

readonly required_bridges=(ovs-bridge0 ovs-bridge1)
readonly ownership_key=clab-mt-managed

usage() {
    echo "Usage: $0 ensure|cleanup" >&2
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

action=$1
if [[ "$action" != ensure && "$action" != cleanup ]]; then
    usage
    exit 2
fi

if ! command -v ovs-vsctl >/dev/null 2>&1; then
    echo "ovs-bridges: ovs-vsctl not found; install Open vSwitch on the host" >&2
    exit 1
fi

for bridge in "${required_bridges[@]}"; do
    status=0
    error=$(sudo ovs-vsctl br-exists "$bridge" 2>&1) || status=$?
    if [[ $status -eq 0 ]]; then
        if [[ "$action" == ensure ]]; then
            echo "OVS bridge already exists; leaving ownership unchanged: $bridge"
        fi
        continue
    fi

    if [[ "$action" == ensure ]]; then
        if [[ $status -ne 2 ]]; then
            echo "ovs-bridges: $error; run with sudo if access is denied" >&2
            exit "$status"
        fi
        sudo ovs-vsctl add-br "$bridge" -- set bridge "$bridge" \
            "external_ids:${ownership_key}=true"
        echo "Created managed OVS bridge: $bridge"
        continue
    fi

    if [[ $status -ne 0 && $status -ne 2 ]]; then
        echo "ovs-bridges: $error; run with sudo if access is denied" >&2
        exit "$status"
    fi
done

if [[ "$action" == cleanup ]]; then
    for bridge in "${required_bridges[@]}"; do
        status=0
        error=$(sudo ovs-vsctl br-exists "$bridge" 2>&1) || status=$?
        case $status in
            0) ;;
            2) continue ;;
            *)
                echo "ovs-bridges: $error; run with sudo if access is denied" >&2
                exit "$status"
                ;;
        esac

        owner=$(sudo ovs-vsctl --if-exists get bridge "$bridge" "external_ids:${ownership_key}" 2>/dev/null || true)
        if [[ "$owner" != '"true"' ]]; then
            echo "Leaving unmanaged OVS bridge in place: $bridge"
            continue
        fi

        ports=$(sudo ovs-vsctl list-ports "$bridge")
        if [[ -n "$ports" ]]; then
            echo "Leaving managed OVS bridge with remaining ports in place: $bridge" >&2
            continue
        fi

        sudo ovs-vsctl --if-exists del-br "$bridge"
        echo "Removed managed OVS bridge: $bridge"
    done
fi
