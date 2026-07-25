# North Mini Code Helm static validation — 2026-07-25

## Scope and result

**Passed the Phase 2 static packaging gate. No live K3s resource was changed.**

The current serving chart passed client-side chart checks and K3s API server
validation. Live rollout behavior, UI/API behavior, upgrade, rollback,
uninstall, and SSE are not claimed by this static result.

## Environment

| Item | Value |
| --- | --- |
| Platform | WSL2 Ubuntu, Linux ARM64 |
| K3s | `v1.36.2+k3s1` |
| Helm | `v4.2.0+g0646808` |
| Helm archive SHA-256 | `1f8de130dfbd04de64978e7b852a7a547be1404956a366608276d2520b678670` |
| Chart | `charts/north-mini-code`, version `0.1.1` |

The Helm version was chosen because Helm 4.2 supports Kubernetes 1.33 through
1.36. The official Linux ARM64 archive was downloaded from `get.helm.sh` and
verified before installation.

## Variable and fixed configuration

| Variable values | Fixed baseline |
| --- | --- |
| local model source path | model identity, Q4_0 filename, size, and SHA-256 |
| context size | official runtime image ARM64 digest |
| thread count | one replica and `Recreate` strategy |
| CPU and memory requests/limits | 24 GiB local-path PVC and ClusterIP Service |
| startup/readiness/liveness timing | non-root, read-only, no API token mount |
| termination grace period | parallel=1, Jinja, metrics, and embedded Web UI |

The ignored `.north-mini-code-values.yaml` supplied only the real local model
source path. The separate `.lab-config.yaml` remains limited to K3s operator
access. No personal path or account name is stored in the chart or this evidence.

## Commands

```bash
helm lint charts/north-mini-code --strict -f .north-mini-code-values.yaml
helm template north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml
helm upgrade north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --dry-run=server
helm list --kubeconfig /etc/rancher/k3s/k3s.yaml -n edge-llm
```

## Observed results

```text
1 chart(s) linted, 0 chart(s) failed
server-side Helm dry-run: PASS
rendered resource count: 3
schema rejected relative model path: PASS
schema rejected unknown value: PASS
```

The chart rendered exactly three managed resources: Deployment, PVC, and
Service. The `llama-server` image digest, model path, inference arguments,
resource envelope, probes, Pod security context, PVC request, selectors,
Service type, and port remain aligned with the verified serving baseline. The
Pod spec explicitly disables automatic ServiceAccount token mounting because
neither container accesses the Kubernetes API.

The server-side operation used dry-run mode and did not change the live
release.

Helm did not automatically discover K3s's kubeconfig. Cluster-aware Helm
commands use the explicit `/etc/rancher/k3s/k3s.yaml` path, which is readable by
the restricted local `k3s` group. No additional credential copy was created.
