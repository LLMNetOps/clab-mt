#!/usr/bin/env bash
set -euo pipefail

readonly containerlab_installer_url="https://get.containerlab.dev"
apt_packages=()

if ! command -v ovs-vsctl >/dev/null 2>&1; then
    apt_packages+=(openvswitch-switch)
fi
if ! command -v unzip >/dev/null 2>&1; then
    apt_packages+=(unzip)
fi
if ! command -v containerlab >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    apt_packages+=(curl)
fi

run_privileged() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "deploy dependencies: root privileges or sudo are required to install missing tools" >&2
        return 1
    fi
}

if ((${#apt_packages[@]} > 0)); then
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "deploy dependencies: apt-get is required to install ${apt_packages[*]}" >&2
        exit 1
    fi
    echo "Installing missing host packages: ${apt_packages[*]}"
    run_privileged apt-get update
    run_privileged apt-get install --yes "${apt_packages[@]}"
fi

if ! command -v containerlab >/dev/null 2>&1; then
    if ! command -v curl >/dev/null 2>&1; then
        echo "deploy dependencies: curl is required to install Containerlab" >&2
        exit 1
    fi

    installer_path=$(mktemp)
    trap 'rm -f "$installer_path"' EXIT
    echo "Installing Containerlab with its official installer"
    curl --fail --location --silent --show-error \
        --output "$installer_path" "$containerlab_installer_url"
    run_privileged bash "$installer_path"
fi

for executable in ovs-vsctl unzip containerlab; do
    if ! command -v "$executable" >/dev/null 2>&1; then
        echo "deploy dependencies: $executable is still unavailable after installation" >&2
        exit 1
    fi
done

echo "Deploy dependencies are ready."