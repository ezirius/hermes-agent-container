#!/bin/bash
# Wrapper entrypoint: stay close to the latest upstream release, add host AGENTS seeding.
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="${INSTALL_DIR:-/home/hermes/hermes-agent}"

# Create essential directory structure. Cache and platform directories are created
# on demand by Hermes so new installs follow the current upstream layout.
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills}

if [ ! -f "$HERMES_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
fi

if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
fi

if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

# Wrapper-specific: seed host-backed AGENTS.md so HERMES_HOME remains the
# authoritative default context source for this container wrapper.
if [ ! -f "$HERMES_HOME/AGENTS.md" ]; then
    cp "$INSTALL_DIR/AGENTS.md" "$HERMES_HOME/AGENTS.md"
fi

# Sync bundled skills (manifest-based so user edits are preserved).
if [ -d "$INSTALL_DIR/skills" ] && [ -f "$INSTALL_DIR/tools/skills_sync.py" ]; then
    HERMES_HOME="$HERMES_HOME" python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

exec hermes "$@"
