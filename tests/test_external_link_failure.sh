#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

output=$(bash tools/external-link-failure.sh)

grep -F "ISP ExaBGP process continuity verified." <<<"$output"
grep -F "IDREN ExaBGP process continuity verified." <<<"$output"
grep -F "External-link failure scenarios passed." <<<"$output"
