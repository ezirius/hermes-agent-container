#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

INSTALL_DIR="$TMPDIR/install"
HERMES_HOME_DIR="$TMPDIR/hermes-home"
WORKSPACE_DIR="$TMPDIR/hermes-workspace"
MOCK_BIN="$TMPDIR/bin"
LOG_FILE="$TMPDIR/hermes.log"
mkdir -p "$INSTALL_DIR/docker" "$INSTALL_DIR/tools" "$INSTALL_DIR/skills" "$MOCK_BIN"

printf 'OPENAI_API_KEY=example\n' > "$INSTALL_DIR/.env.example"
printf 'model: test-model\n' > "$INSTALL_DIR/cli-config.yaml.example"
printf 'soul template\n' > "$INSTALL_DIR/docker/SOUL.md"
cat > "$INSTALL_DIR/tools/skills_sync.py" <<'PY'
import os
from pathlib import Path
home = Path(os.environ["HERMES_HOME"])
(home / "skills-sync-ran").write_text("yes", encoding="utf-8")
PY

cat > "$MOCK_BIN/hermes" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$HERMES_TEST_LOG"
printf 'HERMES_HOME=%s\n' "$HERMES_HOME" >> "$HERMES_TEST_LOG"
printf 'HOME=%s\n' "$HOME" >> "$HERMES_TEST_LOG"
EOF
chmod +x "$MOCK_BIN/hermes"

cat > "$MOCK_BIN/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script_path="${1:-}"
if [[ -n "$script_path" && -f "$script_path" ]]; then
  printf 'yes' > "$HERMES_HOME/skills-sync-ran"
  exit 0
fi
printf 'unexpected python3 invocation in test-entrypoint.sh\n' >&2
exit 1
EOF
chmod +x "$MOCK_BIN/python3"

cat > "$MOCK_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sleep %s\n' "$*" >> "$HERMES_TEST_LOG"
EOF
chmod +x "$MOCK_BIN/sleep"

assert_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || { printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2; exit 1; }
}

assert_not_contains() {
  local file="$1" needle="$2" message="$3"
  if grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nunexpected: %s\n' "$message" "$needle" >&2
    exit 1
  fi
}

assert_not_exists() {
  local path="$1" message="$2"
  if [[ -e "$path" ]]; then
    printf 'assertion failed: %s\nunexpected path: %s\n' "$message" "$path" >&2
    exit 1
  fi
}

PATH="$MOCK_BIN:$PATH" HERMES_HOME="$HERMES_HOME_DIR" INSTALL_DIR="$INSTALL_DIR" HERMES_TEST_LOG="$LOG_FILE" \
  bash "$ROOT/config/containers/entrypoint.sh" gateway run

for required_dir in cron sessions logs hooks memories skills; do
  test -d "$HERMES_HOME_DIR/$required_dir"
done
assert_contains "$HERMES_HOME_DIR/.env" 'OPENAI_API_KEY=example' 'entrypoint seeds .env from example file'
assert_contains "$HERMES_HOME_DIR/config.yaml" 'model: test-model' 'entrypoint seeds config.yaml from example file'
assert_contains "$HERMES_HOME_DIR/SOUL.md" 'soul template' 'entrypoint seeds SOUL.md from install template'
assert_not_exists "$HERMES_HOME_DIR/AGENTS.md" 'entrypoint does not seed AGENTS.md from the install tree'
test -f "$HERMES_HOME_DIR/skills-sync-ran"
assert_contains "$LOG_FILE" 'gateway run' 'entrypoint forwards command to hermes'
assert_contains "$LOG_FILE" "HERMES_HOME=$HERMES_HOME_DIR" 'entrypoint exports HERMES_HOME for hermes commands'
assert_contains "$LOG_FILE" "HOME=$HERMES_HOME_DIR" 'entrypoint keeps HOME aligned with HERMES_HOME for hermes commands'

printf 'user env\n' > "$HERMES_HOME_DIR/.env"
printf 'user config\n' > "$HERMES_HOME_DIR/config.yaml"
printf 'user soul\n' > "$HERMES_HOME_DIR/SOUL.md"
rm -f "$HERMES_HOME_DIR/skills-sync-ran"
: > "$LOG_FILE"

PATH="$MOCK_BIN:$PATH" HERMES_HOME="$HERMES_HOME_DIR" INSTALL_DIR="$INSTALL_DIR" HERMES_TEST_LOG="$LOG_FILE" \
  bash "$ROOT/config/containers/entrypoint.sh" chat

assert_contains "$HERMES_HOME_DIR/.env" 'user env' 'entrypoint does not overwrite existing .env'
assert_contains "$HERMES_HOME_DIR/config.yaml" 'user config' 'entrypoint does not overwrite existing config.yaml'
assert_contains "$HERMES_HOME_DIR/SOUL.md" 'user soul' 'entrypoint does not overwrite existing SOUL.md'
assert_not_exists "$HERMES_HOME_DIR/AGENTS.md" 'entrypoint leaves AGENTS.md unmanaged on later runs'
test -f "$HERMES_HOME_DIR/skills-sync-ran"
assert_contains "$LOG_FILE" 'chat' 'entrypoint forwards later commands to hermes'
assert_contains "$LOG_FILE" "HERMES_HOME=$HERMES_HOME_DIR" 'entrypoint preserves exported HERMES_HOME on later runs'
assert_contains "$LOG_FILE" "HOME=$HERMES_HOME_DIR" 'entrypoint preserves exported HOME on later runs'

rm -f "$INSTALL_DIR/tools/skills_sync.py" "$HERMES_HOME_DIR/skills-sync-ran"
rm -f "$HERMES_HOME_DIR/config.yaml"
: > "$LOG_FILE"

PATH="$MOCK_BIN:$PATH" HERMES_HOME="$HERMES_HOME_DIR" INSTALL_DIR="$INSTALL_DIR" HERMES_TEST_LOG="$LOG_FILE" \
  bash "$ROOT/config/containers/entrypoint.sh" doctor --verbose

assert_contains "$HERMES_HOME_DIR/.env" 'user env' 'entrypoint still preserves existing .env when sync helper is absent'
assert_contains "$HERMES_HOME_DIR/config.yaml" 'model: test-model' 'entrypoint seeds only missing config files on later runs'
assert_contains "$LOG_FILE" 'doctor --verbose' 'entrypoint forwards arbitrary later command arguments'
test ! -f "$HERMES_HOME_DIR/skills-sync-ran"
assert_not_contains "$LOG_FILE" 'skills_sync.py' 'entrypoint does not invoke missing skills sync helper'
assert_contains "$LOG_FILE" "HERMES_HOME=$HERMES_HOME_DIR" 'entrypoint still exports HERMES_HOME when the sync helper is absent'
assert_contains "$LOG_FILE" "HOME=$HERMES_HOME_DIR" 'entrypoint still exports HOME when the sync helper is absent'

rm -rf "$HERMES_HOME_DIR" "$WORKSPACE_DIR"
: > "$LOG_FILE"

PATH="$MOCK_BIN:$PATH" \
  HERMES_CONTAINER_RUNTIME_HOME="$HERMES_HOME_DIR" \
  HERMES_CONTAINER_WORKSPACE_DIR="$WORKSPACE_DIR" \
  INSTALL_DIR="$INSTALL_DIR" \
  HERMES_TEST_LOG="$LOG_FILE" \
  bash "$ROOT/config/containers/entrypoint.sh" gateway resume

test -d "$WORKSPACE_DIR"
assert_contains "$HERMES_HOME_DIR/.env" 'OPENAI_API_KEY=example' 'entrypoint seeds .env when only the container runtime home is configured'
assert_not_exists "$HERMES_HOME_DIR/AGENTS.md" 'entrypoint still leaves AGENTS.md unmanaged through the container runtime home'
assert_contains "$LOG_FILE" 'gateway resume' 'entrypoint forwards commands when using container path defaults'
assert_contains "$LOG_FILE" "HERMES_HOME=$HERMES_HOME_DIR" 'entrypoint exports HERMES_HOME from the container runtime home fallback'
assert_contains "$LOG_FILE" "HOME=$HERMES_HOME_DIR" 'entrypoint keeps HOME aligned when only the container runtime home is configured'

rm -rf "$HERMES_HOME_DIR" "$WORKSPACE_DIR"
: > "$LOG_FILE"

PATH="$MOCK_BIN:$PATH" \
  HERMES_CONTAINER_RUNTIME_HOME="$HERMES_HOME_DIR" \
  HERMES_CONTAINER_WORKSPACE_DIR="$WORKSPACE_DIR" \
  INSTALL_DIR="$INSTALL_DIR" \
  HERMES_TEST_LOG="$LOG_FILE" \
  bash "$ROOT/config/containers/entrypoint.sh" sleep infinity

assert_contains "$LOG_FILE" 'sleep infinity' 'entrypoint preserves the idle sleep command for the wrapper default container lifecycle'
assert_not_contains "$LOG_FILE" 'hermes sleep infinity' 'entrypoint does not wrap the idle sleep command in hermes'

echo "Entrypoint behaviour checks passed"
