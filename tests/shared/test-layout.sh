#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

test -f "$ROOT/README.md"
test -f "$ROOT/docs/shared/usage.md"
test -f "$ROOT/docs/shared/implementation-plan.md"
test -f "$ROOT/config/shared/hermes.conf"
test -f "$ROOT/config/containers/Dockerfile"
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

grep -q '^ARG UBUNTU_LTS_VERSION=24.04$' "$ROOT/config/containers/Dockerfile"
grep -q '^ARG NODE_LTS_VERSION=24$' "$ROOT/config/containers/Dockerfile"
grep -q '^FROM ubuntu:\${UBUNTU_LTS_VERSION}$' "$ROOT/config/containers/Dockerfile"
grep -q 'https://deb.nodesource.com/node_\${NODE_LTS_VERSION}.x' "$ROOT/config/containers/Dockerfile"
grep -q '^  && python3 /tmp/hermes-patches/apply-hermes-matrix-device-id.py \\$' "$ROOT/config/containers/Dockerfile"
grep -q '^  && python3 /tmp/hermes-patches/apply-hermes-matrix-config-overrides.py \\$' "$ROOT/config/containers/Dockerfile"
grep -q '^  && python3 /tmp/hermes-patches/apply-hermes-transcription-oga.py \\$' "$ROOT/config/containers/Dockerfile"
if grep -q 'apply-hermes-matrix-auto-verification.py' "$ROOT/config/containers/Dockerfile"; then
  printf 'assertion failed: Dockerfile should not apply removed matrix auto verification patch\n' >&2
  exit 1
fi
if grep -q 'apply-hermes-matrix-upload-filesize.py' "$ROOT/config/containers/Dockerfile"; then
  printf 'assertion failed: Dockerfile should not apply removed matrix upload filesize patch\n' >&2
  exit 1
fi
if grep -q 'apply-hermes-matrix-encrypted-media.py' "$ROOT/config/containers/Dockerfile"; then
  printf 'assertion failed: Dockerfile should not apply removed matrix encrypted media patch\n' >&2
  exit 1
fi

grep -q '^HERMES_UBUNTU_LTS_VERSION="24.04"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_NODE_LTS_VERSION="24"$' "$ROOT/config/shared/hermes.conf"
grep -q '^HERMES_BASE_ROOT="\$HOME/Documents/Ezirius/.applications-data/.containers-artificial-intelligence"$' "$ROOT/config/shared/hermes.conf"
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

grep -q 'there is no `hermes-upgrade` command and no `bootstrap-test`' "$ROOT/README.md"
grep -q 'hermes-workspace' "$ROOT/README.md"
grep -q 'newer image-only targets remain selectable' "$ROOT/README.md"
grep -q 'used by' "$ROOT/README.md"
grep -q 'implementation-plan.md' "$ROOT/README.md"
grep -q 'picker-based workspace commands' "$ROOT/docs/shared/usage.md"
grep -q '/workspace/hermes-workspace' "$ROOT/docs/shared/usage.md"
grep -q 'used by' "$ROOT/docs/shared/usage.md"
grep -q 'newer immutable image exists' "$ROOT/docs/shared/usage.md"

echo "Layout checks passed"
