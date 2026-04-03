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
PATCH_ROOT="$TMPDIR/patches"
mkdir -p \
  "$UPSTREAM_ROOT/gateway/platforms" \
  "$UPSTREAM_ROOT/website/docs/user-guide/messaging" \
  "$UPSTREAM_ROOT/agent" \
  "$PATCH_ROOT/templates"

touch "$UPSTREAM_ROOT/gateway/__init__.py" "$UPSTREAM_ROOT/gateway/platforms/__init__.py"

cat > "$UPSTREAM_ROOT/gateway/config.py" <<'EOF'
from dataclasses import dataclass, field
from enum import Enum

class Platform(Enum):
    MATRIX = "matrix"

@dataclass
class PlatformConfig:
    token: str = ""
    extra: dict = field(default_factory=dict)
EOF

cat > "$UPSTREAM_ROOT/gateway/platforms/base.py" <<'EOF'
class BasePlatformAdapter:
    def __init__(self, *args, **kwargs):
        pass

    def _mark_connected(self):
        pass

    def _mark_disconnected(self):
        pass

class MessageEvent:
    pass

class MessageType:
    TEXT = "text"
    IMAGE = "image"
    FILE = "file"
    AUDIO = "audio"
    VOICE = "voice"
    VIDEO = "video"
    STICKER = "sticker"

class SendResult:
    def __init__(self, success=True, message_id=None, error=None, metadata=None):
        self.success = success
        self.message_id = message_id
        self.error = error
        self.metadata = metadata or {}
EOF

cat > "$UPSTREAM_ROOT/hermes_constants.py" <<'EOF'
from pathlib import Path

def get_hermes_dir(*parts):
    return Path('/tmp/hermes-test-store')
EOF

cat > "$UPSTREAM_ROOT/pyproject.toml" <<'EOF'
matrix = ["matrix-nio[e2e]>=0.24.0,<1"]
EOF

cat > "$UPSTREAM_ROOT/gateway/run.py" <<'EOF'
logger.warning("Matrix: matrix-nio not installed or credentials not set. Run: pip install 'matrix-nio[e2e]'")
EOF

cat > "$UPSTREAM_ROOT/website/docs/user-guide/messaging/matrix.md" <<'EOF'
Hermes Agent integrates with Matrix. The bot connects via the `matrix-nio` Python SDK.

## End-to-End Encryption (E2EE)

E2EE requires the `matrix-nio` library with encryption extras and the `libolm` C library:

```bash
# Install matrix-nio with E2EE support
pip install 'matrix-nio[e2e]'

# Or install with hermes extras
pip install 'hermes-agent[matrix]'
```

When E2EE is enabled, Hermes:
- Stores encryption keys in `~/.hermes/matrix/store/`

If `matrix-nio[e2e]` is not installed or `libolm` is missing, the bot falls back to a plain (unencrypted) client automatically. You'll see a warning in the logs.

### "matrix-nio not installed" error

**Cause**: The `matrix-nio` Python package is not installed.

**Fix**: Install it:

```bash
pip install 'matrix-nio[e2e]'
```

Or with Hermes extras:

```bash
pip install 'hermes-agent[matrix]'
```
EOF

cat > "$UPSTREAM_ROOT/agent/prompt_builder.py" <<'EOF'
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
old upstream matrix adapter placeholder
EOF

cp "$ROOT/config/patches/templates/hermes-matrix-mautrix.py" "$PATCH_ROOT/templates/hermes-matrix-mautrix.py"

python3 - "$ROOT" "$UPSTREAM_ROOT" "$PATCH_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
upstream_root = Path(sys.argv[2])
patch_root = Path(sys.argv[3])

mautrix_patch = (root / 'config/patches/apply-hermes-mautrix-migration.py').read_text(encoding='utf-8')
mautrix_patch = mautrix_patch.replace('ROOT = Path("/home/hermes/hermes-agent")', f'ROOT = Path({str(upstream_root)!r})')
mautrix_patch = mautrix_patch.replace('PATCH_ROOT = Path("/tmp/hermes-patches")', f'PATCH_ROOT = Path({str(patch_root)!r})')
exec(compile(mautrix_patch, 'apply-hermes-mautrix-migration.py', 'exec'), {})

host_patch = (root / 'config/patches/apply-hermes-host-agents-context.py').read_text(encoding='utf-8')
host_patch = host_patch.replace('Path("/home/hermes/hermes-agent/agent/prompt_builder.py")', f'Path({str(upstream_root / "agent/prompt_builder.py")!r})')
exec(compile(host_patch, 'apply-hermes-host-agents-context.py', 'exec'), {})
PY

python3 -m py_compile "$UPSTREAM_ROOT/gateway/platforms/matrix.py" "$UPSTREAM_ROOT/agent/prompt_builder.py"

assert_contains "$UPSTREAM_ROOT/pyproject.toml" 'mautrix>=0.20.8,<1' 'mautrix patch rewrites matrix dependency'
assert_contains "$UPSTREAM_ROOT/pyproject.toml" 'python-olm>=3.2.16,<4' 'mautrix patch includes python-olm requirement'
assert_contains "$UPSTREAM_ROOT/pyproject.toml" 'unpaddedbase64>=2.1.0,<3' 'mautrix patch includes unpaddedbase64 requirement'
assert_contains "$UPSTREAM_ROOT/pyproject.toml" 'base58>=2.1.1,<3' 'mautrix patch includes base58 requirement'
assert_contains "$UPSTREAM_ROOT/gateway/run.py" "pip install 'hermes-agent[matrix]'" 'gateway warning text is updated to hermes matrix extras'
assert_contains "$UPSTREAM_ROOT/website/docs/user-guide/messaging/matrix.md" '`mautrix` Python framework' 'matrix docs describe mautrix rather than matrix-nio'
assert_contains "$UPSTREAM_ROOT/website/docs/user-guide/messaging/matrix.md" 'Stores encryption keys under `HERMES_HOME`' 'matrix docs describe HERMES_HOME-backed crypto storage'
assert_contains "$UPSTREAM_ROOT/website/docs/user-guide/messaging/matrix.md" 'Matrix crypto dependencies are missing' 'matrix docs explain mautrix dependency failure mode'
assert_contains "$UPSTREAM_ROOT/website/docs/user-guide/messaging/matrix.md" '"mautrix dependencies not installed" error' 'matrix troubleshooting heading is updated'
assert_not_contains "$UPSTREAM_ROOT/website/docs/user-guide/messaging/matrix.md" 'matrix-nio[e2e]' 'matrix docs should not retain matrix-nio install commands after patching'
assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'prefer HERMES_HOME, then cwd top-level only' 'host AGENTS patch updates prompt builder precedence'
assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'hermes_home_agents = get_hermes_home() / "AGENTS.md"' 'host AGENTS patch prefers HERMES_HOME AGENTS file'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'Wrapper-managed replacement for the upstream matrix-nio adapter.' 'mautrix template replaces upstream matrix adapter'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'restored %s inbound Megolm session(s)' 'mautrix template logs restored Megolm sessions'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'payload["inbound_sessions"]' 'mautrix template persists inbound Megolm sessions'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'InboundGroupSession.import_session' 'mautrix template restores inbound Megolm sessions into the live store'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'stored_auth_path = _STORE_DIR / "mautrix_auth.json"' 'mautrix template considers stored auth during requirement checks'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'MATRIX_USER_ID not set for password-based login' 'mautrix template validates password login user id requirements'

if python3 -c 'import mautrix' >/dev/null 2>&1; then
  PYTHONPATH="$UPSTREAM_ROOT${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY'
import asyncio
import json
import tempfile
from pathlib import Path

from mautrix.crypto.sessions import InboundGroupSession, OutboundGroupSession
from gateway.platforms.matrix import _LiteFileCryptoStore

room_id = "!room:example.org"
outbound = OutboundGroupSession(room_id)
session_id = outbound.id
sender_key = "curve25519-sender"
signing_key = "ed25519-sender"
session_key = InboundGroupSession(
    outbound.session_key,
    signing_key=signing_key,
    sender_key=sender_key,
    room_id=room_id,
).export_session(0)

async def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        state_path = Path(td) / "mautrix_crypto.json"
        state_path.write_text(
            json.dumps(
                {
                    "device_id": "HERMES",
                    "inbound_sessions": [
                        {
                            "room_id": room_id,
                            "sender_key": sender_key,
                            "signing_key": signing_key,
                            "session_id": session_id,
                            "session_key": session_key,
                            "forwarding_curve25519_key_chain": [],
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )

        store = _LiteFileCryptoStore("@bot:example.org", "pickle-key", state_path)
        await store.open()
        restored = await store.get_group_session(room_id, session_id)
        assert restored is not None, "inbound Megolm session was not restored into MemoryCryptoStore"
        await store.flush()

        after = json.loads(state_path.read_text(encoding="utf-8"))
        assert after.get("inbound_sessions"), "flush dropped inbound Megolm sessions"
        assert after["inbound_sessions"][0]["session_id"] == session_id, "flushed inbound session changed session_id"

asyncio.run(main())
PY
else
  echo "Skipping runtime Megolm persistence check because mautrix is unavailable in the host Python environment"
fi

PYTHONPATH="$UPSTREAM_ROOT${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY'
import importlib
import json
import os
import tempfile
from pathlib import Path

mod = importlib.import_module('gateway.platforms.matrix')

with tempfile.TemporaryDirectory() as td:
    store_dir = Path(td)
    auth_path = store_dir / 'mautrix_auth.json'
    auth_path.write_text(json.dumps({'user_id': '@bot:example.org', 'access_token': 'stored-token'}), encoding='utf-8')
    mod._STORE_DIR = store_dir

    original = dict(os.environ)
    try:
        os.environ.pop('MATRIX_ACCESS_TOKEN', None)
        os.environ.pop('MATRIX_USER_ID', None)
        os.environ.pop('MATRIX_PASSWORD', None)
        os.environ['MATRIX_HOMESERVER'] = 'https://matrix.example.org'
        assert mod.check_matrix_requirements() is True, 'stored auth should satisfy requirement checks'

        os.environ.pop('MATRIX_ACCESS_TOKEN', None)
        os.environ.pop('MATRIX_USER_ID', None)
        os.environ['MATRIX_PASSWORD'] = 'secret'
        assert mod.check_matrix_requirements() is True, 'stored auth token/user id should satisfy password flow checks'

        auth_path.unlink()
        assert mod.check_matrix_requirements() is False, 'password-only auth without MATRIX_USER_ID should fail requirement checks'
    finally:
        os.environ.clear()
        os.environ.update(original)
PY

PYTHONPATH="$UPSTREAM_ROOT${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY'
import asyncio
import json
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, patch

from gateway.config import PlatformConfig
from gateway.platforms.matrix import MatrixAdapter

class DummyStateStore:
    def __init__(self, _path):
        self.open = AsyncMock()
        self.close = AsyncMock()

class DummyClient:
    def __init__(self, user_id, *, base_url, token, sync_store, state_store):
        self.user_id = user_id
        self.base_url = base_url
        self.api = type('Api', (), {'token': token})()
        self.sync_store = sync_store
        self.state_store = state_store
        self.syncing_task = None
        self.crypto = None
        self.mxid = None
        self.device_id = None
        self.get_joined_rooms = AsyncMock(return_value=[])
        self.start = lambda _arg: object()
        self.stop = lambda: None
        self.add_event_handler = lambda *args, **kwargs: None
        self.whoami = AsyncMock(return_value=type('WhoAmI', (), {'user_id': '@stored:example.org', 'device_id': 'HERMES'})())

async def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        store_dir = Path(td)
        (store_dir / 'mautrix_auth.json').write_text(
            json.dumps({'user_id': '@stored:example.org', 'access_token': 'stored-token'}),
            encoding='utf-8',
        )
        cfg = PlatformConfig(token='', extra={'homeserver': 'https://matrix.example.org', 'encryption': False})
        adapter = MatrixAdapter(cfg)
        with patch('gateway.platforms.matrix._STORE_DIR', store_dir), \
             patch('mautrix.client.state_store.file.FileStateStore', DummyStateStore), \
             patch('mautrix.client.Client', DummyClient):
            ok = await adapter.connect()
            assert ok is True, 'connect should succeed from stored auth'
            assert adapter._crypto_store.account_id == '@stored:example.org', 'crypto store account_id should use stored auth user id'
            await adapter.disconnect()

asyncio.run(main())
PY

echo "Patch application checks passed"
