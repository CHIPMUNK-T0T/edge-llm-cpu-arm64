# ADR-0002: Test North Mini Code Q4_0 on CPU-only ARM64

**Status:** accepted as the initial local-serving model
**Date:** 2026-07-22

## Context

The target is a Surface Laptop 7 running WSL2 and single-node K3s with no
discrete GPU. The experiment should exercise a current Cohere model while
remaining within 46 GiB of Linux-visible memory and a 40 GiB workload ceiling.

North Mini Code 1.0 is a 30B-total, 3B-active sparse MoE model. Cohere publishes
the base model, but not a GGUF artifact for this CPU runtime. The CPU experiment
therefore requires either a costly local conversion or a separately verified
third-party GGUF.

## Options considered

1. Convert the official source weights to GGUF locally.
2. Test a pinned third-party Q4_0 GGUF and verify its identity before execution.
3. Stop at runtime validation without attempting this model.

## Decision

Use the pinned `North-Mini-Code-1.0-Q4_0.gguf` artifact from
`bartowski/North-Mini-Code-1.0-GGUF` as the initial local-serving model.

Q4_0 is selected for the first test because its 17.52 GB file fits the measured
memory envelope and is eligible for the ARM runtime's repacking path. Begin at
4,096 tokens of context, 12 CPU threads, one parallel request, and a 40 GiB
container memory limit.

## Pinned inputs

- Official base revision: `d11e61a842617a22dc328552fa5bb86231ee4f37`
- GGUF repository revision: `6ff6563002170723a6f7a672bf4c99775be6c0dd`
- Filename: `North-Mini-Code-1.0-Q4_0.gguf`
- Expected size: `17,521,204,800` bytes
- Expected SHA-256:
  `e4803e44e2b97269deb3b33b1ea8d4309d06773ca5f07684f876bd8f751f4f86`

## Consequences

- The test covers a model relevant to the intended portfolio and exposes
  sparse-MoE, ARM64, quantization, and memory-management constraints.
- Size and SHA-256 verification identify the downloaded bytes, but do not make
  the third-party conversion an official Cohere artifact.
- Q4_0 can reduce quality compared with higher-precision quantization.
- File size alone does not establish runtime memory use; serving validation
  must measure the workload under its configured memory limit.
- A 4,096-token test does not validate the model's advertised long context.

## Validation

1. Download only the pinned file and verify byte size plus SHA-256.
2. Record the official source and third-party-conversion provenance separately.
3. Use the same verified bytes in later ARM64 runtime and K3s validation.
