# Local inference Gateway verification

- **Date:** 2026-08-06
- **Environment:** Surface Laptop 7, WSL2 Ubuntu ARM64, single-node K3s
- **Gateway release:** inference-gateway, namespace edge-llm, Helm revision 4
- **Chart:** inference-gateway-0.1.0
- **Image:** envoyproxy/envoy:distroless-v1.39.0
- **ARM64 digest:** sha256:8dbb967dba5d22a28f0e7974173aa6d4a5621ce48ac6d44142d9b4d9c960af14
- **Inference release:** north-mini-code, Helm revision 7
- **Inference chart:** north-mini-code-0.2.2

## Purpose

Verify the local client boundary before Tailscale is introduced. The Gateway
must provide the fixed-model Web UI, public health, OpenAI-compatible chat, and
Anthropic-compatible Messages while keeping inference operational and
model-management endpoints internal.

## Static and server-side validation

These commands passed:

    tests/gateway-chart-contract.sh

    helm upgrade --install inference-gateway charts/inference-gateway \
      --namespace edge-llm \
      --create-namespace \
      --kubeconfig /etc/rancher/k3s/k3s.yaml \
      --dry-run=server

The static contract rendered exactly one ConfigMap, Deployment, and ClusterIP
Service. It verified the pinned image, non-root and read-only security context,
disabled ServiceAccount token mount, one published Service port, route
allowlist for both chat formats, request-size limit, streaming timeout policy,
and fixed-model UI.

## Live workload

Gateway Helm revision 4 and inference Helm revision 7 reached deployed. Both
Deployments reached 1/1 available with one Running Pod each and zero restarts.
The Gateway Service published only port 8080; Envoy admin port 9901 remained
outside the Service. The inference runtime used a public model alias instead
of its internal model mount path.

Windows-local access used this one-line command:

    wsl -d Ubuntu-24.04 -- kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml --namespace edge-llm port-forward service/inference-gateway 18080:8080 --address 127.0.0.1

http://localhost:18080/ returned HTTP 200, server identity
inference-gateway, and the Edge LLM Chat document. A port-forward connected to
a replaced Pod had to be restarted after Helm upgrade; it is an operator
process, not a persistent ingress component.

## Client contract

The final command was:

    tests/gateway-api-contract.sh http://localhost:18080

All ten groups passed with `max_tokens: 512` for both API formats:

1. Web UI, local assets, and browser security headers;
2. public health;
3. 404 isolation of metrics, properties, slots, model list, and model load;
4. method and JSON media-type policy for both chat paths;
5. OpenAI-compatible non-streaming chat;
6. OpenAI-compatible multi-frame SSE with one final `[DONE]`;
7. Anthropic-compatible non-streaming Messages;
8. Anthropic-compatible SSE ending in `message_stop`;
9. deny-by-default unknown routes;
10. removal of upstream timing and wildcard CORS response metadata.

A separate 1,048,577-byte POST to `/v1/messages` was rejected with HTTP 413,
confirming the configured 1 MiB request-body limit.

The selected model can stream reasoning before final content. The OpenAI
contract reconstructs `reasoning_content` and `content`; the Anthropic contract
reconstructs `thinking_delta` and `text_delta`. Both non-streaming responses
returned the fixed public model alias rather than an internal `/models` path.
The 512 value is the reviewed client setting, not a Gateway-enforced JSON
rewrite or a server-side cap on arbitrary client requests.

## Unavailable upstream

A temporary gateway-unavailable release used a nonexistent in-cluster
inference DNS name. GET /health, POST /v1/chat/completions, and POST
/v1/messages all returned HTTP 503 with:

    {"error":{"message":"inference unavailable","type":"service_unavailable"}}

The response contained neither the internal DNS name nor upstream connection
details. The temporary release was removed after the check.

## Remaining boundary

This evidence covers K3s and Windows-local access only. It does not demonstrate
Tailscale routing, external PC or Android connectivity, tailnet policy,
network-loss behavior, rate limiting, authentication outside Tailscale, or
long-running Gateway stability. Those remain later verification work.
