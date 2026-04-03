# Hermes Agent container wrapper

This repo is a multi-workspace wrapper around the latest upstream Hermes Agent release.

Upstream already provides the official single-container Docker image and Docker workflow. This repo exists to add:

- named workspace containers
- separate persistent Hermes state and project workspace mounts
- release tracking with local rebuild fingerprinting
- Podman-first lifecycle commands and macOS TTY handling

By default, the image resolves the latest upstream GitHub release and builds from that release tag.

## When to use this wrapper

Use upstream Docker directly when you want one standard Hermes container with upstream defaults.

Use this wrapper when you want:

- multiple named workspaces on one host
- a dedicated `/workspace` mount alongside Hermes state
- wrapper commands for build, upgrade, start, open, logs, and status
- Podman-first operation

## Layout

- `config/containers/` contains the shared image Dockerfile
- `config/patches/` contains wrapper-specific upstream patching
- `docs/shared/usage.md` contains workflow notes
- `lib/shell/common.sh` contains shared shell helpers
- `scripts/shared/` contains the wrapper commands
- `tests/shared/` contains the shell test suite

## Quick start

1. Create the workspace directory and env file:

   `mkdir -p "$HOME/Documents/Ezirius/.applications-data/.hermes-agent/ezirius/hermes-home" && touch "$HOME/Documents/Ezirius/.applications-data/.hermes-agent/ezirius/hermes-home/.env"`

2. Put Hermes secrets such as provider keys in `hermes-home/.env`.

3. Put non-secret configuration such as model selection, base URLs, provider routing, MCP settings, and other runtime config in `hermes-home/config.yaml`.

4. Start Hermes:

   `./scripts/shared/bootstrap ezirius`

`bootstrap` builds the shared local Hermes image from the latest upstream release by default, upgrades it if the requested upstream source changed, starts the Hermes Gateway container for the selected workspace, and then opens Hermes interactively.

Common forwarded `bootstrap` examples:

- `./scripts/shared/bootstrap ezirius setup`
- `./scripts/shared/bootstrap ezirius model`
- `./scripts/shared/bootstrap ezirius doctor`

Common `bootstrap-test` examples:

- `./scripts/shared/bootstrap-test`
- `./scripts/shared/bootstrap-test doctor`

Host requirements:

- Podman
- network access for release resolution and image builds
- a writable host base directory under `~/Documents/Ezirius/.applications-data/.hermes-agent`

The Hermes gateway and CLI do not need to be installed on the host.

## Workspace layout

Each workspace lives under `HERMES_BASE_ROOT` with this host layout:

```text
<workspace-root>/
├── hermes-home/
│   ├── .env
│   ├── config.yaml
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
└── workspace/
    └── ...your own workspace files...
```

The scripts create the workspace root and runtime directories automatically. Hermes runs with `/opt/data` mapped to `<workspace-root>/hermes-home` and `/workspace` mapped to `<workspace-root>/workspace`.

On first run, the wrapper seeds `.env`, `config.yaml`, `SOUL.md`, and `AGENTS.md` into `hermes-home` when they are missing. The wrapper also patches upstream context discovery so the operative `AGENTS.md` is the host-backed `/opt/data/AGENTS.md`, not only the internal upstream checkout copy, without suppressing other project-local context files under `/workspace`.

In practice that means:

- editing `hermes-home/.env` or `hermes-home/config.yaml` does not require an image rebuild
- stopping and starting the workspace container is enough for Hermes to read updated config
- rebuilding is only needed when the wrapper image recipe changes or when you want a newer upstream release

## Wrapper workspaces versus upstream profiles

These are not the same thing.

- wrapper workspace: this repo’s host-level unit of isolation; one named container, one `hermes-home`, one mounted project workspace
- upstream profile: Hermes’s internal isolation layer inside one Hermes home

Default recommendation:
- use one wrapper workspace with the upstream default profile
- use upstream profiles inside a wrapper workspace only when you explicitly want a second isolation layer

## Workflow

- `hermes-build` ensures the shared image exists
- `hermes-upgrade` rebuilds the shared image when the requested upstream release changed or when the local wrapper image recipe changed
- `hermes-start` starts or reuses the local Hermes Gateway container only
- `hermes-open` runs the Hermes CLI in a transient interactive container that shares the workspace mounts of the running gateway container
- `bootstrap` performs the full `build -> upgrade -> start -> open` flow
- `bootstrap-test` performs a destructive full fresh test-lane build and open against the dedicated `test` workspace and `hermes-agent-local-test` image
- by default, `hermes-build` and `hermes-upgrade` resolve the latest upstream Hermes release tag and fail clearly if no upstream release is available
- repeated `bootstrap` runs keep the wrapper aligned with the latest upstream release and the current wrapper image recipe
- if you set `HERMES_REF` to an explicit tag or branch, `hermes-upgrade` compares that literal ref only
- the gateway container is created with Podman restart policy `unless-stopped`
- on macOS hosts, interactive `hermes-open` and `hermes-shell` calls can wrap Podman TTY allocation with `script`

Container lifecycle details:

- if the workspace container already exists and is stopped on the same image, `hermes-start` uses `podman start`
- if the image changed, `hermes-start` removes the old container and recreates it on the new image
- because Hermes reads `/opt/data/.env` and `/opt/data/config.yaml` on process start, a plain stop/start is enough for config changes in those files
- for image-recipe changes, the normal path is `hermes-upgrade` then `hermes-start <workspace>`; you do not need `hermes-remove` unless you explicitly want manual container cleanup first

The local wrapper build fingerprint covers all non-generated image recipe files under `config/containers/` and `config/patches/`. That means local image-behaviour changes such as the entrypoint, mautrix migration patch, or compatibility-link setup trigger a rebuild automatically on the next `hermes-upgrade` or `bootstrap`, even when the upstream release tag has not changed.

## MCP and gateway capabilities

Upstream now includes `hermes mcp serve`, official Docker support, profiles, and broader messaging-platform support.

Within this wrapper, those capabilities are available through the same transient CLI flow. For example:

- `./scripts/shared/hermes-open ezirius mcp serve`
- `./scripts/shared/hermes-open ezirius gateway`
- `./scripts/shared/hermes-open ezirius chat`

This wrapper does not add separate MCP orchestration; it simply exposes the latest-release Hermes CLI inside the workspace container model.

The image now follows an upstream-style entrypoint model: the container bootstraps state under `/opt/data` and then runs Hermes with the forwarded command.

## Matrix

The image includes Matrix support so Matrix and encrypted Matrix rooms can work inside the container. The wrapper now applies a local mautrix migration patch during image build, replacing the upstream matrix-nio adapter path inside the image with a wrapper-managed mautrix-based implementation.

For Matrix state persistence:

- upstream Hermes resolves Matrix storage through `HERMES_HOME`
- the wrapper also links `/home/hermes/.hermes` to `/opt/data` as a compatibility fallback for any remaining hardcoded `~/.hermes` paths

### Matrix validation on the real Podman host

This repository can validate the wrapper patching logic locally, but full Matrix verification still requires a real image build and a live homeserver test from the actual Podman host.

Recommended validation sequence:

1. Rebuild the shared image:

   `./scripts/shared/hermes-build`

2. Start the workspace container:

   `./scripts/shared/hermes-start ezirius`

3. Open a shell inside the image-backed workspace and inspect the patched upstream tree:

   `./scripts/shared/hermes-shell ezirius`

   Then verify:

   - `/home/hermes/hermes-agent/gateway/platforms/matrix.py` contains mautrix imports
   - `/home/hermes/hermes-agent/pyproject.toml` no longer depends on `matrix-nio[e2e]`
   - `python3 -m py_compile /home/hermes/hermes-agent/gateway/platforms/matrix.py` succeeds

4. Configure Matrix credentials in `hermes-home/.env` and restart the container.

5. Run encrypted smoke tests against the real homeserver:

   - encrypted DM text in -> Hermes reply out
   - encrypted group-room text in -> Hermes reply out
   - encrypted threaded reply in -> threaded reply out
   - encrypted voice note in -> STT and Hermes reply
   - encrypted image in -> media path works
   - encrypted file in -> document path works
   - encrypted video in -> media path works
   - device appears in Element/Element X and can be verified
   - restart the container and confirm the same device persists

6. Follow logs during the test run:

   `./scripts/shared/hermes-logs ezirius -f`

Until that host-side validation is complete, treat the mautrix migration here as implementation-ready but not yet production-proven.

## Security notes

This repo containerises Hermes itself. Inside that container, Hermes can safely use its normal `local` terminal backend because the container is the execution boundary.

If you want Hermes to use Docker as an internal execution backend too, that is a separate configuration choice. Do not casually forward extra secrets or runtime sockets into nested backends. Keep secrets in `.env`, keep non-secret config in `config.yaml`, and only expose additional credentials deliberately.

## Useful commands

- `./scripts/shared/hermes-build`
- `./scripts/shared/hermes-upgrade`
- `./scripts/shared/bootstrap-test [hermes args...]`
- `./scripts/shared/hermes-start <workspace-name>`
- `./scripts/shared/hermes-open <workspace-name> [hermes args...]`
- `./scripts/shared/hermes-status <workspace-name>`
- `./scripts/shared/hermes-logs <workspace-name> [podman args...]`
- `./scripts/shared/hermes-shell <workspace-name>`
- `./scripts/shared/hermes-stop <workspace-name>`
- `./scripts/shared/hermes-remove <workspace-name>`

Useful `hermes-open` examples:

- `./scripts/shared/hermes-open ezirius setup`
- `./scripts/shared/hermes-open ezirius model`
- `./scripts/shared/hermes-open ezirius tools`
- `./scripts/shared/hermes-open ezirius doctor`
- `./scripts/shared/hermes-open ezirius gateway`
- `./scripts/shared/hermes-open ezirius chat`
- `./scripts/shared/hermes-open ezirius mcp serve`

Useful `hermes-logs` examples:

- `./scripts/shared/hermes-logs ezirius -f`
- `./scripts/shared/hermes-logs ezirius --tail 100`
- `./scripts/shared/hermes-logs ezirius --since 10m`

All wrapper scripts support `--help` and document their argument contracts there.

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
