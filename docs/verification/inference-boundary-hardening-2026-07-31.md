# Inference boundary and foundation image verification

- **Date:** 2026-07-31
- **Environment:** Surface Laptop 7, WSL2 Ubuntu ARM64, single-node K3s
- **Inference release:** `north-mini-code`, namespace `edge-llm`, Helm revision 6
- **Chart:** `north-mini-code-0.2.1`

## Purpose

Verify three bounded corrections to the existing serving baseline:

1. restrict browser origins at the ClusterIP-only inference backend;
2. keep operational inference endpoints separate from the future external
   gateway contract;
3. pin the Phase 0 nginx and BusyBox validation images by digest.

The inference server remains unauthenticated inside the cluster. It is not an
external entry point. The future gateway remains responsible for Tailscale
client access policy and must not expose inference `/metrics` as a client API.

## Static and server-side validation

The following passed before the live Helm update:

```bash
tests/chart-contract.sh .north-mini-code-values.yaml
tests/model-artifact-contract.sh
tests/profile-consistency.sh
helm upgrade north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --dry-run=server
```

The chart contract verified `--cors-origins localhost` and
`--no-cors-credentials`. The internal test entry point is now
`tests/inference-api-contract.sh`; no current document refers to the old
generic test name or requires a future gateway to expose the same operational
surface.

## Phase 0 image digest verification

The ARM64 node had resolved these exact repository digests:

```text
nginx:1.28.0-alpine@sha256:30f1c0d78e0ad60901648be663a710bdadf19e4c10ac6782c235200619158284
busybox:1.37.0@sha256:9532d8c39891ca2ecde4d30d7710e01fb739c87a8b9299685c63704296b16028
```

The Phase 0 manifests were applied with those references. The nginx
Deployment completed its rollout with one Ready replica. The storage Job was
recreated because a Job Pod template is immutable, completed once, and logged:

```text
PVC write/read verification: PASS (edge-llm-storage-ok)
```

The existing storage PVC was retained.

## Live inference verification

Helm revision 6 reached `deployed`. The replacement inference Pod reached
`1/1 Running` with zero restarts. Model init logged:

```text
Model already present and verified.
```

The retained model was not recopied. The localhost-only port-forward was
restarted after the Pod replacement, and the embedded Web UI returned HTTP 200.

The final internal contract command was:

```bash
tests/inference-api-contract.sh http://localhost:18080
```

It passed six checks: health, browser origins, Prometheus metrics, invalid
request handling, non-streaming chat, and SSE. SSE contained 92 JSON frames and
one final `[DONE]` event.

For browser origins, an untrusted HTTPS origin received no
`Access-Control-Allow-Origin` response header. A localhost origin was
reflected, and no `Access-Control-Allow-Credentials` header was returned. The
previous startup warning about wildcard CORS and missing API keys was absent.

## Remaining boundary

This result does not implement external access or application authentication.
The gateway will be a separate Deployment and Helm release with its own
external-client contract. That contract must cover access policy, chat, SSE,
backend unavailability, and network loss without publishing the internal
metrics endpoint.
