#!/bin/sh

set -eu

repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
base_url="${1:-${API_BASE_URL:-}}"
default_model_id="$(awk '$1 == "filename:" { gsub(/"/, "", $2); print $2; exit }' \
  "$repository_root/config/models/north-mini-code-q4-0.yaml")"
model_id="${API_MODEL_ID:-$default_model_id}"
connect_timeout="${API_CONNECT_TIMEOUT_SECONDS:-5}"
request_timeout="${API_REQUEST_TIMEOUT_SECONDS:-180}"
local_origin="${INFERENCE_LOCAL_ORIGIN:-http://localhost}"

if [ -z "$base_url" ]; then
  printf 'usage: %s BASE_URL\n' "$0" >&2
  printf 'or set API_BASE_URL; for example http://localhost:18080\n' >&2
  exit 2
fi

case "$base_url" in
  http://*|https://*) ;;
  *)
    printf 'BASE_URL must start with http:// or https://: %s\n' "$base_url" >&2
    exit 2
    ;;
esac

base_url="${base_url%/}"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -n "$model_id" ] || fail 'model identity is missing from the canonical profile'

curl_request() {
  curl --fail --silent --show-error \
    --connect-timeout "$connect_timeout" \
    --max-time "$request_timeout" \
    "$@"
}

printf '1/8 health contract\n'
curl_request --output "$work_dir/health.json" "$base_url/health"
[ -s "$work_dir/health.json" ] || fail 'health response is empty'
python3 - "$work_dir/health.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)
if payload.get("status") != "ok":
    raise SystemExit("health response does not report status ok")
PY

printf '2/8 browser-origin contract\n'
curl_request \
  --header 'Origin: https://untrusted.example' \
  --dump-header "$work_dir/untrusted-origin-headers.txt" \
  --output /dev/null \
  "$base_url/health"
if grep -Eiq '^access-control-allow-origin:' \
  "$work_dir/untrusted-origin-headers.txt"; then
  fail 'untrusted browser origin received an allow-origin header'
fi

curl_request \
  --header "Origin: $local_origin" \
  --dump-header "$work_dir/localhost-origin-headers.txt" \
  --output /dev/null \
  "$base_url/health"
tr -d '\r' <"$work_dir/localhost-origin-headers.txt" \
  >"$work_dir/localhost-origin-headers-normalized.txt"
grep -Fqi "Access-Control-Allow-Origin: $local_origin" \
  "$work_dir/localhost-origin-headers-normalized.txt" || \
  fail 'localhost browser origin was not reflected'
if grep -Eiq '^access-control-allow-credentials:' \
  "$work_dir/localhost-origin-headers-normalized.txt"; then
  fail 'CORS credentials are enabled'
fi

cat >"$work_dir/non-stream-request.json" <<EOF
{"model":"$model_id","messages":[{"role":"user","content":"Reply with exactly: hello"}],"max_tokens":512,"temperature":0,"stream":false}
EOF

printf '3/8 metrics contract\n'
curl_request --output "$work_dir/metrics.txt" "$base_url/metrics"
[ -s "$work_dir/metrics.txt" ] || fail 'metrics response is empty'
grep -Eq '^# (HELP|TYPE) llamacpp:' "$work_dir/metrics.txt" || \
  fail 'metrics response has no llama.cpp Prometheus metadata'

printf '4/8 invalid request contract\n'
invalid_status="$(curl --silent --show-error \
  --connect-timeout "$connect_timeout" \
  --max-time "$request_timeout" \
  --header 'Content-Type: application/json' \
  --data-binary '{}' \
  --output "$work_dir/invalid-response.json" \
  --write-out '%{http_code}' \
  "$base_url/v1/chat/completions")"
case "$invalid_status" in
  4??) ;;
  *) fail "invalid request did not return 4xx: $invalid_status" ;;
esac
python3 - "$work_dir/invalid-response.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)
if not isinstance(payload.get("error"), dict):
    raise SystemExit("invalid request response has no error object")
PY

printf '5/8 OpenAI-compatible non-streaming chat contract\n'
curl_request \
  --header 'Content-Type: application/json' \
  --data-binary "@$work_dir/non-stream-request.json" \
  --output "$work_dir/non-stream-response.json" \
  "$base_url/v1/chat/completions"
[ -s "$work_dir/non-stream-response.json" ] || fail 'non-streaming response is empty'
python3 - "$work_dir/non-stream-response.json" "$model_id" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)
choices = payload.get("choices")
if not isinstance(choices, list) or not choices:
    raise SystemExit("non-streaming response has no choices")
message = choices[0].get("message")
if not isinstance(message, dict):
    raise SystemExit("non-streaming response has no message object")
content = message.get("content")
if not isinstance(content, str) or not content.strip():
    raise SystemExit("non-streaming response content is empty")
if choices[0].get("finish_reason") != "stop":
    raise SystemExit("non-streaming response did not finish with stop")
if payload.get("model") != sys.argv[2]:
    raise SystemExit(f"OpenAI response model alias is unexpected: {payload.get('model')!r}")
PY

cat >"$work_dir/stream-request.json" <<EOF
{"model":"$model_id","messages":[{"role":"user","content":"Reply with exactly: one two three four five"}],"max_tokens":512,"temperature":0,"stream":true}
EOF

printf '6/8 OpenAI-compatible SSE chat contract\n'
curl_request --no-buffer \
  --dump-header "$work_dir/stream-headers.txt" \
  --header 'Accept: text/event-stream' \
  --header 'Content-Type: application/json' \
  --data-binary "@$work_dir/stream-request.json" \
  --output "$work_dir/stream-body.txt" \
  "$base_url/v1/chat/completions"

tr -d '\r' <"$work_dir/stream-headers.txt" >"$work_dir/stream-headers-normalized.txt"
grep -Eiq '^content-type:[[:space:]]*text/event-stream([[:space:]]*;|[[:space:]]*$)' \
  "$work_dir/stream-headers-normalized.txt" || fail 'SSE content type is not text/event-stream'

frame_counts="$(python3 - "$work_dir/stream-body.txt" "$model_id" <<'PY'
import json
import sys

json_frames = []
done_frames = 0
data_events = []
with open(sys.argv[1], encoding="utf-8") as response:
    for raw_line in response:
        line = raw_line.rstrip("\r\n")
        if not line.startswith("data: "):
            continue
        data = line[6:]
        data_events.append(data)
        if data == "[DONE]":
            done_frames += 1
            continue
        json_frames.append(json.loads(data))

if len(json_frames) < 2:
    raise SystemExit(f"SSE returned fewer than two JSON frames: {len(json_frames)}")
if done_frames != 1:
    raise SystemExit(f"SSE terminal frame count is not one: {done_frames}")
if not data_events or data_events[-1] != "[DONE]":
    raise SystemExit("SSE terminal frame is not the final data event")
unexpected_models = sorted(
    {
        repr(frame.get("model"))
        for frame in json_frames
        if frame.get("model") != sys.argv[2]
    }
)
if unexpected_models:
    raise SystemExit(
        "OpenAI SSE model alias is unexpected: " + ", ".join(unexpected_models)
    )

content_chunks = []
for frame in json_frames:
    choices = frame.get("choices")
    if not isinstance(choices, list) or not choices:
        continue
    delta = choices[0].get("delta")
    if isinstance(delta, dict):
        for field in ("content", "reasoning_content"):
            part = delta.get(field)
            if isinstance(part, str):
                content_chunks.append(part)
if not "".join(content_chunks).strip():
    raise SystemExit("SSE frames contain no reconstructed content")

print(len(json_frames), done_frames)
PY
)"
json_frames="${frame_counts%% *}"
done_frames="${frame_counts##* }"

cat >"$work_dir/anthropic-non-stream-request.json" <<EOF
{"model":"$model_id","messages":[{"role":"user","content":"Reply with exactly: hello"}],"max_tokens":512,"temperature":0,"stream":false}
EOF

printf '7/8 Anthropic-compatible non-streaming Messages contract\n'
curl_request \
  --header 'Content-Type: application/json' \
  --header 'anthropic-version: 2023-06-01' \
  --header 'x-api-key: local-contract-key' \
  --data-binary "@$work_dir/anthropic-non-stream-request.json" \
  --output "$work_dir/anthropic-non-stream-response.json" \
  "$base_url/v1/messages"
python3 - "$work_dir/anthropic-non-stream-response.json" "$model_id" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)
if payload.get("type") != "message" or payload.get("role") != "assistant":
    raise SystemExit("Anthropic response is not an assistant message")
if payload.get("model") != sys.argv[2]:
    raise SystemExit(f"Anthropic response model alias is unexpected: {payload.get('model')!r}")
content = payload.get("content")
if not isinstance(content, list) or not content:
    raise SystemExit("Anthropic response has no content blocks")
output = []
for block in content:
    if not isinstance(block, dict):
        continue
    for field in ("text", "thinking"):
        part = block.get(field)
        if isinstance(part, str):
            output.append(part)
if not "".join(output).strip():
    raise SystemExit("Anthropic response content is empty")
if not isinstance(payload.get("usage"), dict):
    raise SystemExit("Anthropic response has no usage object")
PY

cat >"$work_dir/anthropic-stream-request.json" <<EOF
{"model":"$model_id","messages":[{"role":"user","content":"Reply with exactly: one two three"}],"max_tokens":512,"temperature":0,"stream":true}
EOF

printf '8/8 Anthropic-compatible SSE Messages contract\n'
curl_request --no-buffer \
  --dump-header "$work_dir/anthropic-stream-headers.txt" \
  --header 'Accept: text/event-stream' \
  --header 'Content-Type: application/json' \
  --header 'anthropic-version: 2023-06-01' \
  --header 'x-api-key: local-contract-key' \
  --data-binary "@$work_dir/anthropic-stream-request.json" \
  --output "$work_dir/anthropic-stream-body.txt" \
  "$base_url/v1/messages"
tr -d '\r' <"$work_dir/anthropic-stream-headers.txt" \
  >"$work_dir/anthropic-stream-headers-normalized.txt"
grep -Eiq '^content-type:[[:space:]]*text/event-stream([[:space:]]*;|[[:space:]]*$)' \
  "$work_dir/anthropic-stream-headers-normalized.txt" || \
  fail 'Anthropic SSE content type is not text/event-stream'
python3 - "$work_dir/anthropic-stream-body.txt" "$model_id" <<'PY'
import json
import sys

event_names = []
output = []
pending_event = None
start_models = []
with open(sys.argv[1], encoding="utf-8") as response:
    for raw_line in response:
        line = raw_line.rstrip("\r\n")
        if line.startswith("event: "):
            pending_event = line[7:]
            event_names.append(pending_event)
        elif line.startswith("data: "):
            payload = json.loads(line[6:])
            if pending_event and payload.get("type") != pending_event:
                raise SystemExit(
                    f"Anthropic SSE event/data type mismatch: {pending_event}"
                )
            if payload.get("type") == "message_start":
                message = payload.get("message")
                start_models.append(
                    message.get("model") if isinstance(message, dict) else None
                )
            delta = payload.get("delta")
            if isinstance(delta, dict):
                for field in ("text", "thinking"):
                    part = delta.get(field)
                    if isinstance(part, str):
                        output.append(part)
required = {
    "message_start",
    "content_block_start",
    "content_block_delta",
    "content_block_stop",
    "message_delta",
    "message_stop",
}
missing = sorted(required.difference(event_names))
if missing:
    raise SystemExit(f"Anthropic SSE events are missing: {', '.join(missing)}")
if not event_names or event_names[-1] != "message_stop":
    raise SystemExit("Anthropic SSE terminal event is invalid")
if start_models != [sys.argv[2]]:
    raise SystemExit(f"Anthropic SSE model alias is unexpected: {start_models!r}")
if not "".join(output).strip():
    raise SystemExit("Anthropic SSE contains no reconstructed model output")
PY

printf 'Inference API contract: PASS (OpenAI SSE JSON frames=%s, terminal frames=%s; Anthropic sync/SSE passed)\n' \
  "$json_frames" "$done_frames"
