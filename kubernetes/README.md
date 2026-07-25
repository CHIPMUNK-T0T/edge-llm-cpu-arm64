# Kubernetes deployment

These manifests deploy one inference replica to the single-node K3s lab. They
use the pinned official Linux ARM64 `llama-server` image and do not build a
custom runtime image.

## 1. Set the local model source

Copy `.lab-config.example.yaml` to the ignored `.lab-config.yaml` and set
`operatorUser` plus the absolute `modelSourcePath`. Do not put the local
account name into the tracked Kubernetes manifest.

Example shape:

```yaml
operatorUser: your-user
modelSourcePath: /home/your-user/work/edge-llm-cpu-arm64/models/north-mini-code
```

## 2. Import the model

The import Job reads the already-verified GGUF from the reference host path and
copies it into a 24 GiB local-path PVC. It verifies the exact byte size and
SHA-256 before renaming the temporary file to its serving name.

```powershell
wsl -d Ubuntu-24.04 --user root -- bash -lc 'cd /home/your-user/work/edge-llm-cpu-arm64 && scripts/render-north-mini-code-model.sh | k3s kubectl apply -f -'
wsl -d Ubuntu-24.04 --user root -- k3s kubectl wait --for=condition=complete job/import-north-mini-code-model -n edge-llm --timeout=10m
wsl -d Ubuntu-24.04 --user root -- k3s kubectl logs -n edge-llm job/import-north-mini-code-model
```

Expected final log:

```text
Model import and verification: PASS
```

The renderer changes only the source `hostPath`; the tracked manifest retains
a non-personal placeholder. Helm packaging will keep this environment-specific
input explicit.

## 3. Start inference

```powershell
wsl -d Ubuntu-24.04 --user root -- k3s kubectl apply -f /home/your-user/work/edge-llm-cpu-arm64/kubernetes/north-mini-code-serving.yaml
wsl -d Ubuntu-24.04 --user root -- k3s kubectl rollout status deployment/north-mini-code -n edge-llm --timeout=10m
wsl -d Ubuntu-24.04 --user root -- k3s kubectl get deployment,pod,service -n edge-llm
```

Expected state:

```text
deployment.apps/north-mini-code   1/1
pod/north-mini-code-...           1/1   Running
service/north-mini-code           ClusterIP
```

## 4. Open the embedded Web UI from Windows

Keep this command running in one PowerShell window:

```powershell
wsl -d Ubuntu-24.04 --user root -- k3s kubectl port-forward --address=127.0.0.1 -n edge-llm service/north-mini-code 18080:8080
```

Then open:

```text
http://localhost:18080
```

This is a localhost-only validation path, not the later Tailscale/gateway
external-access design.
