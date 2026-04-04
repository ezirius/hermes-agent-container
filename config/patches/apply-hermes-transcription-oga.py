from pathlib import Path


path = Path("/home/hermes/hermes-agent/tools/transcription_tools.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f"could not apply transcription .oga patch: {description}")
    text = text.replace(old, new, 1)


replace_once(
    'Supported input formats: mp3, mp4, mpeg, mpga, m4a, wav, webm, ogg, aac\n',
    'Supported input formats: mp3, mp4, mpeg, mpga, m4a, wav, webm, ogg, oga, aac\n',
    "docstring supported input formats",
)

replace_once(
    'SUPPORTED_FORMATS = {".mp3", ".mp4", ".mpeg", ".mpga", ".m4a", ".wav", ".webm", ".ogg", ".aac"}\n',
    'SUPPORTED_FORMATS = {".mp3", ".mp4", ".mpeg", ".mpga", ".m4a", ".wav", ".webm", ".ogg", ".oga", ".aac"}\n',
    "SUPPORTED_FORMATS set",
)

path.write_text(text, encoding="utf-8")
