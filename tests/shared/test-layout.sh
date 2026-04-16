#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

test -f "$ROOT/README.md"
test -f "$ROOT/docs/shared/usage.md"
test -f "$ROOT/docs/shared/implementation-plan.md"
test -f "$ROOT/config/shared/hermes.conf"
test -f "$ROOT/config/shared/tool-versions.conf"
test -f "$ROOT/config/containers/Containerfile.wrapper"
test -f "$ROOT/config/containers/Containerfile.source-base.template"
test -f "$ROOT/config/containers/entrypoint.sh"
test -f "$ROOT/config/patches/apply-hermes-host-agents-context.py"
test -f "$ROOT/config/patches/apply-hermes-matrix-device-id.py"
test -f "$ROOT/config/patches/apply-hermes-matrix-config-overrides.py"
test -f "$ROOT/config/patches/apply-hermes-transcription-oga.py"
test -f "$ROOT/lib/shell/common.sh"
test -f "$ROOT/scripts/shared/hermes-bootstrap"
test -f "$ROOT/scripts/shared/hermes-build"
test -f "$ROOT/scripts/shared/hermes-start"
test -f "$ROOT/scripts/shared/hermes-open"
test -f "$ROOT/scripts/shared/hermes-status"
test -f "$ROOT/scripts/shared/hermes-logs"
test -f "$ROOT/scripts/shared/hermes-shell"
test -f "$ROOT/scripts/shared/hermes-stop"
test -f "$ROOT/scripts/shared/hermes-remove"

test ! -e "$ROOT/scripts/shared/hermes-upgrade"
test ! -e "$ROOT/scripts/shared/bootstrap-test"
test ! -d "$ROOT/config/patches/__pycache__"
test ! -e "$ROOT/config/patches/apply-hermes-matrix-auto-verification.py"
test ! -e "$ROOT/config/patches/apply-hermes-matrix-upload-filesize.py"
test ! -e "$ROOT/config/patches/apply-hermes-matrix-encrypted-media.py"

grep -q '^HERMES_LABEL_NAMESPACE="hermes.wrapper"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_LABEL_WORKSPACE="hermes.wrapper.workspace"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_LABEL_LANE="hermes.wrapper.lane"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_LABEL_UPSTREAM="hermes.wrapper.upstream"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_LABEL_WRAPPER="hermes.wrapper.context"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_LABEL_COMMITSTAMP="hermes.wrapper.commitstamp"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_LANE_PRODUCTION="production"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_LANE_TEST="test"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_UPSTREAM_MAIN_SELECTOR="main"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_DEFAULT_UPSTREAM_SELECTOR="latest"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_RELEASE_TAG_PREFIX="v"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_BASE_ROOT="\$HOME/Documents/Ezirius/.applications-data/.containers-artificial-intelligence"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_WORKSPACE_HOME_DIRNAME="hermes-home"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_WORKSPACE_DIRNAME="hermes-workspace"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_CONTAINER_RUNTIME_HOME="/home/hermes"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_CONTAINER_WORKSPACE_DIR="/workspace/hermes-workspace"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_CONTAINER_RESTART_POLICY="unless-stopped"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_PODMAN_TTY_WRAPPER="auto"$' "$ROOT/config/shared/hermes.conf"
if grep -q '^# HERMES_HOST_SERVER_PORT=' "$ROOT/config/shared/hermes.conf"; then
  printf 'assertion failed: shared config should not advertise an unsupported managed host port setting\n' >&2
  exit 1
fi
grep -q '^HERMES_UBUNTU_LTS_VERSION="24.04"$' "$ROOT/config/shared/tool-versions.conf"
grep -q '^HERMES_NODE_LTS_VERSION="24"$' "$ROOT/config/shared/tool-versions.conf"
grep -q '^ARG UBUNTU_VERSION$' "$ROOT/config/containers/Containerfile.wrapper"
grep -q '^FROM ubuntu:${UBUNTU_VERSION}$' "$ROOT/config/containers/Containerfile.wrapper"
[[ "$(grep -c '^ARG HERMES_CONTAINER_WORKSPACE_DIR$' "$ROOT/config/containers/Containerfile.wrapper")" == '2' ]]
[[ "$(grep -c '^ARG HERMES_CONTAINER_RUNTIME_HOME$' "$ROOT/config/containers/Containerfile.wrapper")" == '2' ]]
grep -q '^ENTRYPOINT \["/usr/bin/tini", "--", "/usr/local/bin/hermes-entrypoint.sh"\]$' "$ROOT/config/containers/Containerfile.wrapper"
grep -q '^CMD \["sleep", "infinity"\]$' "$ROOT/config/containers/Containerfile.wrapper"
grep -q '^USER hermes$' "$ROOT/config/containers/Containerfile.wrapper"
grep -q '^FROM ubuntu:__HERMES_UBUNTU_LTS_VERSION__$' "$ROOT/config/containers/Containerfile.source-base.template"
grep -q '__HERMES_CONTAINER_WORKSPACE_DIR__' "$ROOT/config/containers/Containerfile.source-base.template"
grep -q '__HERMES_CONTAINER_RUNTIME_HOME__' "$ROOT/config/containers/Containerfile.source-base.template"
grep -q '^USER hermes$' "$ROOT/config/containers/Containerfile.source-base.template"
test ! -e "$ROOT/config/containers/Dockerfile"
grep -q '^update_config_assignment() {$' "$ROOT/lib/shell/common.sh"
grep -q '^tool_versions_config_path() {$' "$ROOT/lib/shell/common.sh"
grep -q '^hermes_upstream_ref_label_key() {$' "$ROOT/lib/shell/common.sh"
grep -q '^hermes_build_fingerprint_label_key() {$' "$ROOT/lib/shell/common.sh"
grep -q '^container_restart_policy() {$' "$ROOT/lib/shell/common.sh"
grep -q '^workspace_names_from_base_root() {$' "$ROOT/lib/shell/common.sh"
grep -q '^resolve_workspace_argument() {$' "$ROOT/lib/shell/common.sh"
grep -q '^wrapper_build_commitstamp() {$' "$ROOT/lib/shell/common.sh"
grep -q '^latest_ubuntu_lts_version() {$' "$ROOT/lib/shell/common.sh"
grep -q '^latest_node_lts_version() {$' "$ROOT/lib/shell/common.sh"
grep -q '^require_canonical_main_checkout() {$' "$ROOT/lib/shell/common.sh"
grep -q '^require_main_pushed() {$' "$ROOT/lib/shell/common.sh"
grep -q '^current_wrapper_context() {$' "$ROOT/lib/shell/common.sh"
grep -q '^git_commit_stamp() {$' "$ROOT/lib/shell/common.sh"
grep -q '^build_tags_for_lane() {$' "$ROOT/lib/shell/common.sh"
grep -q '^list_upstream_release_tags() {$' "$ROOT/lib/shell/common.sh"
grep -q 'extra\["allowed_users"\] = os.getenv("MATRIX_ALLOWED_USERS", "")' "$ROOT/config/patches/apply-hermes-matrix-config-overrides.py"
if grep -q 'MATRIX_DEVICE_ID' "$ROOT/config/patches/apply-hermes-matrix-config-overrides.py"; then
  printf 'assertion failed: matrix config overrides patch should no longer wire MATRIX_DEVICE_ID\n' >&2
  exit 1
fi
if grep -q 'implementation source of truth for the current worktree' "$ROOT/docs/shared/implementation-plan.md"; then
  printf 'assertion failed: historical implementation plan must not be described as the current source of truth\n' >&2
  exit 1
fi
if grep -q '^## Current source of truth$' "$ROOT/README.md"; then
  printf 'assertion failed: README must not describe the historical implementation plan as the current source of truth\n' >&2
  exit 1
fi
grep -q -- '- `USER hermes` with `HOME=/home/hermes` and `HERMES_HOME=/home/hermes`$' "$ROOT/README.md"
grep -q -- '- `/home/hermes` backed by the host `hermes-home` mount$' "$ROOT/README.md"
grep -q -- '- `/workspace/hermes-workspace` backed by the host `hermes-workspace` mount$' "$ROOT/README.md"
grep -q -- '- no wrapper-managed `AGENTS.md` bootstrap$' "$ROOT/README.md"
grep -q -- '- the `/opt/data` to `/home/hermes` move is a clean breaking change with no compatibility layer$' "$ROOT/README.md"
grep -q -- '- `USER hermes` with `HOME=/home/hermes` and `HERMES_HOME=/home/hermes`$' "$ROOT/docs/shared/usage.md"
grep -q -- '- `/home/hermes` mapped to `hermes-home`$' "$ROOT/docs/shared/usage.md"
grep -q -- '- `/workspace/hermes-workspace` mapped to `hermes-workspace`$' "$ROOT/docs/shared/usage.md"
grep -q -- '- no wrapper-managed `AGENTS.md` bootstrap$' "$ROOT/docs/shared/usage.md"
grep -q -- '- `/opt/data` has been replaced by `/home/hermes` with no compatibility layer$' "$ROOT/docs/shared/usage.md"

echo "Layout checks passed"
