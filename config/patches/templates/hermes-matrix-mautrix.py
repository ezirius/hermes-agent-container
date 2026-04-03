"""Matrix gateway adapter using mautrix.

Wrapper-managed replacement for the upstream matrix-nio adapter.
Designed for encrypted-room-first operation inside hermes-agent-container.
"""

from __future__ import annotations

import asyncio
import json
import logging
import mimetypes
import os
import re
import time
from pathlib import Path
from typing import Any, Dict, Optional, Set

from gateway.config import Platform, PlatformConfig
from gateway.platforms.base import (
    BasePlatformAdapter,
    MessageEvent,
    MessageType,
    SendResult,
)
from hermes_constants import get_hermes_dir as _get_hermes_dir

logger = logging.getLogger(__name__)

MAX_MESSAGE_LENGTH = 4000
_STORE_DIR = _get_hermes_dir("platforms/matrix/store", "matrix/store")
_STARTUP_GRACE_SECONDS = 5


def check_matrix_requirements() -> bool:
    token = os.getenv("MATRIX_ACCESS_TOKEN", "")
    password = os.getenv("MATRIX_PASSWORD", "")
    homeserver = os.getenv("MATRIX_HOMESERVER", "")
    if not token and not password:
        logger.debug("Matrix: neither MATRIX_ACCESS_TOKEN nor MATRIX_PASSWORD set")
        return False
    if not homeserver:
        logger.warning("Matrix: MATRIX_HOMESERVER not set")
        return False
    try:
        import mautrix.client  # noqa: F401
        import mautrix.crypto  # noqa: F401
        return True
    except ImportError:
        logger.warning(
            "Matrix: mautrix not installed. Run: pip install 'hermes-agent[matrix]'"
        )
        return False


class _LiteFileCryptoStore:
    """Lightweight persistence wrapper around mautrix MemoryCryptoStore.

    This preserves account, device ID and sync token across restarts. Session/device
    data stays in memory per runtime. That is not perfect, but it preserves stable
    device identity and reduces churn while keeping the wrapper self-contained.
    """

    def __init__(self, account_id: str, pickle_key: str, path: Path) -> None:
        from mautrix.crypto.store.memory import MemoryCryptoStore

        self._store = MemoryCryptoStore(account_id=account_id, pickle_key=pickle_key)
        self._path = path
        self.account_id = self._store.account_id
        self.pickle_key = self._store.pickle_key

    def __getattr__(self, name: str) -> Any:
        return getattr(self._store, name)

    async def open(self) -> None:
        if not self._path.exists():
            return
        try:
            raw = json.loads(self._path.read_text(encoding="utf-8"))
        except Exception as exc:
            logger.warning("Matrix: failed to read mautrix crypto state: %s", exc)
            return

        try:
            device_id = raw.get("device_id")
            if device_id:
                await self._store.put_device_id(device_id)
            next_batch = raw.get("next_batch")
            if next_batch:
                await self._store.put_next_batch(next_batch)
            account_pickle = raw.get("account_pickle")
            shared = bool(raw.get("account_shared", False))
            if account_pickle:
                from mautrix.crypto.account import OlmAccount

                account = OlmAccount.from_pickle(
                    account_pickle.encode("latin1"),
                    self.pickle_key,
                    shared=shared,
                )
                await self._store.put_account(account)
        except Exception as exc:
            logger.warning("Matrix: failed to restore mautrix crypto state: %s", exc)

    async def flush(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        payload: Dict[str, Any] = {}
        try:
            payload["device_id"] = await self._store.get_device_id()
            payload["next_batch"] = await self._store.get_next_batch()
            account = await self._store.get_account()
            if account is not None:
                payload["account_pickle"] = account.pickle(self.pickle_key).decode("latin1")
                payload["account_shared"] = bool(getattr(account, "shared", False))
        except Exception as exc:
            logger.warning("Matrix: failed to snapshot mautrix crypto state: %s", exc)
            return
        self._path.write_text(json.dumps(payload), encoding="utf-8")

    async def close(self) -> None:
        await self.flush()

    async def delete(self) -> None:
        if self._path.exists():
            self._path.unlink()
        await self._store.delete()


class MatrixAdapter(BasePlatformAdapter):
    """Gateway adapter for Matrix via mautrix."""

    def __init__(self, config: PlatformConfig):
        super().__init__(config, Platform.MATRIX)
        self._homeserver: str = (
            config.extra.get("homeserver", "") or os.getenv("MATRIX_HOMESERVER", "")
        ).rstrip("/")
        self._access_token: str = config.token or os.getenv("MATRIX_ACCESS_TOKEN", "")
        self._user_id: str = (
            config.extra.get("user_id", "") or os.getenv("MATRIX_USER_ID", "")
        )
        self._password: str = (
            config.extra.get("password", "") or os.getenv("MATRIX_PASSWORD", "")
        )
        self._encryption: bool = config.extra.get(
            "encryption",
            os.getenv("MATRIX_ENCRYPTION", "").lower() in ("true", "1", "yes"),
        )
        self._device_name: str = config.extra.get("device_name", "Hermes Agent")
        self._device_id: str = config.extra.get("device_id", os.getenv("MATRIX_DEVICE_ID", ""))
        self._pickle_key: str = os.getenv("MATRIX_PICKLE_KEY", "hermes-matrix")

        self._client: Any = None
        self._crypto_store: Any = None
        self._state_store: Any = None
        self._sync_task: Optional[asyncio.Task] = None
        self._closing = False
        self._startup_ts: float = 0.0

        self._dm_rooms: Dict[str, bool] = {}
        self._joined_rooms: Set[str] = set()
        from collections import deque
        self._processed_events: deque = deque(maxlen=1000)
        self._processed_events_set: set = set()

    def _is_duplicate_event(self, event_id) -> bool:
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
        from mautrix.client import Client
        from mautrix.client.state_store.file import FileStateStore
        from mautrix.crypto import OlmMachine

        if not self._homeserver:
            logger.error("Matrix: homeserver URL not configured")
            return False

        _STORE_DIR.mkdir(parents=True, exist_ok=True)
        state_store_path = _STORE_DIR / "mautrix_state.bin"
        crypto_store_path = _STORE_DIR / "mautrix_crypto.json"
        auth_state_path = _STORE_DIR / "mautrix_auth.json"

        self._state_store = FileStateStore(state_store_path)
        await self._state_store.open()

        account_id = self._user_id or "matrix-user"
        self._crypto_store = _LiteFileCryptoStore(account_id, self._pickle_key, crypto_store_path)
        await self._crypto_store.open()

        stored_device_id = self._device_id or (await self._crypto_store.get_device_id()) or ""
        stored_auth: Dict[str, Any] = {}
        if auth_state_path.exists():
            try:
                stored_auth = json.loads(auth_state_path.read_text(encoding="utf-8"))
            except Exception:
                stored_auth = {}
        effective_token = self._access_token or stored_auth.get("access_token", "")
        effective_user_id = self._user_id or stored_auth.get("user_id", "")

        client = Client(
            effective_user_id or "@unknown:invalid",
            base_url=self._homeserver,
            token=effective_token or None,
            sync_store=self._crypto_store,
            state_store=self._state_store,
        )
        self._client = client

        if effective_token:
            whoami = await client.whoami()
            self._user_id = str(whoami.user_id)
            self._device_id = str(getattr(whoami, "device_id", stored_device_id or ""))
            client.mxid = self._user_id
            client.device_id = self._device_id
            logger.info("Matrix: using access token for %s (device %s)", self._user_id, self._device_id or "unknown")
        elif self._password and (effective_user_id or self._user_id):
            login_resp = await client.login(
                identifier=effective_user_id or self._user_id,
                password=self._password,
                device_name=self._device_name,
                device_id=stored_device_id or None,
            )
            self._user_id = str(login_resp.user_id)
            self._device_id = str(login_resp.device_id)
            self._access_token = str(login_resp.access_token)
            auth_state_path.write_text(
                json.dumps(
                    {
                        "user_id": self._user_id,
                        "device_id": self._device_id,
                        "access_token": self._access_token,
                    }
                ),
                encoding="utf-8",
            )
            logger.info("Matrix: logged in as %s (device %s)", self._user_id, self._device_id)
        else:
            logger.error("Matrix: need MATRIX_ACCESS_TOKEN or MATRIX_USER_ID + MATRIX_PASSWORD")
            return False

        if self._device_id:
            await self._crypto_store.put_device_id(self._device_id)

        if self._encryption:
            crypto = OlmMachine(client, self._crypto_store, self._state_store)
            await crypto.load()
            client.crypto = crypto
            logger.info("Matrix: mautrix crypto initialised")

        from mautrix.types import EventType
        client.add_event_handler(EventType.ROOM_MESSAGE, self._on_room_message_event)
        client.add_event_handler(EventType.STICKER, self._on_sticker_event)
        client.add_event_handler(EventType.REACTION, self._on_reaction_event)
        client.add_event_handler(EventType.ROOM_REDACTION, self._on_redaction_event)
        client.add_event_handler(EventType.ROOM_MEMBER, self._on_member_event)
        client.add_event_handler(EventType.find("m.direct", EventType.Class.ACCOUNT_DATA), self._on_account_data_event)

        try:
            joined = await client.get_joined_rooms()
            self._joined_rooms = set(str(room_id) for room_id in joined)
        except Exception as exc:
            logger.warning("Matrix: failed to list joined rooms: %s", exc)

        self._startup_ts = time.time()
        self._closing = False
        self._sync_task = client.start(None)
        self._mark_connected()
        return True

    async def disconnect(self) -> None:
        self._closing = True
        if self._client:
            try:
                self._client.stop()
                if self._client.syncing_task:
                    try:
                        await self._client.syncing_task
                    except asyncio.CancelledError:
                        pass
                if self._crypto_store:
                    await self._crypto_store.close()
                if self._state_store:
                    await self._state_store.close()
            finally:
                self._client = None
        logger.info("Matrix: disconnected")

    async def send(self, chat_id: str, content: str, reply_to: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None) -> SendResult:
        from mautrix.types import RelatesTo, InReplyTo, RelationType

        if not content:
            return SendResult(success=True)
        if not self._client:
            return SendResult(success=False, error="Matrix client not connected")

        formatted = self.format_message(content)
        chunks = self.truncate_message(formatted, MAX_MESSAGE_LENGTH)
        last_event_id = None
        for chunk in chunks:
            html = self._markdown_to_html(chunk)
            relates_to = self._build_relates_to(reply_to=reply_to, metadata=metadata)
            try:
                last_event_id = await self._client.send_text(
                    chat_id,
                    text=chunk,
                    html=html if html and html != chunk else None,
                    relates_to=relates_to,
                )
            except Exception as exc:
                logger.error("Matrix: failed to send to %s: %s", chat_id, exc)
                return SendResult(success=False, error=str(exc))
        return SendResult(success=True, message_id=str(last_event_id) if last_event_id else None)

    async def get_chat_info(self, chat_id: str) -> Dict[str, Any]:
        return {
            "id": chat_id,
            "name": chat_id,
            "type": "dm" if self._dm_rooms.get(chat_id, False) else "group",
        }

    async def send_photo(self, chat_id: str, image_url: str, caption: Optional[str] = None, reply_to: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None) -> SendResult:
        import httpx
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            resp = await client.get(image_url)
            resp.raise_for_status()
            filename = Path(image_url).name or "image"
            mime = resp.headers.get("Content-Type") or mimetypes.guess_type(filename)[0] or "image/jpeg"
            return await self._upload_and_send_media(chat_id, resp.content, filename, mime, "m.image", caption, reply_to, metadata)

    async def send_image_file(self, chat_id: str, image_path: str, caption: Optional[str] = None, reply_to: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None) -> SendResult:
        return await self._send_local_file(chat_id, image_path, "m.image", caption, reply_to, metadata=metadata)

    async def send_document(self, chat_id: str, file_path: str, caption: Optional[str] = None, file_name: Optional[str] = None, reply_to: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None) -> SendResult:
        return await self._send_local_file(chat_id, file_path, "m.file", caption, reply_to, file_name=file_name, metadata=metadata)

    async def send_voice(self, chat_id: str, audio_path: str, caption: Optional[str] = None, reply_to: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None) -> SendResult:
        return await self._send_local_file(chat_id, audio_path, "m.audio", caption, reply_to, metadata=metadata, is_voice=True)

    async def send_video(self, chat_id: str, video_path: str, caption: Optional[str] = None, reply_to: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None) -> SendResult:
        return await self._send_local_file(chat_id, video_path, "m.video", caption, reply_to, metadata=metadata)

    def format_message(self, content: str) -> str:
        content = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", r"\2", content)
        return content

    async def _send_local_file(self, room_id: str, file_path: str, msgtype: str, caption: Optional[str] = None, reply_to: Optional[str] = None, file_name: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None, is_voice: bool = False) -> SendResult:
        p = Path(file_path)
        if not p.exists():
            return await self.send(room_id, f"{caption or ''}\n(file not found: {file_path})", reply_to)
        fname = file_name or p.name
        mime = mimetypes.guess_type(fname)[0] or "application/octet-stream"
        return await self._upload_and_send_media(room_id, p.read_bytes(), fname, mime, msgtype, caption, reply_to, metadata, is_voice=is_voice)

    async def _upload_and_send_media(self, room_id: str, data: bytes, filename: str, mime: str, msgtype: str, caption: Optional[str] = None, reply_to: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None, is_voice: bool = False) -> SendResult:
        from mautrix.crypto.attachments import encrypt_attachment
        from mautrix.types import EventType, MediaMessageEventContent, AudioInfo, ImageInfo, VideoInfo, FileInfo

        if not self._client:
            return SendResult(success=False, error="Matrix client not connected")

        encrypted_bytes, encrypted_file = encrypt_attachment(data)
        mxc = await self._client.upload_media(encrypted_bytes, mime_type="application/octet-stream", filename=filename, size=len(encrypted_bytes))
        encrypted_file.url = mxc

        if msgtype == "m.image":
            info = ImageInfo(mimetype=mime, size=len(data))
        elif msgtype == "m.video":
            info = VideoInfo(mimetype=mime, size=len(data))
        elif msgtype == "m.audio":
            info = AudioInfo(mimetype=mime, size=len(data))
        else:
            info = FileInfo(mimetype=mime, size=len(data))

        body = caption or filename
        content = MediaMessageEventContent(msgtype=msgtype, body=body, info=info, file=encrypted_file, filename=filename)
        if is_voice:
            content["org.matrix.msc3245.voice"] = {}
        relates_to = self._build_relates_to(reply_to=reply_to, metadata=metadata)
        if relates_to:
            content.relates_to = relates_to
        try:
            event_id = await self._client.send_message_event(room_id, EventType.ROOM_MESSAGE, content)
            return SendResult(success=True, message_id=str(event_id))
        except Exception as exc:
            logger.error("Matrix: failed to send media to %s: %s", room_id, exc)
            return SendResult(success=False, error=str(exc))

    def _build_relates_to(self, reply_to: Optional[str], metadata: Optional[Dict[str, Any]]) -> Any:
        from mautrix.types import RelatesTo, InReplyTo, RelationType

        reply_to = reply_to or None
        thread_id = (metadata or {}).get("thread_id") if metadata else None
        if not reply_to and not thread_id:
            return None
        relates_to = RelatesTo()
        if reply_to:
            relates_to.in_reply_to = InReplyTo(event_id=reply_to)
        if thread_id:
            relates_to.rel_type = RelationType.THREAD
            relates_to.event_id = thread_id
            relates_to.is_falling_back = True
            if not relates_to.in_reply_to:
                relates_to.in_reply_to = InReplyTo(event_id=thread_id)
        return relates_to

    async def _on_account_data_event(self, evt: Any) -> None:
        try:
            if getattr(evt, "type", None) and str(evt.type) == "m.direct":
                content = getattr(evt, "content", {}) or {}
                if isinstance(content, dict):
                    dm_rooms: Set[str] = set()
                    for room_ids in content.values():
                        if isinstance(room_ids, list):
                            dm_rooms.update(str(r) for r in room_ids)
                    for room_id in self._joined_rooms:
                        self._dm_rooms[room_id] = room_id in dm_rooms
        except Exception as exc:
            logger.debug("Matrix: failed to process m.direct account data: %s", exc)

    async def _on_member_event(self, evt: Any) -> None:
        try:
            room_id = str(getattr(evt, "room_id", ""))
            state_key = str(getattr(evt, "state_key", ""))
            content = getattr(evt, "content", None)
            membership = getattr(content, "membership", None)
            if room_id:
                self._joined_rooms.add(room_id)
            if state_key == self._user_id and str(membership) == "invite":
                try:
                    await self._client.join_room(room_id)
                    self._joined_rooms.add(room_id)
                    logger.info("Matrix: auto-joined invited room %s", room_id)
                except Exception as exc:
                    logger.warning("Matrix: failed to auto-join %s: %s", room_id, exc)
        except Exception as exc:
            logger.debug("Matrix: member event handling failed: %s", exc)

    async def _on_reaction_event(self, evt: Any) -> None:
        logger.debug("Matrix: ignoring reaction event %s", getattr(evt, "event_id", None))

    async def _on_redaction_event(self, evt: Any) -> None:
        logger.debug("Matrix: received redaction event %s", getattr(evt, "event_id", None))

    async def _on_sticker_event(self, evt: Any) -> None:
        await self._handle_message_like_event(evt, forced_type=MessageType.STICKER)

    async def _on_room_message_event(self, evt: Any) -> None:
        await self._handle_message_like_event(evt)

    async def _handle_message_like_event(self, evt: Any, forced_type: Optional[MessageType] = None) -> None:
        try:
            room_id = str(getattr(evt, "room_id", ""))
            sender = str(getattr(evt, "sender", ""))
            event_id = str(getattr(evt, "event_id", ""))
            if sender == self._user_id:
                return
            if self._is_duplicate_event(event_id):
                return
            event_ts = getattr(evt, "timestamp", None) or getattr(evt, "server_timestamp", 0)
            if event_ts and event_ts > 10_000_000_000:
                event_ts = event_ts / 1000.0
            if event_ts and event_ts < self._startup_ts - _STARTUP_GRACE_SECONDS:
                return

            content = getattr(evt, "content", None)
            body = getattr(content, "body", None) or ""
            msgtype = str(getattr(content, "msgtype", "")) if content is not None else ""
            relates_to = getattr(content, "relates_to", None)
            reply_to = getattr(getattr(relates_to, "in_reply_to", None), "event_id", None) if relates_to else None
            thread_id = getattr(relates_to, "event_id", None) if relates_to and str(getattr(relates_to, "rel_type", "")) == "m.thread" else None

            if msgtype == "m.text":
                message_type = MessageType.TEXT
            elif msgtype == "m.notice":
                message_type = MessageType.TEXT
            elif msgtype == "m.emote":
                message_type = MessageType.TEXT
            elif msgtype == "m.image":
                message_type = MessageType.PHOTO
            elif msgtype == "m.video":
                message_type = MessageType.VIDEO
            elif msgtype == "m.audio":
                message_type = MessageType.VOICE if isinstance(content, dict) and content.get("org.matrix.msc3245.voice") is not None else MessageType.AUDIO
                if hasattr(content, "get") and content.get("org.matrix.msc3245.voice") is not None:
                    message_type = MessageType.VOICE
                elif getattr(content, "__getitem__", None):
                    try:
                        if content["org.matrix.msc3245.voice"] is not None:
                            message_type = MessageType.VOICE
                    except Exception:
                        pass
            elif msgtype == "m.file":
                message_type = MessageType.DOCUMENT
            elif msgtype == "m.location":
                message_type = MessageType.LOCATION
            elif forced_type is not None:
                message_type = forced_type
            else:
                message_type = forced_type or MessageType.TEXT

            is_dm = await self._is_dm_room(room_id)
            source = self.build_source(
                chat_id=room_id,
                chat_type="dm" if is_dm else "group",
                user_id=sender,
                user_name=await self._get_display_name(room_id, sender),
                thread_id=thread_id,
            )

            media_urls = None
            media_types = None
            if message_type in {MessageType.PHOTO, MessageType.VIDEO, MessageType.AUDIO, MessageType.VOICE, MessageType.DOCUMENT, MessageType.STICKER}:
                local_path, local_type = await self._resolve_media_content(content, msgtype)
                if local_path:
                    media_urls = [local_path]
                    media_types = [local_type]

            msg_event = MessageEvent(
                text=body,
                message_type=message_type,
                source=source,
                raw_message=self._serialize_event(evt),
                message_id=event_id,
                reply_to_message_id=reply_to,
                media_urls=media_urls,
                media_types=media_types,
            )
            await self.handle_message(msg_event)
        except Exception as exc:
            logger.exception("Matrix: failed to handle event: %s", exc)

    async def _resolve_media_content(self, content: Any, msgtype: str) -> tuple[Optional[str], str]:
        from gateway.platforms.base import cache_audio_from_bytes, cache_document_from_bytes, cache_image_from_bytes
        from mautrix.crypto.attachments import decrypt_attachment

        file_obj = getattr(content, "file", None)
        url = getattr(content, "url", None)
        info = getattr(content, "info", None)
        mimetype = getattr(info, "mimetype", None) or mimetypes.guess_type(getattr(content, "filename", None) or getattr(content, "body", None) or "")[0] or "application/octet-stream"

        encrypted = file_obj is not None and getattr(file_obj, "url", None)
        mxc = getattr(file_obj, "url", None) if encrypted else url
        if not mxc:
            return None, mimetype

        data = await self._client.download_media(mxc)
        if encrypted:
            data = decrypt_attachment(data, file_obj.key.key, file_obj.hashes.get("sha256", ""), file_obj.iv)

        if msgtype in {"m.image", "m.sticker"}:
            ext = mimetypes.guess_extension(mimetype) or ".jpg"
            return cache_image_from_bytes(data, ext=ext), mimetype
        if msgtype == "m.audio":
            ext = mimetypes.guess_extension(mimetype) or ".ogg"
            return cache_audio_from_bytes(data, ext=ext), mimetype
        if msgtype == "m.video":
            filename = getattr(content, "filename", None) or getattr(content, "body", None) or f"video{mimetypes.guess_extension(mimetype) or '.mp4'}"
            return cache_document_from_bytes(data, filename), mimetype
        filename = getattr(content, "filename", None) or getattr(content, "body", None) or "document.bin"
        return cache_document_from_bytes(data, filename), mimetype

    async def _is_dm_room(self, room_id: str) -> bool:
        cached = self._dm_rooms.get(room_id)
        if cached is not None:
            return cached
        try:
            members = await self._client.get_joined_members(room_id)
            is_dm = len(members) == 2
            self._dm_rooms[room_id] = is_dm
            return is_dm
        except Exception:
            return False

    async def _get_display_name(self, room_id: str, user_id: str) -> str:
        try:
            members = await self._client.get_joined_members(room_id)
            member = members.get(user_id)
            if member and getattr(member, "displayname", None):
                return str(member.displayname)
        except Exception:
            pass
        return user_id

    def _serialize_event(self, evt: Any) -> Dict[str, Any]:
        try:
            if hasattr(evt, "serialize"):
                return evt.serialize()
        except Exception:
            pass
        return getattr(evt, "__dict__", {}) or {}

    def _markdown_to_html(self, text: str) -> str:
        text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        text = re.sub(r"\*(.+?)\*", r"<em>\1</em>", text)
        text = text.replace("\n", "<br>")
        return text
