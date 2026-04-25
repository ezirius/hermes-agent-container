# Hermes Agent Architecture

This repo keeps a small wrapper around the official Hermes Agent container with three responsibility layers:

- `config/agent/shared/hermes-agent-settings-shared.conf` owns runtime and build configuration.
- `lib/shell/shared/common.sh` owns shared shell helpers for config loading, workspace parsing, and container lookup.
- `scripts/agent/shared/*` are thin entrypoints for build, run, and shell flows.

## Layout

- `config/containers/shared/Containerfile` derives from the official upstream `nousresearch/hermes-agent` image and adds repo-local customization packages.
- `config/containers/shared/Containerfile` currently installs `nushell`; the official image owns Hermes, bash, git, frontend assets, and the upstream entrypoint.
- `lib/shell/shared/common.sh` is the only shared shell library path.
- `scripts/agent/shared/hermes-agent-build` builds an image from config.
- `scripts/agent/shared/hermes-agent-run` starts selected workspace gateway and dashboard pods, runs one container in each pod, mounts host paths into both containers, recreates poisoned exact-match pod/container pairs once, and prints startup diagnostics on failure.
- `scripts/agent/shared/hermes-agent-shell` connects to the existing workspace gateway container and opens `nu` by default.
- `tests/agent/shared/*` verify behavior and layout, using focused source-text assertions where they check stable build or runtime contract strings.
- The dashboard pod owns Podman port publishing, while the wrapper keeps the published host port bound to `127.0.0.1`.

## Design Constraints

- Config belongs in config files, not in scripts or shell libraries.
- The host base path is rooted at `${HOME}`.
- The host workspace dirname is `hermes-agent-general`.
- The container Hermes data path is `/opt/data`, matching the official image.
- The container workspace path is `/workspace/general`.
- Scripts should stay small and defer shared behavior to `lib/shell/shared/common.sh`.
- Startup failures should expose enough container state and recent logs to diagnose dashboard boot problems directly from wrapper output.
- Test helpers stay in the test tree under `tests/agent/shared/` so the repo keeps a consistent 3-level path shape.
