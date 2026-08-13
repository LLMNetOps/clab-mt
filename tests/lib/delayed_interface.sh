#!/usr/bin/env bash

cleanup_test_container() {
    docker rm -f "$1" >/dev/null 2>&1 || true
}

assert_test_container_running() {
    local container=$1
    local label=$2
    local phase=$3

    if [[ "$(docker inspect -f '{{.State.Running}}' "$container")" != "true" ]]; then
        echo "$label startup test: container exited $phase eth1 was attached" >&2
        docker logs "$container" >&2
        exit 1
    fi
}

verify_delayed_interface_startup() {
    local container=$1
    local label=$2
    local post_attach_wait=$3

    sleep 1
    assert_test_container_running "$container" "$label" before
    docker exec "$container" ip link add eth1 type dummy
    sleep "$post_attach_wait"
    assert_test_container_running "$container" "$label" after
}
