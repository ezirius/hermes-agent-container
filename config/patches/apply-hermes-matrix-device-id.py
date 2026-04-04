from pathlib import Path


path = Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f"could not apply matrix device-id patch: {description}")
    text = text.replace(old, new, 1)


replace_once(
    '    MATRIX_ENCRYPTION       Set "true" to enable E2EE\n'
    '    MATRIX_ALLOWED_USERS    Comma-separated Matrix user IDs (@user:server)\n',
    '    MATRIX_ENCRYPTION       Set "true" to enable E2EE\n'
    '    MATRIX_DEVICE_ID        Optional stable device ID for password login\n'
    '    MATRIX_ALLOWED_USERS    Comma-separated Matrix user IDs (@user:server)\n',
    "module docstring env var list",
)

replace_once(
    '        self._encryption: bool = config.extra.get(\n'
    '            "encryption",\n'
    '            os.getenv("MATRIX_ENCRYPTION", "").lower() in ("true", "1", "yes"),\n'
    '        )\n\n'
    '        self._client: Any = None  # nio.AsyncClient\n',
    '        self._encryption: bool = config.extra.get(\n'
    '            "encryption",\n'
    '            os.getenv("MATRIX_ENCRYPTION", "").lower() in ("true", "1", "yes"),\n'
    '        )\n'
    '        self._device_id: str = (\n'
    '            config.extra.get("device_id", "")\n'
    '            or os.getenv("MATRIX_DEVICE_ID", "")\n'
    '        )\n\n'
    '        self._client: Any = None  # nio.AsyncClient\n',
    "MatrixAdapter __init__ stable device_id field",
)

replace_once(
    '                logger.info(\n'
    '                    "Matrix: using access token for %s%s",\n'
    '                    self._user_id or "(unknown user)",\n'
    '                    f" (device {resolved_device_id})" if resolved_device_id else "",\n'
    '                )\n',
    '                if self._device_id and resolved_device_id and self._device_id != resolved_device_id:\n'
    '                    logger.warning(\n'
    '                        "Matrix: MATRIX_DEVICE_ID=%s ignored for access-token auth; homeserver restored device %s",\n'
    '                        self._device_id,\n'
    '                        resolved_device_id,\n'
    '                    )\n'
    '                if resolved_device_id:\n'
    '                    self._device_id = resolved_device_id\n'
    '                logger.info(\n'
    '                    "Matrix: using access token for %s%s",\n'
    '                    self._user_id or "(unknown user)",\n'
    '                    f" (device {resolved_device_id})" if resolved_device_id else "",\n'
    '                )\n',
    "access-token path retains resolved device and warns on mismatch",
)

replace_once(
    '        elif self._password and self._user_id:\n'
    '            resp = await client.login(\n'
    '                self._password,\n'
    '                device_name="Hermes Agent",\n'
    '            )\n'
    '            if isinstance(resp, nio.LoginResponse):\n'
    '                logger.info("Matrix: logged in as %s", self._user_id)\n',
    '        elif self._password and self._user_id:\n'
    '            auth_dict = {\n'
    '                "type": "m.login.password",\n'
    '                "identifier": {\n'
    '                    "type": "m.id.user",\n'
    '                    "user": self._user_id,\n'
    '                },\n'
    '                "password": self._password,\n'
    '                "initial_device_display_name": "Hermes Agent",\n'
    '            }\n'
    '            if self._device_id:\n'
    '                auth_dict["device_id"] = self._device_id\n'
    '            resp = await client.login_raw(auth_dict)\n'
    '            if isinstance(resp, nio.LoginResponse):\n'
    '                resolved_device_id = getattr(resp, "device_id", "")\n'
    '                if self._device_id and resolved_device_id and self._device_id != resolved_device_id:\n'
    '                    logger.warning(\n'
    '                        "Matrix: MATRIX_DEVICE_ID=%s requested for password login, but homeserver returned device %s",\n'
    '                        self._device_id,\n'
    '                        resolved_device_id,\n'
    '                    )\n'
    '                if resolved_device_id:\n'
    '                    self._device_id = resolved_device_id\n'
    '                    client.device_id = resolved_device_id\n'
    '                elif self._device_id:\n'
    '                    logger.warning(\n'
    '                        "Matrix: password login response omitted device_id; continuing with requested device %s",\n'
    '                        self._device_id,\n'
    '                    )\n'
    '                    client.device_id = self._device_id\n'
    '                logger.info(\n'
    '                    "Matrix: logged in as %s%s",\n'
    '                    self._user_id,\n'
    '                    f" (device {self._device_id})" if self._device_id else "",\n'
    '                )\n',
    "password login_raw path with stable MATRIX_DEVICE_ID",
)

path.write_text(text, encoding="utf-8")
