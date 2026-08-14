#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

source_node=${TRAFFIC_SOURCE:-H1}
destination_node=${TRAFFIC_DESTINATION:-H2}
count=${TRAFFIC_COUNT:-0}
interval=${TRAFFIC_INTERVAL:-1}

usage() {
    cat <<EOF
Usage: $0 [--source H1|H2] [--destination H1|H2] [--count NUMBER] [--interval SECONDS]

Send ICMP traffic between the endpoint hosts. A count of 0 sends traffic until
you press Ctrl-C. Defaults: source H1, destination H2, count 0, interval 1.
EOF
}

while (($#)); do
    case $1 in
        --source|--destination|--count|--interval)
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
                --count) count=$value ;;
                --interval) interval=$value ;;
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

case "$source_node:$destination_node" in
    H1:H2|H2:H1) ;;
    *)
        echo "Traffic endpoints must be H1 and H2 in opposite directions." >&2
        exit 2
        ;;
esac

if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    echo "Traffic count must be zero or a positive integer." >&2
    exit 2
fi
if [[ ! "$interval" =~ ^[0-9]+([.][0-9]+)?$ || "$interval" =~ ^0+([.]0+)?$ ]]; then
    echo "Traffic interval must be a positive number of seconds." >&2
    exit 2
fi

LAB_CONTEXT="traffic"
source tools/lib/lab.sh

source_container=$(lab_require_running "$source_node")
destination_container=$(lab_require_running "$destination_node")
destination_ip=$(lab_wait_for_interface_ip "$destination_container" eth1 30 1)

ping_arguments=(-n -i "$interval")
if ((count > 0)); then
    ping_arguments+=(-c "$count")
    echo "Sending $count ICMP probes from $source_node to $destination_node ($destination_ip)..."
else
    echo "Sending ICMP traffic from $source_node to $destination_node ($destination_ip). Press Ctrl-C to stop."
fi

docker exec "$source_container" ping "${ping_arguments[@]}" "$destination_ip"
