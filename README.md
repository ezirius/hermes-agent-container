# Hermes Agent container wrapper

This repo provides a thin local container wrapper for upstream Hermes Agent.

It keeps the design close to upstream:

- Hermes is still installed from upstream source
- persistent agent data lives in a host-mounted workspace root
- the wrapper only handles image lifecycle, workspace selection, and container orchestration

By default, the image resolves the latest upstream GitHub release and builds from that released source tag.

## Layout

- `config/containers/` contains the Dockerfile used for the shared image
- `docs/shared/usage.md` contains workflow notes
- `lib/shell/common.sh` contains shared shell helpers
- `scripts/shared/` contains the shared bootstrap, build, upgrade, start, open, status, shell, logs, stop, and remove commands
- `tests/shared/` contains aggregate, helper, argument-contract, ref-resolution, and runtime checks

## Quick start

1. Create the workspace directory and env file:

   `mkdir -p "$HOME/Documents/Ezirius/.applications-data/.hermes-agent/ezirius" && touch "$HOME/Documents/Ezirius/.applications-data/.hermes-agent/ezirius/.env"`

2. Add at least one Hermes LLM provider key to the workspace `.env`.

   The wrapper passes this workspace `.env` into the container at start time, so provider keys and Hermes environment overrides are available inside Hermes.

3. Start Hermes:

   `./scripts/shared/bootstrap ezirius`

`bootstrap` builds the shared local Hermes image from the latest upstream GitHub release by default, upgrades it if the requested upstream source changed, starts the container for the selected workspace, and then opens Hermes interactively.

Host requirements for the base setup are intentionally small:

- Podman
- network access for release resolution and image builds
- a writable host base directory under `~/Documents/Ezirius/.applications-data/.hermes-agent`

The Hermes gateway and CLI themselves do not need to be installed on the host.

Each workspace lives under `HERMES_BASE_ROOT` with this host layout:

```text
<workspace-root>/
├── .env
├── hermes-home/
│   ├── config.yaml     # optional
│   ├── cron/
│   ├── sessions/
│   ├── logs/
│   ├── memories/
│   ├── skills/
│   ├── pairing/
│   ├── hooks/
│   ├── image_cache/
│   ├── audio_cache/
│   └── whatsapp/
│       └── session/
├── workspace/
└── ...your own workspace files...
```

The scripts create the workspace root and these data directories automatically. You still need to create the workspace `.env` file yourself. Hermes runs with `/data` mapped to `<workspace-root>/hermes-home` and `/workspace` mapped to `<workspace-root>/workspace`.

## Workflow

- `hermes-build` ensures the shared image exists
- `hermes-upgrade` rebuilds the shared image only when the requested upstream source changed
- `hermes-start` starts or reuses the local Hermes container only
- `hermes-open` runs the Hermes CLI inside the running container
- `bootstrap` performs the full `build -> upgrade -> start -> open` flow
- by default, `hermes-build` and `hermes-upgrade` resolve the latest upstream Hermes release tag and fail clearly if no upstream release is available
- in practice, repeated `bootstrap` runs are what keep you on the latest upstream release: `hermes-build` is no-op when the image exists, while `hermes-upgrade` re-checks the latest GitHub release and rebuilds only when it changed
- if you set `HERMES_REF` to an explicit tag or branch, `hermes-upgrade` compares that literal ref only; it does not poll for branch-head movement

Scripts that take no positional arguments reject them explicitly. Workspace-scoped scripts require exactly one workspace name, except `hermes-open` and `hermes-logs`, which accept a workspace name plus optional extra arguments.

This repo containerises Hermes itself. Inside the container, Hermes can use its normal `local` terminal backend safely because the container is the execution boundary. In the current design that means Hermes runs commands inside its own long-lived container rather than spawning nested Docker sandboxes. If you want Hermes to use Docker as an internal execution backend too, you must separately provide a container runtime socket into the Hermes container.

## Useful commands

- `./scripts/shared/hermes-build`
- `./scripts/shared/hermes-upgrade`
- `./scripts/shared/hermes-start <workspace-name>`
- `./scripts/shared/hermes-open <workspace-name> [hermes args...]`
- `./scripts/shared/hermes-status <workspace-name>`
- `./scripts/shared/hermes-logs <workspace-name> [podman args...]`
- `./scripts/shared/hermes-shell <workspace-name>`
- `./scripts/shared/hermes-stop <workspace-name>`
- `./scripts/shared/hermes-remove <workspace-name>`

## GitHub setup on Maldoria

This repo is configured to use the repo-specific SSH alias:

- `github-maldoria-hermes-agent-container`

If `git push` says it cannot resolve that hostname, the repo remote is already correct but your host SSH config has not been materialised yet. On Maldoria, run the managed setup from inside this repo:

`/workspace/Development/OpenCode/installations-configurations/scripts/macos/git-configure`

That workflow writes the matching `Host github-maldoria-hermes-agent-container` block into `~/.ssh/config`, exports the public key file `~/.ssh/maldoria-github-ezirius-hermes-agent-container.pub`, and points the repo remote at the alias.

After that, test SSH auth with:

`ssh -T git@github-maldoria-hermes-agent-container`

## Verification

Run `tests/shared/test-all.sh` to execute the repository shell checks in one command.
