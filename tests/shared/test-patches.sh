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
mkdir -p "$UPSTREAM_ROOT/agent"

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

python3 - "$ROOT" "$UPSTREAM_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
upstream_root = Path(sys.argv[2])

host_patch = (root / 'config/patches/apply-hermes-host-agents-context.py').read_text(encoding='utf-8')
host_patch = host_patch.replace('Path("/home/hermes/hermes-agent/agent/prompt_builder.py")', f'Path({str(upstream_root / "agent/prompt_builder.py")!r})')
exec(compile(host_patch, 'apply-hermes-host-agents-context.py', 'exec'), {})
PY

python3 -m py_compile "$UPSTREAM_ROOT/agent/prompt_builder.py"

assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'prefer HERMES_HOME, then cwd top-level only' 'host AGENTS patch updates prompt builder precedence'
assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'hermes_home_agents = get_hermes_home() / "AGENTS.md"' 'host AGENTS patch prefers HERMES_HOME AGENTS file'
assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'if candidate.exists() and candidate != hermes_home_agents:' 'host AGENTS patch preserves cwd fallback without duplicating HERMES_HOME'
assert_not_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'mautrix' 'host AGENTS patch should stay independent of Matrix strategy'

echo "Patch application checks passed"
