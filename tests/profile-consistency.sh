#!/bin/sh

set -eu

repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
model_config="$repository_root/config/models/north-mini-code-q4-0.yaml"
chart_values="$repository_root/charts/north-mini-code/values.yaml"
gateway_values="$repository_root/charts/inference-gateway/values.yaml"
download_script="$repository_root/scripts/download-north-mini-code-q4-0.sh"
benchmark_input="$repository_root/benchmark/inputs/north-mini-code-q4-0-k3s-smoke.json"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  label="$1"
  expected="$2"
  actual="$3"
  [ "$expected" = "$actual" ] || \
    fail "$label drift: expected '$expected', got '$actual'"
}

artifact_value() {
  key="$1"
  awk -v key="$key" '
    $1 == "artifact:" { artifact = 1; next }
    artifact && $1 == key ":" { print $2; exit }
  ' "$model_config"
}

chart_value() {
  key="$1"
  awk -v key="$key" '$1 == key ":" { gsub(/"/, "", $2); print $2; exit }' \
    "$chart_values"
}

gateway_value() {
  key="$1"
  awk -v key="$key" '$1 == key ":" { gsub(/"/, "", $2); print $2; exit }' \
    "$gateway_values"
}

script_value() {
  key="$1"
  sed -n 's/^'"$key"'="\(.*\)"$/\1/p' "$download_script"
}

canonical_filename="$(artifact_value filename)"
canonical_quantization="$(artifact_value quantization)"
canonical_size="$(artifact_value sizeBytes)"
canonical_sha256="$(artifact_value sha256)"
canonical_repository="$(artifact_value repository)"
canonical_revision="$(artifact_value revision)"

assert_equal filename "$canonical_filename" "$(chart_value fileName)"
assert_equal quantization "$canonical_quantization" "$(chart_value quantization)"
assert_equal sizeBytes "$canonical_size" "$(chart_value sizeBytes)"
assert_equal sha256 "$canonical_sha256" "$(chart_value sha256)"
assert_equal gateway-model-id "$canonical_filename" "$(gateway_value modelId)"

assert_equal download-filename "$canonical_filename" "$(script_value filename)"
assert_equal download-size "$canonical_size" "$(script_value expected_size)"
assert_equal download-sha256 "$canonical_sha256" "$(script_value expected_sha256)"
assert_equal download-repository "$canonical_repository" "$(script_value repository)"
assert_equal download-revision "$canonical_revision" "$(script_value revision)"

benchmark_model="$(python3 - "$benchmark_input" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    payload = json.load(source)
print(payload["requests"][0]["body"]["model"])
PY
)"
assert_equal benchmark-model "$canonical_filename" "$benchmark_model"

printf 'Profile consistency: PASS\n'
