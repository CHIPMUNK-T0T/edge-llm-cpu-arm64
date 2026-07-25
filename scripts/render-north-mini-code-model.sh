#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
lab_config="$repo_dir/.lab-config.yaml"
manifest="$repo_dir/kubernetes/north-mini-code-model.yaml"
placeholder="/home/your-user/work/edge-llm-cpu-arm64/models/north-mini-code"

if [[ ! -f "$lab_config" ]]; then
  echo "Missing local configuration: $lab_config" >&2
  echo "Copy .lab-config.example.yaml to .lab-config.yaml and set modelSourcePath." >&2
  exit 1
fi

model_source_path="$(
  awk '
    /^[[:space:]]*modelSourcePath[[:space:]]*:/ {
      sub(/^[^:]*:[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      print
      exit
    }
  ' "$lab_config"
)"
readonly model_source_path

if [[ -z "$model_source_path" || "$model_source_path" == *"your-user"* ]]; then
  echo "Set modelSourcePath in $lab_config to the absolute local model directory." >&2
  exit 1
fi

if [[ "$model_source_path" != /* ]]; then
  echo "modelSourcePath must be an absolute Linux path: $model_source_path" >&2
  exit 1
fi

if [[ ! -d "$model_source_path" ]]; then
  echo "Model source directory does not exist: $model_source_path" >&2
  exit 1
fi

if [[ "$(grep -Foc -- "$placeholder" "$manifest")" -ne 1 ]]; then
  echo "Expected exactly one model source placeholder in $manifest" >&2
  exit 1
fi

awk -v old="$placeholder" -v new="$model_source_path" '
  {
    position = index($0, old)
    if (position > 0) {
      $0 = substr($0, 1, position - 1) new \
        substr($0, position + length(old))
    }
    print
  }
' "$manifest"
