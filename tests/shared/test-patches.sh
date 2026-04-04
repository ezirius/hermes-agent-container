#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || { printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2; exit 1; }
}

assert_not_contains() {
  local file="$1" needle="$2" message="$3"
  if grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nunexpected: %s\n' "$message" "$needle" >&2
    exit 1
  fi
}

UPSTREAM_ROOT="$TMPDIR/upstream"
mkdir -p "$UPSTREAM_ROOT/agent" "$UPSTREAM_ROOT/gateway/platforms"

cat > "$UPSTREAM_ROOT/agent/prompt_builder.py" <<'EOF'
from pathlib import Path

from hermes_constants import get_hermes_home


def _load_agents_md(cwd_path: Path) -> str:
    """AGENTS.md — top-level only (no recursive walk)."""
    for name in ["AGENTS.md", "agents.md"]:
        candidate = cwd_path / name
        if candidate.exists():
            try:
                content = candidate.read_text(encoding="utf-8").strip()
                if content:
                    content = _scan_context_content(content, name)
                    result = f"## {name}\n\n{content}"
                    return _truncate_content(result, "AGENTS.md")
            except Exception as e:
                logger.debug("Could not read %s: %s", candidate, e)
    return ""
EOF

cat > "$UPSTREAM_ROOT/gateway/platforms/matrix.py" <<'EOF'
"""Matrix gateway adapter.

Connects to any Matrix homeserver (self-hosted or matrix.org) via the
matrix-nio Python SDK.  Supports optional end-to-end encryption (E2EE)
when installed with ``pip install "matrix-nio[e2e]"``.

Environment variables:
    MATRIX_HOMESERVER       Homeserver URL (e.g. https://matrix.example.org)
    MATRIX_ACCESS_TOKEN     Access token (preferred auth method)
    MATRIX_USER_ID          Full user ID (@bot:server) — required for password login
    MATRIX_PASSWORD         Password (alternative to access token)
    MATRIX_ENCRYPTION       Set "true" to enable E2EE
    MATRIX_ALLOWED_USERS    Comma-separated Matrix user IDs (@user:server)
    MATRIX_HOME_ROOM        Room ID for cron/notification delivery
"""

from __future__ import annotations

import asyncio
import mimetypes
import os
import time
from pathlib import Path
from typing import Any, Dict, Optional, Set


class MessageType:
    DOCUMENT = "document"
    PHOTO = "photo"
    AUDIO = "audio"
    VOICE = "voice"
    VIDEO = "video"


class MessageEvent:
    def __init__(self, **kwargs):
        self.kwargs = kwargs


_STARTUP_GRACE_SECONDS = 5


class MatrixAdapter:
    def __init__(self, config):
        self._access_token = "token"
        self._password = "password"
        self._user_id = "@bot:example.org"
        self._homeserver = "https://matrix.example.org"
        self._encryption: bool = config.extra.get(
            "encryption",
            os.getenv("MATRIX_ENCRYPTION", "").lower() in ("true", "1", "yes"),
        )

        self._client: Any = None  # nio.AsyncClient
        self._sync_task: Optional[asyncio.Task] = None
        self._closing = False
        self._startup_ts: float = 0.0
        self._dm_rooms = {}
        from collections import deque
        self._processed_events: deque = deque(maxlen=1000)
        self._processed_events_set: set = set()
        self._pending_megolm = []

    def _is_duplicate_event(self, event_id) -> bool:
        """Return True if this event was already processed. Tracks the ID otherwise."""
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

    async def connect(self) -> bool:
        import nio
        client = self._client
        if self._access_token:
            resp = await client.whoami()
            if isinstance(resp, nio.WhoamiResponse):
                resolved_user_id = getattr(resp, "user_id", "") or self._user_id
                resolved_device_id = getattr(resp, "device_id", "")
                if resolved_user_id:
                    self._user_id = resolved_user_id

                # restore_login() is the matrix-nio path that binds the access
                # token to a specific device and loads the crypto store.
                if resolved_device_id and hasattr(client, "restore_login"):
                    client.restore_login(
                        self._user_id or resolved_user_id,
                        resolved_device_id,
                        self._access_token,
                    )
                else:
                    if self._user_id:
                        client.user_id = self._user_id
                    if resolved_device_id:
                        client.device_id = resolved_device_id
                    client.access_token = self._access_token
                    if self._encryption:
                        logger.warning(
                            "Matrix: access-token login did not restore E2EE state; "
                            "encrypted rooms may fail until a device_id is available"
                        )

                logger.info(
                    "Matrix: using access token for %s%s",
                    self._user_id or "(unknown user)",
                    f" (device {resolved_device_id})" if resolved_device_id else "",
                )
        elif self._password and self._user_id:
            resp = await client.login(
                self._password,
                device_name="Hermes Agent",
            )
            if isinstance(resp, nio.LoginResponse):
                logger.info("Matrix: logged in as %s", self._user_id)

        # Register event callbacks.
        client.add_event_callback(self._on_room_message, nio.RoomMessageText)
        client.add_event_callback(self._on_room_message_media, nio.RoomMessageImage)
        client.add_event_callback(self._on_room_message_media, nio.RoomMessageAudio)
        client.add_event_callback(self._on_room_message_media, nio.RoomMessageVideo)
        client.add_event_callback(self._on_room_message_media, nio.RoomMessageFile)
        client.add_event_callback(self._on_invite, nio.InviteMemberEvent)

        # If E2EE: handle encrypted events.
        if self._encryption and hasattr(client, "olm"):
            client.add_event_callback(
                self._on_room_message, nio.MegolmEvent
            )
        return True

    async def _retry_pending_decryptions(self) -> None:
        import nio
        still_pending = []
        for room, event, ts in self._pending_megolm:
            decrypted = event
            if isinstance(decrypted, nio.MegolmEvent):
                # decrypt_event returned the same undecryptable event.
                still_pending.append((room, event, ts))
                continue

            logger.info(
                "Matrix: decrypted buffered event %s (%s)",
                getattr(event, "event_id", "?"),
                type(decrypted).__name__,
            )

            # Route to the appropriate handler based on decrypted type.
            try:
                if isinstance(decrypted, nio.RoomMessageText):
                    await self._on_room_message(room, decrypted)
                elif isinstance(
                    decrypted,
                    (nio.RoomMessageImage, nio.RoomMessageAudio,
                     nio.RoomMessageVideo, nio.RoomMessageFile),
                ):
                    await self._on_room_message_media(room, decrypted)
                else:
                    logger.debug(
                        "Matrix: decrypted event %s has unhandled type %s",
                        getattr(event, "event_id", "?"),
                        type(decrypted).__name__,
                    )
            except Exception as exc:
                logger.warning("Matrix: error handling decrypted buffered event: %s", exc)
        self._pending_megolm = still_pending

    async def _on_room_message(self, room: Any, event: Any) -> None:
        return None

    async def _on_room_message_media(self, room: Any, event: Any) -> None:
        """Handle incoming media messages (images, audio, video, files)."""
        import nio

        # Ignore own messages.
        if event.sender == self._user_id:
            return

        # Deduplicate by event ID.
        if self._is_duplicate_event(getattr(event, "event_id", None)):
            return

        # Startup grace.
        event_ts = getattr(event, "server_timestamp", 0) / 1000.0
        if event_ts and event_ts < self._startup_ts - _STARTUP_GRACE_SECONDS:
            return

        body = getattr(event, "body", "") or ""
        url = getattr(event, "url", "")

        # Convert mxc:// to HTTP URL for downstream processing.
        http_url = ""
        if url and url.startswith("mxc://"):
            http_url = self._mxc_to_http(url)

        # Determine message type from event class.
        # Use the MIME type from the event's content info when available,
        # falling back to category-level MIME types for downstream matching
        # (gateway/run.py checks startswith("image/"), startswith("audio/"), etc.)
        content_info = getattr(event, "content", {}) if isinstance(getattr(event, "content", None), dict) else {}
        event_mimetype = (content_info.get("info") or {}).get("mimetype", "")
        media_type = "application/octet-stream"
        msg_type = MessageType.DOCUMENT
        is_voice_message = False

        if isinstance(event, nio.RoomMessageImage):
            msg_type = MessageType.PHOTO
            media_type = event_mimetype or "image/png"
        elif isinstance(event, nio.RoomMessageAudio):
            # Check for MSC3245 voice flag: org.matrix.msc3245.voice: {}
            source_content = getattr(event, "source", {}).get("content", {})
            if source_content.get("org.matrix.msc3245.voice") is not None:
                is_voice_message = True
                msg_type = MessageType.VOICE
            else:
                msg_type = MessageType.AUDIO
            media_type = event_mimetype or "audio/ogg"
        elif isinstance(event, nio.RoomMessageVideo):
            msg_type = MessageType.VIDEO
            media_type = event_mimetype or "video/mp4"
        elif event_mimetype:
            media_type = event_mimetype

        # For images, download and cache locally so vision tools can access them.
        # Matrix MXC URLs require authentication, so direct URL access fails.
        cached_path = None
        if msg_type == MessageType.PHOTO and url:
            try:
                ext_map = {
                    "image/jpeg": ".jpg", "image/png": ".png",
                    "image/gif": ".gif", "image/webp": ".webp",
                }
                ext = ext_map.get(event_mimetype, ".jpg")
                download_resp = await self._client.download(url)
                if isinstance(download_resp, nio.DownloadResponse):
                    from gateway.platforms.base import cache_image_from_bytes
                    cached_path = cache_image_from_bytes(download_resp.body, ext=ext)
                    logger.info("[Matrix] Cached user image at %s", cached_path)
            except Exception as e:
                logger.warning("[Matrix] Failed to cache image: %s", e)

        is_dm = self._dm_rooms.get(room.room_id, False)
        if not is_dm and room.member_count == 2:
            is_dm = True
        chat_type = "dm" if is_dm else "group"

        # Thread/reply detection.
        source_content = getattr(event, "source", {}).get("content", {})
        relates_to = source_content.get("m.relates_to", {})
        thread_id = None
        if relates_to.get("rel_type") == "m.thread":
            thread_id = relates_to.get("event_id")

        # For voice messages, cache audio locally for transcription tools.
        # Use the authenticated nio client to download (Matrix requires auth for media).
        media_urls = [http_url] if http_url else None
        media_types = [media_type] if http_url else None

        if is_voice_message and url and url.startswith("mxc://"):
            try:
                import nio
                from gateway.platforms.base import cache_audio_from_bytes

                resp = await self._client.download(mxc=url)
                if isinstance(resp, nio.MemoryDownloadResponse):
                    # Extract extension from mimetype or default to .ogg
                    ext = ".ogg"
                    if media_type and "/" in media_type:
                        subtype = media_type.split("/")[1]
                        ext = f".{subtype}" if subtype else ".ogg"
                    local_path = cache_audio_from_bytes(resp.body, ext)
                    media_urls = [local_path]
                    logger.debug("Matrix: cached voice message to %s", local_path)
                else:
                    logger.warning("Matrix: failed to download voice: %s", getattr(resp, "message", resp))
            except Exception as e:
                logger.warning("Matrix: failed to cache voice message, using HTTP URL: %s", e)

        source = self.build_source(
            chat_id=room.room_id,
            chat_type=chat_type,
            user_id=event.sender,
            user_name=self._get_display_name(room, event.sender),
            thread_id=thread_id,
        )

        # Use cached local path for images (voice messages already handled above).
        if cached_path:
            media_urls = [cached_path]
        media_types = [media_type] if media_urls else None

        msg_event = MessageEvent(
            text=body,
            message_type=msg_type,
            source=source,
            raw_message=getattr(event, "source", {}),
            message_id=event.event_id,
            media_urls=media_urls,
            media_types=media_types,
        )

        await self.handle_message(msg_event)

    async def _on_invite(self, room: Any, event: Any) -> None:
        return None

    def _mxc_to_http(self, mxc_url: str) -> str:
        """Convert mxc://server/media_id to an HTTP download URL."""
        if not mxc_url.startswith("mxc://"):
            return mxc_url
        parts = mxc_url[6:]
        return f"{self._homeserver}/_matrix/client/v1/media/download/{parts}"
EOF

python3 - "$ROOT" "$UPSTREAM_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
upstream_root = Path(sys.argv[2])

host_patch = (root / 'config/patches/apply-hermes-host-agents-context.py').read_text(encoding='utf-8')
host_patch = host_patch.replace('Path("/home/hermes/hermes-agent/agent/prompt_builder.py")', f'Path({str(upstream_root / "agent/prompt_builder.py")!r})')
exec(compile(host_patch, 'apply-hermes-host-agents-context.py', 'exec'), {})

matrix_patch = (root / 'config/patches/apply-hermes-matrix-device-id.py').read_text(encoding='utf-8')
matrix_patch = matrix_patch.replace('Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")', f'Path({str(upstream_root / "gateway/platforms/matrix.py")!r})')
exec(compile(matrix_patch, 'apply-hermes-matrix-device-id.py', 'exec'), {})

encrypted_media_patch = (root / 'config/patches/apply-hermes-matrix-encrypted-media.py').read_text(encoding='utf-8')
encrypted_media_patch = encrypted_media_patch.replace('Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")', f'Path({str(upstream_root / "gateway/platforms/matrix.py")!r})')
exec(compile(encrypted_media_patch, 'apply-hermes-matrix-encrypted-media.py', 'exec'), {})
PY

python3 -m py_compile "$UPSTREAM_ROOT/agent/prompt_builder.py" "$UPSTREAM_ROOT/gateway/platforms/matrix.py"

assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'prefer HERMES_HOME, then cwd top-level only' 'host AGENTS patch updates prompt builder precedence'
assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'hermes_home_agents = get_hermes_home() / "AGENTS.md"' 'host AGENTS patch prefers HERMES_HOME AGENTS file'
assert_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'if candidate.exists() and candidate != hermes_home_agents:' 'host AGENTS patch preserves cwd fallback without duplicating HERMES_HOME'
assert_not_contains "$UPSTREAM_ROOT/agent/prompt_builder.py" 'mautrix' 'host AGENTS patch should stay independent of Matrix strategy'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'MATRIX_DEVICE_ID        Optional stable device ID for password login' 'matrix patch documents MATRIX_DEVICE_ID'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'self._device_id: str = (' 'matrix patch adds stable device field'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'Matrix: MATRIX_DEVICE_ID=%s ignored for access-token auth; homeserver restored device %s' 'matrix patch warns when access-token auth chooses a different device'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'auth_dict["device_id"] = self._device_id' 'matrix patch forwards MATRIX_DEVICE_ID in password auth'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'resp = await client.login_raw(auth_dict)' 'matrix patch uses login_raw for stable device reuse'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'requested for password login, but homeserver returned device %s' 'matrix patch warns when password login returns a different device'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'response omitted device_id; continuing with requested device %s' 'matrix patch warns when the login response omits device_id'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'if self._encryption and getattr(client, "olm", None):' 'encrypted media patch uses truthy crypto-loaded callback gate'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" '"RoomEncryptedAudio"' 'encrypted media patch registers encrypted audio callback names'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'self._allow_reprocess_event(getattr(decrypted, "event_id", None))' 'encrypted media patch allows retried media events to bypass duplicate suppression'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'from nio.crypto import decrypt_attachment' 'encrypted media patch uses nio attachment decrypt helper'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'def _get_encrypted_filename(self, content: Dict[str, Any], media_type: str) -> str:' 'encrypted media patch adds filename selection helper'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'cache_document_from_bytes' 'encrypted media patch caches encrypted file/video payloads locally'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'media_urls = None' 'encrypted media patch drops bogus fallback URLs on decrypt failure'
assert_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'logger.info("Matrix: cached encrypted media %s to %s", event.event_id, cached_path)' 'encrypted media patch logs successful encrypted-media cache writes'
assert_not_contains "$UPSTREAM_ROOT/gateway/platforms/matrix.py" 'if self._encryption and hasattr(client, "olm"):' 'encrypted media patch removes weaker encrypted callback gate'

if [ "${HERMES_UPSTREAM_PATCH_SMOKE:-0}" = "1" ]; then
  REAL_UPSTREAM_ROOT="${HERMES_UPSTREAM_REPO:-/home/hermes/hermes-agent}"
  if [ ! -f "$REAL_UPSTREAM_ROOT/gateway/platforms/matrix.py" ]; then
    printf 'assertion failed: HERMES_UPSTREAM_PATCH_SMOKE=1 but upstream repo not found at %s\n' "$REAL_UPSTREAM_ROOT" >&2
    exit 1
  fi

  REAL_TMP="$TMPDIR/real-upstream"
  mkdir -p "$REAL_TMP/gateway/platforms"
  cp "$REAL_UPSTREAM_ROOT/gateway/platforms/matrix.py" "$REAL_TMP/gateway/platforms/matrix.py"

  python3 - "$ROOT" "$REAL_TMP" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
real_tmp = Path(sys.argv[2])

matrix_patch = (root / 'config/patches/apply-hermes-matrix-encrypted-media.py').read_text(encoding='utf-8')
matrix_patch = matrix_patch.replace('Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")', f'Path({str(real_tmp / "gateway/platforms/matrix.py")!r})')
exec(compile(matrix_patch, 'apply-hermes-matrix-encrypted-media.py', 'exec'), {})
PY

  python3 -m py_compile "$REAL_TMP/gateway/platforms/matrix.py"
  assert_contains "$REAL_TMP/gateway/platforms/matrix.py" 'RoomEncryptedAudio' 'real upstream smoke keeps encrypted audio callback registration'
  assert_contains "$REAL_TMP/gateway/platforms/matrix.py" 'from nio.crypto import decrypt_attachment' 'real upstream smoke keeps nio attachment decrypt helper'
  assert_contains "$REAL_TMP/gateway/platforms/matrix.py" 'cache_document_from_bytes' 'real upstream smoke keeps local document cache path for encrypted file/video'
  printf 'Real upstream patch smoke passed (%s)\n' "$REAL_UPSTREAM_ROOT"
fi

echo "Patch application checks passed"
