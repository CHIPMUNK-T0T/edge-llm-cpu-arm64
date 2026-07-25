#!/usr/bin/env bash
set -euo pipefail

readonly HELM_VERSION="v4.2.0"
readonly HELM_SHA256="1f8de130dfbd04de64978e7b852a7a547be1404956a366608276d2520b678670"
readonly HELM_PLATFORM="linux-arm64"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root (for WSL: wsl.exe -d Ubuntu-24.04 -u root -- bash scripts/install-helm.sh)." >&2
  exit 1
fi

case "$(uname -m)" in
  aarch64|arm64) ;;
  *)
    echo "This lab installer supports Linux ARM64 only." >&2
    exit 1
    ;;
esac

archive="helm-${HELM_VERSION}-${HELM_PLATFORM}.tar.gz"
temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "$temporary_directory"' EXIT

curl --fail --silent --show-error --location \
  "https://get.helm.sh/${archive}" \
  --output "${temporary_directory}/${archive}"

printf '%s  %s\n' \
  "$HELM_SHA256" \
  "${temporary_directory}/${archive}" |
  sha256sum --check -

tar --extract --gzip --file "${temporary_directory}/${archive}" \
  --directory "$temporary_directory"
install --mode 0755 \
  "${temporary_directory}/${HELM_PLATFORM}/helm" \
  /usr/local/bin/helm

helm version --short
