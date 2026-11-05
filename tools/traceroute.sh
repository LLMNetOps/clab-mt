#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

source_node=${TRAFFIC_SOURCE:-H1}
destination_node=${TRAFFIC_DESTINATION:-H2}

usage() {
    cat <<EOF
Usage: $0 [--source H1|H2|H3|H4|R1|R2|R3|ISP|REN] [--destination H1|H2|H3|H4|R1|R2|R3|ISP|REN]

Trace the route between endpoint hosts. Defaults: source H1, destination H2.
EOF
}

is_routeros_node() {
    case $1 in
        R1|R2|R3) return 0 ;;
        *) return 1 ;;
    esac
}

routeros_loopback_ip() {
    case $1 in
        R1) printf '%s\n' 10.255.0.1 ;;
        R2) printf '%s\n' 10.255.0.2 ;;
        R3) printf '%s\n' 10.255.0.3 ;;
        *) return 1 ;;
    esac
}

while (($#)); do
    case $1 in
        --source|--destination)
            if (($# < 2)); then
                echo "Missing value for $1" >&2
                usage >&2
                exit 2
            fi
            option=$1
            value=$2
            shift 2
            case "$option" in
                --source) source_node=$value ;;
                --destination) destination_node=$value ;;
            esac
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$source_node" in
    H1|H2|H3|H4|R1|R2|R3|ISP|REN) ;;
    *)
        echo "Unknown traceroute source node: $source_node (expected H1-H4, R1-R3, ISP, or REN)." >&2
        exit 2
        ;;
esac
case "$destination_node" in
    H1|H2|H3|H4|R1|R2|R3|ISP|REN) ;;
    *)
        echo "Unknown traceroute destination node: $destination_node (expected H1-H4, R1-R3, ISP, or REN)." >&2
        exit 2
        ;;
esac
if [[ "$source_node" == "$destination_node" ]]; then
    echo "Traceroute source and destination must be different nodes." >&2
    exit 2
fi

LAB_CONTEXT="traceroute"
source tools/lib/lab.sh

source_container=$(lab_require_running "$source_node")
if is_routeros_node "$destination_node"; then
    lab_require_running "$destination_node" >/dev/null
    destination_ip=$(routeros_loopback_ip "$destination_node")
else
    destination_container=$(lab_require_running "$destination_node")
    destination_ip=$(lab_wait_for_interface_ip "$destination_container" eth1 30 1)
fi

echo "Tracing route from $source_node to $destination_node ($destination_ip)..."
if is_routeros_node "$source_node"; then
    lab_routeros_command "$source_node" \
        "/tool traceroute address=$destination_ip duration=5s"
else
    docker exec "$source_container" traceroute -n "$destination_ip"
fi