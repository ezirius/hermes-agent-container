# Hermes Agent Architecture

This repo keeps a small wrapper around a Hermes Agent container with three responsibility layers:

- `config/agent/shared/hermes-agent-settings-shared.conf` owns runtime and build configuration.
- `lib/shell/shared/common.sh` owns shared shell helpers for config loading, workspace parsing, and container lookup.
- `scripts/agent/shared/*` are thin entrypoints for build, run, and shell flows.

## Layout

- `config/containers/shared/Containerfile` builds the image and reflects the config contract through build args and runtime env vars.
- `lib/shell/shared/common.sh` is the only shared shell library path.
- `scripts/agent/shared/hermes-agent-build` builds an image from config.
- `scripts/agent/shared/hermes-agent-run` starts a selected workspace and mounts host paths into the container.
- `scripts/agent/shared/hermes-agent-shell` connects to an existing workspace container.
- `tests/agent/shared/*` verify behavior and layout without relying on brittle source-text assertions.

## Design Constraints

- Config belongs in config files, not in scripts or shell libraries.
- The host base path is rooted at `${HOME}`.
- The host workspace dirname is `hermes-agent-general`.
- The container workspace path is `/workspace/general`.
- Scripts should stay small and defer shared behavior to `lib/shell/shared/common.sh`.
- Test helpers stay in the test tree under `tests/agent/shared/` so the repo keeps a consistent 3-level path shape.
