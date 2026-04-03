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
assert_eq "$ROOT/.tmp/workspaces/ezirius/hermes-home/config.yaml" "$HERMES_CONFIG_FILE" "Hermes config file resolves under Hermes home"
assert_eq "$ROOT/.tmp/workspaces/ezirius/workspace" "$HERMES_WORKSPACE_DIR" "workspace dir resolves under workspace root"

ensure_workspace_dirs
test -d "$HERMES_HOME_DIR/sessions"
test -d "$HERMES_HOME_DIR/cache/images"
test -d "$HERMES_HOME_DIR/cache/audio"
test -d "$HERMES_HOME_DIR/platforms/whatsapp/session"
test -d "$HERMES_WORKSPACE_DIR"

touch "$WORKSPACE_ROOT/auth.json"
touch "$WORKSPACE_ROOT/.env"
mkdir -p "$WORKSPACE_ROOT/logs" "$WORKSPACE_ROOT/image_cache" "$WORKSPACE_ROOT/audio_cache" "$WORKSPACE_ROOT/whatsapp/session"
touch "$WORKSPACE_ROOT/logs/runtime.log" "$WORKSPACE_ROOT/image_cache/legacy-image" "$WORKSPACE_ROOT/audio_cache/legacy-audio" "$WORKSPACE_ROOT/whatsapp/session/legacy-wa"
mkdir -p "$HERMES_HOME_DIR/image_cache" "$HERMES_HOME_DIR/audio_cache" "$HERMES_HOME_DIR/whatsapp/session"
touch "$HERMES_HOME_DIR/image_cache/home-image" "$HERMES_HOME_DIR/audio_cache/home-audio" "$HERMES_HOME_DIR/whatsapp/session/home-wa"
migrate_legacy_workspace_layout
test -f "$HERMES_HOME_DIR/auth.json"
test -f "$HERMES_HOME_DIR/logs/runtime.log"
test -f "$HERMES_ENV_FILE"
test -f "$HERMES_HOME_DIR/cache/images/legacy-image"
test -f "$HERMES_HOME_DIR/cache/images/home-image"
test -f "$HERMES_HOME_DIR/cache/audio/legacy-audio"
test -f "$HERMES_HOME_DIR/cache/audio/home-audio"
test -f "$HERMES_HOME_DIR/platforms/whatsapp/session/legacy-wa"
test -f "$HERMES_HOME_DIR/platforms/whatsapp/session/home-wa"
test ! -e "$WORKSPACE_ROOT/auth.json"
test ! -e "$WORKSPACE_ROOT/image_cache"
test ! -e "$WORKSPACE_ROOT/audio_cache"
test ! -e "$WORKSPACE_ROOT/whatsapp"
test ! -e "$HERMES_HOME_DIR/image_cache"
test ! -e "$HERMES_HOME_DIR/audio_cache"
test ! -e "$HERMES_HOME_DIR/whatsapp"

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

if bash -lc 'set -euo pipefail; source "$1"; export HERMES_PODMAN_TTY_WRAPPER=bad; should_wrap_podman_tty_with_script' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: unsupported tty wrapper modes should fail\n' >&2
  exit 1
fi
grep -Fq 'unsupported HERMES_PODMAN_TTY_WRAPPER value: bad' "$ERR_FILE"

if bash -lc 'set -euo pipefail; source "$1"; export HERMES_PODMAN_TTY_WRAPPER=script; PATH="/nonexistent"; should_wrap_podman_tty_with_script' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: explicit script tty mode should fail when script is unavailable\n' >&2
  exit 1
fi
grep -Fq "HERMES_PODMAN_TTY_WRAPPER=script requires 'script' to be installed" "$ERR_FILE"

if bash -lc 'set -euo pipefail; source "$1"; export HERMES_BASE_ROOT="~other/tmp"; resolve_workspace ezirius' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: unsupported ~user path forms should fail\n' >&2
  exit 1
fi
grep -Fq 'unsupported path form: ~other/tmp (use an absolute path or ~/...)' "$ERR_FILE"

EXPECTED_BUILD_FINGERPRINT="$(python3 - "$ROOT" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
paths = []
for tracked_dir in (root / "config/containers", root / "config/patches"):
    if not tracked_dir.exists():
        continue
    paths.extend(
        sorted(
            path
            for path in tracked_dir.rglob("*")
            if path.is_file()
            and "__pycache__" not in path.parts
            and path.suffix != ".pyc"
            and path.name != ".DS_Store"
        )
    )

digest = hashlib.sha256()
for path in paths:
    digest.update(path.relative_to(root).as_posix().encode("utf-8"))
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")

print(digest.hexdigest())
PY
)"
assert_eq "$EXPECTED_BUILD_FINGERPRINT" "$(local_build_fingerprint)" "local build fingerprint covers all non-generated image recipe files"

FINGERPRINT_BEFORE="$(local_build_fingerprint)"
mkdir -p "$ROOT/config/patches/__pycache__"
touch "$ROOT/config/patches/__pycache__/ignored-test-artifact.pyc"
FINGERPRINT_AFTER="$(local_build_fingerprint)"
assert_eq "$FINGERPRINT_BEFORE" "$FINGERPRINT_AFTER" "local build fingerprint ignores generated patch artifacts"
rm -f "$ROOT/config/patches/__pycache__/ignored-test-artifact.pyc"

echo "Common helper checks passed"
