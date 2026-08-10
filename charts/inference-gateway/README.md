# Inference Gateway Helm chart

This chart deploys the client-facing boundary for the single-node ARM64 K3s
lab. It creates one Envoy Deployment, one ClusterIP Service, and one ConfigMap.
It is a separate Helm release from the inference workload.

The public contract is deliberately small:

- GET / and its local assets provide a fixed-model chat UI;
- GET /health proxies inference readiness;
- POST /v1/chat/completions proxies OpenAI-compatible non-streaming and SSE chat;
- POST /v1/messages proxies Anthropic-compatible non-streaming and SSE chat.

Every other path returns 404. In particular, inference /metrics, /props,
/slots, /v1/models, /v1/messages/count_tokens, and model-management endpoints
are not exposed. The UI
has no model selector or generation settings. Envoy's admin port 9901 is used
for Kubernetes probes but is not published by the Service. It binds the Pod
interface and remains reachable from the cluster Pod network; this chart does
not yet install a NetworkPolicy.

## Validation

From the repository root:

    tests/gateway-chart-contract.sh

    helm upgrade --install inference-gateway charts/inference-gateway \
      --namespace edge-llm \
      --create-namespace \
      --kubeconfig /etc/rancher/k3s/k3s.yaml \
      --dry-run=server

The chart contract checks resource count, the digest-pinned ARM64 image,
non-root/read-only security controls, the single public Service port, the route
allowlist, request-size and stream-time limits, fixed-model UI, release
identity, and values-schema rejection of arbitrary images and unsafe model
identifiers. Public API routes accept only `application/json` with an optional
`charset` parameter; JSON prefix near misses are rejected.

The live contract sends both API formats with `max_tokens` set to 512. This is
the reviewed client setting, not a Gateway-enforced body rewrite or a claim
that arbitrary client values are capped. The inference runtime returns the
fixed public model alias rather than its internal `/models` mount path.

## Install or upgrade

The inference release must already be serving at the default in-cluster
address:

    north-mini-code.edge-llm.svc.cluster.local:8080

Install or upgrade the gateway:

    helm upgrade --install inference-gateway charts/inference-gateway \
      --namespace edge-llm \
      --create-namespace \
      --kubeconfig /etc/rancher/k3s/k3s.yaml \
      --wait=watcher \
      --timeout 3m

For Windows-local verification, keep the Service private and run this command
on one line:

    wsl -d Ubuntu-24.04 -- kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml --namespace edge-llm port-forward service/inference-gateway 18080:8080 --address 127.0.0.1

Open http://localhost:18080/, then run the reusable contract from WSL:

    tests/gateway-api-contract.sh http://localhost:18080

The live contract includes the 1 MiB request-body limit. The unavailable
upstream behavior is reproduced with a temporary Helm release that is removed
automatically:

    tests/gateway-unavailable-contract.sh

A separate temporary backend accepts connections without responding, allowing
the configured 504 local reply to be verified without modifying inference:

    tests/gateway-timeout-contract.sh

If a Gateway upgrade replaces its Pod, restart a long-running
kubectl port-forward before retesting. Port-forward is only the local operator
path; Tailscale exposure is a separate milestone.

## Configuration boundary

The default values bind the reviewed Envoy version and ARM64 platform digest,
the fixed inference Service address, model identifier, request limit,
timeouts, resources, and probes. The schema permits changing the upstream
Service for a tested replacement or failure fixture, but it does not permit an
arbitrary gateway image.

The gateway has no persistent state, public metrics endpoint, application API
key, or public-internet listener. External access must remain within the
private Tailscale design and requires its own verification.
