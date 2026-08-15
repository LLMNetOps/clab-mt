#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

source tools/lib/links.sh

[[ "$(lab_link_names | paste -sd ' ' -)" == "r2-r3 isp idren" ]]
[[ "$(lab_link_target r2-r3)" == "R2|eth2|R2:ether3 - R3:ether3" ]]
[[ "$(lab_link_target isp)" == "R1|eth3|R1:ether4 - ISP:eth1" ]]
[[ "$(lab_link_target idren)" == "R1|eth4|R1:ether5 - IDREN:eth1" ]]
if lab_link_target unknown >/dev/null; then
    echo "Unknown link was accepted" >&2
    exit 1
fi

bash tools/build-routeros-image.sh --help | grep -F "vrnetlab/mikrotik_routeros:7.21.5" >/dev/null
routeros_inputs=$(bash tools/build-routeros-image.sh --print-inputs)
grep -F "vrnetlab-commit: 9dbcd465a75f7c2d048bd3342eac10c3537eb00d" \
    <<<"$routeros_inputs" >/dev/null
grep -F "archive-sha256: acc6b562ad870116c28ce0246e99deac984d815bd9893197ee9b5897422543eb" \
    <<<"$routeros_inputs" >/dev/null
grep -F "vrnetlab-base-digest: sha256:57f36ae1cf44a78a6b2cad35a6276565c56edfd28e8160ae9a772929db28fd6d" \
    <<<"$routeros_inputs" >/dev/null
grep -F "debian-snapshot: 20260610T000000Z" <<<"$routeros_inputs" >/dev/null
grep -F "ftp-package: 20230507-2" <<<"$routeros_inputs" >/dev/null
grep -F "tnftp-package: 20230507-2+b1" <<<"$routeros_inputs" >/dev/null
grep -F "qemu-efi-aarch64-package: 2025.02-8+deb13u1" \
    <<<"$routeros_inputs" >/dev/null
grep -F "qemu-system-x86-package: 1:10.0.8+ds-0+deb13u1+b2" \
    <<<"$routeros_inputs" >/dev/null
bash tools/link-state.sh --help | grep -F "r2-r3|isp|idren" >/dev/null
bash tools/restart-router.sh --help | grep -F "Usage: tools/restart-router.sh R1" >/dev/null
bash tools/traffic.sh --help | grep -F "Send ICMP traffic" >/dev/null
bash tools/dhcp-client.sh --help | grep -F "H1|H2" >/dev/null
sh containers/endpoint/dhcp-client.sh --help | grep -F "status|release|renew" >/dev/null

if bash tools/link-state.sh down unknown >/dev/null 2>&1; then
    echo "link-state accepted an unknown link" >&2
    exit 1
fi
if bash tools/restart-router.sh H1 >/dev/null 2>&1; then
    echo "restart-router accepted an endpoint host" >&2
    exit 1
fi
if bash tools/restart-router.sh R2 >/dev/null 2>&1; then
    echo "restart-router accepted an out-of-scope campus router" >&2
    exit 1
fi
if bash tools/traffic.sh --count invalid >/dev/null 2>&1; then
    echo "traffic accepted an invalid count" >&2
    exit 1
fi
if bash tools/traffic.sh --interval 0 >/dev/null 2>&1; then
    echo "traffic accepted a zero interval" >&2
    exit 1
fi
if bash tools/dhcp-client.sh renew R1 >/dev/null 2>&1; then
    echo "DHCP client tool accepted a router as an endpoint host" >&2
    exit 1
fi

echo "Operator tool interfaces passed."
