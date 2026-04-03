from pathlib import Path
import re


path = Path("/home/hermes/hermes-agent/agent/prompt_builder.py")
text = path.read_text(encoding="utf-8")

pattern = re.compile(
    r"def _load_agents_md\(cwd_path: Path\) -> str:\n"
    r"(?:    .*\n)+?"
    r"    return \"\"\n",
    flags=re.MULTILINE,
)

replacement = '''def _load_agents_md(cwd_path: Path) -> str:
    """AGENTS.md — prefer HERMES_HOME, then cwd top-level only."""
    candidates = []

    hermes_home_agents = get_hermes_home() / "AGENTS.md"
    if hermes_home_agents.exists():
        candidates.append((hermes_home_agents, "AGENTS.md"))

    for name in ["AGENTS.md", "agents.md"]:
        candidate = cwd_path / name
        if candidate.exists() and candidate != hermes_home_agents:
            candidates.append((candidate, name))

    for candidate, label in candidates:
        try:
            content = candidate.read_text(encoding="utf-8").strip()
            if content:
                content = _scan_context_content(content, label)
                result = f"## {label}\\n\\n{content}"
                return _truncate_content(result, "AGENTS.md")
        except Exception as e:
            logger.debug("Could not read %s: %s", candidate, e)
    return ""
'''

updated, count = pattern.subn(lambda _match: replacement, text, count=1)
if count != 1:
    raise SystemExit("could not apply host AGENTS patch: AGENTS loader block not found")

path.write_text(updated, encoding="utf-8")
