"""Strict length-prefixed protocol shared by FastAPI and Coach executor."""

from __future__ import annotations

import asyncio
import json
import struct
from collections.abc import Iterable
from datetime import UTC, datetime
from typing import Any


COACH_EXECUTOR_PROTOCOL_VERSION = "coach-executor-v1"
COACH_EXECUTOR_MAX_REQUEST_BYTES = 12 * 1024 * 1024
COACH_EXECUTOR_MAX_RESPONSE_BYTES = 512 * 1024
COACH_EXECUTOR_MAX_PROMPT_BYTES = 256 * 1024
COACH_EXECUTOR_MAX_TRACE_BYTES = 256 * 1024
COACH_EXECUTOR_MAX_SNAPSHOT_BYTES = 8 * 1024 * 1024
COACH_EXECUTOR_RESERVATION_SECONDS = 240
COACH_EXECUTOR_IO_TIMEOUT_SECONDS = 5

_FRAME_HEADER = struct.Struct("!I")


class ExecutorProtocolError(ValueError):
    pass


class ExecutorProtocolTimeout(ExecutorProtocolError):
    """A bounded transport timeout, distinct from malformed protocol input."""


def exact_object(
    value: object,
    *,
    keys: Iterable[str],
    label: str,
) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != set(keys):
        raise ExecutorProtocolError(f"{label} has an invalid shape.")
    return value


def bounded_text(
    value: object,
    *,
    label: str,
    max_bytes: int,
    allow_empty: bool = False,
) -> str:
    if not isinstance(value, str):
        raise ExecutorProtocolError(f"{label} must be text.")
    if not allow_empty and not value:
        raise ExecutorProtocolError(f"{label} must not be empty.")
    try:
        encoded = value.encode("utf-8", errors="strict")
    except UnicodeEncodeError as exc:
        raise ExecutorProtocolError(f"{label} is not valid UTF-8 text.") from exc
    if len(encoded) > max_bytes:
        raise ExecutorProtocolError(f"{label} exceeds its byte limit.")
    return value


def utc_datetime(value: object, *, label: str) -> datetime:
    text = bounded_text(value, label=label, max_bytes=64)
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ExecutorProtocolError(f"{label} is invalid.") from exc
    if parsed.tzinfo is None:
        raise ExecutorProtocolError(f"{label} must include an offset.")
    return parsed.astimezone(UTC)


def decode_json_object(raw: bytes, *, label: str) -> dict[str, Any]:
    try:
        text = raw.decode("utf-8", errors="strict")
        value = json.loads(text, object_pairs_hook=_unique_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ExecutorProtocolError(f"{label} is not valid JSON.") from exc
    if not isinstance(value, dict):
        raise ExecutorProtocolError(f"{label} must be a JSON object.")
    return value


def encode_json_object(value: dict[str, Any], *, max_bytes: int) -> bytes:
    try:
        raw = json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            separators=(",", ":"),
        ).encode("utf-8", errors="strict")
    except (TypeError, ValueError, UnicodeEncodeError) as exc:
        raise ExecutorProtocolError("Protocol response is not serializable.") from exc
    if not raw or len(raw) > max_bytes:
        raise ExecutorProtocolError("Protocol response exceeds its byte limit.")
    return raw


async def read_frame(
    reader: asyncio.StreamReader,
    *,
    max_bytes: int,
    timeout_seconds: float = COACH_EXECUTOR_IO_TIMEOUT_SECONDS,
) -> bytes:
    try:
        async with asyncio.timeout(timeout_seconds):
            header = await reader.readexactly(_FRAME_HEADER.size)
            (size,) = _FRAME_HEADER.unpack(header)
            if size == 0 or size > max_bytes:
                raise ExecutorProtocolError("Protocol frame size is invalid.")
            return await reader.readexactly(size)
    except asyncio.IncompleteReadError as exc:
        raise ExecutorProtocolError("Protocol frame ended early.") from exc
    except TimeoutError as exc:
        raise ExecutorProtocolTimeout("Protocol frame timed out.") from exc


async def write_frame(
    writer: asyncio.StreamWriter,
    value: dict[str, Any],
    *,
    max_bytes: int,
    timeout_seconds: float = COACH_EXECUTOR_IO_TIMEOUT_SECONDS,
) -> None:
    raw = encode_json_object(value, max_bytes=max_bytes)
    writer.write(_FRAME_HEADER.pack(len(raw)))
    writer.write(raw)
    try:
        async with asyncio.timeout(timeout_seconds):
            await writer.drain()
    except TimeoutError as exc:
        raise ExecutorProtocolTimeout("Protocol response write timed out.") from exc


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ExecutorProtocolError("Protocol JSON contains a duplicate key.")
        value[key] = item
    return value
