#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/shell/common.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  [[ "$haystack" == *"$needle"* ]] || { printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2; exit 1; }
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$expected" == "$actual" ]] || { printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2; exit 1; }
}

export HERMES_BASE_ROOT="$ROOT/.tmp/workspaces"
rm -rf "$HERMES_BASE_ROOT"
assert_eq "$HOME" "$(normalize_path '~')" 'normalize_path expands bare tilde'
assert_eq "$HOME/tmp/demo" "$(normalize_path '~/tmp/demo')" 'normalize_path expands home-relative path'
assert_eq '/tmp/demo' "$(normalize_path '/tmp/demo')" 'normalize_path leaves absolute path unchanged'

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

WRAP_TMP="$(mktemp -d)"
trap 'rm -f "$ERR_FILE"; rm -rf "$WRAP_TMP"' EXIT
cat > "$WRAP_TMP/podman" <<'EOF'
#!/usr/bin/env bash
printf 'podman %s\n' "$*" > "$WRAP_TMP/podman-args"
EOF
cat > "$WRAP_TMP/script" <<'EOF'
#!/usr/bin/env bash
printf 'script %s\n' "$*" > "$WRAP_TMP/script-args"
exit 0
EOF
chmod +x "$WRAP_TMP/podman" "$WRAP_TMP/script"
PATH="$WRAP_TMP:$PATH" WRAP_TMP="$WRAP_TMP" bash -c 'set -euo pipefail; source "$1"; export HERMES_PODMAN_TTY_WRAPPER=script; export HERMES_FORCE_EXEC_TTY=1; export OSTYPE=linux-gnu; exec_podman_interactive_command exec demo container' _ "$ROOT/lib/shell/common.sh" >/dev/null 2>&1 || true
grep -Fq 'script -q -e -c podman exec -it demo container /dev/null' "$WRAP_TMP/script-args"

if bash -lc 'set -euo pipefail; source "$1"; export HERMES_BASE_ROOT="~other/tmp"; resolve_workspace ezirius' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: unsupported ~user path forms should fail\n' >&2
  exit 1
fi
grep -Fq 'unsupported path form: ~other/tmp (use an absolute path or ~/...)' "$ERR_FILE"

assert_eq 'main' "$(HERMES_RELEASE_OPTION_CACHE=$'1.2.3\tv1.2.3' display_upstream_ref main)" 'display_upstream_ref preserves main'
assert_eq '1.2.3' "$(HERMES_RELEASE_OPTION_CACHE=$'1.2.3\tv1.2.3' display_upstream_ref v1.2.3)" 'display_upstream_ref maps git tag to display label'
assert_eq 'custom-tag' "$(HERMES_RELEASE_OPTION_CACHE=$'1.2.3\tv1.2.3' display_upstream_ref custom-tag)" 'display_upstream_ref falls back to literal ref'
assert_eq $'beta\nalpha' "$(bash -lc 'set -euo pipefail; source "$1"; export HERMES_SELECT_INDEX=2,1; prompt_select_option prompt alpha beta; printf "\\n"; prompt_select_option prompt alpha beta' _ "$ROOT/lib/shell/common.sh")" 'prompt_select_option consumes scripted selections in order'

resolve_build_target "ezirius" "test" "main" "feature-worktree" "20260408-153210-ab12cd3"
assert_eq 'main' "$HERMES_UPSTREAM_REF" 'resolve_build_target stores resolved upstream ref'
assert_eq 'feature-worktree' "$HERMES_WRAPPER_CONTEXT" 'resolve_build_target stores wrapper context'
assert_eq '20260408-153210-ab12cd3' "$HERMES_COMMITSTAMP" 'resolve_build_target stores commit stamp'
assert_eq 'hermes-agent-ezirius-test-main-feature-worktree' "$HERMES_CONTAINER_NAME" 'resolve_build_target builds deterministic container name'
assert_eq 'hermes-agent-local:test-main-feature-worktree-20260408-153210-ab12cd3' "$HERMES_IMAGE" 'resolve_build_target builds immutable image ref'
assert_eq 'test-main-feature-worktree-20260408-153210-ab12cd3' "$(build_tags_for_lane test main feature-worktree 20260408-153210-ab12cd3)" 'build_tags_for_lane emits immutable image tag'

if ! bash -lc 'set -euo pipefail; source "$1"; is_ignorable_host_untracked_path .DS_Store' _ "$ROOT/lib/shell/common.sh"; then
  printf 'assertion failed: .DS_Store should be treated as ignorable host junk\n' >&2
  exit 1
fi
if bash -lc 'set -euo pipefail; source "$1"; is_ignorable_host_untracked_path src/app.js' _ "$ROOT/lib/shell/common.sh"; then
  printf 'assertion failed: ordinary untracked files must not be treated as ignorable\n' >&2
  exit 1
fi
if ! bash -lc 'set -euo pipefail; source "$1"; has_meaningful_untracked_files <<"EOF"
.DS_Store
._tmp
EOF' _ "$ROOT/lib/shell/common.sh"; then
  :
else
  printf 'assertion failed: only ignorable host files should not count as meaningful untracked files\n' >&2
  exit 1
fi
if ! bash -lc 'set -euo pipefail; source "$1"; has_meaningful_untracked_files <<"EOF"
.DS_Store
notes.txt
EOF' _ "$ROOT/lib/shell/common.sh"; then
  printf 'assertion failed: meaningful untracked files should be detected\n' >&2
  exit 1
fi

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

if bash -lc 'set -euo pipefail; unset ROOT; source "$1"; local_build_fingerprint' _ "$ROOT/lib/shell/common.sh" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: local_build_fingerprint should fail clearly when ROOT is unset\n' >&2
  exit 1
fi
grep -Fq 'ROOT must be set before calling local_build_fingerprint' "$ERR_FILE"

CONFLICT_TMP="$(mktemp -d)"
mkdir -p "$CONFLICT_TMP/source" "$CONFLICT_TMP/target"
touch "$CONFLICT_TMP/source/existing.txt" "$CONFLICT_TMP/target/existing.txt"
if bash -lc 'set -euo pipefail; source "$1"; move_path_contents "$2" "$3"' _ "$ROOT/lib/shell/common.sh" "$CONFLICT_TMP/source" "$CONFLICT_TMP/target" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: migration conflicts should fail explicitly\n' >&2
  exit 1
fi
grep -Fq 'migration target already exists:' "$ERR_FILE"
rm -rf "$CONFLICT_TMP"

GIT_TMP="$(mktemp -d)"
trap 'rm -f "$ERR_FILE"; rm -rf "$WRAP_TMP" "$GIT_TMP"' EXIT
git init "$GIT_TMP" >/dev/null 2>&1
git -C "$GIT_TMP" config user.name test >/dev/null 2>&1
git -C "$GIT_TMP" config user.email test@example.com >/dev/null 2>&1
printf 'tracked\n' > "$GIT_TMP/tracked.txt"
git -C "$GIT_TMP" add tracked.txt
git -C "$GIT_TMP" commit -m 'test' >/dev/null 2>&1

if ! bash -lc 'set -euo pipefail; source "$1"; require_clean_git "$2"' _ "$ROOT/lib/shell/common.sh" "$GIT_TMP" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: clean git repo should pass require_clean_git\n' >&2
  exit 1
fi

touch "$GIT_TMP/.DS_Store"
if ! bash -lc 'set -euo pipefail; source "$1"; require_clean_git "$2"' _ "$ROOT/lib/shell/common.sh" "$GIT_TMP" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: macOS junk files should not fail require_clean_git\n' >&2
  exit 1
fi
rm -f "$GIT_TMP/.DS_Store"

chmod +x "$GIT_TMP/tracked.txt"
if ! bash -lc 'set -euo pipefail; source "$1"; require_clean_git "$2"' _ "$ROOT/lib/shell/common.sh" "$GIT_TMP" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: mode-only changes should not fail require_clean_git\n' >&2
  exit 1
fi
chmod -x "$GIT_TMP/tracked.txt"

printf 'changed\n' > "$GIT_TMP/tracked.txt"
if bash -lc 'set -euo pipefail; source "$1"; require_clean_git "$2"' _ "$ROOT/lib/shell/common.sh" "$GIT_TMP" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: tracked content changes should fail require_clean_git\n' >&2
  exit 1
fi
grep -Fq 'uncommitted changes detected in' "$ERR_FILE"

git -C "$GIT_TMP" checkout -- tracked.txt >/dev/null 2>&1
touch "$GIT_TMP/notes.txt"
if bash -lc 'set -euo pipefail; source "$1"; require_clean_git "$2"' _ "$ROOT/lib/shell/common.sh" "$GIT_TMP" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: meaningful untracked files should fail require_clean_git\n' >&2
  exit 1
fi
grep -Fq 'uncommitted changes detected in' "$ERR_FILE"

echo "Common helper checks passed"
