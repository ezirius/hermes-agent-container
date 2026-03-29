from pathlib import Path
import re


path = Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")
text = path.read_text(encoding="utf-8")


def replace_regex_once(pattern: str, replacement: str, description: str) -> None:
    global text

    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"could not apply Matrix patch: {description}")
    text = updated


def replace_regex_once_fn(pattern: str, replacer, description: str) -> None:
    global text

    updated, count = re.subn(pattern, replacer, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"could not apply Matrix patch: {description}")
    text = updated


if "import json\n" not in text:
    replace_regex_once(
        r"^import asyncio\n",
        "import asyncio\nimport json\n",
        "json import",
    )


if "def _describe_sync_issue(self, resp: Any) -> str:" not in text:
    replace_regex_once_fn(
        r"(    def _is_duplicate_event\(self, event_id\) -> bool:\n(?:        .*\n)+?        return False\n)",
        lambda match: match.group(1)
        + '''

    def _describe_sync_issue(self, resp: Any) -> str:
        """Summarise a Matrix sync failure response for logs."""
        details = [f"type={type(resp).__name__}"]

        for attr in ("message", "status_code", "retry_after_ms", "soft_logout"):
            value = getattr(resp, attr, None)
            if value not in (None, "", [], {}, False):
                details.append(f"{attr}={value}")

        transport_response = getattr(resp, "transport_response", None)
        if transport_response is not None:
            status = getattr(transport_response, "status", None)
            reason = getattr(transport_response, "reason", None)
            if status is not None:
                details.append(f"http_status={status}")
            if reason:
                details.append(f"http_reason={reason}")

        payload = None
        for attr in ("source", "content", "body", "response_dict"):
            value = getattr(resp, attr, None)
            if value not in (None, "", [], {}):
                payload = value
                break

        if payload is None:
            payload = getattr(resp, "__dict__", None)

        if payload not in (None, "", [], {}):
            try:
                rendered = json.dumps(payload, sort_keys=True, default=str)
            except TypeError:
                rendered = str(payload)
            rendered = rendered.replace("\\n", " ")
            if len(rendered) > 500:
                rendered = f"{rendered[:497]}..."
            details.append(f"payload={rendered}")

        return ", ".join(details)
''',
        "helper insertion",
    )


replace_regex_once(
    r'''        else:\n            logger\.warning\("Matrix: initial sync returned %s", type\(resp\)\.__name__\)\n\n        # Start the sync loop\.\n''',
    '''        else:
            logger.warning(
                "Matrix: initial sync failed: %s",
                self._describe_sync_issue(resp),
            )
            await client.close()
            self._client = None
            return False

        # Start the sync loop.
''',
    "initial sync failure handling",
)


replace_regex_once(
    r'''(?s)    async def _sync_loop\(self\) -> None:\n.*?(?=\n    async def _run_e2ee_maintenance\(self\) -> None:|\n    # ------------------------------------------------------------------\n    # Event callbacks)''',
    '''    async def _sync_loop(self) -> None:
        """Continuously sync with the homeserver."""
        import nio

        while not self._closing:
            try:
                resp = await self._client.sync(timeout=30000)
                if not isinstance(resp, nio.SyncResponse):
                    if self._closing:
                        return
                    logger.warning(
                        "Matrix: sync returned non-success response: %s - retrying in 5s",
                        self._describe_sync_issue(resp),
                    )
                    await asyncio.sleep(5)
                    continue

                if hasattr(self, "_run_e2ee_maintenance"):
                    await self._run_e2ee_maintenance()
            except asyncio.CancelledError:
                return
            except Exception as exc:
                if self._closing:
                    return
                logger.warning("Matrix: sync error: %s - retrying in 5s", exc)
                await asyncio.sleep(5)
''',
    "sync loop diagnostics",
)


path.write_text(text, encoding="utf-8")
