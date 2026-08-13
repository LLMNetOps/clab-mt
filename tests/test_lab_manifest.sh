#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

fixture_dir=$(mktemp -d)
cleanup() {
    rm -rf "$fixture_dir"
}
trap cleanup EXIT

manifest_fixture="$fixture_dir/manifest.json"
routes_fixture="$fixture_dir/routes.conf"
printf '%s\n' '{"counts":{"isp":7,"idren":3}}' >"$manifest_fixture"
printf '%s\n' \
    '        route 10.64.0.0/16 next-hop self;' \
    '        route 10.65.0.0/16 {' \
    '            next-hop self;' \
    '        }' >"$routes_fixture"

LAB_MANIFEST_PATH=$manifest_fixture
source tools/lib/lab.sh

[[ "$(lab_manifest_count isp)" == 7 ]]
[[ "$(lab_manifest_count idren)" == 3 ]]
[[ "$(lab_generated_route_count "$routes_fixture")" == 2 ]]

echo "Generated route metadata lookups passed."
