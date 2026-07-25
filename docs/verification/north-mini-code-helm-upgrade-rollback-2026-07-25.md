# North Mini Code Helm upgrade and rollback verification

**Date:** 2026-07-25
**Environment:** Surface Laptop 7, Windows 11 ARM64, WSL2 Ubuntu ARM64,
single-node K3s
**Helm:** v4.2.0
**Release:** `north-mini-code` in `edge-llm`

## Objective

Prove that an experiment input can be changed through the Helm values
interface, verified on the live K3s workload, and restored through Helm
rollback without replacing the Deployment, Service, PVC, or stored model.

The controlled change was `serving.contextSize: 4096 -> 3072`. Model identity,
runtime image, threads, CPU/memory, probes, storage, and Service configuration
were not changed. The ignored `.north-mini-code-values.yaml` was used instead
of an ad hoc `--set` override.

## Preflight

Release revision 1 was `deployed`. The Deployment was `1/1` Ready, the Pod had
zero restarts, health returned `{"status":"ok"}`, and the effective argument
was `--ctx-size 4096`.

The identities recorded for comparison were:

| Resource | Identity before change |
| --- | --- |
| Deployment | `48a35e9e-3d6e-4a56-979c-2a234eaef6c6` |
| Service | `b2fb521f-d42a-4d0f-8c3c-6c4d3bfbfad2` |
| Service ClusterIP | `10.43.245.211` |
| PVC | `7e9dca97-c302-40bf-8a5f-13862a28d5c5` |
| PV binding | `pvc-7e9dca97-c302-40bf-8a5f-13862a28d5c5` |

The proposed revision passed `helm upgrade --dry-run=server` and rendered
`--ctx-size 3072`.

The ignored local values file contained the machine-specific model source path
and this temporary experiment value:

```yaml
serving:
  contextSize: 3072
```

The proposed release was checked without changing the cluster:

```bash
helm upgrade north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --dry-run=server
```

## Ownership conflict discovered during the first live change

The initial live upgrade created failed release revision 2 before changing the
workload:

```text
conflict with "kubectl-client-side-apply":
.spec.template.spec.containers[name="llama-server"].args
```

The old 4096 Pod remained `1/1` Ready and the PVC remained Bound. This was not a
model, memory, probe, or application failure. Phase 1 had created the
Deployment with client-side `kubectl apply`; the Phase 2 `--take-ownership`
install adopted Helm labels and annotations but left the old managed-field
owner on `args`.

`kubectl --show-managed-fields` confirmed both `helm` and
`kubectl-client-side-apply` on that field. Because the repository had already
made Helm the only serving source of truth, the same reviewed upgrade was
retried once with Helm 4's `--force-conflicts`. `--force-replace` was not used.
The retry transferred field control without replacing the Deployment, Service,
or PVC. Routine later upgrades must not add `--force-conflicts` by default.

The reviewed one-time retry was:

```bash
helm upgrade north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --force-conflicts \
  --wait=watcher \
  --timeout 15m
```

## Upgrade result

The successful retry created revision 3. Helm waited until the new Pod was
Ready. The `Recreate` strategy deleted the 4096 Pod and created a different Pod
for 3072; Deployment, Service, and PVC objects were not replaced. This
single-replica rollout necessarily included an availability gap, but endpoint
availability was not sampled continuously and no downtime duration is claimed.

| Check | Revision 3 result |
| --- | --- |
| Helm status | `deployed` |
| Effective argument | `--ctx-size 3072` |
| Pod | `1/1` Running, zero restarts |
| Init verification | `Model already present and verified.` |
| Deployment, Service, PVC identities | unchanged |
| Service ClusterIP and PV binding | unchanged |
| Embedded UI through ClusterIP | HTTP 200, `text/html; charset=utf-8`, 1,302 bytes |
| Health | `{"status":"ok"}` |
| Fixed chat input | correct `add(a, b)` function in 25.18 seconds |
| Chat usage | 135 prompt, 113 completion, 248 total tokens |

The model was verified in place on the retained PVC; it was not copied again.
The approximately 51-second Helm wait covered Pod replacement, full model hash
verification, model load, and readiness.

The same checks were used for the upgraded and rolled-back workloads:

```bash
k3s kubectl get deployment,pod,service,pvc -n edge-llm
k3s kubectl get deployment north-mini-code -n edge-llm \
  -o jsonpath='{.spec.template.spec.containers[0].args}'
k3s kubectl get deployment north-mini-code -n edge-llm \
  --show-managed-fields -o json
curl --compressed --fail --output /dev/null \
  http://10.43.245.211:8080/
curl --fail http://10.43.245.211:8080/health
jq -c '.requests[0].body' \
  benchmark/inputs/north-mini-code-q4-0-k3s-smoke.json |
  curl --fail \
    --header 'Content-Type: application/json' \
    --data-binary @- \
    http://10.43.245.211:8080/v1/chat/completions
```

The fixed request is tracked as
[the North Mini Code K3s smoke input](../../benchmark/inputs/north-mini-code-q4-0-k3s-smoke.json).
After the one-time ownership transfer, the managed-fields check showed `helm`
as the only manager owning the container `args`. A normal server-side Helm
dry-run without `--force-conflicts` then passed.

## Rollback result

Revision 1 was selected explicitly rather than relying on the failed revision
2 or an implicit previous-revision assumption:

```bash
helm rollback north-mini-code 1 \
  --namespace edge-llm \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --wait=watcher \
  --timeout 15m
```

The rollback created release revision 4 with description `Rollback to 1`.

| Check | Revision 4 result |
| --- | --- |
| Helm status | `deployed` |
| Computed and effective context size | 4096 |
| Pod | `1/1` Running, zero restarts |
| Init verification | `Model already present and verified.` |
| Deployment, Service, PVC identities | unchanged from preflight |
| Service ClusterIP and PV binding | unchanged from preflight |
| Embedded UI through ClusterIP | HTTP 200, `text/html; charset=utf-8`, 1,302 bytes |
| Health | `{"status":"ok"}` |
| Fixed chat input | correct `add(a, b)` function in 18.14 seconds |
| Chat usage | 135 prompt, 113 completion, 248 total tokens |

Rollback also replaced the Pod while preserving the Deployment, Service, PVC,
and model data. The rollback Pod was created at `07:26:32Z`, completed init
verification at `07:26:47Z`, and became Ready at `07:27:44Z`: 72 seconds from
Pod creation to Ready. This is a Pod lifecycle measurement, not a continuously
sampled endpoint-downtime figure.

The local values file was restored to the 4096 baseline after rollback, so a
future normal upgrade cannot silently reapply 3072. No model data, credential,
machine-specific path, or generated secret is recorded in this evidence.

## Conclusion

Controlled Helm upgrade and rollback passed. The exercise also exposed and
resolved a migration-specific Kubernetes field-ownership issue while the old
serving Pod remained available. The release is now revision 4, deployed at the
original 4096 context-size baseline. Uninstall/reinstall with the retained PVC
and explicit SSE streaming remain separate Phase 2 gates.
