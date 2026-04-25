#!/usr/bin/env bash

set -euo pipefail

# This test checks that the build script uses saved config values and refuses messy checkouts.

# This finds the repo root so the test can reach the script, config, and shared helpers.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

# This points at the shared config file the test rewrites for a short time.
CONFIG_PATH="$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
CONFIG_BACKUP="$(mktemp)"
TMP_DIR="$(mktemp -d)"
REAL_SMOKE_IMAGE_NAME=""
REAL_SMOKE_CONTAINER_NAME=""

# This checks that two required snippets both exist and appear in the expected textual order.
assert_text_appears_in_order() {
  local first_text="$1"
  local second_text="$2"
  local haystack="$3"
  local message="$4"
  local after_first_text=""

  if [[ "$haystack" != *"$first_text"* ]]; then
    fail "$message: missing [$first_text]"
  fi

  if [[ "$haystack" != *"$second_text"* ]]; then
    fail "$message: missing [$second_text]"
  fi

  after_first_text="${haystack#*"$first_text"}"
  if [[ "$after_first_text" != *"$second_text"* ]]; then
    fail "$message: [$first_text] must appear before [$second_text]"
  fi
}

# This lists real Hermes Agent image names so the smoke check can find the new build output.
list_real_smoke_images() {
  local output_path="$1"

  podman images --format '{{.Repository}}' | while IFS= read -r image_name; do
    case "$image_name" in
      localhost/${HERMES_AGENT_IMAGE_BASENAME}-${HERMES_AGENT_VERSION}-*|${HERMES_AGENT_IMAGE_BASENAME}-${HERMES_AGENT_VERSION}-*)
        printf '%s\n' "$image_name"
        ;;
    esac
  done | sort -u >"$output_path"
}

# This optional smoke case builds the real image and proves the setup-safe entrypoint stays alive.
run_real_image_smoke_check() {
  local before_images="$TMP_DIR/real-images.before"
  local after_images="$TMP_DIR/real-images.after"
  local build_stderr="$TMP_DIR/real-build.stderr"
  local run_stderr="$TMP_DIR/real-run.stderr"
  local running_state=""
  local port_binding=""
  local attempt

  if ! command -v podman >/dev/null 2>&1; then
    fail 'real smoke check requires podman in PATH'
  fi

  if ! podman info >/dev/null 2>&1; then
    fail 'real smoke check requires a working Podman service'
  fi

  # The real build enforces a clean checkout, so restore the tracked config before invoking it.
  cp "$CONFIG_BACKUP" "$CONFIG_PATH"
  # shellcheck disable=SC1090
  source "$CONFIG_PATH"

  list_real_smoke_images "$before_images"

  if ! bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$build_stderr"; then
    cat "$build_stderr" >&2
    fail 'real smoke check expected hermes-agent-build to succeed'
  fi

  list_real_smoke_images "$after_images"
  while IFS= read -r image_name; do
    if [[ -n "$image_name" ]] && ! grep -Fxq -- "$image_name" "$before_images"; then
      REAL_SMOKE_IMAGE_NAME="$image_name"
    fi
  done <"$after_images"

  if [[ -z "$REAL_SMOKE_IMAGE_NAME" ]]; then
    fail 'real smoke check expected the build to create a new Hermes Agent image'
  fi

  REAL_SMOKE_CONTAINER_NAME="hermes-agent-build-smoke-$$"
  if ! podman run -d --rm --name "$REAL_SMOKE_CONTAINER_NAME" -p "127.0.0.1::${HERMES_AGENT_DASHBOARD_PORT}" "$REAL_SMOKE_IMAGE_NAME" >/dev/null 2>"$run_stderr"; then
    cat "$run_stderr" >&2
    fail 'real smoke check expected the built image to start with the default dashboard command'
  fi

  for attempt in 1 2 3 4 5; do
    running_state="$(podman inspect -f '{{.State.Running}}' "$REAL_SMOKE_CONTAINER_NAME" 2>/dev/null || true)"
    if [[ "$running_state" == 'true' ]]; then
      break
    fi
    sleep 1
  done

  assert_equals 'true' "$running_state" 'real smoke check should observe a running dashboard container after startup'

  port_binding="$(podman port "$REAL_SMOKE_CONTAINER_NAME" "${HERMES_AGENT_DASHBOARD_PORT}/tcp" 2>/dev/null || true)"
  if [[ -z "$port_binding" ]]; then
    fail 'real smoke check expected the dashboard port to be published for the running container'
  fi

  sleep 2
  running_state="$(podman inspect -f '{{.State.Running}}' "$REAL_SMOKE_CONTAINER_NAME" 2>/dev/null || true)"
  if [[ "$running_state" != 'true' ]]; then
    podman logs "$REAL_SMOKE_CONTAINER_NAME" >&2 || true
    fail 'real smoke check expected the dashboard command to stay running after startup'
  fi
}

# This puts the real config back and removes the temporary test files.
cleanup() {
  if [[ -n "$REAL_SMOKE_CONTAINER_NAME" ]] && command -v podman >/dev/null 2>&1; then
    podman rm -f "$REAL_SMOKE_CONTAINER_NAME" >/dev/null 2>&1 || true
  fi

  if [[ -n "$REAL_SMOKE_IMAGE_NAME" ]] && command -v podman >/dev/null 2>&1; then
    podman rmi -f "$REAL_SMOKE_IMAGE_NAME" >/dev/null 2>&1 || true
  fi

  cp "$CONFIG_BACKUP" "$CONFIG_PATH"
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

# This saves the real config before the test writes its own version.
cp "$CONFIG_PATH" "$CONFIG_BACKUP"

# This folder holds fake commands so the test can watch what the script would do.
FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

# This fake Podman records the build command, exposes before/after dangling-image snapshots, and writes a stable fake image id to the requested iidfile.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"

if [[ "${1:-}" == 'images' ]]; then
  case "$*" in
    *'--filter dangling=true --format {{.ID}}'*)
      phase_file="${HERMES_TEST_PODMAN_IMAGES_PHASE_FILE:-}"
      if [[ -n "$phase_file" && -f "$phase_file" ]]; then
        current_phase="$(<"$phase_file")"
      else
        current_phase='before'
      fi

      case "$current_phase" in
        before)
          printf 'old-dangling-id\n'
          ;;
        after)
          printf 'old-dangling-id\nnew-dangling-id\n'
          ;;
        multi-after)
          printf 'old-dangling-id\nnew-dangling-id\nother-new-dangling-id\n'
          ;;
      esac
      ;;
    *)
      printf 'unexpected images invocation\n' >&2
      exit 1
      ;;
  esac
elif [[ "${1:-}" == 'rmi' ]]; then
  exit 0
elif [[ "${1:-}" == 'build' ]]; then
  iidfile_path=''
  if [[ -n "${HERMES_TEST_PODMAN_IMAGES_PHASE_FILE:-}" ]]; then
    printf '%s\n' "${HERMES_TEST_PODMAN_IMAGES_PHASE_AFTER:-after}" >"$HERMES_TEST_PODMAN_IMAGES_PHASE_FILE"
  fi
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --iidfile)
        if [[ $# -lt 2 ]]; then
          printf 'expected --iidfile to include a path\n' >&2
          exit 1
        fi
        iidfile_path="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ -z "$iidfile_path" ]]; then
    printf 'expected build to pass --iidfile\n' >&2
    exit 1
  fi

  printf 'new-image-id\n' >"$iidfile_path"
fi
EOF

# This fake git lets the test choose between clean, dirty, no-commit, and broken-worktree states.
cat >"$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$HERMES_TEST_GIT_LOG"

if [[ "$1" == '-C' ]]; then
  shift 2
fi

case "$1 $2 ${3:-}" in
  'rev-parse --show-toplevel ')
    if [[ "${HERMES_TEST_GIT_MODE:-clean}" == "broken-worktree" ]]; then
      printf 'fatal: not a git repository: /workspace/project/.git/worktrees/fix-matrix-device-backport-2\n' >&2
      exit 128
    fi
    printf '%s\n' "${HERMES_TEST_GIT_TOPLEVEL:-$PWD}"
    ;;
  'rev-parse --verify HEAD')
    if [[ "${HERMES_TEST_GIT_MODE:-clean}" == "no-commit" ]]; then
      exit 1
    elif [[ "${HERMES_TEST_GIT_MODE:-clean}" == "broken-worktree" ]]; then
      printf 'fatal: not a git repository: /workspace/project/.git/worktrees/fix-matrix-device-backport-2\n' >&2
      exit 128
    fi
    printf 'deadbeef\n'
    ;;
  'branch --show-current ')
    printf '%s\n' "${HERMES_TEST_GIT_BRANCH:-main}"
    ;;
  'rev-parse --abbrev-ref --symbolic-full-name')
    if [[ "${4:-}" != '@{upstream}' ]]; then
      printf 'unexpected git invocation: %s\n' "$*" >&2
      exit 1
    fi

    if [[ "${HERMES_TEST_GIT_UPSTREAM_STATE:-configured}" == "missing" ]]; then
      exit 1
    fi

    printf '%s\n' "${HERMES_TEST_GIT_UPSTREAM_NAME:-origin/main}"
    ;;
  'rev-list --count @{upstream}..HEAD')
    if [[ "${HERMES_TEST_GIT_AHEAD_STATE:-not-ahead}" == "ahead" ]]; then
      printf '1\n'
    else
      printf '0\n'
    fi
    ;;
  'update-index -q --refresh')
    ;;
  'diff --numstat '|'diff --summary '|'diff --cached --numstat'|'diff --cached --summary')
    if [[ "${HERMES_TEST_GIT_MODE:-clean}" == "dirty" ]]; then
      printf '1\t0\tscripts/agent/shared/hermes-agent-build\n'
    fi
    ;;
  'ls-files --others --exclude-standard')
    ;;
  *)
    printf 'unexpected git invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

# This fake date makes sure the script uses the portable absolute-path date command.
cat >"$FAKE_BIN/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'portable date helper required\n' >&2
exit 1
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/git" "$FAKE_BIN/date"

# This test config keeps the build inputs small and predictable.
cat >"$CONFIG_PATH" <<'EOF'
# Hermes Agent runtime and build configuration.
HERMES_AGENT_IMAGE_BASENAME="hermes-agent"
HERMES_AGENT_UPSTREAM_IMAGE="docker.io/nousresearch/hermes-agent"
HERMES_AGENT_UID="1000"
HERMES_AGENT_GID="1000"
HERMES_AGENT_VERSION="0.10.0"
HERMES_AGENT_RELEASE_TAG="v2026.4.16"
HERMES_AGENT_DASHBOARD_PORT="9234"
HERMES_AGENT_CHAT_COMMAND="hermes"
HERMES_AGENT_SHELL_COMMAND="nu"
HERMES_AGENT_OPEN_COMMAND="open"
HERMES_AGENT_BASE_PATH="${HOME}/tmp/hermes-agent"
HERMES_AGENT_WORKSPACES="alpha:100 beta:200"
HERMES_AGENT_CONTAINER_HOME="/opt/data"
HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"
HERMES_AGENT_HOST_HOME_DIRNAME="hermes-agent-home"
HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"
EOF

# This loads the test config so the optional real smoke check can reuse the saved values.
source "$CONFIG_PATH"

# These logs capture the fake command calls so the test can check behavior.
PODMAN_LOG="$TMP_DIR/podman.log"
GIT_LOG="$TMP_DIR/git.log"
BUILD_STDOUT="$TMP_DIR/build.stdout"
PODMAN_IMAGES_PHASE_FILE="$TMP_DIR/podman-images.phase"
printf 'before\n' >"$PODMAN_IMAGES_PHASE_FILE"

# This clean case should build and should check commit state before building.
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_PODMAN_IMAGES_PHASE_FILE="$PODMAN_IMAGES_PHASE_FILE" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$BUILD_STDOUT"

# These checks prove the build used saved config values and asked git about checkout state.
assert_file_contains 'Image ID: new-image-id' "$BUILD_STDOUT" 'build should print the image id with a label'
if grep -Fxq -- 'new-image-id' "$BUILD_STDOUT"; then
  fail 'build should not print the raw image id on its own line'
fi
assert_file_contains 'rmi new-dangling-id' "$PODMAN_LOG" 'build should remove the exact new dangling builder image created by this build'
assert_file_not_contains 'rmi old-dangling-id' "$PODMAN_LOG" 'build should not remove pre-existing dangling images'
assert_file_not_contains 'rmi new-image-id' "$PODMAN_LOG" 'build should not remove the final tagged runtime image'
assert_file_not_contains 'image prune' "$PODMAN_LOG" 'build should not run a global image prune'

# This multi-dangling case should refuse to guess which new dangling image belongs to this build.
PODMAN_LOG_MULTI="$TMP_DIR/podman-multi.log"
BUILD_STDOUT_MULTI="$TMP_DIR/build-multi.stdout"
printf 'before\n' >"$PODMAN_IMAGES_PHASE_FILE"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG_MULTI" HERMES_TEST_PODMAN_IMAGES_PHASE_FILE="$PODMAN_IMAGES_PHASE_FILE" HERMES_TEST_PODMAN_IMAGES_PHASE_AFTER='multi-after' HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$BUILD_STDOUT_MULTI"
assert_file_not_contains 'rmi new-dangling-id' "$PODMAN_LOG_MULTI" 'build should not remove a dangling image when more than one new dangling image appears during this build window'
assert_file_not_contains 'rmi other-new-dangling-id' "$PODMAN_LOG_MULTI" 'build should not guess between multiple new dangling images'
assert_file_contains '--build-arg HERMES_AGENT_UPSTREAM_IMAGE=docker.io/nousresearch/hermes-agent' "$PODMAN_LOG" 'build should pass the official upstream image from config'
assert_file_contains '--build-arg HERMES_AGENT_RELEASE_TAG=v2026.4.16' "$PODMAN_LOG" 'build should pass release tag from config'
assert_file_contains '--iidfile' "$PODMAN_LOG" 'build should request an iidfile so podman output can keep streaming normally'
assert_file_contains "-C $ROOT rev-parse --verify HEAD" "$GIT_LOG" 'build should check commit state for the repo root'
assert_file_contains "-C $ROOT update-index -q --refresh" "$GIT_LOG" 'build should refresh the index before checking cleanliness'
assert_file_contains "-C $ROOT diff --numstat" "$GIT_LOG" 'build should check unstaged content changes for the repo root'
assert_file_contains "-C $ROOT diff --cached --numstat" "$GIT_LOG" 'build should check staged content changes for the repo root'
assert_file_contains "-C $ROOT ls-files --others --exclude-standard" "$GIT_LOG" 'build should check meaningful untracked files for the repo root'
assert_file_contains "-C $ROOT branch --show-current" "$GIT_LOG" 'build should check the current branch before enforcing push policy'
assert_file_contains "-C $ROOT rev-parse --abbrev-ref --symbolic-full-name @{upstream}" "$GIT_LOG" 'build should look up the upstream branch when building from main'
assert_file_contains "-C $ROOT rev-list --count @{upstream}..HEAD" "$GIT_LOG" 'build should check whether local main is ahead of its upstream'
# These checks lock in the official-image customization contract.
containerfile_path="$ROOT/config/containers/shared/Containerfile"
containerfile_text="$(<"$containerfile_path")"

# This keeps the official image arg ahead of the first FROM so Podman can interpolate the base image.
first_from_match="$(grep -n -m 1 '^[[:space:]]*FROM[[:space:]]' "$containerfile_path" || true)"
if [[ -z "$first_from_match" ]]; then
  fail 'container build test expected the Containerfile to declare at least one FROM instruction'
fi
first_from_line="${first_from_match%%:*}"

arg_match="$(grep -n -m 1 '^[[:space:]]*ARG[[:space:]]\+HERMES_AGENT_UPSTREAM_IMAGE$' "$containerfile_path" || true)"
if [[ -z "$arg_match" ]]; then
  fail 'container build should declare HERMES_AGENT_UPSTREAM_IMAGE before the first FROM'
fi
arg_line="${arg_match%%:*}"
if (( arg_line >= first_from_line )); then
  fail 'container build should declare HERMES_AGENT_UPSTREAM_IMAGE before the first FROM'
fi

assert_file_contains 'FROM ${HERMES_AGENT_UPSTREAM_IMAGE}:${HERMES_AGENT_RELEASE_TAG}' "$ROOT/config/containers/shared/Containerfile" 'container build should derive from the official upstream Hermes Agent image'
assert_file_contains 'apt-get update && apt-get install -y --no-install-recommends' "$ROOT/config/containers/shared/Containerfile" 'container build should use apt to install the local customization packages'
assert_file_contains 'nushell' "$ROOT/config/containers/shared/Containerfile" 'container build should install nushell for the default workspace shell'
assert_file_contains 'rm -rf /var/lib/apt/lists/*' "$ROOT/config/containers/shared/Containerfile" 'container build should clean apt lists after installing nushell'

if grep -Eq 'npm ci|npm run build|uv pip install|curl -fsSL "https://github.com/NousResearch/hermes-agent' "$ROOT/config/containers/shared/Containerfile"; then
  fail 'container build should not rebuild Hermes or the upstream web frontend from source'
fi

if grep -Fq 'hermes-agent-entrypoint' "$ROOT/config/containers/shared/Containerfile"; then
  fail 'container build should use the official upstream entrypoint inherited from the base image'
fi

if grep -Fq 'COPY skills/' "$ROOT/config/containers/shared/Containerfile"; then
  fail 'runtime image should not copy the obsolete repo placeholder skills directory into the image'
fi

if grep -Fq 'CMD ["bash", "-lc", "exec hermes dashboard --host 0.0.0.0 --port \"$HERMES_AGENT_DASHBOARD_PORT\" --no-open --insecure"]' "$ROOT/config/containers/shared/Containerfile"; then
  fail 'runtime image should not keep the old dashboard-only default command once the entrypoint manages startup'
fi

# This dirty case should stop the build before Podman is used.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="dirty" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/dirty.stderr"; then
  fail 'build should fail when the current checkout is dirty'
fi

assert_file_contains 'Build requires a clean checkout with all changes committed.' "$TMP_DIR/dirty.stderr" 'build should explain dirty checkout failures'

# This no-commit case should stop the build before Podman is used.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="no-commit" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/no-commit.stderr"; then
  fail 'build should fail when the current checkout has no commits'
fi

# This checks that the no-commit failure message stays clear.
assert_file_contains 'Build requires the current checkout to have at least one commit.' "$TMP_DIR/no-commit.stderr" 'build should explain missing-commit failures'

# This main-branch case should stop the build when local main is ahead of upstream.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" HERMES_TEST_GIT_BRANCH="main" HERMES_TEST_GIT_UPSTREAM_STATE="configured" HERMES_TEST_GIT_AHEAD_STATE="ahead" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/main-ahead.stderr"; then
  fail 'build should fail when local main is ahead of its upstream'
fi

assert_file_contains 'Build from main requires all commits to be pushed to the remote first.' "$TMP_DIR/main-ahead.stderr" 'build should refuse to run from main when local commits are not pushed'

# This main-branch case should stop the build when no upstream is configured.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" HERMES_TEST_GIT_BRANCH="main" HERMES_TEST_GIT_UPSTREAM_STATE="missing" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/main-no-upstream.stderr"; then
  fail 'build should fail when main has no upstream configured'
fi

assert_file_contains 'Build from main requires a configured upstream remote.' "$TMP_DIR/main-no-upstream.stderr" 'build should refuse to run from main when no upstream remote is configured'

# This non-main case should allow a clean committed checkout even with no upstream configured.
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" HERMES_TEST_GIT_BRANCH="feature/test" HERMES_TEST_GIT_UPSTREAM_STATE="missing" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$TMP_DIR/non-main-no-upstream.stdout"
assert_file_contains 'Image ID: new-image-id' "$TMP_DIR/non-main-no-upstream.stdout" 'build should allow a clean non-main branch even when no upstream is configured'

# This non-main case should allow a clean committed checkout even when ahead of upstream.
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" HERMES_TEST_GIT_BRANCH="feature/test" HERMES_TEST_GIT_UPSTREAM_STATE="configured" HERMES_TEST_GIT_AHEAD_STATE="ahead" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$TMP_DIR/non-main-ahead.stdout"
assert_file_contains 'Image ID: new-image-id' "$TMP_DIR/non-main-ahead.stdout" 'build should allow a clean non-main branch even when it is ahead of upstream'

# This broken-worktree case should explain cross-namespace gitdir failures clearly for a managed worktree path.
mkdir -p "$TMP_DIR/.worktrees/fix-matrix-device-backport-2"
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="broken-worktree" bash -c 'set -euo pipefail; source "$1"; hermes_require_clean_committed_checkout "$2"' _ "$ROOT/lib/shell/shared/common.sh" "$TMP_DIR/.worktrees/fix-matrix-device-backport-2" >/dev/null 2>"$TMP_DIR/broken-worktree.stderr"; then
  fail 'build helper should fail when the checkout points at a missing managed worktree gitdir path'
fi

assert_file_contains 'This checkout is not a usable git worktree in this environment.' "$TMP_DIR/broken-worktree.stderr" 'build helper should explain cross-namespace worktree failures clearly'
assert_file_contains 'Recreate or relink this worktree using relative gitdir paths before building.' "$TMP_DIR/broken-worktree.stderr" 'build helper should tell the user how to recover from a broken worktree link'
assert_file_not_contains 'Build requires the current checkout to have at least one commit.' "$TMP_DIR/broken-worktree.stderr" 'build helper should not misclassify a broken worktree as a no-commit checkout'

# This real file check proves the helper rewrites absolute worktree gitdir links to relative paths.
WORKTREE_TMP="$TMP_DIR/worktree-paths"
mkdir -p "$WORKTREE_TMP/.git/worktrees/feature" "$WORKTREE_TMP/.worktrees/feature"
printf 'gitdir: /workspace/project/.git/worktrees/feature\n' >"$WORKTREE_TMP/.worktrees/feature/.git"

rewritten_gitfile="$(bash -c 'set -euo pipefail; source "$1"; hermes_repair_relative_worktree_gitdir "$2"; cat "$2/.git"' _ "$ROOT/lib/shell/shared/common.sh" "$WORKTREE_TMP/.worktrees/feature")"
assert_equals 'gitdir: ../../.git/worktrees/feature' "$rewritten_gitfile" 'build helper should rewrite managed worktree gitdir links to relative paths'

printf 'gitdir: /foreign/repo/.git/worktrees/feature\n' >"$WORKTREE_TMP/.worktrees/feature/.git"

unchanged_gitfile="$(bash -c 'set -euo pipefail; source "$1"; hermes_repair_relative_worktree_gitdir "$2"; cat "$2/.git"' _ "$ROOT/lib/shell/shared/common.sh" "$WORKTREE_TMP/.worktrees/feature")"
assert_equals 'gitdir: /foreign/repo/.git/worktrees/feature' "$unchanged_gitfile" 'build helper should leave foreign absolute worktree links untouched'

# This real git repo checks that executable-bit changes still count as dirty git changes.
GIT_TMP="$TMP_DIR/git-cleanliness"
mkdir -p "$GIT_TMP"
git init "$GIT_TMP" >/dev/null 2>&1
git -C "$GIT_TMP" config user.name test >/dev/null 2>&1
git -C "$GIT_TMP" config user.email test@example.com >/dev/null 2>&1
printf 'tracked\n' >"$GIT_TMP/tracked.txt"
git -C "$GIT_TMP" add tracked.txt >/dev/null 2>&1
git -C "$GIT_TMP" commit -m 'test' >/dev/null 2>&1
chmod +x "$GIT_TMP/tracked.txt"

if bash -lc 'set -euo pipefail; ROOT="$2"; source "$1"; hermes_require_clean_committed_checkout "$3"' _ "$ROOT/lib/shell/shared/common.sh" "$ROOT" "$GIT_TMP" >/dev/null 2>"$TMP_DIR/mode-change.stderr"; then
  fail 'build should fail when git records an executable-bit change'
fi

assert_file_contains 'Build requires a clean checkout with all changes committed.' "$TMP_DIR/mode-change.stderr" 'build should treat executable-bit changes as dirty checkout state'

# This optional smoke case uses a real image build to verify the dashboard command stays running.
if [[ "${HERMES_TEST_REAL_IMAGE_SMOKE:-0}" == "1" ]]; then
  run_real_image_smoke_check
fi

printf 'hermes-agent-build behavior checks passed\n'
