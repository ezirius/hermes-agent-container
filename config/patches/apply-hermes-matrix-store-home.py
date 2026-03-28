from pathlib import Path


path = Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text

    if old not in text:
        raise SystemExit(f"could not apply Matrix store patch: {description}")
    text = text.replace(old, new, 1)


replace_once(
    "from gateway.config import Platform, PlatformConfig\n",
    "from gateway.config import Platform, PlatformConfig\nfrom hermes_constants import get_hermes_home\n",
    "hermes home import",
)

replace_once(
    '_STORE_DIR = Path.home() / ".hermes" / "matrix" / "store"\n',
    '_STORE_DIR = get_hermes_home() / "matrix" / "store"\n',
    "matrix store path",
)

path.write_text(text, encoding="utf-8")
