#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

fixture_dir=$(mktemp -d)
cleanup() {
    rm -rf "$fixture_dir"
}
trap cleanup EXIT

fake_bin="$fixture_dir/bin"
state_dir="$fixture_dir/state"
mkdir -p "$fake_bin" "$state_dir"

cat >"$fake_bin/docker" <<'SH'
#!/bin/sh
case "$1" in
    info)
        exit 0
        ;;
    image)
        exit 1
        ;;
    *)
        exit 1
        ;;
esac
SH

cat >"$fake_bin/git" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$ROUTEROS_TEST_STATE/git.log"
if [ "$1" = clone ]; then
    for argument in "$@"; do
        destination=$argument
    done
    printf '%s\n' "$destination" >"$ROUTEROS_TEST_STATE/checkout"
    mkdir -p "$destination/mikrotik/routeros/docker"
    cat >"$destination/mikrotik/routeros/docker/Dockerfile" <<'DOCKERFILE'
FROM ghcr.io/srl-labs/vrnetlab-base:0.3.0
LABEL org.opencontainers.image.authors="roman@dodin.dev"

RUN apt-get update -qy \
   && apt-get install -y --no-install-recommends \
   qemu-system-x86 \
   qemu-efi-aarch64 \
   ftp \
   && rm -rf /var/lib/apt/lists/*
DOCKERFILE
fi
SH

cat >"$fake_bin/curl" <<'SH'
#!/bin/sh
set -eu

output=""
checkout=$(cat "$ROUTEROS_TEST_STATE/checkout")
dockerfile="$checkout/mikrotik/routeros/docker/Dockerfile"
grep -F 'FROM ghcr.io/srl-labs/vrnetlab-base:0.3.0@sha256:57f36ae1cf44a78a6b2cad35a6276565c56edfd28e8160ae9a772929db28fd6d' "$dockerfile" >/dev/null
grep -F 'snapshot.debian.org/archive/debian/20260610T000000Z' "$dockerfile" >/dev/null
grep -F 'snapshot.debian.org/archive/debian-security/20260610T000000Z' "$dockerfile" >/dev/null
grep -F "Check-Valid-Until: no" "$dockerfile" >/dev/null
grep -F 'qemu-system-x86=1:10.0.8+ds-0+deb13u1+b2' "$dockerfile" >/dev/null
grep -F 'qemu-efi-aarch64=2025.02-8+deb13u1' "$dockerfile" >/dev/null
grep -F 'ftp=20230507-2' "$dockerfile" >/dev/null
grep -F 'tnftp=20230507-2+b1' "$dockerfile" >/dev/null
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            output=$2
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
printf '%s\n' 'not the official RouterOS archive' >"$output"
SH

cat >"$fake_bin/unzip" <<'SH'
#!/bin/sh
touch "$ROUTEROS_TEST_STATE/unzip-called"
SH

cat >"$fake_bin/make" <<'SH'
#!/bin/sh
touch "$ROUTEROS_TEST_STATE/make-called"
SH

chmod 0755 "$fake_bin"/*

build_output="$state_dir/build-output"
if PATH="$fake_bin:$PATH" ROUTEROS_TEST_STATE="$state_dir" \
    bash tools/build-routeros-image.sh >"$build_output" 2>&1; then
    echo "RouterOS build accepted an archive with the wrong checksum" >&2
    exit 1
fi

if ! grep -F "RouterOS archive checksum mismatch" "$build_output" >/dev/null; then
    echo "RouterOS build did not reach archive verification:" >&2
    cat "$build_output" >&2
    exit 1
fi
grep -F "9dbcd465a75f7c2d048bd3342eac10c3537eb00d" "$state_dir/git.log" >/dev/null
if [[ -e "$state_dir/unzip-called" || -e "$state_dir/make-called" ]]; then
    echo "RouterOS build used an unverified archive" >&2
    exit 1
fi

echo "RouterOS image build rejects unverified input."
