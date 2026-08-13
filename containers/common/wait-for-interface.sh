#!/bin/sh

wait_for_interface() {
    interface=$1
    wait_seconds=$2
    caller=$3
    elapsed=0

    while ! ip link show dev "$interface" >/dev/null 2>&1; do
        if [ "$elapsed" -ge "$wait_seconds" ]; then
            echo "$caller: interface $interface did not appear within ${wait_seconds}s" >&2
            return 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
}
