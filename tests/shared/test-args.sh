#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || { printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2; exit 1; }
}

assert_rejects() {
  local script_path="$1" expected="$2"
  shift 2
  local err="$TMPDIR/$(basename "$script_path").err"
  if "$script_path" "$@" >/dev/null 2> "$err"; then
    printf 'assertion failed: %s should reject invalid arguments\n' "$script_path" >&2
    exit 1
  fi
  assert_contains "$err" "$expected" "script reports invalid usage clearly"
}

assert_rejects "$ROOT/scripts/shared/hermes-build" 'requires 1 or 2 arguments'
assert_rejects "$ROOT/scripts/shared/hermes-build" "lane must be 'production' or 'test'" badlane
assert_rejects "$ROOT/scripts/shared/hermes-build" 'upstream must be' production 'has spaces'

assert_rejects "$ROOT/scripts/shared/hermes-start" 'requires 1 argument for picker mode or 3 explicit arguments'
assert_rejects "$ROOT/scripts/shared/hermes-open" 'requires at least 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-shell" 'requires at least 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-stop" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-status" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-logs" 'requires at least 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-remove" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-remove" "mode must be 'container' or 'image'" bad
assert_rejects "$ROOT/scripts/shared/hermes-bootstrap" 'requires at least 1 argument'

HELP_FILE="$TMPDIR/help.out"
"$ROOT/scripts/shared/hermes-build" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage: hermes-build <lane> [upstream]' 'build help documents optional upstream arg'
assert_contains "$HELP_FILE" 'The image gets one immutable tag only:' 'build help documents immutable image tag model'

"$ROOT/scripts/shared/hermes-bootstrap" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage: hermes-bootstrap <workspace-name> [hermes args...]' 'hermes-bootstrap help documents workspace-only contract'

"$ROOT/scripts/shared/hermes-start" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Image naming:' 'start help documents immutable image naming'

"$ROOT/scripts/shared/hermes-open" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Open Hermes by execing into the running container' 'open help is available'

"$ROOT/scripts/shared/hermes-remove" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage: hermes-remove <container|image>' 'remove help documents mode-based contract'

echo "Argument contract checks passed"
