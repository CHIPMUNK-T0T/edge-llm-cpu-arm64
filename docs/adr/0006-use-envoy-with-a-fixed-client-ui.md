# ADR-0006: Use Envoy with a fixed client UI

**Status:** accepted
**Date:** 2026-08-05

## Context

External PC and Android clients need one stable boundary in front of the
ClusterIP-only inference Service. The upstream llama-server includes a useful
operator UI, but it also exposes model metadata, slot state, metrics, runtime
properties, and model-management routes. Publishing that whole surface would
make the inference runtime, rather than the platform boundary, define the
client contract.

The portfolio needs to demonstrate request policy, streaming, failure
isolation, and replaceable Kubernetes workload boundaries without turning the
verification UI into a separate product.

## Options considered

1. Proxy the embedded llama-server UI and every route. This is simple, but it
   exposes operational and model-management surfaces that clients do not need.
2. Build a custom application gateway. This provides maximum control, but adds
   application code, dependencies, and product scope unrelated to the
   infrastructure objective.
3. Run Envoy as a separate gateway release and serve a minimal static,
   fixed-model UI from its reviewed configuration.

## Decision

Use option 3. Deploy one digest-pinned official Envoy ARM64 image as a separate
Deployment and Helm release. Its ClusterIP Service publishes only port 8080.
The external-client allowlist is:

- GET / plus the two local UI assets;
- GET /health;
- POST /v1/chat/completions;
- POST /v1/messages.

All other routes return 404. The UI uses the fixed served model and provides
only message entry, SSE output, and request cancellation. It does not provide
model switching or generation settings.

The Gateway routes to the inference Service through Kubernetes DNS. It limits
request bodies, does not retry chat POSTs, preserves SSE streaming, removes
upstream timing headers, and emits metadata-only access logs. Envoy-generated
local replies are configured to use stable JSON for an unavailable upstream
(503) and request timeout (504). Both the missing-upstream 503 and a controlled
delayed-upstream 504 are verified without internal connection details.
Application-generated upstream errors pass through unless separately covered
by a contract.
Envoy admin port 9901 is not published by the Service, but it binds the Pod
interface for kubelet probes and is reachable from the cluster Pod network.

The pinned `llama-server` runtime implements both client protocols in the same
process. Envoy forwards both paths to the same inference Service; it does not
translate request or response bodies, and no protocol-adapter Pod is added.
The reviewed requests use `max_tokens: 512`. This is a tested client contract,
not an Envoy-enforced upper bound. The inference runtime is configured with a
public model alias so neither API response exposes the internal model path.

The browser UI treats each streamed exchange transactionally. It adds the
user and assistant messages to subsequent request context only after the
terminal `[DONE]` event. A canceled or failed exchange remains visible to the
operator but is not included in the next request body. Conversation state is
not persisted outside browser memory.

## Consequences

- Client behavior no longer depends on the complete upstream UI/API surface.
- Inference and Gateway can be updated, replaced, and tested independently.
- OpenAI-compatible and Anthropic-compatible clients share the same model,
  inference process, resource limits, and failure domain.
- The UI remains intentionally small and has no persistent history or product
  features.
- Partial output is retained for visibility without allowing an incomplete
  exchange to alter later model context.
- Envoy configuration and browser JavaScript must both understand the
  inference SSE fields used by the selected model.
- The current localhost port-forward is not remote access or authentication.
  Tailscale policy and external-device checks remain separate work.
- This single-replica Gateway does not provide high availability.

## Validation

- Lint and render the chart with tests/gateway-chart-contract.sh.
- Run a K3s server-side dry-run and Helm install/upgrade.
- Run tests/gateway-api-contract.sh through the Gateway Service.
- Verify non-streaming and SSE responses for both `/v1/chat/completions` and
  `/v1/messages` with `max_tokens: 512`.
- Verify that internal inference routes return 404.
- Run tests/gateway-unavailable-contract.sh to point a temporary Gateway release
  at a missing upstream and verify sanitized Envoy-generated 503 responses for
  health and both chat formats.
- Run tests/gateway-timeout-contract.sh with a temporary delayed backend and
  verify a sanitized Envoy-generated 504 health response.
- Verify the Windows browser UI and later repeat the contract from enrolled
  Tailscale clients.
- Verify in the Windows browser that completed exchanges are retained and a
  canceled exchange is excluded from the next request context.
