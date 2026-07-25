# Environment baseline

**Captured:** 2026-07-21 (Asia/Tokyo)

**Purpose:** establish the observed starting point before K3s or model-serving
components are installed. This is evidence for an ARM64 / Windows on ARM
customer-environment constraint, not a claim of a production specification.

## Host and WSL2

| Item | Observed value |
| --- | --- |
| Windows product reported by system tools | Windows 10 Home |
| Windows version / build | 2009 / 26200 |
| Windows architecture | ARM 64-bit Processor |
| Windows physical memory | 68,175,233,024 bytes (about 63.5 GiB) |
| WSL distribution | Ubuntu 24.04 (default WSL version 2) |
| WSL kernel | 6.18.33.2-microsoft-standard-WSL2 |
| Linux architecture | `aarch64` |
| WSL visible memory | 31 GiB total; 30 GiB available at capture |
| WSL swap | 8 GiB |
| WSL root filesystem | 1007 GiB total; 953 GiB available at capture |
| systemd | running |
| WSL IPv4 at capture | `172.26.175.86/20` on `eth0` |

## Tooling inventory at initial capture

| Tool | Location / result | Readiness |
| --- | --- | --- |
| Git | WSL2: 2.43.0; Windows: installed | ready |
| Docker | WSL2: 29.6.2; server: `linux/arm64`; cgroup v2; overlayfs | ready for ARM64 image validation |
| Tailscale | Windows client installed | not yet verified in WSL2 or against a tailnet |
| `kubectl` | not found in WSL2 | install before Phase 1 |
| Helm | not found in WSL2 | install before Phase 2 (may install with Phase 1 tooling) |
| K3s | not found in WSL2 | install before Phase 1 |

## Allocation update — 2026-07-22

The table above is the original capture. After changing `.wslconfig` and fully
stopping WSL2, the active environment reported:

| Item | Observed value |
| --- | --- |
| Configured WSL2 memory ceiling | 48 GB |
| Linux visible memory | 46 GiB total; about 45 GiB available at capture |
| WSL swap | 12 GiB total; 0 used at capture |
| K3s node | Ready |
| K3s node memory at capture | 877 MiB |

The model workload ceiling is 40 GiB. Swap is available for recovery margin,
but swap growth during inference is treated as a failed performance result.

## Interpretation and verification outcomes

1. **Plan to the active WSL2 limit, not host 64 GB.** The current Linux-visible
   total is 46 GiB and the model workload ceiling is 40 GiB. Model quantization,
   context length, and resource limits must begin from these observed values.
2. **Docker is ARM64-capable.** A pinned Alpine ARM64 container executed and
   reported `aarch64`; the result is recorded in
   `docs/verification/arm64-container-runtime-2026-07-21.md`.
3. **K3s is verified on this baseline.** The node reached Ready and the
   model-independent Pod, Service, DNS, probe, metrics, and local-path storage
   checks passed. Results are recorded under `docs/verification/`.
4. **WSL networking is NAT-based.** The `172.26.x.x` address is ephemeral from
   the Linux perspective. External access must be designed and tested through
   Tailscale and the gateway rather than assumed from this address.
5. **Disk capacity is sufficient for initial testing.** Exact model files and
   cache locations must be recorded before download.

## Deferred verification

1. Measure WSL2 and K3s restart behavior after inference startup is stable.
2. Check the Tailscale design and connectivity after the in-cluster service is
   proven; do not expose inference directly while establishing the cluster.
