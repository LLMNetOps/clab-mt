#!/bin/sh
set -eu

interface=${DHCP_INTERFACE:-eth1}
operation_timeout=${DHCP_OPERATION_TIMEOUT:-30}
state_dir=/run/campus-dhcp-client
enabled_file=$state_dir/enabled
# Debian's dhclient AppArmor profile permits /run/dhclient*.pid even when the
# client runs inside a container. Keep its native PID file in that namespace;
# the supervisor's desired-state marker remains in state_dir.
pid_file=/run/dhclient.campus.pid
lease_file=/var/lib/dhcp/dhclient.campus.leases
child_pid=""

usage() {
    cat <<EOF
Usage: $0 <status|release|renew>

Inspect, release, or renew the IPv4 DHCP lease on $interface.
EOF
}

interface_address() {
    ip -4 -o address show dev "$interface" scope global \
        | awk '{sub("/.*", "", $4); print $4; exit}'
}

default_route() {
    ip -4 route show default dev "$interface" | head -n 1
}

client_is_running() {
    [ -s "$pid_file" ] || return 1
    client_pid=$(cat "$pid_file")
    kill -0 "$client_pid" >/dev/null 2>&1
}

show_status() {
    address=$(interface_address)
    route=$(default_route)
    if [ -e "$enabled_file" ]; then
        desired_state=enabled
    else
        desired_state=released
    fi
    if client_is_running; then
        process_state=running
    else
        process_state=stopped
    fi

    printf 'interface: %s\n' "$interface"
    printf 'client: %s (%s)\n' "$desired_state" "$process_state"
    printf 'address: %s\n' "${address:-none}"
    printf 'default-route: %s\n' "${route:-none}"
}

release_client() {
    mkdir -p "$state_dir"
    rm -f "$enabled_file"

    if client_is_running; then
        dhclient -4 -v -r -pf "$pid_file" -lf "$lease_file" "$interface" || true
    fi

    ip -4 address flush dev "$interface" scope global
    ip -4 route flush default dev "$interface"
}

release_is_complete() {
    ! client_is_running && [ -z "$(interface_address)" ]
}

lease_is_ready() {
    [ -n "$(interface_address)" ] && [ -n "$(default_route)" ]
}

wait_for_state() {
    state_name=$1
    state_check=$2
    elapsed=0
    while [ "$elapsed" -lt "$operation_timeout" ]; do
        if "$state_check"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "DHCP client: lease $state_name did not complete within ${operation_timeout}s" >&2
    return 1
}

release_operation() {
    release_client
    wait_for_state release release_is_complete
    show_status
}

renew_operation() {
    release_client
    wait_for_state release release_is_complete
    touch "$enabled_file"
    wait_for_state renewal lease_is_ready
    show_status
}

stop_supervisor() {
    rm -f "$enabled_file"
    if [ -n "$child_pid" ] && kill -0 "$child_pid" >/dev/null 2>&1; then
        kill "$child_pid" >/dev/null 2>&1 || true
        wait "$child_pid" 2>/dev/null || true
    fi
    exit 0
}

supervise_client() {
    mkdir -p "$state_dir"
    touch "$enabled_file"
    trap stop_supervisor INT TERM HUP

    while :; do
        if [ ! -e "$enabled_file" ]; then
            sleep 1
            continue
        fi

        dhclient -4 -d -v -pf "$pid_file" -lf "$lease_file" "$interface" &
        child_pid=$!
        wait "$child_pid" || true
        child_pid=""
        rm -f "$pid_file"

        if [ -e "$enabled_file" ]; then
            sleep 1
        fi
    done
}

action=${1:-}
if [ "$action" = -h ] || [ "$action" = --help ]; then
    usage
    exit 0
fi
if [ "$#" -ne 1 ]; then
    usage >&2
    exit 2
fi

case "$action" in
    supervise) action_handler=supervise_client ;;
    status) action_handler=show_status ;;
    release) action_handler=release_operation ;;
    renew) action_handler=renew_operation ;;
    *)
        usage >&2
        exit 2
        ;;
esac

case "$operation_timeout" in
    ''|*[!0-9]*)
        echo "DHCP client: operation timeout must be a positive integer" >&2
        exit 2
        ;;
esac
if [ "$operation_timeout" -eq 0 ]; then
    echo "DHCP client: operation timeout must be a positive integer" >&2
    exit 2
fi

"$action_handler"
