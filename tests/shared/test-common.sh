#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/shell/common.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$expected" == "$actual" ]] || { printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2; exit 1; }
}

export HERMES_BASE_ROOT="$ROOT/.tmp/workspaces"
rm -rf "$HERMES_BASE_ROOT"
resolve_workspace "ezirius"
assert_eq "ezirius" "$WORKSPACE_NAME" "workspace name resolves"
assert_eq "$ROOT/.tmp/workspaces/ezirius" "$WORKSPACE_ROOT" "workspace root resolves under base root"
assert_eq "$ROOT/.tmp/workspaces/ezirius/hermes-home" "$HERMES_HOME_DIR" "Hermes home resolves under workspace root"
assert_eq "$ROOT/.tmp/workspaces/ezirius/hermes-home/.env" "$HERMES_ENV_FILE" "Hermes env file resolves under Hermes home"
assert_eq "$ROOT/.tmp/workspaces/ezirius/workspace" "$HERMES_WORKSPACE_DIR" "workspace dir resolves under workspace root"

ensure_workspace_dirs
test -d "$HERMES_HOME_DIR/sessions"
test -d "$HERMES_WORKSPACE_DIR"

touch "$WORKSPACE_ROOT/auth.json"
touch "$WORKSPACE_ROOT/.env"
mkdir -p "$WORKSPACE_ROOT/logs"
touch "$WORKSPACE_ROOT/logs/runtime.log"
migrate_legacy_workspace_layout
test -f "$HERMES_HOME_DIR/auth.json"
test -f "$HERMES_HOME_DIR/logs/runtime.log"
test -f "$HERMES_ENV_FILE"
test ! -e "$WORKSPACE_ROOT/auth.json"

ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT
if bash -lc 'set -euo pipefail; source "$1"; export HERMES_BASE_ROOT="$2"; resolve_workspace "/tmp/absolute"' _ "$ROOT/lib/shell/common.sh" "$ROOT/.tmp/workspaces" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: absolute workspace paths should be rejected\n' >&2
  exit 1
fi
grep -Fq 'workspace name must not contain path separators' "$ERR_FILE"

if bash -lc 'set -euo pipefail; source "$1"; resolve_workspace "."' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: dot workspace names should be rejected\n' >&2
  exit 1
fi
grep -Fq "workspace name must not be '.'" "$ERR_FILE"

if bash -lc 'set -euo pipefail; source "$1"; resolve_workspace ".."' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: dot-dot workspace names should be rejected\n' >&2
  exit 1
fi
grep -Fq "workspace name must not be '..'" "$ERR_FILE"

echo "Common helper checks passed"
