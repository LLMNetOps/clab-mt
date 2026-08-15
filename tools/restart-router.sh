#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

LAB_CONTEXT="router restart"
source tools/lib/lab.sh

usage() {
    cat <<EOF
Usage: $0 R1

Request a native RouterOS reboot of the deployed R1 router.
EOF
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    usage
    exit 0
fi

if [[ $# != 1 ]]; then
    usage >&2
    exit 2
fi

router=$1
case "$router" in
    R1) ;;
    *)
        echo "Unsupported RouterOS node: $router" >&2
        usage >&2
        exit 2
        ;;
esac

lab_require_running "$router" >/dev/null
lab_routeros_command "$router" "/system/identity/print" >/dev/null

# SSH can report a disconnect while RouterOS processes the accepted reboot.
lab_routeros_command "$router" "/system/reboot" >/dev/null 2>&1 || true
echo "$router restart requested."
