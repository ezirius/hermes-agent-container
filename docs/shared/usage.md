# Hermes Agent container usage

## Basic flow

1. Create the workspace directory and copy or create the env file:
   `mkdir -p "$HERMES_BASE_ROOT/ezirius/hermes-home" && touch "$HERMES_BASE_ROOT/ezirius/hermes-home/.env"`
2. Add your Hermes provider credentials to `hermes-home/.env`
3. Start Hermes for a workspace:
   `./scripts/shared/bootstrap ezirius`

`bootstrap` runs `hermes-build`, then `hermes-upgrade`, then `hermes-start`, then `hermes-open`.

`hermes-start` starts the Hermes Gateway inside the container. `hermes-open` then opens the Hermes CLI in that same running container.

Common forwarded `bootstrap` examples:

- `./scripts/shared/bootstrap ezirius setup`
- `./scripts/shared/bootstrap ezirius model`
- `./scripts/shared/bootstrap ezirius doctor`

You pass a workspace name such as `ezirius`.

Workspace names resolve under `HERMES_BASE_ROOT`.

## Environment and state

- upstream Hermes stores its local data in `~/.hermes/`
- this wrapper maps `<workspace-root>/hermes-home` to persistent Hermes state inside the container
- `.env` and optional `config.yaml` live under `<workspace-root>/hermes-home`
- the runtime state directories are created automatically under `hermes-home`
- Hermes runs with `/data` mapped to `<workspace-root>/hermes-home`
- Hermes runs with `/workspace` mapped to `<workspace-root>/workspace`
- `hermes-home/.env` is passed into the container at start time so provider keys and Hermes env overrides are available inside Hermes
- the image includes Matrix support (`matrix-nio[e2e]` plus `libolm`) so Matrix messaging and encrypted Matrix rooms can work inside the container
- the image build also applies a small local Matrix patch so failed initial syncs are surfaced clearly instead of being logged as connected

## Upstream source selection

- `HERMES_REPO_URL`
  - upstream Hermes repo used during image build
  - default: `https://github.com/NousResearch/hermes-agent.git`
- `HERMES_REF`
  - upstream branch or tag to build from
  - default: `latest-release`
  - `latest-release` resolves the latest upstream Hermes release tag and fails clearly if no upstream release entry is available
  - `hermes-upgrade` is the command that re-checks this and rebuilds when a newer upstream release appears or when the local wrapper build fingerprint changes
  - if you set an explicit tag or branch here, upgrade compares that literal ref only and does not poll for branch-head movement
- `HERMES_GITHUB_API_BASE`
  - GitHub API base used to resolve `latest-release`
  - default: `https://api.github.com`

The local wrapper build fingerprint covers the image recipe files under `config/containers/` and `config/patches/`. That means local image-behaviour changes such as the Matrix sync diagnostics patch trigger a rebuild automatically on the next `hermes-upgrade` or `bootstrap`, even if the upstream Hermes ref stays the same.

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

Common `hermes-open` examples:

- `./scripts/shared/hermes-open ezirius setup`
- `./scripts/shared/hermes-open ezirius model`
- `./scripts/shared/hermes-open ezirius tools`
- `./scripts/shared/hermes-open ezirius doctor`
- `./scripts/shared/hermes-open ezirius gateway`
- `./scripts/shared/hermes-open ezirius chat`

Common `hermes-logs` examples:

- `./scripts/shared/hermes-logs ezirius -f`
- `./scripts/shared/hermes-logs ezirius --tail 100`
- `./scripts/shared/hermes-logs ezirius --since 10m`

All wrapper scripts support `--help` and document their argument contracts there.

## Notes

- Hermes upstream normal install is host-based, not container-first; this repo is a thin wrapper around that upstream model
- `hermes-build` takes no positional arguments
- `hermes-upgrade` takes no positional arguments and rebuilds only when the requested upstream source changed
- workspace-scoped commands require exactly one workspace name, except `hermes-open` and `hermes-logs`, which accept optional extra arguments after the workspace
