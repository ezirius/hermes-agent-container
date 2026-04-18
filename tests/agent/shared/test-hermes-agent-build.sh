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

# This optional smoke case builds the real image and proves the dashboard command stays alive.
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

# This fake Podman just records the build command instead of doing a real build.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"
EOF

# This fake git lets the test choose between clean, dirty, and no-commit states.
cat >"$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$HERMES_TEST_GIT_LOG"

if [[ "$1" == '-C' ]]; then
  shift 2
fi

case "$1 $2 ${3:-}" in
  'rev-parse --verify HEAD')
    if [[ "${HERMES_TEST_GIT_MODE:-clean}" == "no-commit" ]]; then
      exit 1
    fi
    printf 'deadbeef\n'
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
HERMES_AGENT_UID="1000"
HERMES_AGENT_GID="1000"
HERMES_AGENT_VERSION="0.10.0"
HERMES_AGENT_RELEASE_TAG="v2026.4.16"
HERMES_AGENT_NODE_IMAGE="node:24-bookworm-slim"
HERMES_AGENT_RUNTIME_IMAGE="ubuntu:24.04"
HERMES_AGENT_DASHBOARD_PORT="9234"
HERMES_AGENT_CHAT_COMMAND="hermes"
HERMES_AGENT_SHELL_COMMAND="bash"
HERMES_AGENT_OPEN_COMMAND="open"
HERMES_AGENT_BASE_PATH="${HOME}/tmp/hermes-agent"
HERMES_AGENT_WORKSPACES="alpha:100 beta:200"
HERMES_AGENT_CONTAINER_HOME="/home/hermes-agent"
HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"
HERMES_AGENT_HOST_HOME_DIRNAME="hermes-agent-home"
HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"
EOF

# This loads the test config so the optional real smoke check can reuse the saved values.
source "$CONFIG_PATH"

# These logs capture the fake command calls so the test can check behavior.
PODMAN_LOG="$TMP_DIR/podman.log"
GIT_LOG="$TMP_DIR/git.log"

# This clean case should build and should check commit state before building.
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" bash "$ROOT/scripts/agent/shared/hermes-agent-build"

# These checks prove the build used saved config values and asked git about checkout state.
assert_file_contains '--build-arg HERMES_AGENT_DASHBOARD_PORT=9234' "$PODMAN_LOG" 'build should pass dashboard port from config'
assert_file_contains '--build-arg HERMES_AGENT_RELEASE_TAG=v2026.4.16' "$PODMAN_LOG" 'build should pass release tag from config'
assert_file_contains '--build-arg HERMES_AGENT_GID=1000' "$PODMAN_LOG" 'build should pass the requested gid through to the image build'
assert_file_contains '--build-arg HERMES_AGENT_NODE_IMAGE=node:24-bookworm-slim' "$PODMAN_LOG" 'build should pass the configured Node base image to the container build'
assert_file_contains '--build-arg HERMES_AGENT_RUNTIME_IMAGE=ubuntu:24.04' "$PODMAN_LOG" 'build should pass the configured runtime base image to the container build'
assert_file_contains "-C $ROOT rev-parse --verify HEAD" "$GIT_LOG" 'build should check commit state for the repo root'
assert_file_contains "-C $ROOT update-index -q --refresh" "$GIT_LOG" 'build should refresh the index before checking cleanliness'
assert_file_contains "-C $ROOT diff --numstat" "$GIT_LOG" 'build should check unstaged content changes for the repo root'
assert_file_contains "-C $ROOT diff --cached --numstat" "$GIT_LOG" 'build should check staged content changes for the repo root'
assert_file_contains "-C $ROOT ls-files --others --exclude-standard" "$GIT_LOG" 'build should check meaningful untracked files for the repo root'
assert_file_contains 'getent group "${HERMES_AGENT_GID}"' "$ROOT/config/containers/shared/Containerfile" 'container build should reuse an existing group when the gid already exists'
assert_file_contains 'chown -R hermes-agent:"${container_group_name}" /opt/hermes-venv' "$ROOT/config/containers/shared/Containerfile" 'container build should make the shared Python venv writable for runtime installs by hermes-agent'
assert_file_contains 'ARG HERMES_AGENT_NODE_IMAGE' "$ROOT/config/containers/shared/Containerfile" 'container build should declare the configured Node base image arg'
assert_file_contains 'ARG HERMES_AGENT_RUNTIME_IMAGE' "$ROOT/config/containers/shared/Containerfile" 'container build should declare the configured runtime base image arg'
assert_file_contains 'FROM ${HERMES_AGENT_NODE_IMAGE} AS hermes-web-builder' "$ROOT/config/containers/shared/Containerfile" 'frontend builder should use the configured Node base image'
assert_file_contains 'FROM ${HERMES_AGENT_RUNTIME_IMAGE}' "$ROOT/config/containers/shared/Containerfile" 'runtime image should use the configured runtime base image'

# These checks lock in the frontend packaging contract for the Hermes dashboard assets.
containerfile_text="$(<"$ROOT/config/containers/shared/Containerfile")"
assert_contains "RUN apt-get update && apt-get install -y --no-install-recommends \\
    ca-certificates \\
    curl \\
    tar \\
    && rm -rf /var/lib/apt/lists/*" "$containerfile_text" 'frontend builder should install ca-certificates before fetching the upstream Hermes source tarball over HTTPS'
assert_file_contains 'npm ci' "$ROOT/config/containers/shared/Containerfile" 'container build should install frontend dependencies with the upstream lockfile before packaging Hermes web assets'
assert_file_contains 'npm run build' "$ROOT/config/containers/shared/Containerfile" 'container build should build Hermes frontend assets before installing the runtime package'
assert_file_contains 'COPY --from=hermes-web-builder /opt/hermes-src/hermes_cli/web_dist /opt/hermes-src/hermes_cli/web_dist' "$ROOT/config/containers/shared/Containerfile" 'runtime image contract should copy the built Hermes web_dist assets into the runtime source tree before installation'

assert_file_contains '--host 0.0.0.0' "$ROOT/config/containers/shared/Containerfile" 'dashboard command should bind the container to all interfaces so the published host port can reach it'
assert_file_contains '--no-open' "$ROOT/config/containers/shared/Containerfile" 'dashboard command should keep browser opening on the host side only'
assert_file_contains '--insecure' "$ROOT/config/containers/shared/Containerfile" 'dashboard command should opt into Hermes insecure binding explicitly'

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
