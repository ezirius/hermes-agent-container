#!/usr/bin/env bash

set -euo pipefail

# This test checks that the run script starts the official two-container workspace shape.

# This finds the repo root so the test can reach the script, config, and helpers.
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

# This fake Podman models the official two-pod workspace runtime.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"

case "$1" in
  pod)
    case "${2:-}" in
      create)
        printf 'new-pod\n'
        ;;
      ps)
        if [[ "${3:-}" == '-aq' ]]; then
          if [[ "${HERMES_TEST_STALE_POD_MODE:-present}" == 'present' ]]; then
            printf 'old-gateway-pod\nold-dashboard-pod\n'
          fi
          exit 0
        fi

        case "${HERMES_TEST_POD_MODE:-missing}" in
          present)
            printf 'hermes-agent-alpha-gateway-0.10.0-20260417-120000-123\n'
            printf 'hermes-agent-alpha-dashboard-0.10.0-20260417-120000-123\n'
            ;;
        esac
        ;;
      rm)
        ;;
    esac
    ;;
  images)
    case "${HERMES_TEST_IMAGE_MODE:-present}" in
      missing) ;;
      localhost) printf 'localhost/hermes-agent-0.10.0-20260417-120000-123\n' ;;
      *) printf 'hermes-agent-0.10.0-20260417-120000-123\n' ;;
    esac
    ;;
  ps)
    if [[ "$2" == '-aq' ]]; then
      if [[ "${HERMES_TEST_STALE_MODE:-present}" == 'present' ]]; then
        printf 'old-gateway\nold-dashboard\n'
      elif [[ "${HERMES_TEST_STALE_MODE:-present}" == 'same-name' ]]; then
        printf 'hermes-agent-alpha-gateway-0.10.0-20260417-120000-123\n'
        printf 'hermes-agent-alpha-dashboard-0.10.0-20260417-120000-123\n'
      fi
      exit 0
    fi

    [[ "${HERMES_TEST_RUNNING_MODE:-running}" == 'never' ]] && exit 0
    if [[ "$*" == *dashboard* ]]; then
      case "$*" in
        *beta*) printf 'hermes-agent-beta-dashboard-0.10.0-20260417-120000-123\n' ;;
        *) printf 'hermes-agent-alpha-dashboard-0.10.0-20260417-120000-123\n' ;;
      esac
    else
      case "$*" in
        *beta*) printf 'hermes-agent-beta-gateway-0.10.0-20260417-120000-123\n' ;;
        *) printf 'hermes-agent-alpha-gateway-0.10.0-20260417-120000-123\n' ;;
      esac
    fi
    ;;
  run)
    printf 'new-container\n'
    ;;
  start|rm|exec)
    ;;
  port)
    printf '127.0.0.1:9234\n'
    ;;
  inspect)
    printf 'status=running running=true exit_code=0\n'
    ;;
  logs)
    printf '(no recent logs)\n'
    ;;
esac
EOF

# This fake opener records dashboard URLs without touching the host browser.
cat >"$FAKE_BIN/xdg-open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_OPEN_LOG"
EOF

# This fake sleep keeps readiness loops fast.
cat >"$FAKE_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
:
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/xdg-open" "$FAKE_BIN/sleep"

# This test config keeps workspace paths, ports, and commands predictable.
cat >"$CONFIG_PATH" <<EOF
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
HERMES_AGENT_OPEN_COMMAND="auto"
HERMES_AGENT_BASE_PATH="$TMP_DIR/base"
HERMES_AGENT_WORKSPACES="alpha:100 beta:200"
HERMES_AGENT_CONTAINER_HOME="/opt/data"
HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"
HERMES_AGENT_HOST_HOME_DIRNAME="hermes-agent-home"
HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"
EOF

PODMAN_LOG="$TMP_DIR/podman.log"
OPEN_LOG="$TMP_DIR/open.log"
RUN_STDOUT="$TMP_DIR/run.stdout"
RUN_STDERR="$TMP_DIR/run.stderr"

# This normal case starts gateway and dashboard pods for the selected workspace.
printf '2\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$RUN_STDERR"

assert_file_contains 'Selection:' "$RUN_STDERR" 'run should show an explicit selection prompt'
assert_file_contains 'pod create --name hermes-agent-beta-gateway-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should create a gateway pod for the workspace'
assert_file_contains 'pod create --name hermes-agent-beta-dashboard-0.10.0-20260417-120000-123 -p 127.0.0.1:9434:9234' "$PODMAN_LOG" 'run should create a dashboard pod with host loopback publishing'
assert_file_contains 'run -d --name hermes-agent-beta-gateway-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should create a gateway container for the workspace'
assert_file_contains 'run -d --name hermes-agent-beta-dashboard-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should create a dashboard container for the workspace'
assert_file_contains '--pod hermes-agent-beta-gateway-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should place the gateway container in the gateway pod'
assert_file_contains '--pod hermes-agent-beta-dashboard-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should place the dashboard container in the dashboard pod'
assert_file_contains '--workdir /workspace/general' "$PODMAN_LOG" 'run should use the mounted workspace as the container working directory'
assert_file_contains 'gateway run' "$PODMAN_LOG" 'run should use the official gateway command'
assert_file_contains 'dashboard --host 0.0.0.0 --port 9234 --no-open' "$PODMAN_LOG" 'run should use the official dashboard command'
assert_file_not_contains 'python -c' "$PODMAN_LOG" 'run health checks should not depend on python being available in the derived image'
assert_file_not_contains 'curl -fsS' "$PODMAN_LOG" 'run health checks should not depend on curl being available in the derived image'
assert_file_not_contains 'run -d --name hermes-agent-beta-dashboard-0.10.0-20260417-120000-123 -e HERMES_UID=1000 -e HERMES_GID=1000 -p 127.0.0.1:9434:9234' "$PODMAN_LOG" 'run should publish dashboard ports on the pod, not the container'
assert_file_contains "$TMP_DIR/base/beta/hermes-agent-home:/opt/data" "$PODMAN_LOG" 'run should mount Hermes state at the official data path'
assert_file_contains "$TMP_DIR/base/beta/hermes-agent-general:/workspace/general" "$PODMAN_LOG" 'run should mount the workspace path'
assert_file_contains 'rm -f old-gateway' "$PODMAN_LOG" 'run should remove stale gateway containers only after replacements are healthy'
assert_file_contains 'rm -f old-dashboard' "$PODMAN_LOG" 'run should remove stale dashboard containers only after replacements are healthy'
assert_file_contains 'pod rm -f old-gateway' "$PODMAN_LOG" 'run should remove stale gateway pods after replacements are healthy'
assert_file_contains 'pod rm -f old-dashboard' "$PODMAN_LOG" 'run should remove stale dashboard pods after replacements are healthy'
assert_file_contains 'pod rm -f old-gateway-pod' "$PODMAN_LOG" 'run should remove stale gateway pods even when their containers are gone'
assert_file_contains 'pod rm -f old-dashboard-pod' "$PODMAN_LOG" 'run should remove stale dashboard pods even when their containers are gone'
assert_file_contains 'http://127.0.0.1:9434' "$OPEN_LOG" 'run should open the derived dashboard URL'
assert_file_contains 'exec -i --workdir /workspace/general hermes-agent-beta-gateway-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach to Hermes inside the gateway container workspace'

# This checks that localhost-prefixed local images are normalized before container naming.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_IMAGE_MODE='localhost' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'run -d --name hermes-agent-alpha-gateway-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should normalize localhost image names before naming gateway containers'
assert_file_contains 'run -d --name hermes-agent-alpha-dashboard-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should normalize localhost image names before naming dashboard containers'

# This checks that missing images fail with a clear message.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_IMAGE_MODE='missing' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" alpha >/dev/null 2>"$TMP_DIR/missing.stderr"; then
  fail 'run should fail when no local derived image exists'
fi
assert_file_contains 'No built Hermes Agent image found. Run scripts/agent/shared/hermes-agent-build first.' "$TMP_DIR/missing.stderr" 'run should explain missing local images'

# This checks that unconfigured workspaces are rejected before container creation.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" gamma >/dev/null 2>"$TMP_DIR/workspace.stderr"; then
  fail 'run should reject unconfigured workspace names'
fi
assert_file_contains 'Workspace gamma is not configured.' "$TMP_DIR/workspace.stderr" 'run should explain unconfigured workspaces'

printf 'hermes-agent-run behavior checks passed\n'
