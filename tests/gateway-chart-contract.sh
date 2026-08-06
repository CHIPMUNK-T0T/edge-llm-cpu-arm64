#!/bin/sh

set -eu

repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
chart="$repository_root/charts/inference-gateway"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

helm lint "$chart" --strict
helm template inference-gateway "$chart" --namespace edge-llm \
  >"$work_dir/baseline.yaml"
helm template alternate-gateway "$chart" --namespace edge-llm \
  >"$work_dir/alternate.yaml"
helm template inference-gateway "$chart" --namespace edge-llm \
  --show-only templates/deployment.yaml >"$work_dir/deployment.yaml"
helm template inference-gateway "$chart" --namespace edge-llm \
  --show-only templates/service.yaml >"$work_dir/service.yaml"
helm template inference-gateway "$chart" --namespace edge-llm \
  --show-only templates/configmap.yaml >"$work_dir/configmap.yaml"

[ "$(grep -c '^kind:' "$work_dir/baseline.yaml")" -eq 3 ] || \
  fail 'chart must render exactly ConfigMap, Deployment, and Service'
grep -q 'automountServiceAccountToken: false' "$work_dir/deployment.yaml" || \
  fail 'ServiceAccount token automount is not disabled'
grep -q 'readOnlyRootFilesystem: true' "$work_dir/deployment.yaml" || \
  fail 'read-only root filesystem is missing'
grep -q 'runAsUser: 65532' "$work_dir/deployment.yaml" || \
  fail 'distroless non-root UID is not explicit'
grep -A2 'capabilities:' "$work_dir/deployment.yaml" | grep -q 'drop:' || \
  fail 'Linux capabilities are not dropped'
grep -q 'seccompProfile:' "$work_dir/deployment.yaml" || \
  fail 'RuntimeDefault seccomp profile is missing'
grep -Fq 'distroless-v1.39.0@sha256:8dbb967dba5d22a28f0e7974173aa6d4a5621ce48ac6d44142d9b4d9c960af14' \
  "$work_dir/deployment.yaml" || fail 'reviewed ARM64 Envoy image is not digest-pinned'

grep -q 'type: ClusterIP' "$work_dir/service.yaml" || \
  fail 'Gateway Service is not ClusterIP'
[ "$(grep -c '^    - name:' "$work_dir/service.yaml")" -eq 1 ] || \
  fail 'Gateway Service must publish exactly one port'
grep -q 'port: 8080' "$work_dir/service.yaml" || \
  fail 'Gateway HTTP port is missing'
if grep -q '9901' "$work_dir/service.yaml"; then
  fail 'Envoy admin port is published by the Service'
fi

grep -q 'path: /health' "$work_dir/configmap.yaml" || \
  fail 'public health route is missing'
grep -q 'path: /v1/chat/completions' "$work_dir/configmap.yaml" || \
  fail 'public OpenAI chat route is missing'
grep -q 'path: /v1/messages' "$work_dir/configmap.yaml" || \
  fail 'public Anthropic Messages route is missing'
grep -q 'filename: /config/index.html' "$work_dir/configmap.yaml" || \
  fail 'minimal Web UI route is missing'
grep -q 'max_request_bytes: 1048576' "$work_dir/configmap.yaml" || \
  fail 'request body limit is missing'
grep -q 'timeout: 0s' "$work_dir/configmap.yaml" || \
  fail 'streaming route has a total request timeout'
grep -q 'prefix: /' "$work_dir/configmap.yaml" || \
  fail 'deny-by-default route is missing'
for internal_path in /metrics /props /slots /v1/models /models/load /v1/messages/count_tokens; do
  if grep -q "path: $internal_path" "$work_dir/configmap.yaml"; then
    fail "internal path is explicitly exposed: $internal_path"
  fi
done

grep -q 'meta name="edge-llm-model"' "$work_dir/configmap.yaml" || \
  fail 'fixed model identity is not injected into the UI'
if grep -Eiq '<select|type="range"|temperature|top[_ -]?p|model selector' \
  "$work_dir/configmap.yaml"; then
  fail 'UI contains a model or generation settings control'
fi

grep -q 'app.kubernetes.io/instance: alternate-gateway' "$work_dir/alternate.yaml" || \
  fail 'alternate release identity is missing'
grep -q '^  name: alternate-gateway$' "$work_dir/alternate.yaml" || \
  fail 'alternate release resource name is missing'

if helm template inference-gateway "$chart" --namespace edge-llm \
  --set-string image.repository=untrusted.example/envoy \
  >"$work_dir/invalid-image.out" 2>"$work_dir/invalid-image.err"; then
  fail 'arbitrary gateway image was accepted'
fi

printf 'Gateway chart contract: PASS\n'
