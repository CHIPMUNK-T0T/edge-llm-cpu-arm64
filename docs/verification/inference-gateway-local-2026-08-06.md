# Local inference Gateway verification

- **Date:** 2026-08-06
- **Additional validation:** 2026-08-10 and 2026-08-11
- **Environment:** Surface Laptop 7, WSL2 Ubuntu ARM64, single-node K3s
- **Gateway release:** inference-gateway, namespace edge-llm, Helm revision 6
- **Chart:** inference-gateway-0.1.2
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

    tests/profile-consistency.sh
    tests/gateway-chart-contract.sh
    node --check charts/inference-gateway/files/app.js

    helm upgrade --install inference-gateway charts/inference-gateway \
      --namespace edge-llm \
      --create-namespace \
      --kubeconfig /etc/rancher/k3s/k3s.yaml \
      --dry-run=server

The static contract rendered exactly one ConfigMap, Deployment, and ClusterIP
Service. It verified the pinned image, non-root and read-only security context,
disabled ServiceAccount token mount, one published Service port, route
allowlist for both chat formats, request-size limit, streaming timeout policy,
strict JSON media types, safe fixed-model identity, early SSE-disconnect
guard presence, and fixed-model UI. The profile contract also verified that the
Gateway model identity matches the canonical artifact profile.

## Live workload

Gateway Helm revision 6 and inference Helm revision 7 reached deployed. Both
Deployments reached 1/1 available with one Running Pod each. On 2026-08-11,
WSL2 resume caused Kubernetes `SandboxChanged` recreation; the inference Pod
reported one prior restart, reused the verified PVC artifact, and returned to
Ready after its startup probe allowed model loading. This was not an OOM kill.
The Gateway Service published only port 8080; Envoy admin port 9901 remained
outside the Service. Port 9901 still binds the Pod interface for kubelet probes
and is reachable from the cluster Pod network; no NetworkPolicy isolation is
claimed. The inference runtime used a public model alias instead of its
internal model mount path.

Windows-local access used this one-line command:

    wsl -d Ubuntu-24.04 -- kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml --namespace edge-llm port-forward service/inference-gateway 18080:8080 --address 127.0.0.1

http://localhost:18080/ returned HTTP 200, server identity
inference-gateway, and the Edge LLM Chat document. A port-forward connected to
a replaced Pod had to be restarted after Helm upgrade; it is an operator
process, not a persistent ingress component.

## Client contract

The final command was:

    tests/gateway-api-contract.sh http://localhost:18080

All eleven groups passed with `max_tokens: 512` for both API formats:

1. Web UI, local assets, and browser security headers;
2. public health;
3. GET and POST 404 isolation of metrics, properties, slots, model list, token
   count, and model load;
4. method and strict JSON media-type policy for both chat paths, including
   rejection of `application/jsonp` and acceptance of a charset parameter;
5. OpenAI-compatible non-streaming chat;
6. OpenAI-compatible multi-frame SSE with one final `[DONE]`;
7. Anthropic-compatible non-streaming Messages;
8. Anthropic-compatible SSE ending in `message_stop`;
9. HTTP 413 for a 1,048,577-byte request on each public chat route, confirming
   the 1 MiB body limit;
10. deny-by-default unknown routes;
11. removal of upstream timing and wildcard CORS response metadata.

The selected model can stream reasoning before final content. The OpenAI
contract reconstructs `reasoning_content` and `content`; the Anthropic contract
reconstructs `thinking_delta` and `text_delta`. Both non-streaming responses
returned the fixed public model alias rather than an internal `/models` path.
The same exact alias was verified in all applicable OpenAI and Anthropic SSE
frames.
The 512 value is the reviewed client setting, not a Gateway-enforced JSON
rewrite or a server-side cap on arbitrary client requests.

The direct inference contract also passed all eight groups. It verifies health,
localhost CORS, metrics, invalid-request handling, OpenAI-compatible normal and
SSE responses, and Anthropic-compatible normal and SSE responses. This proves
that both API formats are supplied by the inference runtime rather than
translated by the Gateway.

With a temporary port-forward to the inference Service on port 18081, the
commands were:

    kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml --namespace edge-llm port-forward service/north-mini-code 18081:8080 --address 127.0.0.1
    tests/inference-api-contract.sh http://127.0.0.1:18081

## Unavailable and timed-out upstream

This reusable command created a temporary Gateway release with a nonexistent
in-cluster inference DNS name and removed it after the checks:

    tests/gateway-unavailable-contract.sh

GET /health, POST /v1/chat/completions, and POST /v1/messages all returned
Envoy-generated HTTP 503 with:

    {"error":{"message":"inference unavailable","type":"service_unavailable"}}

The response body and headers contained neither the internal DNS name nor
upstream connection details. The test preserves its original result, surfaces
cleanup failures, explicitly uninstalls the temporary release, confirms that
it no longer exists, and only then reports PASS.

The timeout contract used the already pinned BusyBox ARM64 image as a temporary
backend that accepts each connection and delays its response. It injected a
one-second health timeout into a separate temporary Gateway release:

    tests/gateway-timeout-contract.sh

GET /health returned Envoy-generated HTTP 504 with
`Content-Type: application/json` and:

    {"error":{"message":"inference timeout","type":"gateway_timeout"}}

The response body and headers contained no backend name, upstream connection
details, or timing header. The test removed and confirmed the absence of the
temporary Helm release, Pod, Service, and ConfigMap before reporting PASS. The
normal inference release was not modified or stopped.

## Browser UI smoke

The UI document and assets returned HTTP 200, browser security headers passed,
and `app.js` passed JavaScript syntax validation. The Chart contract statically
confirms that the UI contains a guard requiring terminal `[DONE]`.

On 2026-08-10, the Windows browser UI passed a manual smoke check after the
Gateway and inference Pods recovered from a WSL2 restart:

1. A normal prompt showed the generating state and Stop control, streamed model
   output, then restored the enabled message input and Send control.
2. A long prompt was stopped after partial output appeared. Generation stopped,
   the partial output remained visible, and the enabled message input and Send
   control returned.
3. The UI health indicator reported `利用可能` after both checks.

This verifies the intended user-visible send and cancel behavior. It does not
simulate an involuntary network disconnect in the browser.

On 2026-08-11, the completed-only conversation rule passed an additional
manual check. A completed exchange using the non-sensitive phrase
`紀州南高梅` was available to the following request. A separate long exchange
containing the same phrase was canceled after partial output; the UI retained
the partial text with `（生成を停止しました）`, and the following request
returned `不明`, confirming that the canceled exchange was not included in its
context. An earlier opaque token containing `COMPLETED` was rejected by the
model as password-like content, so it was unsuitable test data rather than a
Gateway or UI failure.

After the WSL2 resume, `tests/gateway-api-contract.sh
http://127.0.0.1:18080` was rerun against Gateway revision 6 and all eleven
groups passed in 94.3 seconds.

## Remaining boundary

This evidence covers K3s and Windows-local access only. It does not demonstrate
Tailscale routing, external PC or Android connectivity, tailnet policy,
network-loss behavior, rate limiting, authentication outside Tailscale, or
long-running Gateway stability. Those remain later verification work.
