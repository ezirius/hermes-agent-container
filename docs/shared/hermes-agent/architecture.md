# Hermes Agent Architecture

This repo keeps a small wrapper around the official Hermes Agent container with three responsibility layers:

- `configs/shared/hermes-agent/hermes-agent-settings.conf` owns runtime and build configuration.
- `scripts/shared/hermes-agent/common.sh` owns the app-local shell helpers for config loading, workspace parsing, container naming, and container lookup.
- `scripts/shared/hermes-agent/*` are thin entrypoints for build, run, and shell flows.

## Layout

- `configs/shared/hermes-agent/Containerfile` derives from the official upstream `nousresearch/hermes-agent` image and adds repo-local customization packages.
- `configs/shared/hermes-agent/Containerfile` tries the distro `nushell` package first, and otherwise installs the configured fallback upstream binary after checksum verification; the official image still owns Hermes, bash, git, frontend assets, and the upstream entrypoint.
- The derived image starts as root so the upstream entrypoint can drop privileges to the Hermes runtime user after bootstrapping mounted state.
- `scripts/shared/hermes-agent/common.sh` is the internal helper library path for this app.
- `scripts/shared/hermes-agent/hermes-agent-build` builds an `arm64` image from config, then retags it with a 12-character image-id suffix.
- `scripts/shared/hermes-agent/hermes-agent-run` starts one selected workspace pod with gateway and dashboard role containers, mounts host paths into them, recreates a poisoned exact-match pod/container once, and prints startup diagnostics on failure.
- Hermes pod names follow `<image-name>-<workspace>`; role containers inside the pod use `<image-name>-<workspace>-gateway` and `<image-name>-<workspace>-dashboard`, and infra containers use `<image-name>-<workspace>-infrastructure`.
- `scripts/shared/hermes-agent/hermes-agent-run` and `scripts/shared/hermes-agent/hermes-agent-shell` open interactive commands through exact-name CLI containers named `<image-name>-<workspace>-cli`.
- Ephemeral CLI containers share the same `/opt/data` and `/workspace/docs` mounts as the persistent runtime containers, but they do not join the workspace pod and do not publish ports.
- The wrapper clears stale stopped same-workspace exact-name CLI containers before launch and fails with wrapper-owned errors when that exact name is still active or belongs to a different workspace mount.
- `tests/shared/hermes-agent/*` verify behavior and layout, using focused source-text assertions where they check stable build or runtime contract strings.
- The workspace pod owns Podman port publishing, while the wrapper keeps the published host port bound to `127.0.0.1`.
- The run wrapper treats the container as ready when it is running and stable before attach; the browser opener waits for the published dashboard URL rather than probing Hermes internals.
- The `.dockerignore` file follows the OpenCode template ignore policy instead of a Containerfile-only allowlist.

## Design Constraints

- Config belongs in config files, not in scripts or shell libraries.
- The host base path is rooted at `${HOME}`.
- The host docs dirname is `hermes-agent-docs`.
- The container Hermes data path is `/opt/data`, matching the official image.
- The container docs path is `/workspace/docs`.
- Containers use `--userns keep-id`; root-launched wrappers repair mounted host path ownership before container startup.
- The wrapper rejects symlinked managed host paths before root ownership repair.
- Reused dashboard pods must expose exactly one loopback publish binding.
- Reused pods with random Podman infra container names are renamed to the canonical infrastructure name before reuse continues.
- Interactive CLI work stays separate from the persistent gateway process so gateway and dashboard lifecycles remain independent from terminal sessions.
- Setup and state bootstrapping stay delegated to the inherited upstream Hermes entrypoint.
- Scripts should stay small and defer shared behavior to `scripts/shared/hermes-agent/common.sh`.
- Startup failures should expose enough container state and recent logs to diagnose dashboard boot problems directly from wrapper output.
- Test helpers stay in the test tree under `tests/shared/shared/` so the repo keeps a consistent family layout.
