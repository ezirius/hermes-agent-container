#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

test -f "$ROOT/README.md"
test -f "$ROOT/docs/shared/usage.md"
test -f "$ROOT/config/containers/Dockerfile"
test -f "$ROOT/config/containers/entrypoint.sh"
test -f "$ROOT/.dockerignore"
test -f "$ROOT/config/patches/apply-hermes-host-agents-context.py"
test -f "$ROOT/config/patches/apply-hermes-matrix-device-id.py"
test -f "$ROOT/config/patches/apply-hermes-matrix-encrypted-media.py"
test -f "$ROOT/lib/shell/common.sh"
test -f "$ROOT/scripts/shared/bootstrap"
test -f "$ROOT/scripts/shared/bootstrap-test"
test -f "$ROOT/scripts/shared/hermes-build"
test -f "$ROOT/scripts/shared/hermes-upgrade"
test -f "$ROOT/scripts/shared/hermes-start"
test -f "$ROOT/scripts/shared/hermes-open"
test -f "$ROOT/scripts/shared/hermes-status"
test -f "$ROOT/scripts/shared/hermes-logs"
test -f "$ROOT/scripts/shared/hermes-shell"
test -f "$ROOT/scripts/shared/hermes-stop"
test -f "$ROOT/scripts/shared/hermes-remove"
test -f "$ROOT/tests/shared/test-all.sh"
test -f "$ROOT/tests/shared/test-args.sh"
test -f "$ROOT/tests/shared/test-common.sh"
test -f "$ROOT/tests/shared/test-ref-resolution.sh"
test -f "$ROOT/tests/shared/test-runtime.sh"
test -f "$ROOT/tests/shared/test-entrypoint.sh"
test -f "$ROOT/tests/shared/test-patches.sh"
grep -q '^\.git$' "$ROOT/.dockerignore"
grep -q '^tests/$' "$ROOT/.dockerignore"
grep -q '^docs/$' "$ROOT/.dockerignore"

grep -q '^LABEL hermes.repo_url=\$HERMES_REPO_URL$' "$ROOT/config/containers/Dockerfile"
grep -q '^LABEL hermes.ref=\$HERMES_REF$' "$ROOT/config/containers/Dockerfile"
grep -q '^COPY config/patches /tmp/hermes-patches$' "$ROOT/config/containers/Dockerfile"
grep -q '^COPY config/containers/entrypoint.sh /usr/local/bin/hermes-entrypoint.sh$' "$ROOT/config/containers/Dockerfile"
grep -q '^FROM debian:13.4$' "$ROOT/config/containers/Dockerfile"
grep -q '^ARG HERMES_REF$' "$ROOT/config/containers/Dockerfile"
grep -q 'HERMES_REF must be set to a real upstream tag or branch before building' "$ROOT/config/containers/Dockerfile"
grep -q 'build-essential' "$ROOT/config/containers/Dockerfile"
grep -q 'libolm-dev' "$ROOT/config/containers/Dockerfile"
grep -q 'python3-pip' "$ROOT/config/containers/Dockerfile"
grep -q 'python3-dev' "$ROOT/config/containers/Dockerfile"
grep -q 'libffi-dev' "$ROOT/config/containers/Dockerfile"
if grep -q 'cmake' "$ROOT/config/containers/Dockerfile"; then
  printf 'assertion failed: Dockerfile should follow upstream package selection and avoid obsolete cmake dependency\n' >&2
  exit 1
fi
if grep -q 'apply-hermes-mautrix-migration.py' "$ROOT/config/containers/Dockerfile"; then
  printf 'assertion failed: Dockerfile should not apply the obsolete mautrix migration patch\n' >&2
  exit 1
fi
grep -q 'python3 -m pip install -e "/home/hermes/hermes-agent\[matrix\]" --break-system-packages' "$ROOT/config/containers/Dockerfile"
grep -q 'npx playwright install --with-deps chromium --only-shell' "$ROOT/config/containers/Dockerfile"
grep -q 'scripts/whatsapp-bridge' "$ROOT/config/containers/Dockerfile"
grep -q '^ENTRYPOINT \["/usr/local/bin/hermes-entrypoint.sh"\]$' "$ROOT/config/containers/Dockerfile"
grep -q '^VOLUME \["/opt/data"\]$' "$ROOT/config/containers/Dockerfile"
grep -q '^  && python3 /tmp/hermes-patches/apply-hermes-host-agents-context.py \\$' "$ROOT/config/containers/Dockerfile"
grep -q '^  && python3 /tmp/hermes-patches/apply-hermes-matrix-device-id.py \\$' "$ROOT/config/containers/Dockerfile"
grep -q '^  && python3 /tmp/hermes-patches/apply-hermes-matrix-encrypted-media.py \\$' "$ROOT/config/containers/Dockerfile"
grep -q 'python3 -m pip install -e "/home/hermes/hermes-agent\[all\]" --break-system-packages' "$ROOT/config/containers/Dockerfile"
grep -q '^if \[ ! -f "\$HERMES_HOME/AGENTS.md" \]; then$' "$ROOT/config/containers/entrypoint.sh"
grep -q '^    cp "\$INSTALL_DIR/AGENTS.md" "\$HERMES_HOME/AGENTS.md"$' "$ROOT/config/containers/entrypoint.sh"
if grep -q 'apply-hermes-matrix-store-home.py' "$ROOT/config/containers/Dockerfile"; then
  printf 'assertion failed: obsolete matrix store patch should not be referenced by the Dockerfile\n' >&2
  exit 1
fi
if grep -q 'mautrix' "$ROOT/config/containers/Dockerfile"; then
  printf 'assertion failed: Dockerfile should not encode mautrix-specific runtime assumptions\n' >&2
  exit 1
fi
grep -q 'ln -s /opt/data /home/hermes/.hermes' "$ROOT/config/containers/Dockerfile"
grep -q 'hermes_home_agents = get_hermes_home() / "AGENTS.md"' "$ROOT/config/patches/apply-hermes-host-agents-context.py"
grep -q 'MATRIX_DEVICE_ID        Optional stable device ID for password login' "$ROOT/config/patches/apply-hermes-matrix-device-id.py"
grep -q 'auth_dict\["device_id"\] = self._device_id' "$ROOT/config/patches/apply-hermes-matrix-device-id.py"
grep -q 'client.login_raw(auth_dict)' "$ROOT/config/patches/apply-hermes-matrix-device-id.py"
grep -q 'homeserver returned device %s' "$ROOT/config/patches/apply-hermes-matrix-device-id.py"
grep -q 'response omitted device_id; continuing with requested device %s' "$ROOT/config/patches/apply-hermes-matrix-device-id.py"
grep -q 'RoomEncryptedAudio' "$ROOT/config/patches/apply-hermes-matrix-encrypted-media.py"
grep -q 'decrypt_attachment' "$ROOT/config/patches/apply-hermes-matrix-encrypted-media.py"
grep -q 'cache_document_from_bytes' "$ROOT/config/patches/apply-hermes-matrix-encrypted-media.py"
grep -q '_allow_reprocess_event' "$ROOT/config/patches/apply-hermes-matrix-encrypted-media.py"
grep -q '^local_build_fingerprint() {$' "$ROOT/lib/shell/common.sh"
grep -q '^current_image_build_fingerprint() {$' "$ROOT/lib/shell/common.sh"
grep -q '^github_repo_slug() {$' "$ROOT/lib/shell/common.sh"
grep -q '^resolve_hermes_ref() {$' "$ROOT/lib/shell/common.sh"
grep -q '^image_exists() {$' "$ROOT/lib/shell/common.sh"
grep -q '^image_label() {$' "$ROOT/lib/shell/common.sh"
grep -q '^use_interactive_tty() {$' "$ROOT/lib/shell/common.sh"
grep -q 'HERMES_FORCE_EXEC_TTY' "$ROOT/lib/shell/common.sh"
grep -q '^should_wrap_podman_tty_with_script() {$' "$ROOT/lib/shell/common.sh"
grep -q '^exec_podman_interactive_command() {$' "$ROOT/lib/shell/common.sh"
grep -q '^show_help() {$' "$ROOT/lib/shell/common.sh"
grep -q '^require_workspace_name() {$' "$ROOT/lib/shell/common.sh"
grep -q '^migrate_legacy_workspace_layout() {$' "$ROOT/lib/shell/common.sh"
grep -q '^HERMES_BASE_ROOT="\${HERMES_BASE_ROOT:-\$HOME/Documents/Ezirius/.applications-data/.hermes-agent}"$' "$ROOT/lib/shell/common.sh"
if grep -q '^HERMES_BASE_ROOT="\${HERMES_BASE_ROOT:-~/Documents/Ezirius/.applications-data/.hermes-agent}"$' "$ROOT/lib/shell/common.sh"; then
  printf 'assertion failed: HERMES_BASE_ROOT must use $HOME, not a literal ~ path that creates a stray ~ directory\n' >&2
  exit 1
fi
grep -q 'official single-container Docker image and Docker workflow' "$ROOT/README.md"
grep -q 'builds from the latest upstream release tag' "$ROOT/README.md"
grep -q 'It does not use upstream main as the default baseline.' "$ROOT/README.md"
if grep -q 'GitHub setup on Maldoria' "$ROOT/README.md"; then
  printf 'assertion failed: shared README should not retain host-specific Maldoria operational notes\n' >&2
  exit 1
fi
grep -q 'wrapper workspace: this repo’s host-level unit of isolation' "$ROOT/README.md"
grep -q 'upstream profile: Hermes’s internal isolation layer' "$ROOT/README.md"
grep -q 'hermes-open ezirius mcp serve' "$ROOT/README.md"
grep -q 'bootstrap-test' "$ROOT/README.md"
grep -q 'Keep secrets in `.env`, keep non-secret config in `config.yaml`' "$ROOT/README.md"
grep -q '/opt/data' "$ROOT/README.md"
grep -q 'upstream already provides official Docker support' "$ROOT/docs/shared/usage.md"
grep -q 'default: `latest-release`' "$ROOT/docs/shared/usage.md"
grep -q 'Do not treat upstream `main` as the baseline unless you explicitly set `HERMES_REF` for that purpose.' "$ROOT/docs/shared/usage.md"
grep -q '`config.yaml` stores non-secret runtime configuration' "$ROOT/docs/shared/usage.md"
grep -q 'upstream-style entrypoint' "$ROOT/docs/shared/usage.md"
grep -q '/opt/data' "$ROOT/docs/shared/usage.md"
grep -q 'MATRIX_DEVICE_ID=HERMES' "$ROOT/docs/shared/usage.md"
grep -q 'wrapper workspace: this repo’s host-level isolation unit' "$ROOT/docs/shared/usage.md"
grep -q 'hermes-open ezirius mcp serve' "$ROOT/docs/shared/usage.md"
grep -q 'bootstrap-test' "$ROOT/docs/shared/usage.md"
grep -q 'do not forward extra secrets or runtime sockets into nested backends' "$ROOT/docs/shared/usage.md"
grep -q '^"\$SCRIPT_DIR/hermes-build"$' "$ROOT/scripts/shared/bootstrap"
grep -q '^"\$SCRIPT_DIR/hermes-upgrade"$' "$ROOT/scripts/shared/bootstrap"
grep -q '^TEST_WORKSPACE="test"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^TEST_IMAGE_NAME="hermes-agent-local-test"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^require_podman$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^resolve_workspace "\$TEST_WORKSPACE"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^"\$SCRIPT_DIR/hermes-remove" "\$TEST_WORKSPACE"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^podman image rm -f "\$HERMES_IMAGE_NAME" >/dev/null 2>&1 || true$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^rm -rf "\$WORKSPACE_ROOT"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^"\$SCRIPT_DIR/hermes-build"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^"\$SCRIPT_DIR/hermes-start" "\$TEST_WORKSPACE"$' "$ROOT/scripts/shared/bootstrap-test"
if grep -q '^"\$SCRIPT_DIR/hermes-upgrade"$' "$ROOT/scripts/shared/bootstrap-test"; then
  printf 'assertion failed: bootstrap-test should build fresh directly without a redundant hermes-upgrade step\n' >&2
  exit 1
fi
grep -q '^exec "\$SCRIPT_DIR/hermes-open" "\$TEST_WORKSPACE" "\$@"$' "$ROOT/scripts/shared/bootstrap-test"
grep -q '^"\$SCRIPT_DIR/hermes-start" "\$WORKSPACE"$' "$ROOT/scripts/shared/bootstrap"
grep -q '^exec "\$SCRIPT_DIR/hermes-open" "\$WORKSPACE" "\$@"$' "$ROOT/scripts/shared/bootstrap"
grep -q '^if image_exists; then$' "$ROOT/scripts/shared/hermes-build"
grep -q 'hermes.wrapper_fingerprint=' "$ROOT/scripts/shared/hermes-build"
grep -q -- '--restart unless-stopped' "$ROOT/scripts/shared/hermes-start"
grep -q '"\$HERMES_IMAGE_NAME" gateway run' "$ROOT/scripts/shared/hermes-start"
if grep -q -- '--env TERMINAL_CWD=/opt/data' "$ROOT/scripts/shared/hermes-start"; then
  printf 'assertion failed: hermes-start should not force TERMINAL_CWD=/opt/data and suppress workspace context files\n' >&2
  exit 1
fi
grep -q '^exec_podman_interactive_command exec "\${RUN_ARGS\[@\]}"$' "$ROOT/scripts/shared/hermes-open"
if grep -q -- '--env TERMINAL_CWD=/opt/data' "$ROOT/scripts/shared/hermes-open"; then
  printf 'assertion failed: hermes-open should not force TERMINAL_CWD=/opt/data and suppress workspace context files\n' >&2
  exit 1
fi
grep -q '^RUN_ARGS=(--workdir /workspace "\$HERMES_CONTAINER_NAME" hermes)$' "$ROOT/scripts/shared/hermes-open"
grep -q '^exec_podman_interactive_command exec \\$' "$ROOT/scripts/shared/hermes-shell"
grep -q -- '--workdir /workspace' "$ROOT/scripts/shared/hermes-shell"
grep -q '"\$HERMES_CONTAINER_NAME" \\$' "$ROOT/scripts/shared/hermes-shell"
grep -q '^  /bin/bash$' "$ROOT/scripts/shared/hermes-shell"
grep -q '^CURRENT_REPO_URL="\$(image_label hermes.repo_url)"$' "$ROOT/scripts/shared/hermes-upgrade"
grep -q '^CURRENT_REF="\$(image_label hermes.ref)"$' "$ROOT/scripts/shared/hermes-upgrade"
grep -q '^CURRENT_BUILD_FINGERPRINT="\$(current_image_build_fingerprint)"$' "$ROOT/scripts/shared/hermes-upgrade"
grep -q '"\$HERMES_HOME_DIR:/opt/data"' "$ROOT/scripts/shared/hermes-start"
grep -q '"\$HERMES_WORKSPACE_DIR:/workspace"' "$ROOT/scripts/shared/hermes-start"
if grep -q -- '--env-file' "$ROOT/scripts/shared/hermes-start"; then
  printf 'assertion failed: hermes-start should not use --env-file\n' >&2
  exit 1
fi

echo "Layout checks passed"
