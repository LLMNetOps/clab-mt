#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

usage() {
    cat <<EOF
Usage: $0 <status|release|renew> <H1|H2>

Inspect, release, or renew DHCP on one endpoint host.
EOF
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    usage
    exit 0
fi
if [[ $# != 2 ]]; then
    usage >&2
    exit 2
fi

action=$1
endpoint=$2
case "$action" in
    status|release|renew) ;;
    *)
        echo "Unknown DHCP client action: $action" >&2
        usage >&2
        exit 2
        ;;
esac
case "$endpoint" in
    H1|H2) ;;
    *)
        echo "Unknown endpoint host: $endpoint (expected H1 or H2)" >&2
        exit 2
        ;;
esac

timeout=${DHCP_TIMEOUT:-30}
if [[ ! "$timeout" =~ ^[1-9][0-9]*$ ]]; then
    echo "DHCP_TIMEOUT must be a positive integer" >&2
    exit 2
fi

LAB_CONTEXT="DHCP client"
source tools/lib/lab.sh

container=$(lab_require_running "$endpoint")
echo "$endpoint DHCP $action:"
docker exec \
    -e "DHCP_OPERATION_TIMEOUT=$timeout" \
    "$container" \
    /usr/local/bin/campus-dhcp-client "$action"
