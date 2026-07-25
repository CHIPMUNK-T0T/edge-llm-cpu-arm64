# North Mini Code Helm uninstall, reinstall, and SSE verification

**Date:** 2026-07-25
**Environment:** Surface Laptop 7, Windows 11 ARM64, WSL2 Ubuntu ARM64,
single-node K3s
**Helm:** v4.2.0
**Release:** `north-mini-code` in `edge-llm`

## Objective

Verify that the Helm release can be removed and recreated without losing the
model stored in the retained local-path PVC. Then verify the restored serving
path with the embedded UI, health endpoint, fixed non-streaming input, and an
explicit SSE request through the K3s Service.

This is a lifecycle and reproducibility check. It is not a high-availability
or recovery-time benchmark.

## Preflight

Release revision 4 was deployed at the 4096-token context baseline. The Pod was
`1/1` Ready with zero restarts. The init container reported
`Model already present and verified.`

| Resource or check | Before uninstall |
| --- | --- |
| Deployment UID | `48a35e9e-3d6e-4a56-979c-2a234eaef6c6` |
| Service UID | `b2fb521f-d42a-4d0f-8c3c-6c4d3bfbfad2` |
| Service ClusterIP | `10.43.245.211` |
| PVC UID | `7e9dca97-c302-40bf-8a5f-13862a28d5c5` |
| PV binding | `pvc-7e9dca97-c302-40bf-8a5f-13862a28d5c5` |
| Model size | 17,521,204,800 bytes |
| Model SHA-256 | `e4803e44e2b97269deb3b33b1ea8d4309d06773ca5f07684f876bd8f751f4f86` |
| Embedded UI | HTTP 200, `text/html; charset=utf-8`, 1,302 compressed bytes |
| Health | `{"status":"ok"}` |
| Fixed chat input | correct `add(a, b)` function, HTTP 200 |

The effective server arguments included `--ctx-size 4096`.

## Uninstall and retained storage

The release was removed with:

```bash
helm uninstall north-mini-code \
  --namespace edge-llm \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --wait \
  --timeout 10m
```

Helm completed the uninstall from `08:45:06Z` to `08:45:08Z` and explicitly
reported that `PersistentVolumeClaim/north-mini-code-model` was kept by the
resource policy. The Deployment, Service, and Pod were deleted. `helm status`
then returned `release: not found`.

The retained PVC remained `Bound` with the same UID and PV binding. Its
`helm.sh/resource-policy: keep` annotation and matching Helm release-name and
release-namespace annotations remained present. The local-path PV remained
bound to the same claim.

The PV reclaim policy is `Delete`; therefore the retained PVC protects the
model during this Helm release operation, but it is not a backup. Deleting the
PVC would put the local model data at risk.

## Normal reinstall

Before changing the cluster, a normal server-side dry-run passed:

```bash
helm install north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --dry-run=server
```

The retained PVC already had matching release metadata, and the normal install
path accepted it without additional ownership options.

The same normal install was then applied:

```bash
helm install north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --wait \
  --timeout 20m
```

The install ran from `08:46:38Z` to `08:47:42Z` and created a deployed revision
1. Revision numbering restarted because uninstall removed the previous Helm
release record.

## Reinstall result

| Resource or check | After reinstall | Expected interpretation |
| --- | --- | --- |
| Deployment UID | `3bc38c58-1760-4507-8016-84d148b2c7e7` | new object after uninstall |
| Service UID | `65b94669-b3af-445c-b47d-35cc0f925923` | new object after uninstall |
| Service ClusterIP | `10.43.61.232` | new allocation after Service recreation |
| PVC UID | `7e9dca97-c302-40bf-8a5f-13862a28d5c5` | unchanged |
| PV binding | `pvc-7e9dca97-c302-40bf-8a5f-13862a28d5c5` | unchanged |
| Pod | `1/1` Running, zero restarts | passed |
| Effective context | 4096 | baseline restored |
| Init verification | `Model already present and verified.` | no 17 GB recopy |
| Model size | 17,521,204,800 bytes | unchanged |
| Model SHA-256 | `e4803e44e2b97269deb3b33b1ea8d4309d06773ca5f07684f876bd8f751f4f86` | unchanged |

The model SHA was recomputed from the read-only `/models` mount in the new
serving Pod:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --namespace edge-llm \
  exec deployment/north-mini-code \
  --container llama-server -- \
  sha256sum /models/North-Mini-Code-1.0-Q4_0.gguf
```

The new Service passed:

| Check | Result |
| --- | --- |
| Embedded UI | HTTP 200, `text/html; charset=utf-8`, 1,302 compressed bytes |
| Health | `{"status":"ok"}` |
| Fixed non-streaming input | `def add(a, b):` / `return a + b` |
| Non-streaming request | HTTP 200, 24.97 seconds |
| Token usage | 135 prompt, 113 completion, 248 total |

The fixed request is tracked as
[the North Mini Code K3s smoke input](../../benchmark/inputs/north-mini-code-q4-0-k3s-smoke.json).

The previous localhost port-forward did not survive deletion of its target
workload. After starting a new localhost-only port-forward to the recreated
Service, Windows requests to `http://localhost:18080` returned HTTP 200 for the
embedded UI and `{"status":"ok"}` for health:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --namespace edge-llm \
  port-forward --address=127.0.0.1 \
  service/north-mini-code 18080:8080
```

This port-forward is a local validation path, not a persistent ingress or a
Helm-managed resource. It must be re-established after its selected backend is
deleted. The later gateway phase will address a durable private client path.

## Explicit SSE verification

The tracked request body was changed only in memory from `stream: false` to
`stream: true` and sent directly to the Helm-managed K3s Service:

```bash
SERVICE_IP="$(
  kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
    --namespace edge-llm \
    get service north-mini-code \
    --output jsonpath='{.spec.clusterIP}'
)"
SSE_WORK_DIR="$(mktemp -d)"
SSE_HEADERS="$SSE_WORK_DIR/headers.txt"
SSE_BODY="$SSE_WORK_DIR/body.txt"
trap 'rm -rf -- "$SSE_WORK_DIR"' EXIT

jq -c '.requests[0].body | .stream = true' \
  benchmark/inputs/north-mini-code-q4-0-k3s-smoke.json |
  curl --no-buffer --fail --silent --show-error \
    --dump-header "$SSE_HEADERS" \
    --output "$SSE_BODY" \
    --header 'Content-Type: application/json' \
    --data-binary @- \
    --write-out 'HTTP %{http_code}; total=%{time_total}s\n' \
    "http://${SERVICE_IP}:8080/v1/chat/completions"

grep -i -E '^(HTTP/|Content-Type:)' "$SSE_HEADERS"
awk '/^data: / {
  total++
  if (/^data: \[DONE\]/) done++
  else json++
}
END {
  printf "total=%d json=%d done=%d\n", total, json, done
}' "$SSE_BODY"
sed -n 's/^data: //p' "$SSE_BODY" |
  grep -v '^\[DONE\]' |
  jq -j '.choices[0].delta.content // empty'
```

| SSE check | Result |
| --- | --- |
| HTTP status | 200 |
| Content type | `text/event-stream` |
| JSON data frames | 111 |
| Terminal frames | one `data: [DONE]` |
| Total data frames | 112 |
| Reconstructed content | `def add(a, b):` / `return a + b` |
| Request duration | 22.76 seconds |

The response contained multiple incremental JSON frames and exactly one
terminal `[DONE]` frame. Concatenating
`.choices[0].delta.content` from the JSON frames produced the expected function.
The exact frame count and duration are observations from this run, not a
performance contract. The smoke criteria are multiple JSON frames, one
terminal `[DONE]`, and valid reconstructed content.

## ServiceAccount token hardening validation

The review found that omitting `automountServiceAccountToken` caused K3s to add
one `kube-api-access-*` volume and mount it into both the model init container
and `llama-server`. Neither container calls the Kubernetes API. Chart version
0.1.1 therefore fixes the Pod setting as:

```yaml
automountServiceAccountToken: false
```

The rendered manifest and server-side Helm dry-run contained the setting. A
normal Helm upgrade changed release revision 1 / chart 0.1.0 to revision 2 /
chart 0.1.1. The upgrade ran from `10:32:01Z` to `10:34:32Z`; this includes the
single-Pod `Recreate` rollout, full model verification, model load, and Ready
wait, not continuously sampled endpoint downtime.

| Check | Result after upgrade |
| --- | --- |
| Deployment setting | `automountServiceAccountToken: false` |
| `kube-api-access-*` volumes | none |
| init-container token mounts | none |
| `llama-server` token mounts | none |
| Pod | `1/1` Running, zero restarts |
| Context size | 4096 |
| Deployment, Service, PVC identities | unchanged |
| Service ClusterIP and PV binding | unchanged |
| Init verification | `Model already present and verified.` |
| Model size | 17,521,204,800 bytes |
| Embedded UI | HTTP 200, `text/html; charset=utf-8`, 1,302 compressed bytes |
| Health | `{"status":"ok"}` |
| Fixed non-streaming input | correct function, HTTP 200, 12.16 seconds |
| SSE | HTTP 200, 111 JSON frames, one `[DONE]`, valid reconstructed content |

The Pod replacement invalidated the existing localhost port-forward. Starting
a new localhost-only port-forward restored the Windows UI and health checks.

## Limitations and conclusion

The uninstall intentionally removed the only Pod and Service. This
single-replica lab was unavailable until the reinstall became Ready; endpoint
availability was not continuously sampled, so no recovery-time or downtime
performance claim is made.

The ClusterIP changed after Service recreation. Clients must use Kubernetes
Service discovery or obtain the current endpoint instead of depending on a
previous ClusterIP.

The uninstall/reinstall lifecycle check passed through the normal install path.
The PVC, PV binding, model size, and model SHA remained unchanged; the new Pod
did not recopy the model; and UI, health, non-streaming chat, and SSE serving
all passed through the recreated K3s Service.
