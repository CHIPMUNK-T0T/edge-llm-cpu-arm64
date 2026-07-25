# North Mini Code Helm chart

This chart is the only deployment source for the North Mini Code Q4_0 serving
workload. It targets the repository's single-node ARM64 K3s lab and preserves
the verified Phase 1 model and runtime baseline.

The chart creates one `Recreate` Deployment, one ClusterIP Service, and one
24 GiB local-path PVC. An init container imports and verifies the pinned GGUF
before `llama-server` starts. The PVC has `helm.sh/resource-policy: keep`
because deleting a release must not discard the verified 17 GB model artifact.

## Local values

Copy the example and set the absolute WSL2 model directory:

```bash
cp .north-mini-code-values.example.yaml .north-mini-code-values.yaml
```

The ignored `.north-mini-code-values.yaml` contains only local overrides. The
tracked `values.yaml` remains the complete, reviewed serving baseline. The
separate `.lab-config.yaml` remains responsible only for K3s operator access.

## Static validation

From the repository root:

```bash
helm lint charts/north-mini-code --strict -f .north-mini-code-values.yaml
helm template north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml
helm template north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml |
  kubectl apply --dry-run=server -n edge-llm -f -
```

These commands do not install the chart.

## Verified Phase 1 ownership migration

The first live install adopted the same-named Phase 1 Deployment, Service, and
PVC in place:

```bash
helm install north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --take-ownership \
  --wait=watcher \
  --timeout 15m
```

`--take-ownership` is required for this one-time migration and for a reinstall
that adopts the PVC retained by an earlier uninstall. A clean install with no
same-named resources does not require it.

Verify the release and workload:

```bash
helm status north-mini-code \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --namespace edge-llm
kubectl get deployment,pod,service,pvc -n edge-llm
kubectl logs -n edge-llm deployment/north-mini-code -c prepare-model
```

In a separate terminal, start the localhost-only operator path:

```bash
kubectl port-forward --address=127.0.0.1 \
  --namespace edge-llm \
  service/north-mini-code 18080:8080
```

Then verify it:

```bash
curl --compressed --fail --output /dev/null http://localhost:18080/
curl --fail http://localhost:18080/health
```

The embedded UI asset is gzip encoded. Command-line UI checks must advertise
gzip support with `curl --compressed`; normal browsers already do this.

Controlled upgrade, rollback, uninstall/reinstall, and explicit SSE validation
remain the next Phase 2 gate.

## K3s credentials

The K3s kubeconfig remains at `/etc/rancher/k3s/k3s.yaml`, readable by the
restricted local `k3s` group. `kubectl` discovers it through K3s, but Helm does
not. Cluster-aware Helm commands must therefore include:

```text
--kubeconfig /etc/rancher/k3s/k3s.yaml
```

This avoids copying the K3s client credential into the repository or another
operator-owned file.
