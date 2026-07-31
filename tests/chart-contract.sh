#!/bin/sh

set -eu

repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
chart="$repository_root/charts/north-mini-code"
values_file="${1:-}"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

render() {
  release="$1"
  output="$2"
  if [ -n "$values_file" ]; then
    helm template "$release" "$chart" --namespace edge-llm \
      --values "$values_file" >"$output"
  else
    helm template "$release" "$chart" --namespace edge-llm >"$output"
  fi
}

if [ -n "$values_file" ]; then
  helm lint "$chart" --strict --values "$values_file"
else
  helm lint "$chart" --strict
fi

render north-mini-code "$work_dir/baseline.yaml"
render alternate-release "$work_dir/alternate.yaml"
helm template north-mini-code "$chart" --namespace edge-llm \
  --show-only templates/deployment.yaml >"$work_dir/baseline-deployment.yaml"
helm template north-mini-code "$chart" --namespace edge-llm \
  --show-only templates/service.yaml >"$work_dir/baseline-service.yaml"

[ "$(grep -c '^kind:' "$work_dir/baseline.yaml")" -eq 3 ] || \
  fail 'chart must render exactly Deployment, Service, and PVC'
grep -q 'automountServiceAccountToken: false' "$work_dir/baseline.yaml" || \
  fail 'ServiceAccount token automount is not disabled'
grep -q 'helm.sh/resource-policy: keep' "$work_dir/baseline.yaml" || \
  fail 'PVC keep policy is missing'
grep -q 'type: ClusterIP' "$work_dir/baseline.yaml" || \
  fail 'Service is not ClusterIP'
grep -q 'edge-llm/profile-name: "north-mini-code-1.0-q4-0-llama-cpp-b10108"' \
  "$work_dir/baseline-deployment.yaml" || \
  fail 'reviewed profile name is not observable on the Pod template'
awk '/^  selector:/{copy=1} /^  template:/{copy=0} copy' \
  "$work_dir/baseline-deployment.yaml" >"$work_dir/deployment-selector.yaml"
awk '/^  selector:/{copy=1} /^  ports:/{copy=0} copy' \
  "$work_dir/baseline-service.yaml" >"$work_dir/service-selector.yaml"
grep -q 'app.kubernetes.io/instance: north-mini-code' \
  "$work_dir/deployment-selector.yaml" || \
  fail 'Deployment release instance selector is missing'
grep -q 'app.kubernetes.io/instance: north-mini-code' \
  "$work_dir/service-selector.yaml" || \
  fail 'Service release instance selector is missing'
grep -q 'app.kubernetes.io/instance: alternate-release' "$work_dir/alternate.yaml" || \
  fail 'alternate release instance selector is missing'
grep -q '^  name: alternate-release$' "$work_dir/alternate.yaml" || \
  fail 'alternate release resource name is missing'
grep -q '^  name: alternate-release-model$' "$work_dir/alternate.yaml" || \
  fail 'alternate release PVC name is missing'

if helm template north-mini-code "$chart" --namespace edge-llm \
  --set-string profile.runtime.image=untrusted.example/runtime:latest \
  >"$work_dir/invalid-image.out" 2>"$work_dir/invalid-image.err"; then
  fail 'unpinned or unsupported runtime image was accepted'
fi

helm template profile-contract "$chart" --namespace edge-llm \
  --set-string profile.name=fixture-q4-profile \
  --set-string profile.model.fileName=fixture-Q4.gguf \
  --set-string profile.model.quantization=Q4_TEST \
  --set-string profile.model.sizeBytes=1234 \
  --set-string profile.model.sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >"$work_dir/profile.yaml"
grep -q '/models/fixture-Q4.gguf' "$work_dir/profile.yaml" || \
  fail 'injected model profile did not reach the runtime contract'
grep -q 'edge-llm/profile-name: "fixture-q4-profile"' "$work_dir/profile.yaml" || \
  fail 'injected profile name is not observable on the Pod template'

printf 'Chart contract: PASS\n'
