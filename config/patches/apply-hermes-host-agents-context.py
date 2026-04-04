from pathlib import Path


path = Path("/home/hermes/hermes-agent/agent/prompt_builder.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text

    if old not in text:
        raise SystemExit(f"could not apply host AGENTS patch: {description}")
    text = text.replace(old, new, 1)


replace_once(
    '    """AGENTS.md — top-level only (no recursive walk)."""\n',
    '    """AGENTS.md — prefer HERMES_HOME, then cwd top-level only."""\n'
    '    hermes_home_agents = get_hermes_home() / "AGENTS.md"\n'
    '    if hermes_home_agents.exists():\n'
    '        try:\n'
    '            content = hermes_home_agents.read_text(encoding="utf-8").strip()\n'
    '            if content:\n'
    '                content = _scan_context_content(content, "AGENTS.md")\n'
    '                result = f"## AGENTS.md\\n\\n{content}"\n'
    '                return _truncate_content(result, "AGENTS.md")\n'
    '        except Exception as e:\n'
    '            logger.debug("Could not read %s: %s", hermes_home_agents, e)\n'
    '\n',
    "AGENTS loader docstring and HERMES_HOME preference block",
)

replace_once(
    '        if candidate.exists():\n',
    '        if candidate.exists() and candidate != hermes_home_agents:\n',
    "skip duplicate HERMES_HOME AGENTS candidate",
)

path.write_text(text, encoding="utf-8")
