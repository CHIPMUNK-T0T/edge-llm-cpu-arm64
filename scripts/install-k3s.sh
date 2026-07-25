#!/usr/bin/env bash
set -euo pipefail

# Keep the lab reproducible: update this deliberately and record the upgrade.
readonly K3S_VERSION="v1.36.2+k3s1"
readonly K3S_INSTALLER_URL="https://raw.githubusercontent.com/k3s-io/k3s/v1.36.2%2Bk3s1/install.sh"
readonly K3S_INSTALLER_SHA256="46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root (for WSL: wsl.exe -d Ubuntu-24.04 -u root -- bash scripts/install-k3s.sh)." >&2
  exit 1
fi

installer="$(mktemp)"
trap 'rm -f "$installer"' EXIT

curl --fail --silent --show-error --location "$K3S_INSTALLER_URL" --output "$installer"
printf '%s  %s\n' "$K3S_INSTALLER_SHA256" "$installer" | sha256sum --check --status -
chmod 0700 "$installer"

INSTALL_K3S_VERSION="$K3S_VERSION" "$installer"

systemctl is-active --quiet k3s
k3s kubectl wait --for=condition=Ready node --all --timeout=180s

echo "K3s $K3S_VERSION is installed and the node is Ready."
