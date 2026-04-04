from pathlib import Path


path = Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f"could not apply matrix auto-verification patch: {description}")
    text = text.replace(old, new, 1)


replace_once(
    '        self._device_id: str = (\n'
    '            config.extra.get("device_id", "")\n'
    '            or os.getenv("MATRIX_DEVICE_ID", "")\n'
    '        )\n\n'
    '        self._client: Any = None  # nio.AsyncClient\n',
    '        self._device_id: str = (\n'
    '            config.extra.get("device_id", "")\n'
    '            or os.getenv("MATRIX_DEVICE_ID", "")\n'
    '        )\n'
    '        allowed_users_str = (\n'
    '            config.extra.get("allowed_users", "")\n'
    '            or os.getenv("MATRIX_ALLOWED_USERS", "")\n'
    '        )\n'
    '        self._allowed_users: list[str] = [\n'
    '            u.strip() for u in allowed_users_str.split(",") if u.strip()\n'
    '        ]\n\n'
    '        self._client: Any = None  # nio.AsyncClient\n',
    "MatrixAdapter __init__ allowed-users field",
)

replace_once(
    '                client = nio.AsyncClient(\n'
    '                    self._homeserver,\n'
    '                    self._user_id or "",\n'
    '                    store_path=store_path,\n'
    '                )\n',
    '                client = nio.AsyncClient(\n'
    '                    self._homeserver,\n'
    '                    self._user_id or "",\n'
    '                    device_id=self._device_id or None,\n'
    '                    store_path=store_path,\n'
    '                )\n',
    "E2EE AsyncClient device_id wiring",
)

replace_once(
    '                client = nio.AsyncClient(self._homeserver, self._user_id or "")\n',
    '                client = nio.AsyncClient(\n'
    '                    self._homeserver,\n'
    '                    self._user_id or "",\n'
    '                    device_id=self._device_id or None,\n'
    '                )\n',
    "fallback plain AsyncClient device_id wiring",
)

replace_once(
    '            client = nio.AsyncClient(self._homeserver, self._user_id or "")\n',
    '            client = nio.AsyncClient(\n'
    '                self._homeserver,\n'
    '                self._user_id or "",\n'
    '                device_id=self._device_id or None,\n'
    '            )\n',
    "plain AsyncClient device_id wiring",
)

replace_once(
    '        # If E2EE: handle encrypted events.\n'
    '        if self._encryption and hasattr(client, "olm"):\n'
    '            client.add_event_callback(\n'
    '                self._on_room_message, nio.MegolmEvent\n'
    '            )\n',
    '        # If E2EE: handle encrypted events.\n'
    '        if self._encryption and hasattr(client, "olm"):\n'
    '            client.add_event_callback(\n'
    '                self._on_room_message, nio.MegolmEvent\n'
    '            )\n'
    '            client.add_to_device_callback(\n'
    '                self._on_key_verification,\n'
    '                (nio.KeyVerificationStart, nio.KeyVerificationCancel,\n'
    '                 nio.KeyVerificationKey, nio.KeyVerificationMac)\n'
    '            )\n',
    "verification callback registration",
)

replace_once(
    '    async def _on_invite(self, room: Any, event: Any) -> None:\n',
    '    async def _on_key_verification(self, event: Any) -> None:\n'
    '        """Auto-accept device verification from explicitly allowed users."""\n'
    '        import nio\n\n'
    '        if not self._client:\n'
    '            return\n\n'
    '        if not self._allowed_users:\n'
    '            logger.info(\n'
    '                "Matrix: ignoring verification from %s because MATRIX_ALLOWED_USERS is not configured",\n'
    '                event.sender,\n'
    '            )\n'
    '            return\n\n'
    '        if event.sender not in self._allowed_users:\n'
    '            logger.warning("Matrix: ignoring verification from unauthorized user %s", event.sender)\n'
    '            return\n\n'
    '        if isinstance(event, nio.KeyVerificationStart):\n'
    '            logger.info("Matrix: auto-accepting verification from %s", event.sender)\n'
    '            try:\n'
    '                await self._client.accept_key_verification(event.transaction_id)\n'
    '            except Exception as exc:\n'
    '                logger.error("Matrix: failed to accept verification: %s", exc)\n\n'
    '        elif isinstance(event, nio.KeyVerificationCancel):\n'
    '            logger.warning("Matrix: verification cancelled by %s", event.sender)\n\n'
    '        elif isinstance(event, nio.KeyVerificationKey):\n'
    '            logger.info("Matrix: received verification key from %s, confirming...", event.sender)\n'
    '            try:\n'
    '                await self._client.confirm_short_auth_string(event.transaction_id)\n'
    '            except Exception as exc:\n'
    '                logger.error("Matrix: failed to confirm SAS: %s", exc)\n\n'
    '        elif isinstance(event, nio.KeyVerificationMac):\n'
    '            logger.info("Matrix: verification MAC received from %s", event.sender)\n\n'
    '    async def _on_invite(self, room: Any, event: Any) -> None:\n',
    "_on_key_verification handler insertion",
)

path.write_text(text, encoding="utf-8")
