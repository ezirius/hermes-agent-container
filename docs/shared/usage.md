# Hermes Agent container usage

## Basic flow

1. Create the workspace directory and env file:
   `mkdir -p "$HERMES_BASE_ROOT/ezirius/hermes-home" && touch "$HERMES_BASE_ROOT/ezirius/hermes-home/.env"`
2. Put Hermes secrets in `hermes-home/.env`
3. Put non-secret runtime configuration in `hermes-home/config.yaml`
4. Start Hermes for a workspace:
   `./scripts/shared/bootstrap ezirius`

`bootstrap` runs `hermes-build`, then `hermes-upgrade`, then `hermes-start`, then `hermes-open`.

`bootstrap-test` is the destructive fresh test path: it removes the previous dedicated test container, test image, and test workspace data under `HERMES_BASE_ROOT/test`, then builds from scratch, starts the fresh `test` workspace, and opens Hermes by execing inside that dedicated container built from the `hermes-agent-local-test` image.

`hermes-start` starts the Hermes Gateway inside the persistent workspace container. `hermes-open` then execs the Hermes CLI inside that same running container so the wrapper does not run two Hermes containers against the same `/opt/data` at once.

If the workspace container already exists on the current image, `hermes-start` reuses it. If it is stopped, the wrapper uses `podman start`; if the image changed, the wrapper recreates the container on the new image.

Common forwarded `bootstrap` examples:

- `./scripts/shared/bootstrap ezirius setup`
- `./scripts/shared/bootstrap ezirius model`
- `./scripts/shared/bootstrap ezirius doctor`

Common `bootstrap-test` examples:

- `./scripts/shared/bootstrap-test`
- `./scripts/shared/bootstrap-test doctor`

Workspace names resolve under `HERMES_BASE_ROOT`.

## Environment and state

- this wrapper maps `<workspace-root>/hermes-home` to persistent Hermes state inside the container
- Hermes runs with `/opt/data` mapped to `<workspace-root>/hermes-home`
- Hermes runs with `/workspace` mapped to `<workspace-root>/workspace`
- `.env` stores secrets
- `config.yaml` stores non-secret runtime configuration
- the image uses an upstream-style entrypoint to bootstrap and then run Hermes
- the wrapper seeds `.env`, `config.yaml`, `SOUL.md`, and `AGENTS.md` into `hermes-home` on first run when missing
- upstream Hermes reads `/opt/data/.env` and `/opt/data/config.yaml` directly when the gateway process starts
- the wrapper patches upstream context discovery so the operative default `AGENTS.md` is the host-backed `/opt/data/AGENTS.md`; other project-local context files under `/workspace` still load normally, but a project-local `AGENTS.md` does not override the host-backed one unless you replace or remove `/opt/data/AGENTS.md`
- editing `hermes-home/.env` or `hermes-home/config.yaml` only needs a container stop/start, not an image rebuild
- for image-recipe changes, the normal path is `hermes-upgrade` then `hermes-start <workspace>`; you do not need `hermes-remove` unless you explicitly want manual container cleanup first
- the runtime state directories are created automatically under `hermes-home`
- new workspaces follow the latest upstream release layout, including `cache/images`, `cache/audio`, and `platforms/whatsapp/session`; legacy wrapper paths are migrated forward on start when possible
- the image includes Matrix support using the upstream `matrix-nio` adapter path rather than a wrapper-managed replacement
- upstream `hermes-agent[all]` no longer includes Matrix in `v2026.4.3`, so the wrapper installs `hermes-agent[matrix]` explicitly during image build
- upstream Hermes resolves Matrix encrypted-state storage through `HERMES_HOME`
- `/home/hermes/.hermes` is linked to `/opt/data` as a compatibility safeguard for any remaining upstream hardcoded `~/.hermes` paths
- the wrapper patches the upstream `matrix-nio` adapter to honour `MATRIX_DEVICE_ID` for password login so one intended Matrix device can be reused
- the wrapper also patches the upstream `matrix-nio` adapter to register encrypted media callbacks, decrypt Matrix attachment payloads with `nio.crypto.decrypt_attachment`, cache decrypted local files, and avoid bogus ciphertext URL fallbacks for encrypted voice/image/file/video events
- if you import room keys or otherwise change Matrix crypto material while Hermes is already running, restart the workspace container once so the live client reloads state from disk

## Workspaces versus profiles

- wrapper workspace: this repo’s host-level isolation unit
- upstream profile: Hermes’s internal isolation unit inside one Hermes home

Default recommendation:
- one wrapper workspace
- one upstream default profile inside it
- only use multiple upstream profiles inside one workspace when you need an extra isolation layer deliberately

## Upstream source selection

- `HERMES_REPO_URL`
  - upstream Hermes repo used during image build
  - default: `https://github.com/NousResearch/hermes-agent.git`
- `HERMES_REF`
  - upstream branch or tag to build from
  - default: `latest-release`
  - `latest-release` resolves the latest upstream Hermes release tag and fails clearly if no upstream release entry is available
  - `hermes-upgrade` re-checks this and rebuilds when a newer upstream release appears or when the local wrapper build fingerprint changes
  - Do not treat upstream `main` as the baseline unless you explicitly set `HERMES_REF` for that purpose.
  - if you set an explicit tag or branch here, upgrade compares that literal ref only and does not poll for branch-head movement
- `HERMES_GITHUB_API_BASE`
  - GitHub API base used to resolve `latest-release`
  - default: `https://api.github.com`

The local wrapper build fingerprint covers all non-generated image recipe files under `config/containers/` and `config/patches/`. That means local image-behaviour changes such as the entrypoint, host AGENTS precedence patch, or compatibility-link setup trigger a rebuild automatically on the next `hermes-upgrade` or `bootstrap`, even if the upstream release tag stays the same.

## Matrix validation

The wrapper now keeps the upstream Matrix adapter path intact and validates wrapper mechanics separately from live homeserver behaviour. Local shell tests validate the wrapper mechanics, but they do not prove live Matrix behaviour.

For wrapper-maintainer verification, `tests/shared/test-patches.sh` now supports an opt-in real-upstream smoke pass against an actual upstream checkout:
- `HERMES_UPSTREAM_PATCH_SMOKE=1 bash tests/shared/test-patches.sh`
- optional override: `HERMES_UPSTREAM_REPO=/path/to/upstream/hermes-agent`

Use this host-side verification sequence on the real Podman machine:

1. Build or rebuild the shared image:

   `./scripts/shared/hermes-build`

2. Start the workspace container:

   `./scripts/shared/hermes-start ezirius`

3. Inspect the upstream-led install inside the image-backed environment:

   `./scripts/shared/hermes-shell ezirius`

   Verify at minimum:

   - `python3 -c "import nio"` succeeds
   - `/home/hermes/hermes-agent/gateway/platforms/matrix.py` remains the upstream adapter file rather than a wrapper-managed replacement
   - `python3 -m py_compile /home/hermes/hermes-agent/gateway/platforms/matrix.py` succeeds

4. Configure the Matrix credentials in `hermes-home/.env`, then stop/start the workspace container.

   For password-based Matrix auth, set a fixed device ID explicitly, for example:

   ```env
   MATRIX_USER_ID=@yourbot:matrix.org
   MATRIX_PASSWORD=your-password
   MATRIX_DEVICE_ID=HERMES
   MATRIX_ENCRYPTION=true
   ```

5. Run encrypted smoke tests:

   - encrypted DM text in -> Hermes reply out
   - encrypted group-room text in -> Hermes reply out
   - encrypted threaded reply in -> threaded reply out
   - encrypted voice note in -> STT and Hermes reply
   - encrypted image in -> media path works
   - encrypted file in -> document path works
   - encrypted video in -> media path works
   - Element/Element X shows one stable Hermes device that can be verified
   - restart preserves the same device identity

6. Follow the runtime logs during the smoke tests:

   `./scripts/shared/hermes-logs ezirius -f`

Until those host-side checks pass, treat Matrix support here as wrapper-aligned and locally validated, but not yet fully production-validated.

## Runtime model

- Hermes itself runs in a persistent container
- only `<workspace-root>/hermes-home` and `<workspace-root>/workspace` are mounted
- the container restart policy is `unless-stopped`
- rebuilding is only for image-recipe or upstream-source changes; runtime config changes live in the mounted files under `hermes-home`
- on macOS hosts, interactive CLI and shell entry uses `podman exec -it` into the running workspace container and can wrap TTY allocation with `script`
- Hermes can safely use its normal `local` backend inside this container, so terminal work runs inside the Hermes container itself
- if you want Hermes to use Docker as an internal execution backend too, that is a separate configuration choice

## MCP and gateway capabilities

The wrapper exposes the latest-release Hermes CLI inside the workspace model, including current upstream capabilities such as:

- `./scripts/shared/hermes-open ezirius mcp serve`
- `./scripts/shared/hermes-open ezirius gateway`
- `./scripts/shared/hermes-open ezirius chat`

The wrapper does not add separate MCP orchestration; it reuses the standard CLI entry.

## Security notes

This wrapper container is the execution boundary for Hermes’s local backend.

Keep secrets in `.env`, keep non-secret config in `config.yaml`, and do not forward extra secrets or runtime sockets into nested backends unless you intend to.

## Commands

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

Common `hermes-open` examples:

- `./scripts/shared/hermes-open ezirius setup`
- `./scripts/shared/hermes-open ezirius model`
- `./scripts/shared/hermes-open ezirius tools`
- `./scripts/shared/hermes-open ezirius doctor`
- `./scripts/shared/hermes-open ezirius gateway`
- `./scripts/shared/hermes-open ezirius chat`
- `./scripts/shared/hermes-open ezirius mcp serve`

Common `hermes-logs` examples:

- `./scripts/shared/hermes-logs ezirius -f`
- `./scripts/shared/hermes-logs ezirius --tail 100`
- `./scripts/shared/hermes-logs ezirius --since 10m`

All wrapper scripts support `--help` and document their argument contracts there.

## Notes

- upstream already provides official Docker support; this repo is the multi-workspace wrapper layer
- `hermes-build` takes no positional arguments
- `hermes-upgrade` takes no positional arguments and rebuilds when the requested upstream source changed or when the local wrapper image recipe changed
- workspace-scoped commands require exactly one workspace name, except `hermes-open` and `hermes-logs`, which accept optional extra arguments after the workspace
