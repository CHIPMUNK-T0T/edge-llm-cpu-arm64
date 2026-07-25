# North Mini Code Helm static validation — 2026-07-25

## Scope and result

**Passed the Phase 2 static packaging gate. No live K3s resource was changed.**

The current serving baseline was converted to one Helm chart, the replaced raw
serving manifests and renderer were removed, and the rendered output passed
client-side chart checks plus K3s API server validation. Live Helm ownership,
rollout behavior, UI/API regression, upgrade, rollback, uninstall, and SSE are
not claimed by this result.

## Environment

| Item | Value |
| --- | --- |
| Platform | WSL2 Ubuntu, Linux ARM64 |
| K3s | `v1.36.2+k3s1` |
| Helm | `v4.2.0+g0646808` |
| Helm archive SHA-256 | `1f8de130dfbd04de64978e7b852a7a547be1404956a366608276d2520b678670` |
| Chart | `charts/north-mini-code`, version `0.1.0` |

The Helm version was chosen because Helm 4.2 supports Kubernetes 1.36 through
1.33. The official Linux ARM64 archive was downloaded from `get.helm.sh` and
verified before installation.

## Variable and fixed configuration

| Variable values | Fixed baseline |
| --- | --- |
| local model source path | model identity, Q4_0 filename, size, and SHA-256 |
| context size | official runtime image ARM64 digest |
| thread count | one replica and `Recreate` strategy |
| CPU and memory requests/limits | 24 GiB local-path PVC and ClusterIP Service |
| startup/readiness/liveness timing | non-root and read-only security controls |
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
helm template north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml |
  kubectl apply --dry-run=server -n edge-llm -f -
helm list --kubeconfig /etc/rancher/k3s/k3s.yaml -n edge-llm
```

## Observed results

```text
1 chart(s) linted, 0 chart(s) failed
deployment.apps/north-mini-code configured (server dry run)
persistentvolumeclaim/north-mini-code-model configured (server dry run)
service/north-mini-code configured (server dry run)
schema rejected relative model path: PASS
schema rejected unknown value: PASS
```

The chart rendered exactly three managed resources: Deployment, PVC, and
Service. Comparison with the live Phase 1 objects showed these intentional
changes only:

- standard Helm ownership and chart labels;
- a model preparation/verification init container and its read-only host source;
- `helm.sh/resource-policy: keep` on the bound model PVC.

The `llama-server` image digest, model path, inference arguments, resource
envelope, probes, Pod security context, PVC request, selectors, Service type,
and port remain aligned with the verified Phase 1 baseline.

After validation, the live Deployment remained at generation 1 with
observedGeneration 1, no Helm release existed in `edge-llm`, and the Service
health endpoint returned `{"status":"ok"}`. This confirms the static gate did
not apply the rendered changes.

Helm did not automatically discover K3s's kubeconfig. Cluster-aware Helm
commands use the explicit `/etc/rancher/k3s/k3s.yaml` path, which is readable by
the restricted local `k3s` group. No additional credential copy was created.

## Migration boundary

The existing Deployment, Service, and PVC do not yet have Helm release
ownership metadata. Phase 2 live migration must transfer ownership of these
same-named resources while preserving the bound PVC. The completed Phase 1
model import Job is no longer part of the repository implementation and must be
removed from the live namespace during that controlled migration.

That migration subsequently passed. See
[Helm ownership migration and install verification](north-mini-code-helm-install-2026-07-25.md).
