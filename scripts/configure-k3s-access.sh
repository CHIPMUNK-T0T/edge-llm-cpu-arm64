#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
lab_config="$repo_dir/.lab-config.yaml"

if [[ ! -f "$lab_config" ]]; then
  echo "Missing local configuration: $lab_config" >&2
  echo "Copy .lab-config.example.yaml to .lab-config.yaml and replace your-user." >&2
  exit 1
fi

K3S_OPERATOR_USER="$(
  awk '
    /^[[:space:]]*operatorUser[[:space:]]*:/ {
      sub(/^[^:]*:[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      print
      exit
    }
  ' "$lab_config"
)"
readonly K3S_OPERATOR_USER

if [[ -z "$K3S_OPERATOR_USER" || "$K3S_OPERATOR_USER" == "your-user" ]]; then
  echo "Set operatorUser in $lab_config to the WSL operator account." >&2
  exit 1
fi

if ! getent passwd "$K3S_OPERATOR_USER" >/dev/null; then
  echo "K3s operator user does not exist: $K3S_OPERATOR_USER" >&2
  exit 1
fi

groupadd --force k3s
usermod --append --groups k3s "$K3S_OPERATOR_USER"
install --directory --owner root --group root --mode 0755 /etc/rancher/k3s
install --owner root --group root --mode 0644 \
  "$repo_dir/config/k3s/config.yaml" /etc/rancher/k3s/config.yaml

systemctl restart k3s
k3s kubectl wait --for=condition=Ready node --all --timeout=180s

echo "K3s access is configured for $K3S_OPERATOR_USER via the k3s group."
