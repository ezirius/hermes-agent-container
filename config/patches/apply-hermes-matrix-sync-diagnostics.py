from pathlib import Path


path = Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text

    if old not in text:
        raise SystemExit(f"could not apply Matrix patch: {description}")
    text = text.replace(old, new, 1)


helper_old = """    def _is_duplicate_event(self, event_id) -> bool:
        \"\"\"Return True if this event was already processed. Tracks the ID otherwise.\"\"\"
        if not event_id:
            return False
        if event_id in self._processed_events_set:
            return True
        if len(self._processed_events) == self._processed_events.maxlen:
            evicted = self._processed_events[0]
            self._processed_events_set.discard(evicted)
        self._processed_events.append(event_id)
        self._processed_events_set.add(event_id)
        return False
"""

helper_new = """    def _is_duplicate_event(self, event_id) -> bool:
        \"\"\"Return True if this event was already processed. Tracks the ID otherwise.\"\"\"
        if not event_id:
            return False
        if event_id in self._processed_events_set:
            return True
        if len(self._processed_events) == self._processed_events.maxlen:
            evicted = self._processed_events[0]
            self._processed_events_set.discard(evicted)
        self._processed_events.append(event_id)
        self._processed_events_set.add(event_id)
        return False

    def _describe_sync_issue(self, resp: Any) -> str:
        \"\"\"Summarise a Matrix sync failure response for logs.\"\"\"
        details = [f\"type={type(resp).__name__}\"]

        for attr in (\"message\", \"status_code\", \"retry_after_ms\", \"soft_logout\"):
            value = getattr(resp, attr, None)
            if value not in (None, \"\", [], {}, False):
                details.append(f\"{attr}={value}\")

        transport_response = getattr(resp, \"transport_response\", None)
        if transport_response is not None:
            status = getattr(transport_response, \"status\", None)
            reason = getattr(transport_response, \"reason\", None)
            if status is not None:
                details.append(f\"http_status={status}\")
            if reason:
                details.append(f\"http_reason={reason}\")

        payload = None
        for attr in (\"source\", \"content\", \"body\", \"response_dict\"):
            value = getattr(resp, attr, None)
            if value not in (None, \"\", [], {}):
                payload = value
                break

        if payload is None:
            payload = getattr(resp, \"__dict__\", None)

        if payload not in (None, \"\", [], {}):
            try:
                rendered = json.dumps(payload, sort_keys=True, default=str)
            except TypeError:
                rendered = str(payload)
            rendered = rendered.replace(\"\\n\", \" \")
            if len(rendered) > 500:
                rendered = f\"{rendered[:497]}...\"
            details.append(f\"payload={rendered}\")

        return \", \".join(details)
"""

initial_sync_old = """        resp = await client.sync(timeout=10000, full_state=True)
        if isinstance(resp, nio.SyncResponse):
            self._joined_rooms = set(resp.rooms.join.keys())
            logger.info(
                \"Matrix: initial sync complete, joined %d rooms\",
                len(self._joined_rooms),
            )
            # Build DM room cache from m.direct account data.
            await self._refresh_dm_cache()
        else:
            logger.warning(\"Matrix: initial sync returned %s\", type(resp).__name__)

        # Start the sync loop.
"""

initial_sync_new = """        resp = await client.sync(timeout=10000, full_state=True)
        if isinstance(resp, nio.SyncResponse):
            self._joined_rooms = set(resp.rooms.join.keys())
            logger.info(
                \"Matrix: initial sync complete, joined %d rooms\",
                len(self._joined_rooms),
            )
            # Build DM room cache from m.direct account data.
            await self._refresh_dm_cache()
        else:
            logger.warning(
                \"Matrix: initial sync failed: %s\",
                self._describe_sync_issue(resp),
            )
            await client.close()
            self._client = None
            return False

        # Start the sync loop.
"""

sync_loop_old = """    async def _sync_loop(self) -> None:
        \"\"\"Continuously sync with the homeserver.\"\"\"
        while not self._closing:
            try:
                await self._client.sync(timeout=30000)
            except asyncio.CancelledError:
                return
            except Exception as exc:
                if self._closing:
                    return
                logger.warning(\"Matrix: sync error: %s - retrying in 5s\", exc)
                await asyncio.sleep(5)
"""

sync_loop_old_alt = """    async def _sync_loop(self) -> None:
        \"\"\"Continuously sync with the homeserver.\"\"\"
        while not self._closing:
            try:
                await self._client.sync(timeout=30000)
            except asyncio.CancelledError:
                return
            except Exception as exc:
                if self._closing:
                    return
                logger.warning(\"Matrix: sync error: %s — retrying in 5s\", exc)
                await asyncio.sleep(5)
"""

sync_loop_new = """    async def _sync_loop(self) -> None:
        \"\"\"Continuously sync with the homeserver.\"\"\"
        import nio

        while not self._closing:
            try:
                resp = await self._client.sync(timeout=30000)
                if not isinstance(resp, nio.SyncResponse):
                    logger.warning(
                        \"Matrix: sync returned non-success response: %s - retrying in 5s\",
                        self._describe_sync_issue(resp),
                    )
                    await asyncio.sleep(5)
            except asyncio.CancelledError:
                return
            except Exception as exc:
                if self._closing:
                    return
                logger.warning(\"Matrix: sync error: %s - retrying in 5s\", exc)
                await asyncio.sleep(5)
"""

replace_once(helper_old, helper_new, "helper insertion")
replace_once(initial_sync_old, initial_sync_new, "initial sync failure handling")
replace_once(
    "import asyncio\n",
    "import asyncio\nimport json\n",
    "json import",
)

if sync_loop_old in text:
    text = text.replace(sync_loop_old, sync_loop_new, 1)
elif sync_loop_old_alt in text:
    text = text.replace(sync_loop_old_alt, sync_loop_new, 1)
else:
    raise SystemExit("could not apply Matrix patch: sync loop diagnostics")

path.write_text(text, encoding="utf-8")
