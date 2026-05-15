#!/usr/bin/env bash

set -euo pipefail

# This test checks that the repo still keeps the paths and file comments we expect.

# This finds the repo root from git so the checks survive path reshuffles.
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# These checks prove the pre-alignment Hermes paths are gone.
test ! -f "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
test ! -f "$ROOT/config/containers/shared/Containerfile"
test ! -f "$ROOT/docs/usage/shared/usage.md"
test ! -f "$ROOT/docs/usage/shared/architecture.md"
test ! -d "$ROOT/docs/plans"
test ! -d "$ROOT/lib"
test ! -f "$ROOT/scripts/agent/shared/hermes-agent-build"
test ! -f "$ROOT/scripts/agent/shared/hermes-agent-run"
test ! -f "$ROOT/scripts/agent/shared/hermes-agent-shell"
test ! -f "$ROOT/tests/agent/shared/test-asserts.sh"
test ! -f "$ROOT/tests/agent/shared/test-all.sh"
test ! -f "$ROOT/tests/agent/shared/test-hermes-agent-build.sh"
test ! -f "$ROOT/tests/agent/shared/test-hermes-agent-layout.sh"
test ! -f "$ROOT/tests/agent/shared/test-hermes-agent-run.sh"
test ! -f "$ROOT/tests/agent/shared/test-hermes-agent-shell.sh"

# These checks prove the target shared family paths are present.
test -f "$ROOT/scripts/shared/hermes-agent/common.sh"
test ! -d "$ROOT/tests/container"
test ! -d "$ROOT/tests/agent/shared"
test -f "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
test -f "$ROOT/configs/shared/hermes-agent/Containerfile"
test -f "$ROOT/docs/shared/hermes-agent/usage.md"
test -f "$ROOT/docs/shared/hermes-agent/architecture.md"
test -d "$ROOT/scripts/shared/hermes-agent"
test -f "$ROOT/scripts/shared/hermes-agent/hermes-agent-build"
test -f "$ROOT/scripts/shared/hermes-agent/hermes-agent-run"
test -f "$ROOT/scripts/shared/hermes-agent/hermes-agent-shell"
test -f "$ROOT/tests/shared/shared/test-asserts.sh"
test -f "$ROOT/tests/shared/hermes-agent/test-all.sh"
test -f "$ROOT/tests/shared/hermes-agent/test-hermes-agent-build.sh"
test ! -f "$ROOT/tests/shared/hermes-agent/test-hermes-agent-entrypoint.sh"
test -f "$ROOT/tests/shared/hermes-agent/test-hermes-agent-layout.sh"
test -f "$ROOT/tests/shared/hermes-agent/test-hermes-agent-run.sh"
test -f "$ROOT/tests/shared/hermes-agent/test-hermes-agent-shell.sh"

# These checks make sure config-mutating tests only restore from a completed backup.
grep -q '^backup_created=0$' "$ROOT/tests/shared/hermes-agent/test-hermes-agent-build.sh"
grep -q '^backup_created=0$' "$ROOT/tests/shared/hermes-agent/test-hermes-agent-run.sh"
grep -q '^backup_created=0$' "$ROOT/tests/shared/hermes-agent/test-hermes-agent-shell.sh"

# These checks make sure the saved config still contains the values the scripts depend on.
grep -q '^# Hermes Agent runtime and build configuration\.$' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_UPSTREAM_IMAGE="docker.io/nousresearch/hermes-agent"$' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_TARGET_ARCH="arm64"$' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
! grep -q '^HERMES_AGENT_UID=' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
! grep -q '^HERMES_AGENT_GID=' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_BASE_PATH="\${HOME}/' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_CONTAINER_HOME="/opt/data"$' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_NUSHELL_FALLBACK_VERSION="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_NUSHELL_FALLBACK_SHA256_AARCH64="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_NUSHELL_FALLBACK_SHA256_X86_64="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
! grep -q '^HERMES_AGENT_NUSHELL_VERSION=' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
! grep -q '^HERMES_AGENT_NUSHELL_SHA256_AARCH64=' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
! grep -q '^HERMES_AGENT_NUSHELL_SHA256_X86_64=' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_RELEASE_CONNECT_TIMEOUT_SECONDS="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_RELEASE_MAX_TIMEOUT_SECONDS="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_RUNNING_WAIT_ATTEMPTS="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_RUNNING_WAIT_SECONDS="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_STABLE_WAIT_ATTEMPTS="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_STABLE_WAIT_SECONDS="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_PUBLISHED_URL_WAIT_ATTEMPTS="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_PUBLISHED_URL_MAX_TIMEOUT_SECONDS="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_PUBLISHED_URL_WAIT_SECONDS="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_CONTAINER_DOCS="/workspace/docs"$' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_HOST_DOCS_DIRNAME="hermes-agent-docs"$' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_SHELL_COMMAND="nu"$' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
grep -q '^HERMES_AGENT_DASHBOARD_PORT="' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
if grep -q '^HERMES_AGENT_OPEN_COMMAND=' "$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"; then
  printf 'Hermes opener behavior should match OpenCode and not keep HERMES_AGENT_OPEN_COMMAND.\n' >&2
  exit 1
fi

# These checks make sure the docs and script headers still explain the current behavior.
grep -q 'Host docs path' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'macOS and Linux hosts' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q '`localhost/hermes-agent-...`' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'does not remove existing workspace pods or containers until the replacement container has started successfully' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'Exact matching pods with the wrong dashboard publish contract are removed before same-name recreation' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'Workspace pod names use the OpenCode-derived `<image-name>-<workspace>` order' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q '<image-name>-<workspace>-gateway' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q '<image-name>-<workspace>-dashboard' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'Setup and Hermes state bootstrapping are delegated to the upstream Hermes entrypoint' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'Host dirname settings must be single safe directory names' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'exact name `<image-name>-<workspace>-cli`' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'removes stale stopped same-workspace exact-name containers before launch' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'belongs to a different workspace mount' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'falls back to `gio open`' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'fallback Nushell binary' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'image-id suffix' "$ROOT/README.md"
grep -q 'Runtime pods use `<image-name>-<workspace>`' "$ROOT/README.md"
grep -q 'exact name `<image-name>-<workspace>-cli`' "$ROOT/README.md"
grep -q 'tests/shared/shared/test-asserts.sh' "$ROOT/README.md"
grep -q 'tests/shared/hermes-agent/test-all.sh' "$ROOT/README.md"
grep -q 'bash tests/shared/hermes-agent/test-all.sh' "$ROOT/README.md"
grep -q 'arm64' "$ROOT/README.md"
grep -q -- '--userns keep-id' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'newer stable Hermes Agent version available' "$ROOT/docs/shared/hermes-agent/usage.md"
grep -q 'running and stable before attach' "$ROOT/docs/shared/hermes-agent/architecture.md"
grep -q 'Hermes pod names follow `<image-name>-<workspace>`' "$ROOT/docs/shared/hermes-agent/architecture.md"
grep -q 'starts as root so the upstream entrypoint can drop privileges' "$ROOT/docs/shared/hermes-agent/architecture.md"
grep -q 'The wrapper rejects symlinked managed host paths before root ownership repair' "$ROOT/docs/shared/hermes-agent/architecture.md"
grep -q 'Reused dashboard pods must expose exactly one loopback publish binding' "$ROOT/docs/shared/hermes-agent/architecture.md"
grep -q 'exact-name CLI containers named `<image-name>-<workspace>-cli`' "$ROOT/docs/shared/hermes-agent/architecture.md"
grep -q 'clears stale stopped same-workspace exact-name CLI containers before launch' "$ROOT/docs/shared/hermes-agent/architecture.md"
grep -q 'The `.dockerignore` file follows the OpenCode template ignore policy' "$ROOT/docs/shared/hermes-agent/architecture.md"
grep -q 'Historical note:' "$ROOT/docs/shared/hermes-agent/plans/20260418-165535-config-driven-base-images.md"
grep -q 'Build requires main to be pushed and in sync with origin/main' "$ROOT/AGENTS.md"
grep -q 'Hermes pod names follow `<image-name>-<workspace>`' "$ROOT/AGENTS.md"
grep -q 'use the exact name `<image-name>-<workspace>-cli`' "$ROOT/AGENTS.md"
grep -q 'may only remove stale stopped same-workspace exact-name containers' "$ROOT/AGENTS.md"
grep -q 'tests/shared/hermes-agent/test-all.sh' "$ROOT/AGENTS.md"
grep -q 'scripts/shared/hermes-agent/common.sh' "$ROOT/docs/shared/hermes-agent/architecture.md"
grep -q '^# This image derives from the official Hermes Agent container and adds repo-local tools\.$' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q '^FROM ${HERMES_AGENT_UPSTREAM_IMAGE}:${HERMES_AGENT_RELEASE_TAG}$' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q '^ARG HERMES_AGENT_NUSHELL_FALLBACK_VERSION$' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q '^ARG HERMES_AGENT_NUSHELL_FALLBACK_SHA256_AARCH64$' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q '^ARG HERMES_AGENT_NUSHELL_FALLBACK_SHA256_X86_64$' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q 'apt-cache show nushell' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q 'github.com/nushell/nushell/releases/download' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q 'sha256sum -c -' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q 'nushell' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q '^USER root$' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q '^WORKDIR ${HERMES_AGENT_CONTAINER_DOCS}$' "$ROOT/configs/shared/hermes-agent/Containerfile"
! grep -q 'hermes-agent-entrypoint' "$ROOT/configs/shared/hermes-agent/Containerfile"
! grep -q '^ENTRYPOINT' "$ROOT/configs/shared/hermes-agent/Containerfile"
grep -q '^# This file holds the internal shell helpers used by the wrapper scripts\.$' "$ROOT/scripts/shared/hermes-agent/common.sh"
grep -q '^# This script builds a fresh Hermes Agent image from the saved repo settings\.$' "$ROOT/scripts/shared/hermes-agent/hermes-agent-build"
grep -q '^# This script starts a saved workspace container, then opens Hermes\.$' "$ROOT/scripts/shared/hermes-agent/hermes-agent-run"
grep -q '^# This script opens nushell by default, or runs an explicit command in an ephemeral CLI container\.$' "$ROOT/scripts/shared/hermes-agent/hermes-agent-shell"

# This allows the family offset rule while still rejecting obsolete workspace placeholders.
if grep -R -E 'HERMES_AGENT_PORT_OFFSET_|hermes-agent-workspace' "$ROOT/scripts/shared/hermes-agent" >/dev/null; then
  printf 'Scripts and shell libraries must not keep obsolete workspace-specific placeholders.\n' >&2
  exit 1
fi

# This rejects the obsolete placeholder bundled-skills packaging path.
if grep -q 'COPY skills/' "$ROOT/configs/shared/hermes-agent/Containerfile"; then
  printf 'Containerfile must not copy the obsolete repo skills placeholder path.\n' >&2
  exit 1
fi

# This rejects stale OpenCode wording in Hermes wrapper tests.
if grep -F 'OpenCode-style option parsing' \
  "$ROOT/tests/shared/hermes-agent/test-hermes-agent-build.sh" \
  "$ROOT/tests/shared/hermes-agent/test-hermes-agent-run.sh" \
  "$ROOT/tests/shared/hermes-agent/test-hermes-agent-shell.sh" \
  "$ROOT/tests/shared/shared/test-asserts.sh" >/dev/null; then
  printf 'Hermes tests should not keep stale OpenCode wording.\n' >&2
  exit 1
fi

# This keeps first-run setup and service readiness delegated to the upstream Hermes entrypoint.
if grep -R -E 'hermes_container_setup_is_complete|hermes_container_gateway_is_healthy|hermes_container_dashboard_is_healthy|hermes_container_start_gateway|hermes_container_start_dashboard|hermes_container_services_are_healthy|hermes_wait_for_healthy_container|hermes_wait_for_gateway_container|hermes_wait_for_dashboard_container|start_service_if_needed|print_first_run_setup_warning|pause_before_first_run_setup' \
  "$ROOT/scripts/shared/hermes-agent/common.sh" "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" >/dev/null; then
  printf 'Hermes wrapper should delegate setup and service readiness to the upstream image entrypoint.\n' >&2
  exit 1
fi

# This rejects stale wording from the deleted repo entrypoint flow.
if grep -F 'setup-safe entrypoint' "$ROOT/tests/shared/hermes-agent/test-hermes-agent-build.sh" >/dev/null || \
  grep -F 'entrypoint manages startup' "$ROOT/tests/shared/hermes-agent/test-hermes-agent-build.sh" >/dev/null; then
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
