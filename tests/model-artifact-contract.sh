#!/bin/sh

set -eu

repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
prepare_model_script="${PREPARE_MODEL_SCRIPT:-$repository_root/charts/north-mini-code/files/prepare-model.sh}"

if [ ! -f "$prepare_model_script" ]; then
  printf 'prepare-model script not found: %s\n' "$prepare_model_script" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_absent() {
  [ ! -e "$1" ] || fail "unexpected path remains: $1"
}

run_import() {
  SOURCE_FILE="$1" \
  TARGET_FILE="$2" \
  EXPECTED_SIZE="$3" \
  EXPECTED_SHA256="$4" \
    /bin/sh "$prepare_model_script"
}

source_dir="$work_dir/source"
target_dir="$work_dir/target"
mkdir -p "$source_dir" "$target_dir"

source_file="$source_dir/model.gguf"
target_file="$target_dir/model.gguf"
printf 'small-model-fixture-v1\n' >"$source_file"
expected_size="$(stat -c '%s' "$source_file")"
expected_sha256_line="$(sha256sum "$source_file")"
expected_sha256="${expected_sha256_line%% *}"

printf '1/6 initial verified copy\n'
run_import "$source_file" "$target_file" "$expected_size" "$expected_sha256"
cmp -s "$source_file" "$target_file" || fail 'initial target differs from source'
assert_absent "${target_file}.part"

printf '2/6 verified target reuse without reading source\n'
rm -f -- "$source_file"
run_import "$source_file" "$target_file" "$expected_size" "$expected_sha256"
assert_absent "${target_file}.part"

printf '3/6 invalid source size rejection and cleanup\n'
rm -f -- "$target_file"
printf 'wrong-size\n' >"$source_file"
if run_import "$source_file" "$target_file" "$expected_size" "$expected_sha256"; then
  fail 'size mismatch was accepted'
fi
assert_absent "$target_file"
assert_absent "${target_file}.part"

printf '4/6 invalid source hash rejection and cleanup\n'
printf 'small-model-fixture-v2\n' >"$source_file"
hash_test_size="$(stat -c '%s' "$source_file")"
if run_import "$source_file" "$target_file" "$hash_test_size" "$expected_sha256"; then
  fail 'SHA-256 mismatch was accepted'
fi
assert_absent "$target_file"
assert_absent "${target_file}.part"

printf '5/6 stale partial file replacement and atomic promotion\n'
printf 'stale-partial-data\n' >"${target_file}.part"
printf 'small-model-fixture-v1\n' >"$source_file"
run_import "$source_file" "$target_file" "$expected_size" "$expected_sha256"
cmp -s "$source_file" "$target_file" || fail 'promoted target differs from source'
assert_absent "${target_file}.part"

printf '6/6 invalid target replacement after source verification\n'
printf 'small-model-fixture-v2\n' >"$target_file"
[ "$(stat -c '%s' "$target_file")" = "$expected_size" ] || \
  fail 'invalid target fixture must have the expected size'

copy_guard_dir="$work_dir/copy-guard"
mkdir -p "$copy_guard_dir"
cat >"$copy_guard_dir/cp" <<'EOF'
#!/bin/sh
if [ -e "${TARGET_FILE:?TARGET_FILE is required}" ]; then
  printf 'invalid target still existed when replacement copy started\n' >&2
  exit 97
fi
exec /bin/cp "$@"
EOF
chmod 755 "$copy_guard_dir/cp"

PATH="$copy_guard_dir:$PATH" \
SOURCE_FILE="$source_file" \
TARGET_FILE="$target_file" \
EXPECTED_SIZE="$expected_size" \
EXPECTED_SHA256="$expected_sha256" \
  /bin/sh "$prepare_model_script"
cmp -s "$source_file" "$target_file" || fail 'repaired target differs from source'
assert_absent "${target_file}.part"

printf 'Model artifact contract: PASS\n'
