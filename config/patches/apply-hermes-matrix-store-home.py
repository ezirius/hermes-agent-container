from pathlib import Path


path = Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text

    if old not in text:
        raise SystemExit(f"could not apply Matrix store patch: {description}")
    text = text.replace(old, new, 1)


replace_once(
    '_STORE_DIR = Path.home() / ".hermes" / "matrix" / "store"\n',
    '_STORE_DIR = Path(os.getenv("HERMES_HOME", Path.home() / ".hermes")) / "matrix" / "store"\n',
    "matrix store path",
)

path.write_text(text, encoding="utf-8")
