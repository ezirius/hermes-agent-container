#!/bin/bash
# Wrapper entrypoint aligned closely to the latest upstream release.
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="${INSTALL_DIR:-/home/hermes/hermes-agent}"
SKILLS_SYNC_SCRIPT="$INSTALL_DIR/tools/skills_sync.py"

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

if [ ! -f "$HERMES_HOME/AGENTS.md" ]; then
    cp "$INSTALL_DIR/AGENTS.md" "$HERMES_HOME/AGENTS.md"
fi

if [ -d "$INSTALL_DIR/skills" ] && [ -f "$SKILLS_SYNC_SCRIPT" ]; then
    HERMES_HOME="$HERMES_HOME" python3 "$SKILLS_SYNC_SCRIPT"
fi

exec hermes "$@"
