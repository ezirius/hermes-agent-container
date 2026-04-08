#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || { printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2; exit 1; }
}

UPSTREAM_ROOT="$TMPDIR/upstream"
mkdir -p "$UPSTREAM_ROOT/agent" "$UPSTREAM_ROOT/gateway/platforms" "$UPSTREAM_ROOT/tools"

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
class MatrixGateway:
    async def connect(self, client, nio, logger):
        if False:
            return True
        elif self._password and self._user_id:
            resp = await client.login(
                self._password,
                device_name="Hermes Agent",
            )
            if isinstance(resp, nio.LoginResponse):
                logger.info("Matrix: logged in as %s", self._user_id)
            else:
                logger.error("Matrix: login failed — %s", getattr(resp, "message", resp))
                await client.close()
                return False
EOF

cat > "$UPSTREAM_ROOT/gateway/config.py" <<'EOF'
import os


class Platform:
    MATRIX = "matrix"


def _apply_env_overrides(config):
    if Platform.MATRIX in config.platforms:
        matrix_e2ee = os.getenv("MATRIX_ENCRYPTION", "").lower() in ("true", "1", "yes")
        config.platforms[Platform.MATRIX].extra["encryption"] = matrix_e2ee
EOF

cat > "$UPSTREAM_ROOT/tools/transcription_tools.py" <<'EOF'
#!/usr/bin/env python3
"""
Supported input formats: mp3, mp4, mpeg, mpga, m4a, wav, webm, ogg, aac
"""

SUPPORTED_FORMATS = {".mp3", ".mp4", ".mpeg", ".mpga", ".m4a", ".wav", ".webm", ".ogg", ".aac"}
EOF

python3 - "$ROOT" "$UPSTREAM_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
upstream_root = Path(sys.argv[2])

patch_targets = {
    "config/patches/apply-hermes-host-agents-context.py": upstream_root / "agent/prompt_builder.py",
    "config/patches/apply-hermes-matrix-device-id.py": upstream_root / "gateway/platforms/matrix.py",
    "config/patches/apply-hermes-matrix-config-overrides.py": upstream_root / "gateway/config.py",
    "config/patches/apply-hermes-transcription-oga.py": upstream_root / "tools/transcription_tools.py",
}

for relative_path, target in patch_targets.items():
    source = (root / relative_path).read_text(encoding="utf-8")
    source = source.replace('Path("/home/hermes/hermes-agent/agent/prompt_builder.py")', f'Path({str(target)!r})' if relative_path.endswith('host-agents-context.py') else 'Path("/home/hermes/hermes-agent/agent/prompt_builder.py")')
    source = source.replace('Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")', f'Path({str(target)!r})' if relative_path.endswith('matrix-device-id.py') else 'Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")')
    source = source.replace('Path("/home/hermes/hermes-agent/gateway/config.py")', f'Path({str(target)!r})' if relative_path.endswith('matrix-config-overrides.py') else 'Path("/home/hermes/hermes-agent/gateway/config.py")')
    source = source.replace('Path("/home/hermes/hermes-agent/tools/transcription_tools.py")', f'Path({str(target)!r})' if relative_path.endswith('transcription-oga.py') else 'Path("/home/hermes/hermes-agent/tools/transcription_tools.py")')
    exec(compile(source, relative_path, 'exec'), {})
PY

assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'prefer HERMES_HOME, then cwd top-level only' 'host AGENTS patch updates prompt builder documentation'
assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'hermes_home_agents = get_hermes_home() / "AGENTS.md"' 'host AGENTS patch prefers HERMES_HOME AGENTS file'
assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'candidate.exists() and candidate != hermes_home_agents' 'host AGENTS patch skips duplicate HERMES_HOME candidate'

assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'auth_dict = {' 'matrix device patch switches password login to login_raw payload'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'auth_dict["device_id"] = self._device_id' 'matrix device patch forwards MATRIX_DEVICE_ID'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'resp = await client.login_raw(auth_dict)' 'matrix device patch uses login_raw'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'Matrix: MATRIX_DEVICE_ID=%s requested for password login, but homeserver returned device %s' 'matrix device patch warns when homeserver chooses another device'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'response omitted device_id; continuing with requested device %s' 'matrix device patch keeps requested device when response omits it'

assert_contains "$UPSTREAM_ROOT/gateway/config.py" 'config.platforms[Platform.MATRIX].extra["allowed_users"] = os.getenv("MATRIX_ALLOWED_USERS", "")' 'matrix config patch adds allowed-users override'

assert_contains "$UPSTREAM_ROOT/tools/transcription_tools.py" 'Supported input formats: mp3, mp4, mpeg, mpga, m4a, wav, webm, ogg, oga, aac' 'transcription patch documents oga support'
assert_contains "$UPSTREAM_ROOT/tools/transcription_tools.py" '".oga"' 'transcription patch adds oga to supported formats'

python3 -m py_compile \
  "$UPSTREAM_ROOT/agent/prompt_builder.py" \
  "$UPSTREAM_ROOT/gateway/platforms/matrix.py" \
  "$UPSTREAM_ROOT/gateway/config.py" \
  "$UPSTREAM_ROOT/tools/transcription_tools.py"

echo "Patch checks passed"
