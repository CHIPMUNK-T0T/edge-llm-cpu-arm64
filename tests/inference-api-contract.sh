#!/bin/sh

set -eu

base_url="${1:-${API_BASE_URL:-}}"
model_id="${API_MODEL_ID:-North-Mini-Code-1.0-Q4_0.gguf}"
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

curl_request() {
  curl --fail --silent --show-error \
    --connect-timeout "$connect_timeout" \
    --max-time "$request_timeout" \
    "$@"
}

printf '1/6 health contract\n'
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

printf '2/6 browser-origin contract\n'
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
{"model":"$model_id","messages":[{"role":"user","content":"Reply with exactly: hello"}],"max_tokens":256,"temperature":0,"stream":false}
EOF

printf '3/6 metrics contract\n'
curl_request --output "$work_dir/metrics.txt" "$base_url/metrics"
[ -s "$work_dir/metrics.txt" ] || fail 'metrics response is empty'
grep -Eq '^# (HELP|TYPE) llamacpp:' "$work_dir/metrics.txt" || \
  fail 'metrics response has no llama.cpp Prometheus metadata'

printf '4/6 invalid request contract\n'
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

printf '5/6 non-streaming chat contract\n'
curl_request \
  --header 'Content-Type: application/json' \
  --data-binary "@$work_dir/non-stream-request.json" \
  --output "$work_dir/non-stream-response.json" \
  "$base_url/v1/chat/completions"
[ -s "$work_dir/non-stream-response.json" ] || fail 'non-streaming response is empty'
python3 - "$work_dir/non-stream-response.json" <<'PY'
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
PY

cat >"$work_dir/stream-request.json" <<EOF
{"model":"$model_id","messages":[{"role":"user","content":"Reply with exactly: one two three four five"}],"max_tokens":256,"temperature":0,"stream":true}
EOF

printf '6/6 SSE chat contract\n'
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

frame_counts="$(python3 - "$work_dir/stream-body.txt" <<'PY'
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

content_chunks = []
for frame in json_frames:
    choices = frame.get("choices")
    if not isinstance(choices, list) or not choices:
        continue
    delta = choices[0].get("delta")
    if isinstance(delta, dict) and isinstance(delta.get("content"), str):
        content_chunks.append(delta["content"])
if not "".join(content_chunks).strip():
    raise SystemExit("SSE frames contain no reconstructed content")

print(len(json_frames), done_frames)
PY
)"
json_frames="${frame_counts%% *}"
done_frames="${frame_counts##* }"

printf 'Inference API contract: PASS (SSE JSON frames=%s, terminal frames=%s)\n' \
  "$json_frames" "$done_frames"
