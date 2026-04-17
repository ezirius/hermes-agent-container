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
rm -rf "$ROOT/config/patches/__pycache__"
assert_eq 'hermes.wrapper' "$HERMES_LABEL_NAMESPACE" 'label namespace loads from shared config'
assert_eq 'hermes.wrapper.workspace' "$HERMES_LABEL_WORKSPACE" 'workspace label key loads from shared config'
assert_eq '24.04' "$HERMES_UBUNTU_LTS_VERSION" 'ubuntu pin loads from tool versions config'
assert_eq '24' "$HERMES_NODE_LTS_VERSION" 'node pin loads from tool versions config'
assert_eq 'auto' "$HERMES_PODMAN_TTY_WRAPPER" 'podman tty wrapper mode loads from shared config'
assert_eq "$HOME" "$(normalize_path '~')" 'normalize_path expands bare tilde'
assert_eq "$HOME/tmp/demo" "$(normalize_path '~/tmp/demo')" 'normalize_path expands home-relative path'
assert_eq '/tmp/demo' "$(normalize_path '/tmp/demo')" 'normalize_path leaves absolute path unchanged'

mkdir -p "$ROOT/.tmp/workspaces/zeta" "$ROOT/.tmp/workspaces/alpha" "$ROOT/.tmp/workspaces/gamma"
assert_eq $'alpha\ngamma\nzeta' "$(workspace_names_from_base_root)" 'workspace names are listed in alphabetical order'
assert_eq 'manual' "$(resolve_workspace_argument manual)" 'explicit workspace values bypass selection'
assert_eq 'alpha' "$(HERMES_SELECT_INDEX=1 resolve_workspace_argument '')" 'workspace selection chooses the first alphabetical workspace'
assert_eq 'gamma' "$(HERMES_SELECT_INDEX=2 resolve_workspace_argument '')" 'workspace selection honours the chosen alphabetical index'

resolve_workspace "ezirius"
assert_eq "ezirius" "$WORKSPACE_NAME" "workspace name resolves"
assert_eq "$ROOT/.tmp/workspaces/ezirius" "$WORKSPACE_ROOT" "workspace root resolves under base root"
assert_eq "$ROOT/.tmp/workspaces/ezirius/hermes-home" "$HERMES_HOME_DIR" "Hermes home resolves under workspace root"
assert_eq "$ROOT/.tmp/workspaces/ezirius/hermes-home/.env" "$HERMES_ENV_FILE" "Hermes env file resolves under Hermes home"
assert_eq "$ROOT/.tmp/workspaces/ezirius/hermes-home/config.yaml" "$HERMES_CONFIG_FILE" "Hermes config file resolves under Hermes home"
assert_eq "$ROOT/.tmp/workspaces/ezirius/hermes-workspace" "$HERMES_WORKSPACE_DIR" "workspace dir resolves under workspace root"

ensure_workspace_dirs
test -d "$HERMES_HOME_DIR/sessions"
test -d "$HERMES_HOME_DIR/cache/images"
test -d "$HERMES_HOME_DIR/cache/audio"
test -d "$HERMES_HOME_DIR/platforms/whatsapp/session"
test -d "$HERMES_WORKSPACE_DIR"

HERMES_WORKSPACE_HOME_DIRNAME="runtime-home"
HERMES_WORKSPACE_DIRNAME="project-workspace"
resolve_workspace "custom-layout"
ensure_workspace_dirs
assert_eq "$ROOT/.tmp/workspaces/custom-layout/runtime-home" "$HERMES_HOME_DIR" "custom Hermes home dirname resolves under workspace root"
assert_eq "$ROOT/.tmp/workspaces/custom-layout/project-workspace" "$HERMES_WORKSPACE_DIR" "custom workspace dirname resolves under workspace root"
test -d "$HERMES_HOME_DIR/sessions"
test -d "$HERMES_WORKSPACE_DIR"
HERMES_WORKSPACE_HOME_DIRNAME="hermes-home"
HERMES_WORKSPACE_DIRNAME="hermes-workspace"
resolve_workspace "ezirius"

touch "$WORKSPACE_ROOT/auth.json"
touch "$WORKSPACE_ROOT/.env"
mkdir -p "$WORKSPACE_ROOT/logs" "$WORKSPACE_ROOT/image_cache" "$WORKSPACE_ROOT/audio_cache" "$WORKSPACE_ROOT/whatsapp/session" "$WORKSPACE_ROOT/workspace"
touch "$WORKSPACE_ROOT/logs/runtime.log" "$WORKSPACE_ROOT/image_cache/legacy-image" "$WORKSPACE_ROOT/audio_cache/legacy-audio" "$WORKSPACE_ROOT/whatsapp/session/legacy-wa" "$WORKSPACE_ROOT/workspace/legacy-workspace-file"
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
test ! -e "$WORKSPACE_ROOT/workspace"
test ! -e "$HERMES_HOME_DIR/image_cache"
test ! -e "$HERMES_HOME_DIR/audio_cache"
test ! -e "$HERMES_HOME_DIR/whatsapp"
test -f "$HERMES_WORKSPACE_DIR/legacy-workspace-file"

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
trap 'rm -f "$ERR_FILE"; rm -rf "${WRAP_TMP:-}" "${CONFIG_UPDATE_TMP:-}" "${BROKEN_ROOT:-}" "${GIT_TMP:-}"' EXIT
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

CONFIG_UPDATE_TMP="$(mktemp)"
printf 'HERMES_NODE_LTS_VERSION="24"\n' > "$CONFIG_UPDATE_TMP"
update_config_assignment "$CONFIG_UPDATE_TMP" HERMES_NODE_LTS_VERSION 25
grep -Fq 'HERMES_NODE_LTS_VERSION="25"' "$CONFIG_UPDATE_TMP"

if bash -lc 'set -euo pipefail; source "$1"; update_config_assignment "$2" MISSING_KEY value' _ "$ROOT/lib/shell/common.sh" "$CONFIG_UPDATE_TMP" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: updating a missing config assignment should fail clearly\n' >&2
  exit 1
fi
grep -Fq 'missing MISSING_KEY in' "$ERR_FILE"

BROKEN_ROOT="$(mktemp -d)"
mkdir -p "$BROKEN_ROOT/lib/shell" "$BROKEN_ROOT/config/shared"
cp "$ROOT/lib/shell/common.sh" "$BROKEN_ROOT/lib/shell/common.sh"
cat > "$BROKEN_ROOT/config/shared/hermes.conf" <<'EOF'
HERMES_IMAGE_NAME="broken-hermes"
EOF
cat > "$BROKEN_ROOT/config/shared/tool-versions.conf" <<'EOF'
HERMES_UBUNTU_LTS_VERSION="24.04"
HERMES_NODE_LTS_VERSION="24"
EOF
if ROOT="$BROKEN_ROOT" bash -lc 'set -euo pipefail; source "$ROOT/lib/shell/common.sh"' >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: missing required shared config values should fail clearly\n' >&2
  exit 1
fi
grep -Fq 'missing HERMES_PROJECT_PREFIX in config/shared/hermes.conf' "$ERR_FILE"

if bash -lc 'set -euo pipefail; source "$1"; export HERMES_BASE_ROOT="$2"; resolve_workspace_argument ""' _ "$ROOT/lib/shell/common.sh" "$ROOT/.tmp/no-workspaces" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: missing workspaces should fail clearly\n' >&2
  exit 1
fi
grep -Fq 'no workspaces found under' "$ERR_FILE"

assert_eq 'main' "$(HERMES_RELEASE_OPTION_CACHE=$'1.2.3\tv1.2.3' display_upstream_ref main)" 'display_upstream_ref preserves main'
assert_eq '1.2.3' "$(HERMES_RELEASE_OPTION_CACHE=$'1.2.3\tv1.2.3' display_upstream_ref v1.2.3)" 'display_upstream_ref maps git tag to display label'
assert_eq 'custom-tag' "$(HERMES_RELEASE_OPTION_CACHE=$'1.2.3\tv1.2.3' display_upstream_ref custom-tag)" 'display_upstream_ref falls back to literal ref'
assert_eq $'mock-hermes-image:test-main-improve-production-and-testing-20260409-080000-beef123\ttest\tmain\timprove-production-and-testing\t20260409-080000-beef123' "$(image_metadata 'mock-hermes-image:test-main-improve-production-and-testing-20260409-080000-beef123')" 'image metadata parsing preserves hyphenated wrapper contexts'
assert_eq $'beta\nalpha' "$(bash -lc 'set -euo pipefail; source "$1"; export HERMES_SELECT_INDEX=2,1; prompt_select_option prompt alpha beta; printf "\\n"; prompt_select_option prompt alpha beta' _ "$ROOT/lib/shell/common.sh")" 'prompt_select_option consumes scripted selections in order'

resolve_build_target "ezirius" "test" "main" "feature-worktree" "20260408-153210-ab12cd3"
assert_eq 'main' "$HERMES_UPSTREAM_REF" 'resolve_build_target stores resolved upstream ref'
assert_eq 'feature-worktree' "$HERMES_WRAPPER_CONTEXT" 'resolve_build_target stores wrapper context'
assert_eq '20260408-153210-ab12cd3' "$HERMES_COMMITSTAMP" 'resolve_build_target stores commit stamp'
assert_eq 'hermes-agent-ezirius-test-main-feature-worktree' "$HERMES_CONTAINER_NAME" 'resolve_build_target builds deterministic container name'
assert_eq 'hermes-agent-local:test-main-feature-worktree-20260408-153210-ab12cd3' "$HERMES_IMAGE" 'resolve_build_target builds immutable image ref'
assert_eq 'test-main-feature-worktree-20260408-153210-ab12cd3' "$(build_tags_for_lane test main feature-worktree 20260408-153210-ab12cd3)" 'build_tags_for_lane emits immutable image tag'

export HERMES_WRAPPER_CONTEXT_OVERRIDE='feature-worktree'
latest_matching_image_target() { printf 'mock-hermes-image:test-main-feature-worktree-20260409-080000-beef123\ttest\tmain\tfeature-worktree\t20260409-080000-beef123\timage only\n'; }
resolve_start_target "ezirius" "test" "main"
assert_eq 'feature-worktree' "$HERMES_WRAPPER_CONTEXT" 'resolve_start_target uses current wrapper context for explicit start resolution'
assert_eq '20260409-080000-beef123' "$HERMES_COMMITSTAMP" 'resolve_start_target picks newest matching image commit stamp when explicit start omits one'
HERMES_RELEASE_OPTION_CACHE=$'1.2.3\tv1.2.3'
latest_matching_image_target() { printf 'mock-hermes-image:test-1.2.3-feature-worktree-20260410-080000-cafe123\ttest\t1.2.3\tfeature-worktree\t20260410-080000-cafe123\timage only\n'; }
resolve_start_target "ezirius" "test" "latest"
assert_eq '1.2.3' "$HERMES_UPSTREAM_REF" 'resolve_start_target resolves latest to the display upstream label before matching images'
assert_eq '20260410-080000-cafe123' "$HERMES_COMMITSTAMP" 'resolve_start_target matches latest against resolved immutable image labels'
unset HERMES_WRAPPER_CONTEXT_OVERRIDE
unset HERMES_RELEASE_OPTION_CACHE
unset -f latest_matching_image_target

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
for tracked_dir in (root / "config/shared", root / "config/containers", root / "config/patches"):
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

assert_eq "$EXPECTED_BUILD_FINGERPRINT" "$(bash -lc 'set -euo pipefail; unset ROOT; source "$1"; local_build_fingerprint' _ "$ROOT/lib/shell/common.sh")" 'local build fingerprint derives ROOT automatically when sourced without ROOT preset'
assert_eq 'latest' "$(bash -lc 'set -euo pipefail; source "$1"; printf "%s" "$HERMES_REF"' _ "$ROOT/lib/shell/common.sh")" 'default Hermes upstream selector comes from shared config'

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
git -C "$GIT_TMP" branch -M main >/dev/null 2>&1

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
assert_eq "$(git -C "$GIT_TMP" show -s --format='%cd-%h' --date=format:'%Y%m%d-%H%M%S')" "$(wrapper_build_commitstamp "$GIT_TMP" abcdef123456)" 'wrapper build commit stamp matches git commit identity when the worktree is clean'

printf 'changed\n' > "$GIT_TMP/tracked.txt"
DIRTY_COMMITSTAMP="$(wrapper_build_commitstamp "$GIT_TMP" abcdef123456)"
assert_contains "$DIRTY_COMMITSTAMP" 'dirtyabcdef1' 'wrapper build commit stamp switches to a dirty identity suffix when the worktree changes during build'
git -C "$GIT_TMP" checkout -- tracked.txt >/dev/null 2>&1

touch "$GIT_TMP/notes.txt"
if bash -lc 'set -euo pipefail; source "$1"; require_clean_git "$2"' _ "$ROOT/lib/shell/common.sh" "$GIT_TMP" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: meaningful untracked files should fail require_clean_git\n' >&2
  exit 1
fi
grep -Fq 'uncommitted changes detected in' "$ERR_FILE"

rm -f "$GIT_TMP/notes.txt"
WORKTREE_ROOT="$GIT_TMP-wrapper"
mkdir -p "$WORKTREE_ROOT"
git -C "$GIT_TMP" branch feature-worktree >/dev/null 2>&1
git -C "$GIT_TMP" worktree add "$WORKTREE_ROOT/worktrees/feature-worktree" feature-worktree >/dev/null 2>&1

git -C "$GIT_TMP" checkout -b feature-primary >/dev/null 2>&1
assert_eq 'feature-primary' "$(current_wrapper_context "$GIT_TMP")" 'current_wrapper_context reports the real primary-checkout branch name'
git -C "$GIT_TMP" checkout main >/dev/null 2>&1
assert_eq 'feature-worktree' "$(current_wrapper_context "$WORKTREE_ROOT/worktrees/feature-worktree")" 'current_wrapper_context reports linked worktree basename'
assert_eq "$GIT_TMP" "$(fallback_repo_root "$WORKTREE_ROOT/worktrees/feature-worktree")" 'fallback_repo_root resolves the canonical checkout from worktree directory conventions'
assert_eq 'refs/heads/feature-worktree' "$(fallback_ref_for_workdir "$WORKTREE_ROOT/worktrees/feature-worktree")" 'fallback_ref_for_workdir resolves the linked branch ref'
assert_eq false "$(git_is_primary_worktree "$WORKTREE_ROOT/worktrees/feature-worktree" && printf true || printf false)" 'git_is_primary_worktree rejects linked worktrees'
EXPECTED_STAMP="$(git -C "$GIT_TMP" show -s --format=%cd --date=format:%Y%m%d-%H%M%S feature-worktree)-$(git -C "$GIT_TMP" rev-parse --short=7 feature-worktree)"
assert_eq "$EXPECTED_STAMP" "$(git_commit_stamp "$WORKTREE_ROOT/worktrees/feature-worktree")" 'git_commit_stamp resolves linked worktree commit identity'

DOT_WORKTREE_ROOT="$GIT_TMP/.worktrees"
git -C "$GIT_TMP" worktree add "$DOT_WORKTREE_ROOT/dot-worktree" -b dot-worktree >/dev/null 2>&1
assert_eq 'dot-worktree' "$(current_wrapper_context "$DOT_WORKTREE_ROOT/dot-worktree")" 'current_wrapper_context reports project-local dot-worktree basename'
assert_eq "$GIT_TMP" "$(fallback_repo_root "$DOT_WORKTREE_ROOT/dot-worktree")" 'fallback_repo_root resolves the canonical checkout from .worktrees directories'
assert_eq 'refs/heads/dot-worktree' "$(fallback_ref_for_workdir "$DOT_WORKTREE_ROOT/dot-worktree")" 'fallback_ref_for_workdir resolves linked branch refs from .worktrees directories'
assert_eq false "$(git_is_primary_worktree "$DOT_WORKTREE_ROOT/dot-worktree" && printf true || printf false)" 'git_is_primary_worktree rejects .worktrees linked worktrees'
EXPECTED_DOT_STAMP="$(git -C "$GIT_TMP" show -s --format=%cd --date=format:%Y%m%d-%H%M%S dot-worktree)-$(git -C "$GIT_TMP" rev-parse --short=7 dot-worktree)"
assert_eq "$EXPECTED_DOT_STAMP" "$(git_commit_stamp "$DOT_WORKTREE_ROOT/dot-worktree")" 'git_commit_stamp resolves .worktrees linked worktree commit identity'

REMOTE_TMP="$(mktemp -d)"
git init --bare "$REMOTE_TMP/origin.git" >/dev/null 2>&1
git -C "$GIT_TMP" branch -M main >/dev/null 2>&1
git -C "$GIT_TMP" remote add origin "$REMOTE_TMP/origin.git" >/dev/null 2>&1
git -C "$GIT_TMP" push -u origin main >/dev/null 2>&1
if ! bash -lc 'set -euo pipefail; source "$1"; require_main_pushed "$2"' _ "$ROOT/lib/shell/common.sh" "$GIT_TMP" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: synced upstream-tracking repo should pass require_main_pushed\n' >&2
  exit 1
fi

project_image_refs_output="$(bash -c '
  source "$1/lib/shell/common.sh"
  podman() {
    if [[ "$1" == "images" ]]; then
      printf "%s\n" "localhost/hermes-agent-local:test-main-main-20260409-153210-ab12cd3"
      printf "%s\n" "hermes-agent-local:test-main-main-20260409-153210-ab12cd3"
      printf "%s\n" "localhost/hermes-agent-local:production-1.2.3-main-20260409-153210-ab12cd3@sha256:deadbeef"
      return 0
    fi
    return 1
  }
  project_image_refs
' _ "$ROOT")"
assert_eq $'hermes-agent-local:test-main-main-20260409-153210-ab12cd3\nhermes-agent-local:production-1.2.3-main-20260409-153210-ab12cd3' "$project_image_refs_output" "project image refs normalize and dedupe localhost and digest variants"

assert_eq 'main' "$(bash -lc 'source "$1"; image_metadata "localhost/hermes-agent-local:test-main-main-20260409-153210-ab12cd3@sha256:deadbeef" | cut -f4' _ "$ROOT/lib/shell/common.sh")" "image metadata parses normalized immutable tags"

assert_eq $'hermes+agent-demo-production-1.2.3-main' "$(bash -lc 'source "$1"; HERMES_PROJECT_PREFIX="hermes+agent"; podman(){ [[ "$1" == "ps" ]] && printf "%s\n" "hermes+agent-demo-production-1.2.3-main" "hermesagent-demo-production-1.2.3-main"; }; project_container_names' _ "$ROOT/lib/shell/common.sh")" "project container discovery treats configured prefixes literally"

assert_eq 'prod' "$(bash -lc 'source "$1"; HERMES_LANE_PRODUCTION=prod; HERMES_LANE_TEST=qa; image_metadata "hermes-agent-local:prod-1.2.3-main-20260409-153210-ab12cd3" | cut -f2' _ "$ROOT/lib/shell/common.sh")" "image metadata honours configured production lane names"

assert_eq 'demo' "$(bash -lc 'source "$1"; HERMES_PROJECT_PREFIX=hermes-agent; HERMES_LANE_PRODUCTION=prod; HERMES_LANE_TEST=qa; podman(){ case "$1" in inspect) if [[ "$3" == "hermes-agent-demo-prod-1.2.3-main" ]]; then printf "|||20260409-153210-ab12cd3|true"; fi ;; esac; }; container_workspace "hermes-agent-demo-prod-1.2.3-main"' _ "$ROOT/lib/shell/common.sh")" "container workspace fallback honours configured lane names"

rm -rf "$HERMES_BASE_ROOT" "$ROOT/config/patches/__pycache__"

echo "Common helper checks passed"
