#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

INSTALL_DIR="$TMPDIR/install"
HERMES_HOME_DIR="$TMPDIR/hermes-home"
MOCK_BIN="$TMPDIR/bin"
LOG_FILE="$TMPDIR/hermes.log"
mkdir -p "$INSTALL_DIR/docker" "$INSTALL_DIR/tools" "$INSTALL_DIR/skills" "$MOCK_BIN"

printf 'OPENAI_API_KEY=example\n' > "$INSTALL_DIR/.env.example"
printf 'model: test-model\n' > "$INSTALL_DIR/cli-config.yaml.example"
printf 'soul template\n' > "$INSTALL_DIR/docker/SOUL.md"
printf 'agents template\n' > "$INSTALL_DIR/AGENTS.md"
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
EOF
chmod +x "$MOCK_BIN/hermes"

assert_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || { printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2; exit 1; }
}

PATH="$MOCK_BIN:$PATH" HERMES_HOME="$HERMES_HOME_DIR" INSTALL_DIR="$INSTALL_DIR" HERMES_TEST_LOG="$LOG_FILE" \
  bash "$ROOT/config/containers/entrypoint.sh" gateway run

for required_dir in cron sessions logs hooks memories skills; do
  test -d "$HERMES_HOME_DIR/$required_dir"
done
assert_contains "$HERMES_HOME_DIR/.env" 'OPENAI_API_KEY=example' 'entrypoint seeds .env from example file'
assert_contains "$HERMES_HOME_DIR/config.yaml" 'model: test-model' 'entrypoint seeds config.yaml from example file'
assert_contains "$HERMES_HOME_DIR/SOUL.md" 'soul template' 'entrypoint seeds SOUL.md from install template'
assert_contains "$HERMES_HOME_DIR/AGENTS.md" 'agents template' 'entrypoint seeds AGENTS.md from install template'
test -f "$HERMES_HOME_DIR/skills-sync-ran"
assert_contains "$LOG_FILE" 'gateway run' 'entrypoint forwards command to hermes'

printf 'user env\n' > "$HERMES_HOME_DIR/.env"
printf 'user config\n' > "$HERMES_HOME_DIR/config.yaml"
printf 'user soul\n' > "$HERMES_HOME_DIR/SOUL.md"
printf 'user agents\n' > "$HERMES_HOME_DIR/AGENTS.md"
rm -f "$HERMES_HOME_DIR/skills-sync-ran"
: > "$LOG_FILE"

PATH="$MOCK_BIN:$PATH" HERMES_HOME="$HERMES_HOME_DIR" INSTALL_DIR="$INSTALL_DIR" HERMES_TEST_LOG="$LOG_FILE" \
  bash "$ROOT/config/containers/entrypoint.sh" chat

assert_contains "$HERMES_HOME_DIR/.env" 'user env' 'entrypoint does not overwrite existing .env'
assert_contains "$HERMES_HOME_DIR/config.yaml" 'user config' 'entrypoint does not overwrite existing config.yaml'
assert_contains "$HERMES_HOME_DIR/SOUL.md" 'user soul' 'entrypoint does not overwrite existing SOUL.md'
assert_contains "$HERMES_HOME_DIR/AGENTS.md" 'user agents' 'entrypoint does not overwrite existing AGENTS.md'
test -f "$HERMES_HOME_DIR/skills-sync-ran"
assert_contains "$LOG_FILE" 'chat' 'entrypoint forwards later commands to hermes'

echo "Entrypoint behaviour checks passed"
