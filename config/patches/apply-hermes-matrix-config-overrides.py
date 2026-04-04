from pathlib import Path


path = Path("/home/hermes/hermes-agent/gateway/config.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f"could not apply matrix config-overrides patch: {description}")
    text = text.replace(old, new, 1)


replace_once(
    '        matrix_e2ee = os.getenv("MATRIX_ENCRYPTION", "").lower() in ("true", "1", "yes")\n'
    '        config.platforms[Platform.MATRIX].extra["encryption"] = matrix_e2ee\n',
    '        matrix_e2ee = os.getenv("MATRIX_ENCRYPTION", "").lower() in ("true", "1", "yes")\n'
    '        config.platforms[Platform.MATRIX].extra["encryption"] = matrix_e2ee\n'
    '        config.platforms[Platform.MATRIX].extra["device_id"] = os.getenv("MATRIX_DEVICE_ID", "")\n'
    '        config.platforms[Platform.MATRIX].extra["allowed_users"] = os.getenv("MATRIX_ALLOWED_USERS", "")\n',
    "Matrix env overrides for device_id and allowed_users",
)

path.write_text(text, encoding="utf-8")
