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

BUILD_ERR="$TMPDIR/hermes-build-upstream.err"
if HERMES_ALLOW_DIRTY=1 "$ROOT/scripts/shared/hermes-build" test 'has spaces' >/dev/null 2> "$BUILD_ERR"; then
  printf 'assertion failed: hermes-build should reject invalid upstream names\n' >&2
  exit 1
fi
assert_contains "$BUILD_ERR" 'upstream must be' 'hermes-build rejects invalid upstream names clearly'

assert_rejects "$ROOT/scripts/shared/hermes-start" 'requires 1 argument for picker mode or 3 explicit arguments'
assert_rejects "$ROOT/scripts/shared/hermes-start" 'requires 1 argument for picker mode or 3 explicit arguments' ezirius production
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
assert_contains "$HELP_FILE" 'Container naming:' 'start help documents deterministic container naming'

"$ROOT/scripts/shared/hermes-open" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Open Hermes by execing into the running container' 'open help is available'

"$ROOT/scripts/shared/hermes-shell" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Open an interactive shell by execing into the running Hermes Gateway container' 'shell help is available'

"$ROOT/scripts/shared/hermes-logs" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Stream container logs for one workspace.' 'logs help is available'

"$ROOT/scripts/shared/hermes-status" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Show the Hermes Gateway container status for one workspace.' 'status help is available'

"$ROOT/scripts/shared/hermes-stop" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Stop the Hermes Gateway container.' 'stop help is available'

"$ROOT/scripts/shared/hermes-remove" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage: hermes-remove <container|image>' 'remove help documents mode-based contract'

echo "Argument contract checks passed"
