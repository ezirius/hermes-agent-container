from pathlib import Path


path = Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text

    if old not in text:
        raise SystemExit(f"could not apply Matrix patch: {description}")
    text = text.replace(old, new, 1)


replace_once(
    """    def _is_duplicate_event(self, event_id) -> bool:\n        \"\"\"Return True if this event was already processed. Tracks the ID otherwise.\"\"\"\n        if not event_id:\n            return False\n        if event_id in self._processed_events_set:\n            return True\n        if len(self._processed_events) == self._processed_events.maxlen:\n            evicted = self._processed_events[0]\n            self._processed_events_set.discard(evicted)\n        self._processed_events.append(event_id)\n        self._processed_events_set.add(event_id)\n        return False\n""",
    """    def _is_duplicate_event(self, event_id) -> bool:\n        \"\"\"Return True if this event was already processed. Tracks the ID otherwise.\"\"\"\n        if not event_id:\n            return False\n        if event_id in self._processed_events_set:\n            return True\n        if len(self._processed_events) == self._processed_events.maxlen:\n            evicted = self._processed_events[0]\n            self._processed_events_set.discard(evicted)\n        self._processed_events.append(event_id)\n        self._processed_events_set.add(event_id)\n        return False\n\n    def _describe_sync_issue(self, resp: Any) -> str:\n        \"\"\"Summarise a Matrix sync failure response for logs.\"\"\"\n        details = [f\"type={type(resp).__name__}\"]\n\n        for attr in (\"message\", \"status_code\", \"retry_after_ms\", \"soft_logout\"):\n            value = getattr(resp, attr, None)\n            if value not in (None, \"\", [], {}, False):\n                details.append(f\"{attr}={value}\")\n\n        transport_response = getattr(resp, \"transport_response\", None)\n        if transport_response is not None:\n            status = getattr(transport_response, \"status\", None)\n            reason = getattr(transport_response, \"reason\", None)\n            if status is not None:\n                details.append(f\"http_status={status}\")\n            if reason:\n                details.append(f\"http_reason={reason}\")\n\n        payload = None\n        for attr in (\"source\", \"content\", \"body\", \"response_dict\"):\n            value = getattr(resp, attr, None)\n            if value not in (None, \"\", [], {}):\n                payload = value\n                break\n\n        if payload is None:\n            payload = getattr(resp, \"__dict__\", None)\n\n        if payload not in (None, \"\", [], {}):\n            try:\n                rendered = json.dumps(payload, sort_keys=True, default=str)\n            except TypeError:\n                rendered = str(payload)\n            rendered = rendered.replace(\"\\n\", \" \")\n            if len(rendered) > 500:\n                rendered = f\"{rendered[:497]}...\"\n            details.append(f\"payload={rendered}\")\n\n        return \", \\".join(details)\n""",
    "helper insertion",
)

replace_once(
    """        resp = await client.sync(timeout=10000, full_state=True)\n        if isinstance(resp, nio.SyncResponse):\n            self._joined_rooms = set(resp.rooms.join.keys())\n            logger.info(\n                \"Matrix: initial sync complete, joined %d rooms\",\n                len(self._joined_rooms),\n            )\n            # Build DM room cache from m.direct account data.\n            await self._refresh_dm_cache()\n        else:\n            logger.warning(\"Matrix: initial sync returned %s\", type(resp).__name__)\n\n        # Start the sync loop.\n""",
    """        resp = await client.sync(timeout=10000, full_state=True)\n        if isinstance(resp, nio.SyncResponse):\n            self._joined_rooms = set(resp.rooms.join.keys())\n            logger.info(\n                \"Matrix: initial sync complete, joined %d rooms\",\n                len(self._joined_rooms),\n            )\n            # Build DM room cache from m.direct account data.\n            await self._refresh_dm_cache()\n        else:\n            logger.warning(\n                \"Matrix: initial sync failed: %s\",\n                self._describe_sync_issue(resp),\n            )\n            await client.close()\n            self._client = None\n            return False\n\n        # Start the sync loop.\n""",
    "initial sync failure handling",
)

replace_once(
    """    async def _sync_loop(self) -> None:\n        \"\"\"Continuously sync with the homeserver.\"\"\"\n        while not self._closing:\n            try:\n                await self._client.sync(timeout=30000)\n            except asyncio.CancelledError:\n                return\n            except Exception as exc:\n                if self._closing:\n                    return\n                logger.warning(\"Matrix: sync error: %s — retrying in 5s\", exc)\n                await asyncio.sleep(5)\n""",
    """    async def _sync_loop(self) -> None:\n        \"\"\"Continuously sync with the homeserver.\"\"\"\n        import nio\n\n        while not self._closing:\n            try:\n                resp = await self._client.sync(timeout=30000)\n                if not isinstance(resp, nio.SyncResponse):\n                    logger.warning(\n                        \"Matrix: sync returned non-success response: %s — retrying in 5s\",\n                        self._describe_sync_issue(resp),\n                    )\n                    await asyncio.sleep(5)\n            except asyncio.CancelledError:\n                return\n            except Exception as exc:\n                if self._closing:\n                    return\n                logger.warning(\"Matrix: sync error: %s — retrying in 5s\", exc)\n                await asyncio.sleep(5)\n""",
    "sync loop diagnostics",
)

path.write_text(text, encoding="utf-8")
