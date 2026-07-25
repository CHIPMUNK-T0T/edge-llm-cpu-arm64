#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
model_dir="${1:-${repo_root}/models/north-mini-code}"

repository="bartowski/North-Mini-Code-1.0-GGUF"
revision="6ff6563002170723a6f7a672bf4c99775be6c0dd"
filename="North-Mini-Code-1.0-Q4_0.gguf"
expected_size="17521204800"
expected_sha256="e4803e44e2b97269deb3b33b1ea8d4309d06773ca5f07684f876bd8f751f4f86"
url="https://huggingface.co/${repository}/resolve/${revision}/${filename}?download=true"

destination="${model_dir}/${filename}"
partial="${destination}.part"

verify_file() {
  local candidate="$1"
  local actual_size
  local actual_sha256

  actual_size="$(stat --format='%s' "${candidate}")"
  if [[ "${actual_size}" != "${expected_size}" ]]; then
    printf 'Size mismatch for %s: expected %s, got %s\n' \
      "${candidate}" "${expected_size}" "${actual_size}" >&2
    return 1
  fi

  actual_sha256="$(sha256sum "${candidate}" | awk '{print $1}')"
  if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    printf 'SHA-256 mismatch for %s\nexpected: %s\nactual:   %s\n' \
      "${candidate}" "${expected_sha256}" "${actual_sha256}" >&2
    return 1
  fi
}

mkdir -p "${model_dir}"

if [[ -f "${destination}" ]]; then
  if verify_file "${destination}"; then
    printf 'Already downloaded and verified: %s\n' "${destination}"
    exit 0
  fi
  printf 'Refusing to overwrite an invalid final file. Move it aside manually: %s\n' \
    "${destination}" >&2
  exit 1
fi

available_bytes="$(df --output=avail -B1 "${model_dir}" | tail -n 1 | tr -d ' ')"
if (( available_bytes < expected_size )); then
  printf 'Insufficient free space: need %s bytes, have %s bytes\n' \
    "${expected_size}" "${available_bytes}" >&2
  exit 1
fi

printf 'Downloading pinned artifact to %s\n' "${partial}"
printf 'Repository revision: %s\n' "${revision}"
curl \
  --fail \
  --location \
  --retry 5 \
  --retry-delay 5 \
  --continue-at - \
  --progress-bar \
  --output "${partial}" \
  "${url}"

if ! verify_file "${partial}"; then
  printf 'Partial download is invalid. Remove it before retrying: %s\n' \
    "${partial}" >&2
  exit 1
fi
mv "${partial}" "${destination}"
printf 'Verified model: %s\n' "${destination}"
printf 'SHA-256: %s\n' "${expected_sha256}"
