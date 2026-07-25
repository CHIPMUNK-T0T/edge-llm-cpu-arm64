# Official llama-server ARM64 validation — 2026-07-24

## Result

**Passed for localhost serving with two deployment controls required.** The
official Linux ARM64 server image loaded the pinned North Mini Code Q4_0 GGUF,
served its embedded Web UI, used the exact official chat template, and passed
single-turn, typed-content, multi-turn, stop, and streaming checks.

The image defaults to root and warns when CORS allows all origins without an
API key. The binary was verified under UID/GID `10001:10001`, a read-only root
filesystem, no Linux capabilities, and no-new-privileges. K3s must enforce those
controls and must not expose the service directly to the public internet.

## Pinned runtime

| Item | Verified value |
| --- | --- |
| Image tag | `ghcr.io/ggml-org/llama.cpp:server-b10108` |
| Linux ARM64 digest | `sha256:06ac0adfef3ce89ce7f080fbe129b4725362a6281ad110c8493fffd6393841c1` |
| Version | `10108 (0a50d9909)` |
| Build platform | GNU 14.2.0, Linux aarch64 |
| Image size | 294,540,243 bytes |
| Default image user | unset, therefore root by default |
| Entrypoint | `/app/llama-server` |

Upstream introduced Cohere2MoE architecture support in `b9626` and the dedicated
North Code chat parser in `b9637`. This later versioned image contains both.
This is upstream implementation support, not a vendor guarantee for this host
and GGUF; the observations below form the local validation evidence.

## Web UI

The server was started with `--ui`. A browser-equivalent compressed request to
`/` returned HTTP 200 and `text/html`. A request without gzip support returned
HTTP 415 with `Error: gzip is not supported by this browser`; normal modern
browsers send the required compression support.

The server also warned that CORS allowed `*` while no API key was configured.
This is acceptable only for the localhost test. External use must go through
the private Tailscale and gateway boundary with request controls.

## Tokenizer and chat template

The pinned official model configuration and runtime-observed GGUF values
matched:

| Token | Official ID | Runtime ID |
| --- | ---: | ---: |
| `<BOS_TOKEN>` | 2 | 2 |
| `<|END_OF_TURN_TOKEN|>` | 255001 | 255001 |
| `<PAD>` | 0 | 0 |

The pinned official `chat_template.jinja` and the runtime template embedded in
the GGUF were byte-for-byte identical:

- Length: 12,397 bytes
- SHA-256:
  `d8366efb9f07c571da620ce6a924594fc52c80273a0fbb46a38b643972df95fd`

The official runtime recognized string and typed content and identified the
template as supporting preserved reasoning.

The warning `special_eos_id is not in special_eog_ids` still appeared. It did
not produce a stop failure, token leak, or stream termination failure in the
checks below. It remains a known warning rather than a resolved metadata claim.

## Functional checks

| Case | Expected | Observed | Finish |
| --- | --- | --- | --- |
| String content | `READY` | `READY` | `stop` |
| Typed content array | `TYPED` | `TYPED` | `stop` |
| Three-message multi-turn | `ORBIT-731` | `ORBIT-731` | `stop` |
| Streaming | `STREAM` | `STREAM` | `stop`, `[DONE]` received |

The streaming response produced 41 valid SSE events, no JSON parse errors, and
no special-token leakage.

## Resource observations

- Model load completed in about 38.17 seconds.
- Docker working set after inference was about 16.28 GiB.
- Raw cgroup `memory.current` peaked at 34,920,005,632 bytes, including
  reclaimable mmap/file-cache accounting for the 17.52 GB GGUF.
- WSL2 still reported 28 GiB available after the checks.
- Container and WSL2 swap remained zero.
- OOM, OOM-kill, and container restarts remained zero.

The raw cgroup value must not be described as entirely anonymous or repacked
model memory. Future controlled memory tests should capture `memory.stat` so
anonymous memory and file cache are recorded separately.

## Next gate

Deploy this exact image digest and model SHA-256 as one K3s serving Pod. Use a
40 GiB memory limit, keep repacking at its upstream default for the first K3s
comparison, and record working set, raw cgroup usage, file cache, swap, and OOM
events before changing runtime settings.
