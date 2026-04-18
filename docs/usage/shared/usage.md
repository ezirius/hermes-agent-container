# Hermes Agent Usage

This repo builds and runs a local Hermes Agent container with all repo-owned settings kept in `config/agent/shared/hermes-agent-settings-shared.conf`.

The shared scripts are intended to work on both macOS and Linux hosts.

## Commands

- Build the image: `scripts/agent/shared/hermes-agent-build`
- Start a configured workspace: `scripts/agent/shared/hermes-agent-run`
- Open a shell in a running workspace container: `scripts/agent/shared/hermes-agent-shell`

Command forms:

- `scripts/agent/shared/hermes-agent-run`
  - no args: show the workspace picker
  - one arg: use that workspace directly
- `scripts/agent/shared/hermes-agent-shell`
  - no args: show the workspace picker, then open `bash`
  - one arg: use that workspace directly, then open `bash`
  - extra args after the workspace: run `hermes <args...>` inside that workspace

Examples:

- `scripts/agent/shared/hermes-agent-run ezirius`
- `scripts/agent/shared/hermes-agent-shell ezirius`
- `scripts/agent/shared/hermes-agent-shell ezirius auth list`

## Host Behavior

The dashboard is opened on the host after the container starts.

The image build runs the upstream Hermes frontend build and carries the resulting `hermes_cli/web_dist` assets into the runtime image, so the dashboard route serves the bundled portal files.

- `HERMES_AGENT_OPEN_COMMAND="auto"` resolves a supported opener for the current host.
- On macOS, the wrapper prefers `open` when it is available.
- On Linux, the wrapper prefers `xdg-open` when it is available.
- If no supported opener exists, or the opener fails, the container still starts and the script still attaches to the Hermes CLI.
- The container starts Hermes with `--host 0.0.0.0 --insecure` so the published host port can reach the dashboard.
- The wrapper binds the published dashboard port to `127.0.0.1` on the host to keep that insecure dashboard local to the developer machine by default.
- Without the bundled frontend assets, Hermes cannot serve the portal files and falls back to its missing-frontend error path.
- Risk: Hermes marks this mode insecure because the dashboard exposes API keys and config without robust authentication. Only run this wrapper on a trusted local host and do not re-publish or forward the mapped loopback port to untrusted networks.

## Host To Container Mappings

For a selected workspace named `WORKSPACE`, the run script creates these host paths under `HERMES_AGENT_BASE_PATH`:

- Host home path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/hermes-agent-home`
- Host workspace path: `${HOME}/Documents/Ezirius/.applications-data/.containers-artificial-intelligence/WORKSPACE/hermes-agent-general`

The container mappings are:

- Host home path -> `/home/hermes-agent`
- Host workspace path -> `/workspace/general`

The dashboard port is derived from `HERMES_AGENT_DASHBOARD_PORT` plus the selected workspace offset from `HERMES_AGENT_WORKSPACES`.

## Image Discovery

Local Podman images may appear as either:

- `hermes-agent-...`
- `localhost/hermes-agent-...`

The wrapper normalizes both forms before matching the newest local Hermes Agent image for `hermes-agent-run`.

## Workspace Safety

When `hermes-agent-run` starts a replacement container for a workspace, it does not remove existing workspace containers until the replacement container has started successfully.

If the selected workspace already has a matching container for the newest image, the wrapper reuses it. If that matching container is stopped, the wrapper starts it before attaching to the Hermes CLI.

If an exact matching container dies before attach, the wrapper removes it and recreates it once with the current dashboard publish contract before giving up.

When startup still fails, the wrapper prints a short container state summary plus recent container logs so the failure is actionable without extra Podman commands.

## Config Rules

- Keep repo-owned settings in `config/agent/shared/hermes-agent-settings-shared.conf`.
- Do not hard-code workspace names, offsets, paths, or ports in scripts or shell libraries.
- Keep `HERMES_AGENT_CONTAINER_WORKSPACE` fixed at `/workspace/general` so only host-side workspace names vary.
- Keep `HERMES_AGENT_WORKSPACES` entries in `name:offset` format with numeric offsets.
