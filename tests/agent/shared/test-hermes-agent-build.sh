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

# This puts the real config back and removes the temporary test files.
cleanup() {
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

# These logs capture the fake command calls so the test can check behavior.
PODMAN_LOG="$TMP_DIR/podman.log"
GIT_LOG="$TMP_DIR/git.log"

# This clean case should build and should check commit state before building.
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_GIT_LOG="$GIT_LOG" HERMES_TEST_GIT_MODE="clean" bash "$ROOT/scripts/agent/shared/hermes-agent-build"

# These checks prove the build used saved config values and asked git about checkout state.
assert_file_contains '--build-arg HERMES_AGENT_DASHBOARD_PORT=9234' "$PODMAN_LOG" 'build should pass dashboard port from config'
assert_file_contains '--build-arg HERMES_AGENT_RELEASE_TAG=v2026.4.16' "$PODMAN_LOG" 'build should pass release tag from config'
assert_file_contains "-C $ROOT rev-parse --verify HEAD" "$GIT_LOG" 'build should check commit state for the repo root'
assert_file_contains "-C $ROOT update-index -q --refresh" "$GIT_LOG" 'build should refresh the index before checking cleanliness'
assert_file_contains "-C $ROOT diff --numstat" "$GIT_LOG" 'build should check unstaged content changes for the repo root'
assert_file_contains "-C $ROOT diff --cached --numstat" "$GIT_LOG" 'build should check staged content changes for the repo root'
assert_file_contains "-C $ROOT ls-files --others --exclude-standard" "$GIT_LOG" 'build should check meaningful untracked files for the repo root'

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

printf 'hermes-agent-build behavior checks passed\n'
