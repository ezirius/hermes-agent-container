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

assert_rejects "$ROOT/scripts/shared/hermes-build" 'takes no arguments' unexpected
assert_rejects "$ROOT/scripts/shared/hermes-upgrade" 'takes no arguments' unexpected
assert_rejects "$ROOT/scripts/shared/hermes-start" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-start" 'requires exactly 1 argument' one two
assert_rejects "$ROOT/scripts/shared/hermes-open" 'requires at least 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-status" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-shell" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-stop" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-remove" 'requires exactly 1 argument'
assert_rejects "$ROOT/scripts/shared/bootstrap" 'requires at least 1 argument'
assert_rejects "$ROOT/scripts/shared/hermes-logs" 'requires at least 1 argument'

HELP_FILE="$TMPDIR/help.out"
"$ROOT/scripts/shared/bootstrap" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Common forwarded Hermes args:' 'bootstrap help documents key forwarded arguments'

"$ROOT/scripts/shared/hermes-build" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Ensure the shared Hermes image exists.' 'build help is available'

"$ROOT/scripts/shared/hermes-upgrade" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'or when the local wrapper image recipe changed.' 'upgrade help is available'

"$ROOT/scripts/shared/bootstrap" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'local wrapper image recipe changed' 'bootstrap help documents local rebuild triggers'
assert_contains "$HELP_FILE" 'transient interactive container' 'bootstrap help documents transient interactive open flow'

"$ROOT/scripts/shared/hermes-open" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Common Hermes args:' 'open help documents key forwarded arguments'

"$ROOT/scripts/shared/hermes-start" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'The wrapper mounts:' 'start help documents mount layout'
assert_contains "$HELP_FILE" '/data/.env and /data/config.yaml' 'start help documents upstream config loading'
assert_contains "$HELP_FILE" 'unless-stopped' 'start help documents restart policy'

"$ROOT/scripts/shared/hermes-logs" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Common podman log args:' 'logs help documents key forwarded arguments'

"$ROOT/scripts/shared/hermes-status" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Show the Hermes Gateway container status' 'status help is available'

"$ROOT/scripts/shared/hermes-shell" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Open an interactive shell in a transient container' 'shell help is available'

"$ROOT/scripts/shared/hermes-stop" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Stop the Hermes Gateway container' 'stop help is available'

"$ROOT/scripts/shared/hermes-remove" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Remove the Hermes Gateway container' 'remove help is available'

echo "Argument contract checks passed"
