#!/usr/bin/env bash
set -euo pipefail

readonly required_bridges=(ovs-bridge0 ovs-bridge1)

if ! command -v ovs-vsctl >/dev/null 2>&1; then
    echo "ovs-preflight: ovs-vsctl not found; install Open vSwitch on the host" >&2
    exit 1
fi

for bridge in "${required_bridges[@]}"; do
    status=0
    error=$(sudo ovs-vsctl br-exists "$bridge" 2>&1) || status=$?
    case $status in
        0) ;;
        2)
            echo "ovs-preflight: missing OVS bridge $bridge; run make ovs-prepare first" >&2
            exit 1
            ;;
        *)
            echo "ovs-preflight: $error; run with sudo if access is denied" >&2
            exit 1
            ;;
    esac
done

echo "OVS bridges present: ${required_bridges[*]}"
