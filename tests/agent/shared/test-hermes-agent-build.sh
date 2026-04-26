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
backup_created=0

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

# This optional smoke case builds the real image and proves the inherited dashboard startup stays alive.
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

  if [[ "$backup_created" == '1' ]]; then
    cp "$CONFIG_BACKUP" "$CONFIG_PATH"
  fi
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

# This saves the real config before the test writes its own version.
cp "$CONFIG_PATH" "$CONFIG_BACKUP"
backup_created=1

# This folder holds fake commands so the test can watch what the script would do.
FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

# This fake Podman records the build, image-id lookup, retag, and cleanup commands without using a real image store.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"

if [[ "${1:-}" == 'image' && "${2:-}" == 'inspect' && "${3:-}" == '--format' ]]; then
  printf 'sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890\n'
elif [[ "${1:-}" == 'tag' ]]; then
  exit 0
elif [[ "${1:-}" == 'images' ]]; then
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

  if [[ -n "$iidfile_path" ]]; then
    printf 'new-image-id\n' >"$iidfile_path"
  fi
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
  'symbolic-ref --quiet --short')
    case "${HERMES_TEST_GIT_MODE:-clean}" in
      clean|dirty|no-commit|main-origin-synced|main-origin-ahead|main-origin-behind|main-origin-diverged|main-no-upstream|main-wrong-head|broken-worktree)
        printf 'main\n'
        ;;
      local-only|feature-upstream)
        printf 'feature-work\n'
        ;;
      detached)
        exit 1
        ;;
      *)
        printf '%s\n' "${HERMES_TEST_GIT_BRANCH:-main}"
        ;;
    esac
    ;;
  'rev-parse --abbrev-ref --symbolic-full-name')
    if [[ "${4:-}" != '@{upstream}' ]]; then
      printf 'unexpected git invocation: %s\n' "$*" >&2
      exit 1
    fi

    if [[ "${HERMES_TEST_GIT_UPSTREAM_STATE:-configured}" == "missing" || "${HERMES_TEST_GIT_MODE:-clean}" == 'local-only' || "${HERMES_TEST_GIT_MODE:-clean}" == 'main-no-upstream' ]]; then
      exit 1
    fi

    if [[ "${HERMES_TEST_GIT_MODE:-clean}" == 'feature-upstream' ]]; then
      printf 'origin/feature-work\n'
      exit 0
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
  'rev-list --left-right --count')
    case "${HERMES_TEST_GIT_MODE:-clean}" in
      clean|main-origin-synced|main-wrong-head)
        printf '0\t0\n'
        ;;
      main-origin-ahead)
        printf '1\t0\n'
        ;;
      main-origin-behind)
        printf '0\t1\n'
        ;;
      main-origin-diverged)
        printf '2\t3\n'
        ;;
      *)
        printf 'unexpected rev-list mode: %s\n' "${HERMES_TEST_GIT_MODE:-clean}" >&2
        exit 1
        ;;
    esac
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

# This fake curl lets the test choose upstream release lookup results without network access.
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${HERMES_TEST_CURL_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$HERMES_TEST_CURL_LOG"
fi

case "$*" in
  *'--connect-timeout 2 --max-time 5'*) ;;
  *)
    printf 'curl missing bounded timeout arguments: %s\n' "$*" >&2
    exit 2
    ;;
esac

case "${HERMES_TEST_LATEST_HERMES_VERSION:-same}" in
  same)
    printf '{"tag_name":"v2026.4.16"}\n'
    ;;
  newer)
    printf '{"tag_name":"v2026.4.17"}\n'
    ;;
  older)
    printf '{"tag_name":"v2026.4.15"}\n'
    ;;
  empty)
    printf '{}\n'
    ;;
  fail)
    exit 7
    ;;
  *)
    printf '{"tag_name":"v%s"}\n' "$HERMES_TEST_LATEST_HERMES_VERSION"
    ;;
esac
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/git" "$FAKE_BIN/date" "$FAKE_BIN/curl"

# This test config keeps the build inputs small and predictable.
cat >"$CONFIG_PATH" <<'EOF'
# Hermes Agent runtime and build configuration.
HERMES_AGENT_IMAGE_BASENAME="hermes-agent"
HERMES_AGENT_UPSTREAM_IMAGE="docker.io/nousresearch/hermes-agent"
HERMES_AGENT_TARGET_ARCH="arm64"
HERMES_AGENT_UID="1000"
HERMES_AGENT_GID="1000"
HERMES_AGENT_VERSION="0.10.0"
HERMES_AGENT_RELEASE_TAG="v2026.4.16"
HERMES_AGENT_DASHBOARD_PORT="9234"
HERMES_AGENT_CHAT_COMMAND="hermes"
HERMES_AGENT_SHELL_COMMAND="nu"
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
CURL_LOG="$TMP_DIR/curl.log"
BUILD_STDOUT="$TMP_DIR/build.stdout"
BUILD_STDERR="$TMP_DIR/build.stderr"
PODMAN_IMAGES_PHASE_FILE="$TMP_DIR/podman-images.phase"
printf 'before\n' >"$PODMAN_IMAGES_PHASE_FILE"

# This clean case should build and should check commit state before building.
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_PODMAN_IMAGES_PHASE_FILE="$PODMAN_IMAGES_PHASE_FILE" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" HERMES_TEST_GIT_MODE="clean" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$BUILD_STDOUT" 2>"$BUILD_STDERR"

# These checks prove the build used saved config values, retagged by image id, and asked git about checkout state.
built_image_line="$(grep '^Built image:' "$BUILD_STDOUT" || true)"
if [[ -z "$built_image_line" ]]; then
  fail 'build should print the final image name with a Built image label'
fi
built_image_name="${built_image_line#Built image: }"
expected_image_regex='^hermes-agent-0\.10\.0-[0-9]{8}-[0-9]{6}-[0-9a-f]{12}$'
if [[ ! "$built_image_name" =~ $expected_image_regex ]]; then
  fail 'build should print the version, timestamp, and 12-character image id in the built image name'
fi
assert_file_contains 'image inspect --format {{.Id}} hermes-agent-0.10.0-' "$PODMAN_LOG" 'build should inspect the temporary image id after building'
assert_file_contains 'api.github.com/repos/NousResearch/hermes-agent/releases/latest' "$CURL_LOG" 'build should check the latest upstream Hermes Agent release before build work'
assert_file_not_contains 'newer Hermes Agent version available' "$BUILD_STDERR" 'build should not warn when the upstream release matches the pinned release tag'
assert_file_contains 'tag hermes-agent-0.10.0-' "$PODMAN_LOG" 'build should retag the temporary image into the final image name'
assert_file_contains 'rmi hermes-agent-0.10.0-' "$PODMAN_LOG" 'build should remove the temporary image tag after retagging'
assert_file_not_contains 'Image ID:' "$BUILD_STDOUT" 'build should not print the old iidfile label'
assert_file_not_contains '--iidfile' "$PODMAN_LOG" 'build should not use iidfile naming once final names include the image id'
assert_file_not_contains 'rmi new-dangling-id' "$PODMAN_LOG" 'build should not remove dangling builder images under the temporary-tag flow'
assert_file_not_contains 'rmi old-dangling-id' "$PODMAN_LOG" 'build should not remove pre-existing dangling images'
assert_file_not_contains 'image prune' "$PODMAN_LOG" 'build should not run a global image prune'

: >"$PODMAN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_LATEST_HERMES_VERSION='newer' HERMES_TEST_GIT_MODE="clean" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$TMP_DIR/build-newer.stdout" 2>"$TMP_DIR/build-newer.stderr"
assert_file_contains 'warning: newer Hermes Agent version available (2026.4.17); continuing with pinned release v2026.4.16' "$TMP_DIR/build-newer.stderr" 'build should warn when upstream has a newer Hermes Agent release'
assert_file_contains 'build -' "$PODMAN_LOG" 'build should continue after a newer-version warning'

: >"$PODMAN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_LATEST_HERMES_VERSION='fail' HERMES_TEST_GIT_MODE="clean" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$TMP_DIR/build-curl-fail.stdout" 2>"$TMP_DIR/build-curl-fail.stderr"
assert_file_not_contains 'newer Hermes Agent version available' "$TMP_DIR/build-curl-fail.stderr" 'build should not warn when the latest release lookup fails'
assert_file_contains 'build -' "$PODMAN_LOG" 'build should continue when the latest release lookup fails'
assert_file_contains '--arch arm64' "$PODMAN_LOG" 'build should pass the configured target architecture to Podman'
assert_file_contains '--build-arg HERMES_AGENT_UPSTREAM_IMAGE=docker.io/nousresearch/hermes-agent' "$PODMAN_LOG" 'build should pass the official upstream image from config'
assert_file_contains '--build-arg HERMES_AGENT_RELEASE_TAG=v2026.4.16' "$PODMAN_LOG" 'build should pass release tag from config'
assert_file_contains '--build-arg HERMES_AGENT_CONTAINER_WORKSPACE=/workspace/general' "$PODMAN_LOG" 'build should pass the configured image working directory into the Containerfile'
assert_file_contains "-C $ROOT rev-parse --verify HEAD" "$GIT_LOG" 'build should check commit state for the repo root'
assert_file_contains "-C $ROOT update-index -q --refresh" "$GIT_LOG" 'build should refresh the index before checking cleanliness'
assert_file_contains "-C $ROOT diff --numstat" "$GIT_LOG" 'build should check unstaged content changes for the repo root'
assert_file_contains "-C $ROOT diff --cached --numstat" "$GIT_LOG" 'build should check staged content changes for the repo root'
assert_file_contains "-C $ROOT ls-files --others --exclude-standard" "$GIT_LOG" 'build should check meaningful untracked files for the repo root'
assert_file_contains "-C $ROOT symbolic-ref --quiet --short HEAD" "$GIT_LOG" 'build should check the current branch before enforcing build policy'
assert_file_contains "-C $ROOT rev-parse --abbrev-ref --symbolic-full-name @{upstream}" "$GIT_LOG" 'build should look up the upstream branch when building from main'
assert_file_contains "-C $ROOT rev-list --left-right --count HEAD...@{upstream}" "$GIT_LOG" 'build should check ahead and behind counts when main tracks origin/main'
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
assert_file_contains 'USER root' "$ROOT/config/containers/shared/Containerfile" 'container build should preserve upstream root entrypoint behavior'
assert_file_contains 'WORKDIR ${HERMES_AGENT_CONTAINER_WORKSPACE}' "$ROOT/config/containers/shared/Containerfile" 'container build should set the configured workspace as the image workdir'

if grep -Fq 'ENTRYPOINT' "$ROOT/config/containers/shared/Containerfile"; then
  fail 'container build should inherit the official upstream entrypoint'
fi

assert_file_contains '.worktrees/' "$ROOT/.dockerignore" 'dockerignore should ignore local worktree directories like the OpenCode template'
assert_file_contains 'dist/' "$ROOT/.dockerignore" 'dockerignore should ignore local build output like the OpenCode template'
assert_file_not_contains '!config/containers/shared/Containerfile' "$ROOT/.dockerignore" 'dockerignore should not use the old Containerfile-only allowlist'

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
  fail 'runtime image should not keep the old dashboard-only default command when it inherits upstream startup behavior'
fi

# This dirty case should stop the build before Podman is used.
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="dirty" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/dirty.stderr"; then
  fail 'build should fail when the current checkout is dirty'
fi

assert_file_contains 'Build requires a clean checkout with all changes committed.' "$TMP_DIR/dirty.stderr" 'build should explain dirty checkout failures'
assert_file_not_contains 'build -' "$PODMAN_LOG" 'dirty checkout failures should stop before Podman build'
assert_file_not_contains 'tag hermes-agent-' "$PODMAN_LOG" 'dirty checkout failures should stop before Podman tag'

# This no-commit case should stop the build before Podman is used.
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="no-commit" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/no-commit.stderr"; then
  fail 'build should fail when the current checkout has no commits'
fi

# This checks that the no-commit failure message stays clear.
assert_file_contains 'Build requires the current checkout to have at least one commit.' "$TMP_DIR/no-commit.stderr" 'build should explain missing-commit failures'
assert_file_not_contains 'build -' "$PODMAN_LOG" 'no-commit failures should stop before Podman build'

# This detached-HEAD case should fail with a clear build-policy message.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="detached" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/detached.stderr"; then
  fail 'build should fail when the checkout is detached'
fi

assert_file_contains 'Build requires a named branch; detached HEAD is not supported.' "$TMP_DIR/detached.stderr" 'build should explain detached HEAD failures'

# This main-branch case should stop the build when local main is ahead of origin/main.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="main-origin-ahead" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/main-ahead.stderr"; then
  fail 'build should fail when local main is ahead of origin/main'
fi

assert_file_contains 'Build requires main to be pushed and in sync with origin/main.' "$TMP_DIR/main-ahead.stderr" 'build should refuse to run from main when local commits are not pushed'

# This main-branch case should stop the build when local main is behind origin/main.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="main-origin-behind" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/main-behind.stderr"; then
  fail 'build should fail when local main is behind origin/main'
fi

assert_file_contains 'Build requires main to be pushed and in sync with origin/main.' "$TMP_DIR/main-behind.stderr" 'build should refuse to run from main when local commits are missing'

# This main-branch case should stop the build when local main has diverged from origin/main.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="main-origin-diverged" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/main-diverged.stderr"; then
  fail 'build should fail when local main has diverged from origin/main'
fi

assert_file_contains 'Build requires main to be pushed and in sync with origin/main.' "$TMP_DIR/main-diverged.stderr" 'build should refuse to run from main when history diverged'

# This main-branch case should stop the build when no upstream is configured.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="main-no-upstream" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/main-no-upstream.stderr"; then
  fail 'build should fail when main has no upstream configured'
fi

assert_file_contains 'Build requires main to track origin/main.' "$TMP_DIR/main-no-upstream.stderr" 'build should refuse to run from main when no upstream remote is configured'

# This non-main case should allow a clean committed checkout even with no upstream configured.
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="local-only" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$TMP_DIR/non-main-no-upstream.stdout"
assert_file_contains 'Built image: hermes-agent-0.10.0-' "$TMP_DIR/non-main-no-upstream.stdout" 'build should allow a clean local-only non-main branch'

# This non-main case should reject remote-tracking feature branches.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="feature-upstream" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/non-main-upstream.stderr"; then
  fail 'build should reject non-main branches with upstreams'
fi
assert_file_contains 'Build only allows remote-tracking builds from main. Use a clean committed local worktree branch or main tracking origin/main.' "$TMP_DIR/non-main-upstream.stderr" 'build should explain non-main upstream branch failures'

# This broken-worktree case should explain cross-namespace gitdir failures clearly for a managed worktree path.
mkdir -p "$TMP_DIR/.worktrees/fix-matrix-device-backport-2"
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="broken-worktree" bash -c 'set -euo pipefail; source "$1"; hermes_require_clean_committed_checkout "$2"' _ "$ROOT/lib/shell/shared/common.sh" "$TMP_DIR/.worktrees/fix-matrix-device-backport-2" >/dev/null 2>"$TMP_DIR/broken-worktree.stderr"; then
  fail 'build helper should fail when the checkout points at a missing managed worktree gitdir path'
fi

assert_file_contains 'This checkout is not a usable git worktree in this environment.' "$TMP_DIR/broken-worktree.stderr" 'build helper should explain cross-namespace worktree failures clearly'
assert_file_contains 'Recreate or relink this worktree using relative gitdir paths before building.' "$TMP_DIR/broken-worktree.stderr" 'build helper should tell the user how to recover from a broken worktree link'
assert_file_not_contains 'Build requires the current checkout to have at least one commit.' "$TMP_DIR/broken-worktree.stderr" 'build helper should not misclassify a broken worktree as a no-commit checkout'

# This real file check proves the build helper does not rewrite worktree gitdir links.
WORKTREE_TMP="$TMP_DIR/worktree-paths"
mkdir -p "$WORKTREE_TMP/.git/worktrees/feature" "$WORKTREE_TMP/.worktrees/feature"
printf 'gitdir: /workspace/project/.git/worktrees/feature\n' >"$WORKTREE_TMP/.worktrees/feature/.git"

rewritten_gitfile="$(bash -c 'set -euo pipefail; source "$1"; hermes_repair_relative_worktree_gitdir "$2"; cat "$2/.git"' _ "$ROOT/lib/shell/shared/common.sh" "$WORKTREE_TMP/.worktrees/feature")"
assert_equals 'gitdir: /workspace/project/.git/worktrees/feature' "$rewritten_gitfile" 'build helper should leave managed worktree gitdir links untouched'

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
