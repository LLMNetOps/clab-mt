#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

output=$(bash tools/validate.sh control-plane-only)

grep -F "BGP sessions and received-route counts verified." <<<"$output"
grep -F "OSPF full-neighbor counts verified." <<<"$output"
grep -F "IDREN local preference verified for shared prefix" <<<"$output"
grep -F "OSPF external type 1 metric 20 verified for shared prefix" <<<"$output"
