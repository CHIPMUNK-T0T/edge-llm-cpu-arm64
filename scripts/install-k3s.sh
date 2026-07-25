#!/usr/bin/env bash
set -euo pipefail

# Keep the lab reproducible: update this deliberately and record the upgrade.
readonly K3S_VERSION="v1.36.2+k3s1"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root (for WSL: wsl.exe -d Ubuntu-24.04 -u root -- bash scripts/install-k3s.sh)." >&2
  exit 1
fi

installer="$(mktemp)"
trap 'rm -f "$installer"' EXIT

curl --fail --silent --show-error --location https://get.k3s.io --output "$installer"
chmod 0700 "$installer"

INSTALL_K3S_VERSION="$K3S_VERSION" "$installer"

systemctl is-active --quiet k3s
k3s kubectl wait --for=condition=Ready node --all --timeout=180s

echo "K3s $K3S_VERSION is installed and the node is Ready."
