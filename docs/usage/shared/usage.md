# Hermes Agent Usage

This repo builds a small local image derived from the official Hermes Agent container, then runs per-workspace gateway and dashboard pods with all repo-owned settings kept in `config/agent/shared/hermes-agent-settings-shared.conf`.

The shared scripts are intended to work on both macOS and Linux hosts.

## Commands

- Build the image: `scripts/agent/shared/hermes-agent-build`
- Start a configured workspace: `scripts/agent/shared/hermes-agent-run`
- Open nushell in a running workspace gateway container: `scripts/agent/shared/hermes-agent-shell`

Command forms:

- `scripts/agent/shared/hermes-agent-run`
  - no args: show the workspace picker
  - one arg: use that workspace directly
- `scripts/agent/shared/hermes-agent-shell`
  - no args: show the workspace picker, then open `nu`
  - one arg: use that workspace directly, then open `nu`
  - extra args after the workspace: run the explicit command inside that workspace gateway container

Examples:

- `scripts/agent/shared/hermes-agent-run ezirius`
- `scripts/agent/shared/hermes-agent-shell ezirius`
- `scripts/agent/shared/hermes-agent-shell ezirius auth list`

## Host Behavior

The dashboard is opened on the host after the container starts.

The image build uses the official upstream Hermes Agent image and only layers local customizations on top. The official image owns Hermes, the frontend assets, bash, git, and the upstream entrypoint; this repo currently adds `nushell`.

- `HERMES_AGENT_OPEN_COMMAND="auto"` resolves a supported opener for the current host.
- On macOS, the wrapper prefers `open` when it is available.
- On Linux, the wrapper prefers `xdg-open` when it is available.
- If no supported opener exists, or the opener fails, the container still starts and the script still attaches to the Hermes CLI.
- The dashboard container starts Hermes with `--host 0.0.0.0` so the published host port can reach the dashboard.
- The wrapper binds the published dashboard port to `127.0.0.1` on the host to keep that insecure dashboard local to the developer machine by default.
- Risk: Hermes marks this mode insecure because the dashboard exposes API keys and config without robust authentication. Only run this wrapper on a trusted local host and do not re-publish or forward the mapped loopback port to untrusted networks.

## Host To Container Mappings

For a selected workspace named `WORKSPACE`, the run script creates these host paths under `HERMES_AGENT_BASE_PATH`:

- Host home path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/hermes-agent-home`
- Host workspace path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/hermes-agent-general`

The gateway and dashboard pods each hold one container. Both containers use these mappings:

- Host home path -> `/opt/data`
- Host workspace path -> `/workspace/general`

The dashboard port is derived from `HERMES_AGENT_DASHBOARD_PORT` plus the selected workspace offset from `HERMES_AGENT_WORKSPACES`.

## Image Discovery

Local Podman images may appear as either:

- `hermes-agent-...`
- `localhost/hermes-agent-...`

The wrapper normalizes both forms before matching the newest local Hermes Agent image for `hermes-agent-run`.

## Workspace Safety

When `hermes-agent-run` starts replacement pods for a workspace, it does not remove existing workspace pods or containers until the replacement gateway and dashboard containers have started successfully.

If the selected workspace already has matching gateway and dashboard pods and containers for the newest image, the wrapper reuses them. If a matching container is stopped, the wrapper starts it before attaching to the Hermes CLI in the gateway container.

If an exact matching gateway or dashboard container dies before attach, the wrapper removes the pod pair and recreates them once with the current dashboard publish contract before giving up.

When startup still fails, the wrapper prints a short container state summary plus recent container logs so the failure is actionable without extra Podman commands.

## Config Rules

- Keep repo-owned settings in `config/agent/shared/hermes-agent-settings-shared.conf`.
- Do not hard-code workspace names, offsets, paths, or ports in scripts or shell libraries.
- Keep `HERMES_AGENT_CONTAINER_WORKSPACE` fixed at `/workspace/general` so only host-side workspace names vary.
- Keep `HERMES_AGENT_WORKSPACES` entries in `name:offset` format with numeric offsets.
