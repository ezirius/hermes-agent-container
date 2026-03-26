# Hermes Agent container usage

## Basic flow

1. Create the workspace directory and copy or create the env file:
   `mkdir -p "$HERMES_BASE_ROOT/ezirius" && touch "$HERMES_BASE_ROOT/ezirius/.env"`
2. Add your Hermes provider credentials to the workspace `.env`
3. Start Hermes for a workspace:
   `./scripts/shared/bootstrap ezirius`

`bootstrap` runs `hermes-build`, then `hermes-upgrade`, then `hermes-start`, then `hermes-open`.

You pass a workspace name such as `ezirius`.

Workspace names resolve under `HERMES_BASE_ROOT`.

## Environment and state

- upstream Hermes stores its local data in `~/.hermes/`
- this wrapper maps each workspace root to persistent Hermes state inside the container
- `.env` and optional `config.yaml` live at the workspace root
- the runtime state directories are created automatically
- Hermes runs with `/workspace` mapped to `<workspace-root>/workspace`

## Upstream source selection

- `HERMES_REPO_URL`
  - upstream Hermes repo used during image build
  - default: `https://github.com/NousResearch/hermes-agent.git`
- `HERMES_REF`
  - upstream branch or tag to build from
  - default: `latest-release`
  - `latest-release` resolves the latest upstream Hermes release tag and fails clearly if no upstream release entry is available
  - `hermes-upgrade` is the command that re-checks this and rebuilds when a newer upstream release appears
  - if you set an explicit tag or branch here, upgrade compares that literal ref only and does not poll for branch-head movement
- `HERMES_GITHUB_API_BASE`
  - GitHub API base used to resolve `latest-release`
  - default: `https://api.github.com`

## Runtime model

- Hermes itself runs in a persistent container
- the workspace root is mounted so memory, sessions, skills, logs, and other state persist across container restarts
- Hermes can safely use its normal `local` backend inside this container, so terminal work runs inside the Hermes container itself
- if you want Hermes to use Docker as an internal execution backend too, you must separately mount a runtime socket and CLI support into this container

## Commands

- `./scripts/shared/hermes-build`
- `./scripts/shared/hermes-upgrade`
- `./scripts/shared/hermes-start <workspace-name>`
- `./scripts/shared/hermes-open <workspace-name> [hermes args...]`
- `./scripts/shared/hermes-status <workspace-name>`
- `./scripts/shared/hermes-logs <workspace-name> [podman args...]`
- `./scripts/shared/hermes-shell <workspace-name>`
- `./scripts/shared/hermes-stop <workspace-name>`
- `./scripts/shared/hermes-remove <workspace-name>`

## Notes

- Hermes upstream normal install is host-based, not container-first; this repo is a thin wrapper around that upstream model
- `hermes-build` takes no positional arguments
- `hermes-upgrade` takes no positional arguments and rebuilds only when the requested upstream source changed
- workspace-scoped commands require exactly one workspace name, except `hermes-open` and `hermes-logs`, which accept optional extra arguments after the workspace
