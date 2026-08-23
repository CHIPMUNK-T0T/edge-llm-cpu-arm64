#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${repo_root}/scripts/measure-pod-recovery.sh"
bash -n "${repo_root}/scripts/measure-invalid-model-recovery.sh"
bash -n "${repo_root}/scripts/monitoring-snapshot.sh"

grep -q 'mktemp' "${repo_root}/scripts/measure-pod-recovery.sh"
grep -q 'rollback_required' "${repo_root}/scripts/measure-invalid-model-recovery.sh"
grep -q 'hostPath type check failed' "${repo_root}/scripts/measure-invalid-model-recovery.sh"
grep -q 'wsl.exe --terminate' "${repo_root}/scripts/measure-wsl-recovery.ps1"
grep -q 'gateway_requests_total' "${repo_root}/scripts/monitoring-snapshot.sh"
grep -q 'Windows boot time did not change' "${repo_root}/scripts/verify-windows-restart.ps1"

if grep -E -n '/home/[^/]+|tail[0-9]+\.ts\.net|100\.[0-9]+\.[0-9]+\.[0-9]+' \
  "${repo_root}/scripts/measure-pod-recovery.sh" \
  "${repo_root}/scripts/measure-invalid-model-recovery.sh" \
  "${repo_root}/scripts/measure-wsl-recovery.ps1" \
  "${repo_root}/scripts/verify-windows-restart.ps1"; then
  echo 'recovery scripts contain a machine-specific identity or address' >&2
  exit 1
fi

echo 'recovery script contract: PASS'
