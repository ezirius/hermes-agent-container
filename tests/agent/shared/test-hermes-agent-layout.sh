#!/usr/bin/env bash

set -euo pipefail

# This test checks that the repo still keeps the paths and file comments we expect.

# This finds the repo root so the layout checks always run from the same place.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# These checks prove the old legacy paths are gone.
test ! -f "$ROOT/tests/test-asserts.sh"
test ! -f "$ROOT/tests/test-hermes-agent-build.sh"
test ! -f "$ROOT/tests/test-hermes-agent-layout.sh"
test ! -f "$ROOT/tests/test-hermes-agent-run.sh"
test ! -f "$ROOT/tests/test-hermes-agent-shell.sh"
test ! -e "$ROOT/config/shared"
test ! -f "$ROOT/docs/shared/usage.md"
test ! -f "$ROOT/docs/shared/implementation-plan.md"
test ! -f "$ROOT/lib/shell/common.sh"
test ! -f "$ROOT/scripts/shared/hermes-agent-build"
test ! -f "$ROOT/scripts/shared/hermes-agent-run"
test ! -f "$ROOT/scripts/shared/hermes-agent-shell"
test ! -d "$ROOT/skills"
test ! -d "$ROOT/tests/shell"

# These checks prove the current normalized paths are present.
test -f "$ROOT/docs/usage/shared/usage.md"
test -f "$ROOT/docs/usage/shared/architecture.md"
test -f "$ROOT/config/containers/shared/Containerfile"
test -f "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
test -f "$ROOT/lib/shell/shared/common.sh"
test ! -d "$ROOT/tests/container"
test -d "$ROOT/tests/agent/shared"
test -f "$ROOT/scripts/agent/shared/hermes-agent-build"
test -f "$ROOT/scripts/agent/shared/hermes-agent-entrypoint"
test -f "$ROOT/scripts/agent/shared/hermes-agent-run"
test -f "$ROOT/scripts/agent/shared/hermes-agent-shell"
test -f "$ROOT/tests/agent/shared/test-asserts.sh"
test -f "$ROOT/tests/agent/shared/test-hermes-agent-build.sh"
test -f "$ROOT/tests/agent/shared/test-hermes-agent-entrypoint.sh"
test -f "$ROOT/tests/agent/shared/test-hermes-agent-layout.sh"
test -f "$ROOT/tests/agent/shared/test-hermes-agent-run.sh"
test -f "$ROOT/tests/agent/shared/test-hermes-agent-shell.sh"

# These checks make sure the saved config still contains the values the scripts depend on.
grep -q '^# Hermes Agent runtime and build configuration\.$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_UID="\${HERMES_AGENT_UID:-\$(id -u)}"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_GID="\${HERMES_AGENT_GID:-\$(id -g)}"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_NODE_IMAGE="node:24-bookworm-slim"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_RUNTIME_IMAGE="ubuntu:24.04"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_BASE_PATH="\${HOME}/' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -Eq '^HERMES_AGENT_WORKSPACES="[^"[:space:]]+:[0-9]+( [^"[:space:]]+:[0-9]+)*"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_DASHBOARD_PORT="' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_OPEN_COMMAND="auto"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"

# These checks make sure the docs and script headers still explain the current behavior.
grep -q 'Host workspace path' "$ROOT/docs/usage/shared/usage.md"
grep -q 'macOS and Linux hosts' "$ROOT/docs/usage/shared/usage.md"
grep -q '`localhost/hermes-agent-...`' "$ROOT/docs/usage/shared/usage.md"
grep -q 'does not remove existing workspace containers until the replacement container has started successfully' "$ROOT/docs/usage/shared/usage.md"
grep -q 'lib/shell/shared/common.sh' "$ROOT/docs/usage/shared/architecture.md"
grep -q '^# This image consumes shared config via build args and keeps the runtime contract in env vars\.$' "$ROOT/config/containers/shared/Containerfile"
grep -q 'HERMES_BUNDLED_SKILLS=/opt/hermes-src/skills' "$ROOT/config/containers/shared/Containerfile"
grep -q '^# This file holds the shared shell helpers used by the wrapper scripts\.$' "$ROOT/lib/shell/shared/common.sh"
grep -q '^# This script builds a fresh Hermes Agent image from the saved repo settings\.$' "$ROOT/scripts/agent/shared/hermes-agent-build"
grep -q '^# This script keeps the container alive and starts Hermes services only after setup is complete\.$' "$ROOT/scripts/agent/shared/hermes-agent-entrypoint"
grep -q '^# This script starts one saved workspace container and opens Hermes inside it\.$' "$ROOT/scripts/agent/shared/hermes-agent-run"
grep -q '^# This script opens bash by default, or runs an explicit command inside a running workspace container\.$' "$ROOT/scripts/agent/shared/hermes-agent-shell"

# This makes sure scripts and helpers do not quietly hard-code workspace-specific settings.
if grep -R -E 'HERMES_AGENT_PORT_OFFSET_|\bezirius\b|\bnala\b|hermes-agent-workspace' "$ROOT/scripts/agent/shared" "$ROOT/lib/shell/shared" >/dev/null; then
  printf 'Scripts and shell libraries must not embed workspace-specific configuration.\n' >&2
  exit 1
fi

# This rejects the obsolete placeholder bundled-skills packaging path.
if grep -q 'COPY skills/' "$ROOT/config/containers/shared/Containerfile"; then
  printf 'Containerfile must not copy the obsolete repo skills placeholder path.\n' >&2
  exit 1
fi

echo "Hermes-agent layout checks passed"
