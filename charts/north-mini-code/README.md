# North Mini Code Helm chart

This chart is the only deployment source for the North Mini Code Q4_0 serving
workload. It targets the repository's single-node ARM64 K3s lab and uses the
verified model and runtime baseline.

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
helm install north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  --create-namespace \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --dry-run=server
```

These commands do not install the chart.

## Install

Install the chart through its normal path. The chart does not create a
Namespace object, so the first install asks Helm to create the release
namespace:

```bash
helm install north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  --create-namespace \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --wait=watcher \
  --timeout 15m
```

Verify the release and workload:

```bash
helm status north-mini-code \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --namespace edge-llm
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  get deployment,pod,service,pvc --namespace edge-llm
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  logs deployment/north-mini-code \
  --namespace edge-llm \
  --container prepare-model
```

In a separate terminal, start the localhost-only operator path:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --namespace edge-llm \
  port-forward --address=127.0.0.1 \
  service/north-mini-code 18080:8080
```

Then verify it:

```bash
curl --compressed --fail --output /dev/null http://localhost:18080/
curl --fail http://localhost:18080/health
```

The embedded UI asset is gzip encoded. Command-line UI checks must advertise
gzip support with `curl --compressed`; normal browsers already do this.

## Controlled upgrade and rollback

Change experiment inputs in the ignored `.north-mini-code-values.yaml`, review
the server-side dry-run, and then upgrade with the same file:

```bash
helm upgrade north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --dry-run=server

helm upgrade north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --wait=watcher \
  --timeout 15m
```

List revisions and roll back to an explicitly selected known-good revision:

```bash
helm history north-mini-code \
  --namespace edge-llm \
  --kubeconfig /etc/rancher/k3s/k3s.yaml

read -r -p "Known-good Helm revision: " REVISION_TO_RESTORE
helm rollback north-mini-code "$REVISION_TO_RESTORE" \
  --namespace edge-llm \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --wait=watcher \
  --timeout 15m
```

Restore the ignored local values file to the rolled-back baseline before the
next upgrade. Otherwise a later upgrade can reapply the experimental value.

## Uninstall and reinstall with retained model storage

Uninstall removes the Deployment, Pod, and Service. The model PVC is retained
by `helm.sh/resource-policy: keep`:

```bash
helm uninstall north-mini-code \
  --namespace edge-llm \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --wait \
  --timeout 10m

kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  get pvc north-mini-code-model --namespace edge-llm
```

Reinstall with the same release name and namespace through the normal install
path:

```bash
helm install north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  --create-namespace \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --wait=watcher \
  --timeout 15m
```

The verified reinstall reused the retained PVC and exact model SHA without
copying the 17 GB artifact again. The PVC protects this Helm lifecycle path,
but it is not a backup: deleting the PVC can delete the local-path PV data.

## K3s credentials

The K3s kubeconfig remains at `/etc/rancher/k3s/k3s.yaml`, readable by the
restricted local `k3s` group. `kubectl` discovers it through K3s, but Helm does
not. Cluster-aware Helm commands must therefore include:

```text
--kubeconfig /etc/rancher/k3s/k3s.yaml
```

This avoids copying the K3s client credential into the repository or another
operator-owned file.
