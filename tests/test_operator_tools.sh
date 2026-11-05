#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

source tools/lib/links.sh

[[ "$(lab_link_names | paste -sd ' ' -)" == "r1-r2 r1-r3 r2-r3 isp ren" ]]
[[ "$(lab_link_target r1-r2)" == "R1|eth1|R1:ether2 - R2:ether2" ]]
[[ "$(lab_link_target r1-r3)" == "R1|eth2|R1:ether3 - R3:ether2" ]]
[[ "$(lab_link_target r2-r3)" == "R2|eth2|R2:ether3 - R3:ether3" ]]
[[ "$(lab_link_target isp)" == "R1|eth3|R1:ether4 - ISP:eth1" ]]
[[ "$(lab_link_target ren)" == "R1|eth4|R1:ether5 - REN:eth1" ]]
[[ "$(lab_link_name_for_pair r1 r2)" == "r1-r2" ]]
[[ "$(lab_link_name_for_pair R1 ISP)" == "isp" ]]
[[ "$(lab_link_name_for_pair r3 r2)" == "r2-r3" ]]
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
bash tools/link-state.sh --help | grep -F "r1-r2|r1-r3|r2-r3|isp|ren" >/dev/null
link_pair_command=$(make -n link status r1 r2)
grep -F 'tools/link-state.sh "status" "r1" "r2"' <<<"$link_pair_command" >/dev/null
link_external_command=$(make -n link down r1 isp)
grep -F 'tools/link-state.sh "down" "r1" "isp"' <<<"$link_external_command" >/dev/null
bash tools/restart-router.sh --help | grep -F "Usage: tools/restart-router.sh R1" >/dev/null
bash tools/traffic.sh --help | grep -F "Send ICMP traffic" >/dev/null
bash tools/traceroute.sh --help | grep -F "H1|H2|H3|H4|R1|R2|R3|ISP|REN" >/dev/null
traceroute_command=$(make -n traceroute H1 H4)
grep -F 'TRAFFIC_SOURCE="H1"' <<<"$traceroute_command" >/dev/null
grep -F 'TRAFFIC_DESTINATION="H4"' <<<"$traceroute_command" >/dev/null
dhcp_status_command=$(make -n dhcp-status H4)
grep -F 'dhcp-client.sh status "H4"' <<<"$dhcp_status_command" >/dev/null
dhcp_default_command=$(make -n dhcp-status)
grep -F 'dhcp-client.sh status "H1"' <<<"$dhcp_default_command" >/dev/null
dhcp_legacy_command=$(make -n dhcp-status ENDPOINT=H2)
grep -F 'dhcp-client.sh status "H2"' <<<"$dhcp_legacy_command" >/dev/null
dhcp_release_command=$(make -n dhcp-release H2)
grep -F 'dhcp-client.sh release "H2"' <<<"$dhcp_release_command" >/dev/null
dhcp_renew_command=$(make -n dhcp-renew H3)
grep -F 'dhcp-client.sh renew "H3"' <<<"$dhcp_renew_command" >/dev/null
bash tools/dhcp-client.sh --help | grep -F "H1|H2|H3|H4" >/dev/null
bash tools/traffic.sh --help | grep -F "H1|H2|H3|H4" >/dev/null
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
if bash tools/traffic.sh --source H5 --destination H4 >/dev/null 2>&1; then
    echo "traffic tool accepted an unknown endpoint host" >&2
    exit 1
fi
if bash tools/traffic.sh --source H3 --destination H3 >/dev/null 2>&1; then
    echo "traffic tool accepted the same endpoint as source and destination" >&2
    exit 1
fi
if bash tools/traceroute.sh --source H5 --destination H4 >/dev/null 2>&1; then
    echo "traceroute tool accepted an unknown endpoint host" >&2
    exit 1
fi
if bash tools/traceroute.sh --source H3 --destination H3 >/dev/null 2>&1; then
    echo "traceroute tool accepted the same endpoint as source and destination" >&2
    exit 1
fi
for node in ISP REN R1 R2 R3; do
    traceroute_error=$(bash tools/traceroute.sh --source "$node" --destination "$node" 2>&1 || true)
    grep -F "Traceroute source and destination must be different nodes." \
        <<<"$traceroute_error" >/dev/null
done

ovs_fixture=$(mktemp -d)
trap 'rm -rf "$ovs_fixture"' EXIT
cat >"$ovs_fixture/ovs-vsctl" <<'EOF'
#!/usr/bin/env bash
set -e
[[ "${OVS_DENIED:-}" != 1 ]] || { echo "database connection failed (Permission denied)" >&2; exit 1; }
case "$1" in
    br-exists)
        if [[ -e "$OVS_FIXTURE/$2" ]]; then exit 0; else exit 2; fi
        ;;
    add-br)
        [[ "$3" == -- && "$4" == set && "$5" == bridge ]] || exit 1
        touch "$OVS_FIXTURE/$2" "$OVS_FIXTURE/$6-owned"
        ;;
    get)
        echo "ovs-vsctl: no key in record" >&2
        exit 1
        ;;
    list-ports)
        if [[ -f "$OVS_FIXTURE/$2-ports" ]]; then
            cat "$OVS_FIXTURE/$2-ports"
        fi
        ;;
    --if-exists)
        if [[ "$2" == get ]]; then
            [[ -e "$OVS_FIXTURE/$4-owned" ]] && echo '"true"'
            exit 0
        fi
        [[ "$2" == del-br ]] || exit 1
        rm -f "$OVS_FIXTURE/$3" "$OVS_FIXTURE/$3-owned"
        ;;
    *)
        exit 1
        ;;
esac
EOF
cat >"$ovs_fixture/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
chmod +x "$ovs_fixture/ovs-vsctl"
chmod +x "$ovs_fixture/sudo"
touch "$ovs_fixture/ovs-bridge0"
OVS_FIXTURE="$ovs_fixture" PATH="$ovs_fixture:$PATH" bash tools/ovs-bridges.sh ensure >/dev/null
OVS_FIXTURE="$ovs_fixture" PATH="$ovs_fixture:$PATH" bash tools/ovs-preflight.sh >/dev/null
[[ -e "$ovs_fixture/ovs-bridge0" && ! -e "$ovs_fixture/ovs-bridge0-owned" ]]
[[ -e "$ovs_fixture/ovs-bridge1" && -e "$ovs_fixture/ovs-bridge1-owned" ]]
rm "$ovs_fixture/ovs-bridge1"
if OVS_FIXTURE="$ovs_fixture" PATH="$ovs_fixture:$PATH" \
    bash tools/ovs-preflight.sh >/dev/null 2>"$ovs_fixture/error"; then
    echo "OVS preflight accepted a missing bridge" >&2
    exit 1
fi
grep -F "missing OVS bridge ovs-bridge1" "$ovs_fixture/error" >/dev/null
OVS_FIXTURE="$ovs_fixture" PATH="$ovs_fixture:$PATH" \
    bash tools/ovs-bridges.sh cleanup >/dev/null
[[ -e "$ovs_fixture/ovs-bridge0" && ! -e "$ovs_fixture/ovs-bridge1" ]]
touch "$ovs_fixture/ovs-bridge0" "$ovs_fixture/ovs-bridge0-owned"
echo "external-port" >"$ovs_fixture/ovs-bridge0-ports"
OVS_FIXTURE="$ovs_fixture" PATH="$ovs_fixture:$PATH" \
    bash tools/ovs-bridges.sh cleanup >/dev/null 2>"$ovs_fixture/error"
[[ -e "$ovs_fixture/ovs-bridge0" ]]
grep -F "remaining ports" "$ovs_fixture/error" >/dev/null
mkdir "$ovs_fixture/empty"
if PATH="$ovs_fixture/empty" "$BASH" tools/ovs-preflight.sh >/dev/null 2>&1; then
    echo "OVS preflight accepted a host without ovs-vsctl" >&2
    exit 1
fi
if OVS_DENIED=1 PATH="$ovs_fixture:$PATH" bash tools/ovs-preflight.sh >/dev/null 2>"$ovs_fixture/error"; then
    echo "OVS preflight accepted a denied database query" >&2
    exit 1
fi
grep -F "Permission denied" "$ovs_fixture/error" >/dev/null

deps_fixture=$(mktemp -d)
trap 'rm -rf "$ovs_fixture" "$deps_fixture"' EXIT
deps_ready_bin="$deps_fixture/ready-bin"
deps_install_bin="$deps_fixture/install-bin"
mkdir -p "$deps_ready_bin" "$deps_install_bin"
for executable in ovs-vsctl unzip containerlab; do
    printf '#!/bin/bash\nexit 0\n' >"$deps_ready_bin/$executable"
    chmod +x "$deps_ready_bin/$executable"
done
PATH="$deps_ready_bin" /bin/bash tools/install-dependencies.sh \
    >"$deps_fixture/ready-output"
grep -F "Deploy dependencies are ready." "$deps_fixture/ready-output" >/dev/null

cat >"$deps_install_bin/apt-get" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$DEPS_LOG"
if [[ "$1" == install ]]; then
    for executable in ovs-vsctl unzip; do
        printf '#!/bin/bash\nexit 0\n' >"$DEPS_BIN/$executable"
        /bin/chmod +x "$DEPS_BIN/$executable"
    done
    /bin/cat >"$DEPS_BIN/curl" <<'CURL'
#!/bin/bash
output=
while (($#)); do
    if [[ "$1" == --output ]]; then output=$2; shift 2; else shift; fi
done
/bin/cat >"$output" <<'INSTALLER'
#!/bin/bash
printf '#!/bin/bash\nexit 0\n' >"$DEPS_BIN/containerlab"
/bin/chmod +x "$DEPS_BIN/containerlab"
INSTALLER
CURL
    /bin/chmod +x "$DEPS_BIN/curl"
fi
EOF
cat >"$deps_install_bin/mktemp" <<'EOF'
#!/bin/bash
: >"$DEPS_TEMP_FILE"
printf '%s\n' "$DEPS_TEMP_FILE"
EOF
cat >"$deps_install_bin/rm" <<'EOF'
#!/bin/bash
exec /bin/rm "$@"
EOF
cat >"$deps_install_bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
chmod +x "$deps_install_bin"/*
ln -s /bin/bash "$deps_install_bin/bash"
DEPS_BIN="$deps_install_bin" \
DEPS_LOG="$deps_fixture/apt.log" \
DEPS_TEMP_FILE="$deps_fixture/containerlab-installer" \
PATH="$deps_install_bin" /bin/bash tools/install-dependencies.sh \
    >"$deps_fixture/install-output"
grep -Fx "update" "$deps_fixture/apt.log" >/dev/null
grep -Fx "install --yes openvswitch-switch unzip curl" "$deps_fixture/apt.log" >/dev/null
[[ -x "$deps_install_bin/ovs-vsctl" ]]
[[ -x "$deps_install_bin/unzip" ]]
[[ -x "$deps_install_bin/containerlab" ]]
grep -F "Installing Containerlab with its official installer" \
    "$deps_fixture/install-output" >/dev/null

echo "Operator tool interfaces passed."
