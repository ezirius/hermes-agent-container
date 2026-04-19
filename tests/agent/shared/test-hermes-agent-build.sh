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

# This fake Podman records the build command and writes a stable fake image id to the requested iidfile.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"

if [[ "${1:-}" == 'build' ]]; then
  iidfile_path=''
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

# This fake git lets the test choose checkout, branch, and upstream states.
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

    printf 'origin/main\n'
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
BUILD_STDOUT="$TMP_DIR/build.stdout"

# This clean case should build and should check commit state before building.
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$BUILD_STDOUT"

# These checks prove the build used saved config values and asked git about checkout state.
assert_file_contains 'Image ID: new-image-id' "$BUILD_STDOUT" 'build should print the image id with a label'
if grep -Fxq -- 'new-image-id' "$BUILD_STDOUT"; then
  fail 'build should not print the raw image id on its own line'
fi
assert_file_contains '--build-arg HERMES_AGENT_DASHBOARD_PORT=9234' "$PODMAN_LOG" 'build should pass dashboard port from config'
assert_file_contains '--build-arg HERMES_AGENT_RELEASE_TAG=v2026.4.16' "$PODMAN_LOG" 'build should pass release tag from config'
assert_file_contains '--build-arg HERMES_AGENT_GID=1000' "$PODMAN_LOG" 'build should pass the requested gid through to the image build'
assert_file_contains '--build-arg HERMES_AGENT_NODE_IMAGE=node:24-bookworm-slim' "$PODMAN_LOG" 'build should pass the configured Node base image to the container build'
assert_file_contains '--build-arg HERMES_AGENT_RUNTIME_IMAGE=ubuntu:24.04' "$PODMAN_LOG" 'build should pass the configured runtime base image to the container build'
assert_file_contains '--iidfile' "$PODMAN_LOG" 'build should request an iidfile so podman output can keep streaming normally'
assert_file_contains "-C $ROOT rev-parse --verify HEAD" "$GIT_LOG" 'build should check commit state for the repo root'
assert_file_contains "-C $ROOT update-index -q --refresh" "$GIT_LOG" 'build should refresh the index before checking cleanliness'
assert_file_contains "-C $ROOT diff --numstat" "$GIT_LOG" 'build should check unstaged content changes for the repo root'
assert_file_contains "-C $ROOT diff --cached --numstat" "$GIT_LOG" 'build should check staged content changes for the repo root'
assert_file_contains "-C $ROOT ls-files --others --exclude-standard" "$GIT_LOG" 'build should check meaningful untracked files for the repo root'
assert_file_contains "-C $ROOT branch --show-current" "$GIT_LOG" 'build should check the current branch before enforcing push policy'
assert_file_contains "-C $ROOT rev-parse --abbrev-ref --symbolic-full-name @{upstream}" "$GIT_LOG" 'build should look up the upstream branch when building from main'
assert_file_contains "-C $ROOT rev-list --count @{upstream}..HEAD" "$GIT_LOG" 'build should check whether local main is ahead of its upstream'
assert_file_contains 'getent group "${HERMES_AGENT_GID}"' "$ROOT/config/containers/shared/Containerfile" 'container build should reuse an existing group when the gid already exists'
assert_file_contains 'chown -R hermes-agent:"${container_group_name}" /opt/hermes-venv' "$ROOT/config/containers/shared/Containerfile" 'container build should make the shared Python venv writable for runtime installs by hermes-agent'
assert_file_contains 'ARG HERMES_AGENT_NODE_IMAGE' "$ROOT/config/containers/shared/Containerfile" 'container build should declare the configured Node base image arg'
assert_file_contains 'ARG HERMES_AGENT_RUNTIME_IMAGE' "$ROOT/config/containers/shared/Containerfile" 'container build should declare the configured runtime base image arg'
assert_file_contains 'FROM ${HERMES_AGENT_NODE_IMAGE} AS hermes-web-builder' "$ROOT/config/containers/shared/Containerfile" 'frontend builder should use the configured Node base image'
assert_file_contains 'FROM ${HERMES_AGENT_RUNTIME_IMAGE}' "$ROOT/config/containers/shared/Containerfile" 'runtime image should use the configured runtime base image'
# These checks lock in the frontend packaging contract for the Hermes dashboard assets.
containerfile_path="$ROOT/config/containers/shared/Containerfile"
containerfile_text="$(<"$containerfile_path")"
single_line_uv_run='RUN export PATH="${HERMES_AGENT_CONTAINER_HOME}/.local/bin:${PATH}" && export UV_PYTHON_INSTALL_DIR="/opt/hermes-python" && uv python install 3.11 && uv venv /opt/hermes-venv --python 3.11'

# This keeps both stage image args ahead of the first FROM without caring about comments or spacing between them.
first_from_match="$(grep -n -m 1 '^[[:space:]]*FROM[[:space:]]' "$containerfile_path" || true)"
if [[ -z "$first_from_match" ]]; then
  fail 'container build test expected the Containerfile to declare at least one FROM instruction'
fi
first_from_line="${first_from_match%%:*}"

for required_image_arg in HERMES_AGENT_NODE_IMAGE HERMES_AGENT_RUNTIME_IMAGE; do
  arg_match="$(grep -n -m 1 "^[[:space:]]*ARG[[:space:]]\+${required_image_arg}$" "$containerfile_path" || true)"
  if [[ -z "$arg_match" ]]; then
    fail "container build should declare ${required_image_arg} before the first FROM so build arg interpolation works in every stage"
  fi

  arg_line="${arg_match%%:*}"
  if (( arg_line >= first_from_line )); then
    fail "container build should declare ${required_image_arg} before the first FROM so build arg interpolation works in every stage"
  fi
done

assert_contains "RUN apt-get update && apt-get install -y --no-install-recommends \\
    ca-certificates \\
    curl \\
    tar \\
    && rm -rf /var/lib/apt/lists/*" "$containerfile_text" 'frontend builder should install ca-certificates before fetching the upstream Hermes source tarball over HTTPS'
assert_file_contains 'npm ci' "$ROOT/config/containers/shared/Containerfile" 'container build should install frontend dependencies with the upstream lockfile before packaging Hermes web assets'
assert_file_contains 'npm run build' "$ROOT/config/containers/shared/Containerfile" 'container build should build Hermes frontend assets before installing the runtime package'
assert_file_contains 'COPY --from=hermes-web-builder /opt/hermes-src/hermes_cli/web_dist /opt/hermes-src/hermes_cli/web_dist' "$ROOT/config/containers/shared/Containerfile" 'runtime image contract should copy the built Hermes web_dist assets into the runtime source tree before installation'
assert_file_contains 'libolm-dev' "$ROOT/config/containers/shared/Containerfile" 'runtime image should install the libolm system package documented for Matrix E2EE support'
assert_file_contains 'uv python install 3.11' "$ROOT/config/containers/shared/Containerfile" 'runtime image should install Python 3.11 the way the upstream full installer documents'
assert_file_contains 'uv venv /opt/hermes-venv --python 3.11' "$ROOT/config/containers/shared/Containerfile" 'runtime image should create its venv with Python 3.11 to match the upstream full install flow'
assert_file_contains "git apply <<'HERMES_MATRIX_DEVICE_BACKPORT'" "$ROOT/config/containers/shared/Containerfile" 'runtime image should apply the Matrix device backport inline during the build'
assert_file_contains 'uv pip install "/opt/hermes-src[all]"' "$ROOT/config/containers/shared/Containerfile" 'runtime image should install Hermes with the upstream full extras from the prepared source tree instead of a web-only package shape'
assert_file_contains 'tools/skills_sync.py' "$ROOT/config/containers/shared/Containerfile" 'runtime image should keep the upstream skills sync tool available from the preserved Hermes source tree'
assert_file_contains 'HOME=${HERMES_AGENT_CONTAINER_HOME}' "$ROOT/config/containers/shared/Containerfile" 'runtime image should set HOME to the configured Hermes container home'
assert_file_contains 'curl -LsSf https://astral.sh/uv/install.sh | sh' "$ROOT/config/containers/shared/Containerfile" 'runtime image should install uv through the upstream installer'
assert_file_contains 'export PATH="${HERMES_AGENT_CONTAINER_HOME}/.local/bin:${PATH}"' "$ROOT/config/containers/shared/Containerfile" 'runtime image should use the configured HOME-local bin path after installing uv'
# This regression proves the ordering check must survive harmless one-line RUN reformatting.
assert_text_appears_in_order 'UV_PYTHON_INSTALL_DIR="/opt/hermes-python"' 'uv python install 3.11' "$single_line_uv_run" 'uv Python install order regression should pass even when the RUN chain is formatted on one line'

# This keeps the uv-managed Python install path outside the mounted home without pinning the whole RUN block layout.
assert_text_appears_in_order 'UV_PYTHON_INSTALL_DIR="/opt/hermes-python"' 'uv python install 3.11' "$containerfile_text" 'runtime image should keep uv-managed Python outside the mounted container home before creating the venv'
assert_text_appears_in_order "git apply <<'HERMES_MATRIX_DEVICE_BACKPORT'" 'uv pip install "/opt/hermes-src[all]"' "$containerfile_text" 'runtime image should apply the Matrix device backport before installing Hermes into the virtualenv'

assert_file_contains 'export VIRTUAL_ENV="/opt/hermes-venv"' "$ROOT/config/containers/shared/Containerfile" 'runtime image should point standalone uv at the created virtualenv before installing Hermes'
assert_file_contains '_reverify_keys_after_upload' "$ROOT/config/containers/shared/Containerfile" 'matrix backport should restore the device re-verification helper from upstream'
assert_file_contains 'device %s is still missing from server after key upload' "$ROOT/config/containers/shared/Containerfile" 'matrix backport should fail closed if device keys are still missing after upload'
assert_file_contains 'stale one-time keys on the server' "$ROOT/config/containers/shared/Containerfile" 'matrix backport should fail closed when startup sees stale one-time keys on the server'

if grep -Fq 'uv pip install /opt/hermes-src[web]' "$ROOT/config/containers/shared/Containerfile"; then
  fail 'runtime image should not use a web-only Hermes install when aligning to the upstream full install path'
fi

if grep -Fq 'uv pip install -e "/opt/hermes-src[all]"' "$ROOT/config/containers/shared/Containerfile"; then
  fail 'runtime image should not use an editable Hermes install because it keeps the upstream web package.json visible at runtime'
fi

if grep -Fq 'rm -rf /opt/hermes-src' "$ROOT/config/containers/shared/Containerfile"; then
  fail 'runtime image should not delete the Hermes source tree because upstream bundled skills sync relies on it'
fi

if grep -Fq 'export PATH="/root/.local/bin:${PATH}"' "$ROOT/config/containers/shared/Containerfile"; then
  fail 'runtime image should not hardcode /root/.local/bin when HOME points at the Hermes container home'
fi

if grep -Fq '/opt/hermes-venv/bin/uv' "$ROOT/config/containers/shared/Containerfile"; then
  fail 'runtime image should not assume uv is installed inside the virtualenv'
fi

assert_file_contains 'HERMES_BUNDLED_SKILLS=/opt/hermes-src/skills' "$ROOT/config/containers/shared/Containerfile" 'runtime image should publish the preserved upstream skills directory through HERMES_BUNDLED_SKILLS'
assert_file_contains 'COPY scripts/agent/shared/hermes-agent-entrypoint /usr/local/bin/hermes-agent-entrypoint' "$ROOT/config/containers/shared/Containerfile" 'runtime image should copy the repo entrypoint script into the image'
assert_file_contains 'chmod +x /usr/local/bin/hermes-agent-entrypoint' "$ROOT/config/containers/shared/Containerfile" 'runtime image should mark the repo entrypoint script executable'
assert_file_contains 'ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hermes-agent-entrypoint"]' "$ROOT/config/containers/shared/Containerfile" 'runtime image should launch the repo entrypoint through tini'

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

# This checks that the ahead-of-upstream failure message stays clear.
assert_file_contains 'Build requires local main to be pushed to its upstream before building.' "$TMP_DIR/main-ahead.stderr" 'build should explain main-ahead failures'

# This main-branch case should stop the build when main has no upstream configured.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" HERMES_TEST_GIT_BRANCH="main" HERMES_TEST_GIT_UPSTREAM_STATE="missing" HERMES_TEST_GIT_AHEAD_STATE="not-ahead" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >/dev/null 2>"$TMP_DIR/main-no-upstream.stderr"; then
  fail 'build should fail when main has no upstream configured'
fi

# This checks that the missing-upstream failure message stays clear.
assert_file_contains 'Build requires main to have an upstream branch configured.' "$TMP_DIR/main-no-upstream.stderr" 'build should explain missing-upstream failures on main'

# This non-main case should allow a clean committed checkout without any upstream.
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" HERMES_TEST_GIT_BRANCH="feature/test" HERMES_TEST_GIT_UPSTREAM_STATE="missing" HERMES_TEST_GIT_AHEAD_STATE="not-ahead" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$TMP_DIR/non-main-no-upstream.stdout"
assert_file_contains 'Image ID: new-image-id' "$TMP_DIR/non-main-no-upstream.stdout" 'build should allow a clean non-main branch without an upstream'

# This non-main case should allow a clean committed checkout even when ahead of upstream.
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" HERMES_TEST_GIT_BRANCH="feature/test" HERMES_TEST_GIT_UPSTREAM_STATE="configured" HERMES_TEST_GIT_AHEAD_STATE="ahead" bash "$ROOT/scripts/agent/shared/hermes-agent-build" >"$TMP_DIR/non-main-ahead.stdout"
assert_file_contains 'Image ID: new-image-id' "$TMP_DIR/non-main-ahead.stdout" 'build should allow a clean non-main branch even when it is ahead of upstream'

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
