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

assert_rejects "$ROOT/scripts/shared/hermes-build" 'lane must be one of <production|test>' badlane

BUILD_ERR="$TMPDIR/hermes-build-upstream.err"
if HERMES_ALLOW_DIRTY=1 "$ROOT/scripts/shared/hermes-build" test 'has spaces' >/dev/null 2> "$BUILD_ERR"; then
  printf 'assertion failed: hermes-build should reject invalid upstream names\n' >&2
  exit 1
fi
assert_contains "$BUILD_ERR" 'upstream selector must be' 'hermes-build rejects invalid upstream names clearly'

BUILD_SELECTOR_ERR="$TMPDIR/hermes-build-selector.err"
if HERMES_ALLOW_DIRTY=1 "$ROOT/scripts/shared/hermes-build" test 'feature-branch' >/dev/null 2> "$BUILD_SELECTOR_ERR"; then
  printf 'assertion failed: hermes-build should reject non-stable explicit selectors\n' >&2
  exit 1
fi
assert_contains "$BUILD_SELECTOR_ERR" 'upstream selector must be' 'hermes-build rejects non-stable explicit selectors clearly'

HELP_FILE="$TMPDIR/help.out"
"$ROOT/scripts/shared/hermes-build" --help > "$HELP_FILE"
assert_contains "$HELP_FILE" 'Usage: hermes-build <production|test> [upstream]' 'build help documents lane and optional upstream args'
assert_contains "$HELP_FILE" 'The image gets one immutable tag only:' 'build help documents immutable image tag model'
assert_contains "$HELP_FILE" 'config/shared/tool-versions.conf' 'build help points pinned version policy at tool-versions config'
if grep -Fq 'production-v2026.4.8-main-' "$HELP_FILE"; then
  printf 'assertion failed: build help should not show a v-prefixed immutable tag example that the implementation does not produce\n' >&2
  exit 1
fi

echo "Argument contract checks passed"
