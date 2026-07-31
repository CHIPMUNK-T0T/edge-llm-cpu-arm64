# North Mini Code contract-boundary verification

- **Date:** 2026-07-31
- **Environment:** Surface Laptop 7, WSL2 Ubuntu ARM64, single-node K3s
- **Release:** `north-mini-code`, namespace `edge-llm`, Helm revision 5
- **Chart:** `north-mini-code-0.2.0`

## Purpose

Verify that the existing serving baseline can expose narrow Kubernetes-native
injection and test boundaries without adding a long-running workload or
changing the verified model/runtime combination.

The target serving unit remains:

- one `Recreate` Deployment and one inference Pod;
- one model-init container followed by one `llama-server` container;
- one ClusterIP Service;
- one retained local-path PVC.

## Static and fixture contracts

The following commands passed:

```bash
tests/chart-contract.sh .north-mini-code-values.yaml
tests/model-artifact-contract.sh
tests/profile-consistency.sh
helm upgrade north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --dry-run=server
```

Observed:

- strict Helm lint passed;
- the chart rendered exactly one Deployment, Service, and PVC;
- two release names rendered distinct
  `app.kubernetes.io/instance` selectors;
- an unpinned, unsupported runtime image was rejected;
- a schema-valid llama.cpp-compatible model profile reached the model path;
- canonical provenance matched the chart, download script, and benchmark;
- model first copy and verified-target reuse passed;
- size and SHA-256 mismatches failed and removed the partial file;
- a stale partial file was replaced and promoted atomically;
- an invalid existing target was removed only after the source passed size and
  SHA-256 verification, then replaced without requiring two full PVC copies.

The model-init script contract is:

```text
SOURCE_FILE
TARGET_FILE
EXPECTED_SIZE
EXPECTED_SHA256
```

The output is one exact size/SHA-verified file at `TARGET_FILE`. The inference
container receives that PVC read-only.

## Controlled live recreation

Adding the release instance to `Deployment.spec.selector.matchLabels` changes
an immutable Kubernetes field. Direct patch server-side dry-run correctly
rejected the change. Helm and generic apply dry-runs rendered/validated the
desired objects but did not expose this immutable-field failure.

The controlled operation therefore:

1. recorded Helm revision 2 and live resource identities;
2. deleted only Deployment `edge-llm/north-mini-code`;
3. retained the Service and model PVC;
4. ran a normal Helm upgrade to chart `0.2.0`;
5. waited for the recreated Deployment to become Ready.

The operation took approximately 158 seconds wall-clock. That interval includes
Deployment deletion, full existing-model verification, model loading, and
readiness; it is not a precise endpoint-downtime measurement.

After the final static-test and documentation adjustments, a normal no-op
upgrade stored the final chart package as revision 4. Pod
`north-mini-code-78c6658b5f-j75tw` kept UID
`5eeb43ab-be69-441e-8258-e6d3577dffb2` with zero restarts, confirming that the
package synchronization did not recreate the workload.

The pre-commit review then identified that an invalid 17 GB target and a new
17 GB partial copy cannot coexist on the 24 GiB PVC. The model-init contract
was changed to verify the host source before removing an invalid target, and a
fixture now fails if replacement copying starts while that target still
exists. The same review made the selected profile observable as the Pod
template annotation `edge-llm/profile-name`.

Helm revision 5 applied these changes. The replacement Pod reached Ready, and
its init log reported `Model already present and verified.` The healthy 17 GB
artifact was therefore reused without a copy; the Service and retained PVC
remained in place.

## Identity and model results

| Object | Before | After | Result |
| --- | --- | --- | --- |
| Deployment UID | `3bc38c58-1760-4507-8016-84d148b2c7e7` | `ec2aa0ea-f106-4164-8be1-d098e119be66` | Recreated as intended |
| Service UID | `65b94669-b3af-445c-b47d-35cc0f925923` | same | Preserved |
| Service ClusterIP | `10.43.61.232` | same | Preserved |
| PVC UID | `7e9dca97-c302-40bf-8a5f-13862a28d5c5` | same | Preserved |
| PV | `pvc-7e9dca97-c302-40bf-8a5f-13862a28d5c5` | same | Preserved |

The new Pod reached `1/1 Running` with zero restarts. Its init log reported:

```text
Model already present and verified.
```

No 17 GB copy was performed. The Pod had
`automountServiceAccountToken: false` and no `kube-api-access` volume.

## Serving contract

After restarting the localhost-only port-forward:

```bash
tests/api-contract.sh http://localhost:18080
```

passed all contract checks:

- `GET /health` reported status `ok`;
- `GET /metrics` returned llama.cpp Prometheus metadata;
- an empty chat request returned HTTP 400 with an error object;
- non-streaming chat returned choices and content;
- streaming chat returned 92 valid JSON data frames and exactly one `[DONE]`.

The exact SSE frame count is an observation, not a compatibility requirement.
The contract requires at least two JSON frames and one terminal `[DONE]`.

The embedded Web UI returned HTTP 200 with
`text/html; charset=utf-8`. The downloaded compressed body was 1,302 bytes.

## Operational limitation

`kubectl port-forward service/north-mini-code` selects a backend Pod for the
forwarding session. Recreating the inference Pod ended the Windows-local
forward even though the Service object and ClusterIP were preserved. The
operator path had to be started again. This is a localhost verification
limitation, not a failure of the in-cluster Service contract; the future
gateway must not depend on this manual session.
