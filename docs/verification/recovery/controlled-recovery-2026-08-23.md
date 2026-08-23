# Controlled recovery verification — 2026-08-23

## Scope

This experiment measures recovery of the single-node ARM64 K3s serving path
after controlled Gateway, inference, configuration, WSL, and Windows restart
events. It tests one replica and records the resulting outage; it does not
claim high availability.

## Environment and controls

- Windows 11 ARM64 with WSL2 Ubuntu 24.04 ARM64
- K3s `v1.36.2+k3s1`
- Inference release `north-mini-code` chart `0.2.2`
- Gateway release `inference-gateway` chart `0.1.2`
- Monitoring release `edge-llm-monitoring` chart `0.1.0`
- North Mini Code Q4_0 GGUF, 17,521,204,800 bytes
- A test starts only from one Ready Gateway Pod, one Ready inference Pod, and
  HTTP 200 from the Gateway `/health` route.
- Every temporary port-forward binds `127.0.0.1` and is removed on exit.
- The invalid-path test refuses to use an existing path and installs a cleanup
  trap that attempts rollback if the measurement exits early.

## Reproduction

From WSL in the repository root:

```bash
bash tests/recovery-script-contract.sh
./scripts/measure-pod-recovery.sh gateway
./scripts/measure-pod-recovery.sh inference
./scripts/measure-invalid-model-recovery.sh
```

Run the WSL restart case from PowerShell. Resolve the script before leaving the
WSL-backed working directory so the Windows process can continue while the
distribution is stopped:

```powershell
$recoveryScript = (Resolve-Path .\scripts\measure-wsl-recovery.ps1).Path
Set-Location C:\Windows\System32
& $recoveryScript
```

## Results

| Failure | Detection / Ready | External health | Recovery mechanism |
| --- | ---: | ---: | --- |
| Delete Gateway Pod | new Pod Ready in 7,676 ms | HTTP 200 in 8,744 ms | Deployment created a replacement Pod |
| Delete inference Pod | new Pod Ready in 169,926 ms | HTTP 200 in 170,968 ms | Deployment recreated the Pod and reloaded the model |
| Invalid model source path | `FailedMount` detected in 4,061 ms; Gateway returned HTTP 503 | HTTP 200 in 67,161 ms from fault injection | rollback to Helm revision 7; rollback Pod Ready in 63,068 ms |
| Terminate WSL distribution | K3s API in 10,488 ms; both serving workloads Ready in 252,601 ms | HTTP 200 in 253,859 ms | WSL started on the first probe, systemd started K3s, containers restarted |
| Restart Windows | K3s API in 11,231 ms; both serving workloads Ready in 64,973 ms from verification start | HTTP 200 in 68,658 ms from verification start | Windows booted, WSL/K3s resumed on verification, and both serving containers restarted |

The invalid source path produced `hostPath type check failed` for the
`source-model` volume. The controlled upgrade was revision 8; rollback produced
the healthy deployed revision 9. The published path is represented as
`/home/your-user/...`; the test script derives the actual site path from the
live Helm release and does not embed an operator identity.

The WSL test proved a real runtime restart: Gateway and inference container
restart counts both changed from 0 to 1. K3s API availability returned quickly,
but the full service remained unavailable until the 17.5 GB model was ready.
Model startup therefore dominates this single-node recovery objective.

## Post-recovery verification

After all five drills:

- Gateway, inference, Prometheus, Grafana, Prometheus Operator, and
  kube-state-metrics were Ready.
- Inference Helm revision 9, Gateway revision 6, and monitoring revision 4 all
  reported `deployed`.
- `scripts/verify-monitoring.sh` passed after both the WSL and Windows restart:
  all eight required raw metric groups and all 14 Grafana PromQL expressions
  returned data.
- The post-Windows-restart monitoring snapshot returned 0.0224 serving CPU
  cores, 17,345,208,320 bytes of serving memory, four Gateway requests, one
  Gateway error, and 0.475 ms inference-upstream p95. These are query-path
  observations, not capacity benchmarks; the counters reflect the current
  Gateway process lifetime.
- No invalid model source remained in the deployed values.

## Windows restart check

Windows reboot is operator-assisted because it terminates the active session.
The two-step script records a pre-reboot baseline and rejects a result unless
Windows reports a newer boot time:

```powershell
pwsh -File .\scripts\verify-windows-restart.ps1 -Mode Prepare
Restart-Computer

# After signing in and returning to the repository:
pwsh -File .\scripts\verify-windows-restart.ps1 -Mode Verify
```

The check passed with Windows boot time `2026-08-23T17:19:26.9528840+09:00`.
Gateway and inference restart counts both increased from 1 to 2. From the start
of the post-login verification, K3s API returned in 11,231 ms, both serving
workloads were Ready in 64,973 ms, and the Gateway returned HTTP 200 in
68,658 ms. `BootToHealthObservationMs` was 163,814 ms. This last value is an
upper bound because verification began after interactive sign-in; it is not an
exact unattended recovery time.

## Interpretation and remaining coverage

- These results demonstrate diagnosis and recovery, not uninterrupted service.
- Gateway replacement is fast because it has no model state. Inference and WSL
  recovery are model-load-bound.
- Helm revision history supplies a controlled recovery path for a bad site
  value without keeping a failed manifest in the repository.
- Memory/OOM, permission, malformed probe, rollout, and Tailscale network-loss
  tests remain. They must be recorded separately rather than inferred from
  these results.
