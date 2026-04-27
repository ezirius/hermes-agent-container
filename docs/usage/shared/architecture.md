# Hermes Agent Architecture

This repo keeps a small wrapper around the official Hermes Agent container with three responsibility layers:

- `config/agent/shared/hermes-agent-settings-shared.conf` owns runtime and build configuration.
- `lib/shell/shared/common.sh` owns shared shell helpers for config loading, workspace parsing, container naming, and container lookup.
- `scripts/agent/shared/*` are thin entrypoints for build, run, and shell flows.

## Layout

- `config/containers/shared/Containerfile` derives from the official upstream `nousresearch/hermes-agent` image and adds repo-local customization packages.
- `config/containers/shared/Containerfile` currently installs `nushell` from the official Nushell Debian package source; the official image owns Hermes, bash, git, frontend assets, and the upstream entrypoint.
- The derived image starts as root so the upstream entrypoint can drop privileges to the Hermes runtime user after bootstrapping mounted state.
- `lib/shell/shared/common.sh` is the only shared shell library path.
- `scripts/agent/shared/hermes-agent-build` builds an `arm64` image from config, then retags it with a 12-character image-id suffix.
- `scripts/agent/shared/hermes-agent-run` starts one selected workspace pod with gateway and dashboard role containers, mounts host paths into them, recreates a poisoned exact-match pod/container once, and prints startup diagnostics on failure.
- Hermes pod names follow `<image-name>-<workspace>`; role containers inside the pod use `<image-name>-<workspace>-gateway` and `<image-name>-<workspace>-dashboard`, and infra containers use `<image-name>-<workspace>-infrastructure`.
- `scripts/agent/shared/hermes-agent-run` and `scripts/agent/shared/hermes-agent-shell` create interactive CLI containers first as the temporary exact name `<image-name>-<workspace>-cli`, then rename them to `<image-name>-<workspace>-cli-<12char-container-id>` before attach.
- Ephemeral CLI containers share the same `/opt/data` and `/workspace/general` mounts as the persistent runtime containers, but they do not join the workspace pod and do not publish ports.
- The wrapper clears stale same-workspace exact-name CLI containers before launch, reclaims stale renamed same-workspace CLI session containers from interrupted runs, and fails with wrapper-owned errors when temporary exact-name or renamed same-workspace containers are still active.
- `tests/agent/shared/*` verify behavior and layout, using focused source-text assertions where they check stable build or runtime contract strings.
- The workspace pod owns Podman port publishing, while the wrapper keeps the published host port bound to `127.0.0.1`.
- The run wrapper treats the container as ready when it is running and stable before attach; the browser opener waits for the published dashboard URL rather than probing Hermes internals.
- The `.dockerignore` file follows the OpenCode template ignore policy instead of a Containerfile-only allowlist.

## Design Constraints

- Config belongs in config files, not in scripts or shell libraries.
- The host base path is rooted at `${HOME}`.
- The host workspace dirname is `hermes-agent-general`.
- The container Hermes data path is `/opt/data`, matching the official image.
- The container workspace path is `/workspace/general`.
- Containers use `--userns keep-id`; root-launched wrappers repair mounted host path ownership before container startup.
- The wrapper rejects symlinked managed host paths before root ownership repair.
- Reused dashboard pods must expose exactly one loopback publish binding.
- Reused pods with random Podman infra container names are renamed to the canonical infrastructure name before reuse continues.
- Interactive CLI work stays separate from the persistent gateway process so gateway and dashboard lifecycles remain independent from terminal sessions.
- Setup and state bootstrapping stay delegated to the inherited upstream Hermes entrypoint.
- Scripts should stay small and defer shared behavior to `lib/shell/shared/common.sh`.
- Startup failures should expose enough container state and recent logs to diagnose dashboard boot problems directly from wrapper output.
- Test helpers stay in the test tree under `tests/agent/shared/` so the repo keeps a consistent 3-level path shape.
