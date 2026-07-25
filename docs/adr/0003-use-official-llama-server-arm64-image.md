# ADR-0003: Use the official versioned llama-server ARM64 image

**Status:** accepted
**Date:** 2026-07-24

## Context

The project goal is Cohere local serving, not maintaining a llama.cpp build.
Upstream added the Cohere2MoE architecture in `b9626` and a dedicated North
Code chat parser in `b9637`. Official versioned server images are now published
for Linux ARM64 and include the embedded Web UI.

A locally maintained API-only ARM64 image was considered, but keeping it as the
default runtime would add build and supply-chain maintenance while removing the
Web UI desired for normal use.

## Options considered

1. Use a versioned official `llama-server` ARM64 container image.
2. Wrap an official Ubuntu ARM64 binary in a locally maintained container.
3. Continue compiling and packaging a custom API-only image.

## Decision

Use:

`ghcr.io/ggml-org/llama.cpp:server-b10108@sha256:06ac0adfef3ce89ce7f080fbe129b4725362a6281ad110c8493fffd6393841c1`

The digest is the Linux ARM64 platform manifest. Keep the embedded Web UI
enabled. Do not maintain a custom Dockerfile, custom image-build or
local-image-import scripts, or locally built images as an alternative runtime
path.

## Consequences

- Installation follows the upstream-supported, immediately usable path.
- The runtime includes upstream fixes after initial North Code support.
- The embedded Web UI becomes available without a separate frontend.
- Build flags and base-image contents are controlled upstream.
- The image still requires local validation for this GGUF, chat template,
  tokenizer, non-root execution, resource behavior, and K3s operation.
- A future runtime upgrade requires a new versioned tag, ARM64 digest, and
  regression test; mutable tags are not used.

## Validation

1. Inspect the OCI manifest and confirm `linux/arm64` plus the pinned digest.
2. Load the pinned Q4_0 GGUF and verify health and Web UI on localhost.
3. Compare embedded tokenizer/chat-template behavior with the model metadata.
4. Verify single-turn, multi-turn, streaming, and stop behavior.
5. Deploy the same digest and GGUF bytes as one K3s serving Pod.
