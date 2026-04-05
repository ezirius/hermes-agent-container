from pathlib import Path


path = Path("/home/hermes/hermes-agent/gateway/platforms/matrix.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f"could not apply matrix upload-filesize patch: {description}")
    text = text.replace(old, new, 1)


def insert_after_once(anchor: str, insertion: str, description: str) -> None:
    global text
    if anchor not in text:
        raise SystemExit(f"could not apply matrix upload-filesize patch: {description}")
    text = text.replace(anchor, anchor + insertion, 1)


if 'filesize=len(data),' not in text:
    if '            filename=filename,\n' in text:
        insert_after_once(
            '            filename=filename,\n',
            '            filesize=len(data),\n',
            "AsyncClient.upload call gains filesize for Matrix media uploads",
        )
    else:
        replace_once(
            '        resp = await self._client.upload(\n'
            '            io.BytesIO(data),\n'
            '            content_type=content_type,\n'
            '            filename=filename,\n'
            '        )\n',
            '        resp = await self._client.upload(\n'
            '            io.BytesIO(data),\n'
            '            content_type=content_type,\n'
            '            filename=filename,\n'
            '            filesize=len(data),\n'
            '        )\n',
            "AsyncClient.upload call gains filesize for Matrix media uploads",
        )

path.write_text(text, encoding="utf-8")
