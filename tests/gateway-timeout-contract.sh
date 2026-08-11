#!/bin/sh

set -eu

repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
chart="$repository_root/charts/inference-gateway"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
namespace="${GATEWAY_TEST_NAMESPACE:-edge-llm}"
release="${GATEWAY_TIMEOUT_RELEASE:-gateway-timeout-contract}"
backend="${GATEWAY_TIMEOUT_BACKEND:-gateway-timeout-backend}"
local_port="${GATEWAY_TIMEOUT_PORT:-18084}"
base_url="http://127.0.0.1:$local_port"
work_dir="$(mktemp -d)"
release_created=0
backend_created=0
port_forward_pid=""

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  exit_status=$?
  trap - EXIT HUP INT TERM
  cleanup_failed=0
  if [ -n "$port_forward_pid" ]; then
    kill "$port_forward_pid" 2>/dev/null || true
    wait "$port_forward_pid" 2>/dev/null || true
  fi
  if [ "$release_created" -eq 1 ]; then
    if ! helm uninstall "$release" \
      --namespace "$namespace" \
      --kubeconfig "$kubeconfig" >/dev/null 2>&1; then
      printf 'CLEANUP FAIL: could not uninstall temporary release: %s\n' \
        "$release" >&2
      cleanup_failed=1
    fi
    if helm status "$release" --namespace "$namespace" --kubeconfig "$kubeconfig" \
      >/dev/null 2>&1; then
      printf 'CLEANUP FAIL: temporary release remains: %s\n' "$release" >&2
      cleanup_failed=1
    fi
  fi
  if [ "$backend_created" -eq 1 ]; then
    if ! kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
      delete pod,service,configmap "$backend" \
      --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1; then
      printf 'CLEANUP FAIL: could not delete delayed backend: %s\n' \
        "$backend" >&2
      cleanup_failed=1
    fi
    if kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
      get pod "$backend" >/dev/null 2>&1 || \
      kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
      get service "$backend" >/dev/null 2>&1 || \
      kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
      get configmap "$backend" >/dev/null 2>&1; then
      printf 'CLEANUP FAIL: delayed backend resources remain: %s\n' \
        "$backend" >&2
      cleanup_failed=1
    fi
  fi
  if ! rm -rf -- "$work_dir"; then
    printf 'CLEANUP FAIL: could not remove work directory: %s\n' "$work_dir" >&2
    cleanup_failed=1
  fi
  if [ "$cleanup_failed" -ne 0 ] && [ "$exit_status" -eq 0 ]; then
    exit_status=1
  fi
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if helm status "$release" --namespace "$namespace" --kubeconfig "$kubeconfig" \
  >/dev/null 2>&1; then
  fail "temporary release already exists: $release"
fi
if kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
  get pod "$backend" >/dev/null 2>&1 || \
  kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
  get service "$backend" >/dev/null 2>&1 || \
  kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
  get configmap "$backend" >/dev/null 2>&1; then
  fail "temporary delayed backend already exists: $backend"
fi

backend_created=1
kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" apply -f - \
  >"$work_dir/backend-apply.log" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $backend
  labels:
    app.kubernetes.io/name: $backend
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: $backend
  ports:
    - name: http
      port: 8080
      targetPort: http
      protocol: TCP
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: $backend
  labels:
    app.kubernetes.io/name: $backend
data:
  delay.sh: |
    #!/bin/sh
    sleep 30
---
apiVersion: v1
kind: Pod
metadata:
  name: $backend
  labels:
    app.kubernetes.io/name: $backend
spec:
  automountServiceAccountToken: false
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    runAsGroup: 65534
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: delayed-http
      image: docker.io/library/busybox:1.37.0@sha256:9532d8c39891ca2ecde4d30d7710e01fb739c87a8b9299685c63704296b16028
      imagePullPolicy: IfNotPresent
      command:
        - /bin/nc
      args:
        - -lk
        - -p
        - "8080"
        - -e
        - /fixture/delay.sh
      ports:
        - name: http
          containerPort: 8080
          protocol: TCP
      startupProbe:
        tcpSocket:
          port: http
        periodSeconds: 1
        timeoutSeconds: 1
        failureThreshold: 30
      resources:
        requests:
          cpu: 5m
          memory: 8Mi
        limits:
          cpu: 50m
          memory: 32Mi
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
      volumeMounts:
        - name: fixture
          mountPath: /fixture
          readOnly: true
  volumes:
    - name: fixture
      configMap:
        name: $backend
        defaultMode: 0555
EOF

kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
  wait --for=condition=Ready "pod/$backend" --timeout=90s >/dev/null
sleep 1

helm install "$release" "$chart" \
  --namespace "$namespace" \
  --kubeconfig "$kubeconfig" \
  --set-string "upstream.host=$backend.$namespace.svc.cluster.local" \
  --set gateway.healthTimeoutSeconds=1 \
  --rollback-on-failure \
  --wait=watcher \
  --timeout 3m >/dev/null
release_created=1

kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
  port-forward "service/$release" "$local_port:8080" --address 127.0.0.1 \
  >"$work_dir/port-forward.log" 2>&1 &
port_forward_pid=$!

attempt=0
while [ "$attempt" -lt 30 ]; do
  status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 1 --max-time 3 "$base_url/health" 2>/dev/null || true)"
  [ "$status" != 000 ] && break
  attempt=$((attempt + 1))
  sleep 1
done
[ "${status:-000}" != 000 ] || \
  fail "temporary Gateway port-forward did not become reachable"

response_file="$work_dir/timeout-response.json"
response_headers="$work_dir/timeout-headers.txt"
status="$(curl --silent --show-error \
  --connect-timeout 2 \
  --max-time 5 \
  --dump-header "$response_headers" \
  --output "$response_file" \
  --write-out '%{http_code}' \
  "$base_url/health")"
[ "$status" = 504 ] || fail "delayed health upstream returned HTTP $status"

expected='{"error":{"message":"inference timeout","type":"gateway_timeout"}}'
actual="$(tr -d '\r\n' <"$response_file")"
[ "$actual" = "$expected" ] || fail 'timeout returned an unexpected error body'
tr -d '\r' <"$response_headers" >"$work_dir/timeout-headers-normalized.txt"
grep -Eiq '^content-type:[[:space:]]*application/json([[:space:]]*;|[[:space:]]*$)' \
  "$work_dir/timeout-headers-normalized.txt" || \
  fail 'timeout response content type is not application/json'
if grep -Eiq "$backend|upstream connect|connection failure|reset reason|x-envoy-upstream-service-time" \
  "$response_headers" "$response_file"; then
  fail 'timeout response exposed upstream connection details'
fi

helm uninstall "$release" \
  --namespace "$namespace" \
  --kubeconfig "$kubeconfig" >/dev/null
if helm status "$release" --namespace "$namespace" --kubeconfig "$kubeconfig" \
  >/dev/null 2>&1; then
  fail "temporary release still exists after uninstall: $release"
fi
release_created=0

kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
  delete pod,service,configmap "$backend" \
  --wait=true --timeout=60s >/dev/null
if kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
  get pod "$backend" >/dev/null 2>&1 || \
  kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
  get service "$backend" >/dev/null 2>&1 || \
  kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
  get configmap "$backend" >/dev/null 2>&1; then
  fail "temporary delayed backend still exists after deletion: $backend"
fi
backend_created=0

printf 'Gateway timeout contract: PASS\n'
