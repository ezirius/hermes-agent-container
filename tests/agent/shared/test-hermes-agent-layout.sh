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
test ! -f "$ROOT/scripts/agent/shared/hermes-agent-entrypoint"
test -f "$ROOT/scripts/agent/shared/hermes-agent-run"
test -f "$ROOT/scripts/agent/shared/hermes-agent-shell"
test -f "$ROOT/tests/agent/shared/test-asserts.sh"
test -f "$ROOT/tests/agent/shared/test-all.sh"
test -f "$ROOT/tests/agent/shared/test-hermes-agent-build.sh"
test ! -f "$ROOT/tests/agent/shared/test-hermes-agent-entrypoint.sh"
test -f "$ROOT/tests/agent/shared/test-hermes-agent-layout.sh"
test -f "$ROOT/tests/agent/shared/test-hermes-agent-run.sh"
test -f "$ROOT/tests/agent/shared/test-hermes-agent-shell.sh"

# These checks make sure config-mutating tests only restore from a completed backup.
grep -q '^backup_created=0$' "$ROOT/tests/agent/shared/test-hermes-agent-build.sh"
grep -q '^backup_created=0$' "$ROOT/tests/agent/shared/test-hermes-agent-run.sh"
grep -q '^backup_created=0$' "$ROOT/tests/agent/shared/test-hermes-agent-shell.sh"

# These checks make sure the saved config still contains the values the scripts depend on.
grep -q '^# Hermes Agent runtime and build configuration\.$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_UPSTREAM_IMAGE="docker.io/nousresearch/hermes-agent"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_TARGET_ARCH="arm64"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
! grep -q '^HERMES_AGENT_UID=' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
! grep -q '^HERMES_AGENT_GID=' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_BASE_PATH="\${HOME}/' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_CONTAINER_HOME="/opt/data"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_SHELL_COMMAND="nu"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -Eq '^HERMES_AGENT_WORKSPACES="[^"[:space:]]+:[0-9]+( [^"[:space:]]+:[0-9]+)*"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_DASHBOARD_PORT="' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
if grep -q '^HERMES_AGENT_OPEN_COMMAND=' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"; then
  printf 'Hermes opener behavior should match OpenCode and not keep HERMES_AGENT_OPEN_COMMAND.\n' >&2
  exit 1
fi

# These checks make sure the docs and script headers still explain the current behavior.
grep -q 'Host workspace path' "$ROOT/docs/usage/shared/usage.md"
grep -q 'macOS and Linux hosts' "$ROOT/docs/usage/shared/usage.md"
grep -q '`localhost/hermes-agent-...`' "$ROOT/docs/usage/shared/usage.md"
grep -q 'does not remove existing workspace pods or containers until the replacement container has started successfully' "$ROOT/docs/usage/shared/usage.md"
grep -q 'Exact matching pods with the wrong dashboard publish contract are removed before same-name recreation' "$ROOT/docs/usage/shared/usage.md"
grep -q 'Workspace pod names use the OpenCode-derived `<image-name>-<workspace>` order' "$ROOT/docs/usage/shared/usage.md"
grep -q '<image-name>-<workspace>-gateway' "$ROOT/docs/usage/shared/usage.md"
grep -q '<image-name>-<workspace>-dashboard' "$ROOT/docs/usage/shared/usage.md"
grep -q 'Setup and Hermes state bootstrapping are delegated to the upstream Hermes entrypoint' "$ROOT/docs/usage/shared/usage.md"
grep -q 'Host dirname settings must be single safe directory names' "$ROOT/docs/usage/shared/usage.md"
grep -q 'remove stale same-workspace exact-name containers before launch' "$ROOT/docs/usage/shared/usage.md"
grep -q 'belongs to a different workspace mount' "$ROOT/docs/usage/shared/usage.md"
grep -q 'falls back to `gio open`' "$ROOT/docs/usage/shared/usage.md"
grep -q 'image-id suffix' "$ROOT/README.md"
grep -q 'Runtime pods use `<image-name>-<workspace>`' "$ROOT/README.md"
grep -q 'exact name `<image-name>-<workspace>-cli`' "$ROOT/README.md"
grep -q 'tests/agent/shared/test-asserts.sh' "$ROOT/README.md"
grep -q 'tests/agent/shared/test-all.sh' "$ROOT/README.md"
grep -q 'bash tests/agent/shared/test-all.sh' "$ROOT/README.md"
grep -q 'arm64' "$ROOT/README.md"
grep -q -- '--userns keep-id' "$ROOT/docs/usage/shared/usage.md"
grep -q 'newer Hermes Agent version available' "$ROOT/docs/usage/shared/usage.md"
grep -q 'running and stable before attach' "$ROOT/docs/usage/shared/architecture.md"
grep -q 'Hermes pod names follow `<image-name>-<workspace>`' "$ROOT/docs/usage/shared/architecture.md"
grep -q 'starts as root so the upstream entrypoint can drop privileges' "$ROOT/docs/usage/shared/architecture.md"
grep -q 'The wrapper rejects symlinked managed host paths before root ownership repair' "$ROOT/docs/usage/shared/architecture.md"
grep -q 'Reused dashboard pods must expose exactly one loopback publish binding' "$ROOT/docs/usage/shared/architecture.md"
grep -q 'clears stale same-workspace exact-name CLI containers before launch' "$ROOT/docs/usage/shared/architecture.md"
grep -q 'The `.dockerignore` file follows the OpenCode template ignore policy' "$ROOT/docs/usage/shared/architecture.md"
grep -q 'Historical note:' "$ROOT/docs/plans/shared/20260418-165535-config-driven-base-images.md"
grep -q 'Build requires main to be pushed and in sync with origin/main' "$ROOT/AGENTS.md"
grep -q 'Hermes pod names follow `<image-name>-<workspace>`' "$ROOT/AGENTS.md"
grep -q 'may only remove stale exact-name containers whose workspace mount still matches' "$ROOT/AGENTS.md"
grep -q 'tests/agent/shared/test-all.sh' "$ROOT/AGENTS.md"
grep -q 'lib/shell/shared/common.sh' "$ROOT/docs/usage/shared/architecture.md"
grep -q '^# This image derives from the official Hermes Agent container and adds repo-local tools\.$' "$ROOT/config/containers/shared/Containerfile"
grep -q '^FROM ${HERMES_AGENT_UPSTREAM_IMAGE}:${HERMES_AGENT_RELEASE_TAG}$' "$ROOT/config/containers/shared/Containerfile"
grep -q 'https://apt.fury.io/nushell/gpg.key' "$ROOT/config/containers/shared/Containerfile"
grep -q '/etc/apt/sources.list.d/fury-nushell.list' "$ROOT/config/containers/shared/Containerfile"
grep -q 'nushell' "$ROOT/config/containers/shared/Containerfile"
grep -q '^USER root$' "$ROOT/config/containers/shared/Containerfile"
grep -q '^WORKDIR ${HERMES_AGENT_CONTAINER_WORKSPACE}$' "$ROOT/config/containers/shared/Containerfile"
! grep -q 'hermes-agent-entrypoint' "$ROOT/config/containers/shared/Containerfile"
! grep -q '^ENTRYPOINT' "$ROOT/config/containers/shared/Containerfile"
grep -q '^# This file holds the shared shell helpers used by the wrapper scripts\.$' "$ROOT/lib/shell/shared/common.sh"
grep -q '^# This script builds a fresh Hermes Agent image from the saved repo settings\.$' "$ROOT/scripts/agent/shared/hermes-agent-build"
grep -q '^# This script starts a saved workspace container, then opens Hermes\.$' "$ROOT/scripts/agent/shared/hermes-agent-run"
grep -q '^# This script opens nushell by default, or runs an explicit command in an ephemeral CLI container\.$' "$ROOT/scripts/agent/shared/hermes-agent-shell"

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

# This rejects stale OpenCode wording in Hermes wrapper tests.
if grep -F 'OpenCode-style option parsing' \
  "$ROOT/tests/agent/shared/test-hermes-agent-build.sh" \
  "$ROOT/tests/agent/shared/test-hermes-agent-run.sh" \
  "$ROOT/tests/agent/shared/test-hermes-agent-shell.sh" \
  "$ROOT/tests/agent/shared/test-asserts.sh" >/dev/null; then
  printf 'Hermes tests should not keep stale OpenCode wording.\n' >&2
  exit 1
fi

# This keeps first-run setup and service readiness delegated to the upstream Hermes entrypoint.
if grep -R -E 'hermes_container_setup_is_complete|hermes_container_gateway_is_healthy|hermes_container_dashboard_is_healthy|hermes_container_start_gateway|hermes_container_start_dashboard|hermes_container_services_are_healthy|hermes_wait_for_healthy_container|hermes_wait_for_gateway_container|hermes_wait_for_dashboard_container|start_service_if_needed|print_first_run_setup_warning|pause_before_first_run_setup' \
  "$ROOT/lib/shell/shared/common.sh" "$ROOT/scripts/agent/shared/hermes-agent-run" >/dev/null; then
  printf 'Hermes wrapper should delegate setup and service readiness to the upstream image entrypoint.\n' >&2
  exit 1
fi

# This rejects stale wording from the deleted repo entrypoint flow.
if grep -F 'setup-safe entrypoint' "$ROOT/tests/agent/shared/test-hermes-agent-build.sh" >/dev/null || \
  grep -F 'entrypoint manages startup' "$ROOT/tests/agent/shared/test-hermes-agent-build.sh" >/dev/null; then
  printf 'Hermes build tests should describe the inherited upstream image flow, not the deleted repo entrypoint.\n' >&2
  exit 1
fi

# This keeps the build context policy aligned with the OpenCode wrapper template.
grep -q '^\.git$' "$ROOT/.dockerignore"
grep -q '^\.git/$' "$ROOT/.dockerignore"
grep -q '^\.worktrees/$' "$ROOT/.dockerignore"
grep -q '^hermes-agent-container-worktrees/$' "$ROOT/.dockerignore"
grep -q '^\.DS_Store$' "$ROOT/.dockerignore"
grep -q '^__pycache__/$' "$ROOT/.dockerignore"
grep -q '^\*\.pyc$' "$ROOT/.dockerignore"
grep -q '^\.idea/$' "$ROOT/.dockerignore"
grep -q '^\.vscode/$' "$ROOT/.dockerignore"
grep -q '^dist/$' "$ROOT/.dockerignore"
! grep -q '^\*$' "$ROOT/.dockerignore"

echo "Hermes-agent layout checks passed"
