#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

LAB_CONTEXT="link state"
source tools/lib/lab.sh
source tools/lib/links.sh

usage() {
    cat <<EOF
Usage: $0 <status|down|up> <r2-r3|isp|idren>
       $0 list

Show, disable, or restore one data-plane link in the deployed lab.
Links that are disabled with this command stay disabled until they are restored
with the 'up' action or the lab is destroyed.
EOF
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    usage
    exit 0
fi

if [[ ${1:-} == list && $# == 1 ]]; then
    lab_link_names
    exit 0
fi

if [[ $# != 2 ]]; then
    usage >&2
    exit 2
fi

action=$1
link=$2
case "$action" in
    status|down|up) ;;
    *)
        echo "Unknown link action: $action" >&2
        usage >&2
        exit 2
        ;;
esac

if ! target=$(lab_link_target "$link"); then
    echo "Unknown link: $link" >&2
    echo "Valid links: $(lab_link_names | paste -sd '|' -)" >&2
    exit 2
fi

IFS='|' read -r node interface label <<<"$target"
container=$(lab_require_running "$node")

if [[ "$action" == status ]]; then
    echo "$link ($label):"
    docker exec "$container" ip -brief link show dev "$interface"
    exit 0
fi

docker exec "$container" ip link set dev "$interface" "$action"
echo "$link ($label) is administratively $action."
