# Hermes Agent Usage

This repo builds a small local image derived from the official Hermes Agent container, then runs one per-workspace runtime pod with all repo-owned settings kept in `configs/shared/hermes-agent/hermes-agent-settings.conf`.

The shared scripts are intended to work on both macOS and Linux hosts.

## Commands

- Build the image: `scripts/shared/hermes-agent/hermes-agent-build`
- Start a configured workspace: `scripts/shared/hermes-agent/hermes-agent-run`
- Open nushell in an ephemeral workspace CLI container: `scripts/shared/hermes-agent/hermes-agent-shell`

Command forms:

- `scripts/shared/hermes-agent/hermes-agent-build`
  - no args: build the latest local Hermes image from the saved config
  - `--help`: print `Usage: scripts/shared/hermes-agent/hermes-agent-build`
  - any other args fail with `This script takes no arguments. See --help.`
- `scripts/shared/hermes-agent/hermes-agent-run`
  - no args: show the workspace picker
  - one arg: use that workspace directly
  - `--help`: print `Usage: scripts/shared/hermes-agent/hermes-agent-run [workspace]`
  - unsupported options fail before workspace validation with `Unsupported option: ... See --help.`
  - too many args fail with `This script takes zero or one argument: [workspace]. See --help.`
- `scripts/shared/hermes-agent/hermes-agent-shell`
  - no args: show the workspace picker, then open `nu`
  - one arg: use that workspace directly, then open `nu`
  - extra args after the workspace: run the explicit command inside an ephemeral CLI container for that workspace
  - `--help`: print `Usage: scripts/shared/hermes-agent/hermes-agent-shell [workspace] [command...]`
  - unsupported options fail before workspace validation with `Unsupported option: ... See --help.`

Examples:

- `scripts/shared/hermes-agent/hermes-agent-run ezirius`
- `scripts/shared/hermes-agent/hermes-agent-shell ezirius`
- `scripts/shared/hermes-agent/hermes-agent-shell ezirius hermes auth list`

## Host Behavior

The dashboard is opened on the host after the container starts.

`hermes-agent-run` also prints a concise success summary before it attaches the ephemeral CLI container:

- `Started workspace: <workspace>`
- `Dashboard: http://localhost:<port>`

The image build uses the official upstream Hermes Agent image and only layers local customizations on top. The official image owns Hermes, the frontend assets, bash, git, and the upstream entrypoint; this repo prefers the distro `nushell` package first and otherwise uses the configured fallback Nushell binary version and checksums.

`hermes-agent-build` and `hermes-agent-run` check the latest stable Hermes Agent release and the configured fallback Nushell release. If newer stable versions exist, they print `Warning: newer stable Hermes Agent version available: ...` or `Warning: newer stable Nushell fallback version available: ...` and continue with the saved config values.

- On macOS, the wrapper prefers `open` when it is available.
- On Linux, the wrapper prefers `xdg-open` and falls back to `gio open` when `xdg-open` fails.
- If no supported opener exists, or the opener fails, the persistent runtime still starts and the script still opens an ephemeral Hermes CLI container.
- The dashboard container starts Hermes with `--host 0.0.0.0` so the published host port can reach the dashboard.
- The wrapper binds the published dashboard port to `127.0.0.1` on the host to keep that insecure dashboard local to the developer machine by default.
- Risk: Hermes marks this mode insecure because the dashboard exposes API keys and config without robust authentication. Only run this wrapper on a trusted local host and do not re-publish or forward the mapped loopback port to untrusted networks.

## Host To Container Mappings

For a selected workspace named `WORKSPACE`, the run script creates these host paths under `HERMES_AGENT_BASE_PATH`:

- Host home path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/hermes-agent-home`
- Host docs path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/hermes-agent-docs`

The persistent workspace pod holds gateway and dashboard role containers. Those containers use these mappings:

- Host home path -> `/opt/data`
- Host docs path -> `/workspace/docs`

Interactive CLI containers created by `hermes-agent-run` and `hermes-agent-shell` use the same mappings and `--workdir /workspace/docs`, but they stay outside the workspace pod and do not publish ports. They use the exact name `<image-name>-<workspace>-cli`. The wrapper removes stale stopped same-workspace exact-name containers before launch and fails clearly when that exact name is already active or belongs to a different workspace mount.

Containers launched by normal users are created with `--userns keep-id` so mounted workspace docs paths follow the invoking host user. If the wrapper is launched as root, it repairs the host home and docs directory ownership before starting containers and skips rootless `keep-id` mode.

The dashboard port is derived from `HERMES_AGENT_DASHBOARD_PORT` plus the family workspace offset rule: `ezirius` gets `10000`, `nala` gets `20000`, and every other discovered workspace gets `60000`. Workspaces whose derived port would fall outside `1..65535` are skipped during discovery instead of being offered and then rejected later.

Workspace pod names use the OpenCode-derived `<image-name>-<workspace>` order. Role containers inside each pod use `<image-name>-<workspace>-gateway` and `<image-name>-<workspace>-dashboard`, and the Podman infra container uses `<image-name>-<workspace>-infrastructure`.

Setup and Hermes state bootstrapping are delegated to the upstream Hermes entrypoint inherited by the derived image.

## Image Discovery

Local Podman images may appear as either:

- `hermes-agent-...`
- `localhost/hermes-agent-...`

The wrapper normalizes both forms before matching the newest local Hermes Agent image for `hermes-agent-run`.

## Workspace Safety

When `hermes-agent-run` starts replacement pods for a workspace, it does not remove existing workspace pods or containers until the replacement container has started successfully.

Exact matching pods with the wrong dashboard publish contract are removed before same-name recreation because Podman cannot create a replacement pod with the same name while the old pod still exists.

If the selected workspace already has a matching pod and gateway container for the newest image, the wrapper reuses them. If the matching gateway container is stopped, the wrapper starts it before opening the ephemeral Hermes CLI container.

When reusing an exact matching pod, the wrapper renames Podman's generated infra container to the canonical `<image-name>-<workspace>-infrastructure` name if needed.

If an exact matching container dies before attach, the wrapper removes the pod and recreates it once with the current dashboard publish contract before giving up.

The wrapper waits for the published dashboard URL before opening the browser, and it only opens the browser when the dashboard runtime was created or started by that invocation.

When startup still fails, the wrapper prints a short container state summary plus recent container logs so the failure is actionable without extra Podman commands.

## Config Rules

- Keep repo-owned settings in `configs/shared/hermes-agent/hermes-agent-settings.conf`.
- Use the family offset rule in shared logic: `ezirius` gets `10000`, `nala` gets `20000`, and every other discovered workspace gets `60000`.
- Keep `HERMES_AGENT_DASHBOARD_PORT` low enough that the configured offset rule still produces valid published ports for the workspaces you expect to expose.
- Keep `HERMES_AGENT_CONTAINER_DOCS` fixed at `/workspace/docs` so only host-side workspace names vary.
- Treat real workspace directories under `HERMES_AGENT_BASE_PATH` as the source of truth for valid workspace names.
- Host dirname settings must be single safe directory names, not paths.
