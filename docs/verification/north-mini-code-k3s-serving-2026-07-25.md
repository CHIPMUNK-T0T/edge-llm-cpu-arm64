# North Mini Code K3s serving verification — 2026-07-25

## Scope and result

**Passed the initial K3s startup and Windows-local Web UI gate.**

This check covers reproducible model placement, one inference Pod becoming
Ready, the ClusterIP Service, embedded Web UI delivery to a Windows browser
path, health, and one completed chat response. It is not a performance verdict,
recovery-time test, external-access test, or long-running stability claim.

## Deployed configuration

| Item | Value |
| --- | --- |
| K3s node | `surface-laptop7`, Linux ARM64, 12 CPU |
| Inference replicas | 1 |
| Runtime | official `server-b10108` ARM64 image, platform digest pinned |
| Model PVC | local-path, ReadWriteOnce, 24 GiB |
| Context | 4,096 tokens |
| Parallel slots | 1 |
| CPU request / limit | 4 / 12 |
| Memory request / limit | 24 GiB / 40 GiB |
| Runtime identity | UID/GID `10001:10001`, non-root |
| Root filesystem | read-only |
| Network exposure | ClusterIP plus temporary localhost port-forward |

The serving Pod mounts the model PVC read-only and uses startup, readiness, and
liveness HTTP probes against `/health`.

## Model placement

The temporary import Job mounted the reference host model directory read-only,
copied to a `.part` path in the PVC, then checked:

- Expected bytes: `17,521,204,800`
- Expected SHA-256:
  `e4803e44e2b97269deb3b33b1ea8d4309d06773ca5f07684f876bd8f751f4f86`
- Job result: `Complete`, `1/1`
- Pod restarts: `0`
- Import and verification duration: `82s`

Final log:

```text
Copying the pinned model into the PVC.
Model import and verification: PASS
```

## Startup

`llama-server` reported:

```text
0.42.412.307 I srv  llama_server: model loaded
0.42.412.315 I srv  llama_server: listening on http://0.0.0.0:8080
```

The Deployment reached `1/1` Ready and Available with zero Pod restarts. The
initial observed rollout took about 51 seconds, including the 42.4-second model
load. It remained `1/1` Ready with zero restarts and zero OOM events through
the final 76-minute observation.

## Windows-local Web UI and API

A temporary port-forward bound only to WSL localhost:

```powershell
wsl -d Ubuntu-24.04 --user root -- k3s kubectl port-forward --address=127.0.0.1 -n edge-llm service/north-mini-code 18080:8080
```

Windows requests to `http://localhost:18080` observed:

| Check | Result |
| --- | --- |
| Embedded Web UI `/` | HTTP 200, `text/html; charset=utf-8`, 1,302 bytes |
| `/health` | `{"status":"ok"}` |
| Chat request, `max_tokens=256` | correct Python function, `finish_reason=stop` |

This proves the K3s-hosted UI and API can be reached from the Windows side
without public or tailnet exposure.

## Resource snapshot after chat

| Observation | Value |
| --- | ---: |
| `kubectl top` memory | 16,598 MiB |
| cgroup `memory.current` | 34,148,413,440 bytes |
| cgroup `memory.peak` | 34,149,617,664 bytes |
| cgroup anonymous memory | 17,294,536,704 bytes |
| cgroup file cache | 16,817,082,368 bytes |
| WSL available memory | 28 GiB |
| WSL swap used | 0 bytes |
| cgroup OOM / OOM-kill | 0 / 0 |

The cgroup total includes the memory-mapped GGUF file cache. It must not be
presented as entirely unreclaimable runtime allocation.

## Known warnings and deferred work

- The existing EOS/EOG metadata warning remains, with no observed stop failure
  in this check.
- CORS allows all origins and no API key is configured. The Service remains
  ClusterIP-only; external access is deferred until the Tailscale and gateway
  boundary is implemented.
- Recovery timing, forced restart drills, monitoring, concurrency, long-context
  behavior, and Tailscale access are intentionally deferred.
