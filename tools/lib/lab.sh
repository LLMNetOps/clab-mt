#!/usr/bin/env bash

LAB_PREFIX=${CLAB_LAB_PREFIX:-clab-campus-ebgp}
LAB_CONTEXT=${LAB_CONTEXT:-lab}
LAB_MANIFEST_PATH=${LAB_MANIFEST_PATH:-generated/manifest.json}

lab_manifest_count() {
    local speaker=$1
    python3 - "$LAB_MANIFEST_PATH" "$speaker" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(manifest["counts"][sys.argv[2]])
PY
}

lab_generated_route_count() {
    local config_path=$1
    awk '/^        route / { count++ } END { print count + 0 }' "$config_path"
}

lab_container_for() {
    local node=$1
    local expected="${LAB_PREFIX}-${node}"
    if docker inspect "$expected" >/dev/null 2>&1; then
        printf '%s\n' "$expected"
        return
    fi
    docker ps -a --filter "name=${expected}" --format '{{.Names}}' | head -n 1
}

lab_require_running() {
    local node=$1
    local container
    container=$(lab_container_for "$node")
    if [[ -z "$container" ]]; then
        echo "$LAB_CONTEXT: container for $node was not found" >&2
        exit 1
    fi
    if [[ "$(docker inspect -f '{{.State.Running}}' "$container")" != "true" ]]; then
        echo "$LAB_CONTEXT: $node ($container) is not running" >&2
        exit 1
    fi
    printf '%s\n' "$container"
}

lab_interface_ip() {
    local container=$1
    local interface=${2:-eth1}
    docker exec "$container" sh -c \
        "ip -4 -o addr show dev '$interface' | awk '\$4 !~ /^169\\.254/ {sub(\"/.*\", \"\", \$4); print \$4; exit}' 2>/dev/null || true"
}

lab_wait_for_interface_ip() {
    local container=$1
    local interface=${2:-eth1}
    local attempts=${3:-30}
    local interval=${4:-1}
    local address=""
    local attempt

    for attempt in $(seq 1 "$attempts"); do
        address=$(lab_interface_ip "$container" "$interface")
        if [[ -n "$address" ]]; then
            printf '%s\n' "$address"
            return 0
        fi
        sleep "$interval"
    done

    echo "$LAB_CONTEXT: $container:$interface has no IPv4 address after $attempts attempts" >&2
    return 1
}

lab_routeros_command() {
    local node=$1
    local command=$2
    local password=${ROUTEROS_PASSWORD:-admin}
    local host="${LAB_PREFIX}-${node}"

    ROUTEROS_HOST="$host" ROUTEROS_PASSWORD="$password" ROUTEROS_COMMAND="$command" python3 -c '
import os
import pexpect

child = pexpect.spawn(
    "ssh",
    [
        "-o", "LogLevel=ERROR",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=5",
        "admin@" + os.environ["ROUTEROS_HOST"],
        os.environ["ROUTEROS_COMMAND"],
    ],
    encoding="utf-8",
    timeout=20,
)
child.expect("(?i)password:")
child.sendline(os.environ["ROUTEROS_PASSWORD"])
child.expect(pexpect.EOF)
print(child.before, end="")
child.close()
raise SystemExit(child.exitstatus or 0)
'
}

lab_routeros_numeric_output() {
    local node=$1
    local command=$2
    lab_routeros_command "$node" "$command" \
        | tr -d '\r' \
        | awk '/^[[:space:]]*[0-9]+[[:space:]]*$/ { value=$1 } END { print value }'
}
