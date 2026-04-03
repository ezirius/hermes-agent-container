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

echo "Patch application checks passed"
