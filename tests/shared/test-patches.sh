#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || { printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2; exit 1; }
}

assert_not_contains() {
  local file="$1" needle="$2" message="$3"
  if grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nunexpected: %s\n' "$message" "$needle" >&2
    exit 1
  fi
}

UPSTREAM_ROOT="$TMPDIR/upstream"
mkdir -p "$UPSTREAM_ROOT/agent" "$UPSTREAM_ROOT/gateway/platforms"

cat > "$UPSTREAM_ROOT/agent/prompt_builder.py" <<'EOF'
from pathlib import Path

from hermes_constants import get_hermes_home


def _load_agents_md(cwd_path: Path) -> str:
    """AGENTS.md — top-level only (no recursive walk)."""
    for name in ["AGENTS.md", "agents.md"]:
        candidate = cwd_path / name
        if candidate.exists():
            try:
                content = candidate.read_text(encoding="utf-8").strip()
                if content:
                    content = _scan_context_content(content, name)
                    result = f"## {name}\n\n{content}"
                    return _truncate_content(result, "AGENTS.md")
            except Exception as e:
                logger.debug("Could not read %s: %s", candidate, e)
    return ""
EOF

cat > "$UPSTREAM_ROOT/gateway/platforms/matrix.py" <<'EOF'
"""Matrix gateway adapter.

Connects to any Matrix homeserver (self-hosted or matrix.org) via the
matrix-nio Python SDK.  Supports optional end-to-end encryption (E2EE)
when installed with ``pip install "matrix-nio[e2e]"``.

Environment variables:
    MATRIX_HOMESERVER       Homeserver URL (e.g. https://matrix.example.org)
    MATRIX_ACCESS_TOKEN     Access token (preferred auth method)
    MATRIX_USER_ID          Full user ID (@bot:server) — required for password login
    MATRIX_PASSWORD         Password (alternative to access token)
    MATRIX_ENCRYPTION       Set "true" to enable E2EE
    MATRIX_ALLOWED_USERS    Comma-separated Matrix user IDs (@user:server)
    MATRIX_HOME_ROOM        Room ID for cron/notification delivery
"""

class MatrixAdapter:
    def __init__(self, config):
        self._encryption: bool = config.extra.get(
            "encryption",
            os.getenv("MATRIX_ENCRYPTION", "").lower() in ("true", "1", "yes"),
        )

        self._client: Any = None  # nio.AsyncClient

    async def connect(self) -> bool:
        import nio
        if self._access_token:
            resp = await client.whoami()
            if isinstance(resp, nio.WhoamiResponse):
                resolved_user_id = getattr(resp, "user_id", "") or self._user_id
                resolved_device_id = getattr(resp, "device_id", "")
                if resolved_user_id:
                    self._user_id = resolved_user_id

                # restore_login() is the matrix-nio path that binds the access
                # token to a specific device and loads the crypto store.
                if resolved_device_id and hasattr(client, "restore_login"):
                    client.restore_login(
                        self._user_id or resolved_user_id,
                        resolved_device_id,
                        self._access_token,
                    )
                else:
                    if self._user_id:
                        client.user_id = self._user_id
                    if resolved_device_id:
                        client.device_id = resolved_device_id
                    client.access_token = self._access_token
                    if self._encryption:
                        logger.warning(
                            "Matrix: access-token login did not restore E2EE state; "
                            "encrypted rooms may fail until a device_id is available"
                        )

                logger.info(
                    "Matrix: using access token for %s%s",
                    self._user_id or "(unknown user)",
                    f" (device {resolved_device_id})" if resolved_device_id else "",
                )
        elif self._password and self._user_id:
            resp = await client.login(
                self._password,
                device_name="Hermes Agent",
            )
            if isinstance(resp, nio.LoginResponse):
                logger.info("Matrix: logged in as %s", self._user_id)
EOF

python3 - "$ROOT" "$UPSTREAM_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
upstream_root = Path(sys.argv[2])

host_patch = (root / 'config/patches/apply-hermes-host-agents-context.py').read_text(encoding='utf-8')
host_patch = host_patch.replace('Path("/home/hermes/hermes-agent/agent/prompt_builder.py")', f'Path({str(upstream_root / "agent/prompt_builder.py")!r})')
exec(compile(host_patch, 'apply-hermes-host-agents-context.py', 'exec'), {})

matrix_patch = (root / 'config/patches/apply-hermes-matrix-device-id.py').read_text(encoding='utf-8')
matrix_patch = matrix_patch.replace('Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")', f'Path({str(upstream_root / "gateway/platforms/matrix.py")!r})')
exec(compile(matrix_patch, 'apply-hermes-matrix-device-id.py', 'exec'), {})
PY

python3 -m py_compile "$UPSTREAM_ROOT/agent/prompt_builder.py" "$UPSTREAM_ROOT/gateway/platforms/matrix.py"

assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'prefer HERMES_HOME, then cwd top-level only' 'host AGENTS patch updates prompt builder precedence'
assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'hermes_home_agents = get_hermes_home() / "AGENTS.md"' 'host AGENTS patch prefers HERMES_HOME AGENTS file'
assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'if candidate.exists() and candidate != hermes_home_agents:' 'host AGENTS patch preserves cwd fallback without duplicating HERMES_HOME'
assert_not_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'mautrix' 'host AGENTS patch should stay independent of Matrix strategy'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'MATRIX_DEVICE_ID        Optional stable device ID for password login' 'matrix patch documents MATRIX_DEVICE_ID'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'self._device_id: str = (' 'matrix patch adds stable device field'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'logger.warning(' 'matrix patch keeps access-token mismatch warning path'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'Matrix: MATRIX_DEVICE_ID=%s ignored for access-token auth; homeserver restored device %s' 'matrix patch warns when access-token auth chooses a different device'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'auth_dict = {' 'matrix patch switches password login to raw auth dict'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'auth_dict["device_id"] = self._device_id' 'matrix patch forwards MATRIX_DEVICE_ID in password auth'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'resp = await client.login_raw(auth_dict)' 'matrix patch uses login_raw for stable device reuse'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'requested for password login, but homeserver returned device %s' 'matrix patch warns when password login returns a different device'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'response omitted device_id; continuing with requested device %s' 'matrix patch warns when the login response omits device_id'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'logger.info(' 'matrix patch keeps login logging'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" '"Matrix: logged in as %s%s"' 'matrix patch logs resolved device id after password login'

echo "Patch application checks passed"
