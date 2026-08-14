#!/usr/bin/env bash
set -euo pipefail

routeros_version=7.21.5
routeros_image="vrnetlab/mikrotik_routeros:$routeros_version"
routeros_archive="chr-$routeros_version.vmdk.zip"
routeros_url="https://download.mikrotik.com/routeros/$routeros_version/$routeros_archive"
vrnetlab_repository="https://github.com/srl-labs/vrnetlab.git"
vrnetlab_commit=9dbcd465a75f7c2d048bd3342eac10c3537eb00d
routeros_archive_sha256=acc6b562ad870116c28ce0246e99deac984d815bd9893197ee9b5897422543eb
vrnetlab_base_digest=sha256:57f36ae1cf44a78a6b2cad35a6276565c56edfd28e8160ae9a772929db28fd6d
debian_snapshot=20260610T000000Z
ftp_package=20230507-2
tnftp_package=20230507-2+b1
qemu_efi_aarch64_package=2025.02-8+deb13u1
qemu_system_x86_package=1:10.0.8+ds-0+deb13u1+b2
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vrnetlab_patch="$root_dir/containers/routeros/vrnetlab-routeros.patch"
force=false

verify_routeros_archive() {
    local archive_path=$1
    local actual_sha256
    actual_sha256=$(sha256sum "$archive_path" | awk '{print $1}')
    if [[ "$actual_sha256" != "$routeros_archive_sha256" ]]; then
        echo "RouterOS archive checksum mismatch" >&2
        echo "  expected: $routeros_archive_sha256" >&2
        echo "  actual:   $actual_sha256" >&2
        return 1
    fi
}

usage() {
    cat <<EOF
Usage: $0 [--force]
       $0 --print-inputs

Build the pinned $routeros_image image from the official MikroTik CHR archive.
The build uses a temporary clone of the Containerlab-compatible vrnetlab fork.

Options:
  --force  rebuild the image even when the local tag already exists
  --print-inputs
           print the immutable source, image, repository, and package inputs
  -h, --help
           show this help
EOF
}

case ${1:-} in
    "") ;;
    --force) force=true ;;
    --print-inputs)
        printf 'vrnetlab-commit: %s\n' "$vrnetlab_commit"
        printf 'archive-sha256: %s\n' "$routeros_archive_sha256"
        printf 'vrnetlab-base-digest: %s\n' "$vrnetlab_base_digest"
        printf 'debian-snapshot: %s\n' "$debian_snapshot"
        printf 'ftp-package: %s\n' "$ftp_package"
        printf 'tnftp-package: %s\n' "$tnftp_package"
        printf 'qemu-efi-aarch64-package: %s\n' "$qemu_efi_aarch64_package"
        printf 'qemu-system-x86-package: %s\n' "$qemu_system_x86_package"
        exit 0
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if (($# > 1)); then
    usage >&2
    exit 2
fi

for command in docker git curl unzip make patch sha256sum; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "RouterOS image build: required command not found: $command" >&2
        exit 1
    fi
done

if ! docker info >/dev/null 2>&1; then
    echo "RouterOS image build: Docker is not available to the current user" >&2
    exit 1
fi

if [[ "$force" == false ]] && docker image inspect "$routeros_image" >/dev/null 2>&1; then
    echo "RouterOS image already exists: $routeros_image"
    exit 0
fi

build_dir=$(mktemp -d)
cleanup() {
    rm -rf "$build_dir"
}
trap cleanup EXIT

echo "Cloning pinned vrnetlab commit $vrnetlab_commit..."
git clone --no-checkout "$vrnetlab_repository" "$build_dir/vrnetlab"
git -C "$build_dir/vrnetlab" checkout --detach "$vrnetlab_commit"

routeros_dir="$build_dir/vrnetlab/mikrotik/routeros"
echo "Locking the vrnetlab base image and Debian package inputs..."
patch --batch --forward --directory="$routeros_dir" --strip=1 <"$vrnetlab_patch"

echo "Downloading RouterOS $routeros_version CHR..."
curl --fail --location --retry 3 --output "$routeros_dir/$routeros_archive" "$routeros_url"

echo "Verifying the RouterOS CHR archive..."
verify_routeros_archive "$routeros_dir/$routeros_archive"

echo "Extracting the RouterOS CHR disk..."
(
    cd "$routeros_dir"
    unzip -q "$routeros_archive"
)

echo "Building $routeros_image..."
make -C "$routeros_dir" docker-image

if ! docker image inspect "$routeros_image" >/dev/null 2>&1; then
    echo "RouterOS image build completed without creating $routeros_image" >&2
    exit 1
fi

echo "RouterOS image is ready: $routeros_image"
