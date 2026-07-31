import json
import re
from typing import Any

from pydantic import ValidationError

from app.models.coach import CoachAgentModelOutput, CoachModelOutput
from app.providers.base import (
    CoachProviderError,
    CoachProviderResult,
)


_MAX_EVENTS = 128
_FORBIDDEN_EVENT_PARTS = {
    "approval",
    "browser",
    "command",
    "computer",
    "delegat",
    "exec",
    "file",
    "hook",
    "image",
    "mcp",
    "plugin",
    "search",
    "shell",
    "tool",
}
_ALLOWED_EVENT_TYPES = {
    "thread.started",
    "turn.started",
    "item.started",
    "item.completed",
    "turn.completed",
    "error",
}
_ALLOWED_CONTENT_ITEM_TYPES = {"reasoning", "agent_message"}
_NON_FATAL_ERROR_ITEM_TYPE = "error"
AGENT_ALLOWED_TOOLS = frozenset({"inspect_data", "query_data", "run_python"})


def reject_unsafe_event_line(line: bytes) -> None:
    """Reject unsafe or terminal failure events while the process is running."""

    try:
        event = json.loads(line.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned an invalid event.",
            retryable=True,
        ) from exc
    if not isinstance(event, dict):
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned an invalid event.",
            retryable=True,
        )
    _raise_if_unsafe_event(event)
    if event.get("type") in {"error", "turn.failed"}:
        raise mapped_process_failure(line, b"")


def _raise_if_unsafe_event(event: Any) -> None:
    if isinstance(event, dict) and _has_unsafe_nested_shape(event):
        raise CoachProviderError(
            "unsafe_provider_event",
            "The local Coach provider attempted an unsupported operation.",
            retryable=False,
        )


def parse_event_stream(
    stdout: bytes,
    *,
    final_output: bytes | None = None,
) -> CoachProviderResult:
    final_text: str | None = None
    model_reported: str | None = None
    seen_thread_started = False
    seen_turn_started = False
    seen_content_item_event = False
    seen_turn_completed = False
    try:
        lines = stdout.decode("utf-8", errors="strict").splitlines()
    except UnicodeDecodeError as exc:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned invalid text encoding.",
            retryable=True,
        ) from exc
    if not lines or len(lines) > _MAX_EVENTS:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned an invalid event stream.",
            retryable=True,
        )
    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned invalid output.",
                retryable=True,
            ) from exc
        if not isinstance(event, dict):
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an unexpected event.",
                retryable=True,
            )
        _raise_if_unsafe_event(event)
        extra_event_keys = set(event) - {
            "type",
            "thread_id",
            "item",
            "usage",
            "message",
            "model",
        }
        if extra_event_keys and any(
            any(part in key.lower() for part in _FORBIDDEN_EVENT_PARTS)
            for key in extra_event_keys
        ):
            raise CoachProviderError(
                "unsafe_provider_event",
                "The local Coach provider attempted an unsupported operation.",
                retryable=False,
            )
        if extra_event_keys:
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an unexpected event.",
                retryable=True,
            )
        usage = event.get("usage")
        if usage is not None:
            if not isinstance(usage, dict):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned invalid usage data.",
                    retryable=True,
                )
            if _has_unsafe_nested_shape(usage):
                raise CoachProviderError(
                    "unsafe_provider_event",
                    "The local Coach provider attempted an unsupported operation.",
                    retryable=False,
                )
        message = event.get("message")
        if message is not None and not isinstance(message, str):
            if _has_unsafe_nested_shape(message):
                raise CoachProviderError(
                    "unsafe_provider_event",
                    "The local Coach provider attempted an unsupported operation.",
                    retryable=False,
                )
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned invalid error data.",
                retryable=True,
            )
        event_type = event.get("type")
        if not isinstance(event_type, str):
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an unsupported event.",
                retryable=True,
            )
        if any(part in event_type.lower() for part in _FORBIDDEN_EVENT_PARTS):
            raise CoachProviderError(
                "unsafe_provider_event",
                "The local Coach provider attempted an unsupported operation.",
                retryable=False,
            )
        if event_type in {"error", "turn.failed"}:
            raise mapped_process_failure(line.encode("utf-8"), b"")
        if event_type not in _ALLOWED_EVENT_TYPES:
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an unsupported event.",
                retryable=True,
            )
        if event_type == "thread.started":
            if (
                seen_thread_started
                or seen_turn_started
                or event.get("item") is not None
            ):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid event sequence.",
                    retryable=True,
                )
            seen_thread_started = True
        elif event_type == "turn.started":
            if (
                not seen_thread_started
                or seen_turn_started
                or seen_content_item_event
                or seen_turn_completed
                or event.get("item") is not None
            ):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid event sequence.",
                    retryable=True,
                )
            seen_turn_started = True
        elif event_type in {"item.started", "item.completed"}:
            if (
                not seen_thread_started
                or seen_turn_completed
                or event.get("item") is None
            ):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid event sequence.",
                    retryable=True,
                )
        elif event_type == "turn.completed":
            if (
                not seen_thread_started
                or seen_turn_completed
                or event.get("item") is not None
            ):
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid event sequence.",
                    retryable=True,
                )
            seen_turn_completed = True
        _validated_event_text(
            event.get("thread_id"),
            field="thread_id",
            limit=200,
        )
        reported = _validated_event_text(
            event.get("model"),
            field="model",
            limit=100,
        )
        if reported is not None:
            model_reported = reported
        item = event.get("item")
        if item is None:
            continue
        if not isinstance(item, dict):
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an invalid item.",
                retryable=True,
            )
        item_type = item.get("type")
        if not isinstance(item_type, str):
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an invalid item.",
                retryable=True,
            )
        if any(part in item_type.lower() for part in _FORBIDDEN_EVENT_PARTS):
            raise CoachProviderError(
                "unsafe_provider_event",
                "The local Coach provider attempted an unsupported operation.",
                retryable=False,
            )
        if item_type == _NON_FATAL_ERROR_ITEM_TYPE:
            if event_type != "item.completed" or set(event) != {"type", "item"}:
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid non-fatal error item.",
                    retryable=True,
                )
            if set(item) != {"id", "type", "message"}:
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid non-fatal error item.",
                    retryable=True,
                )
            error_item_id = _validated_event_text(
                item.get("id"),
                field="item id",
                limit=200,
            )
            error_message = _validated_event_text(
                item.get("message"),
                field="non-fatal error item message",
                limit=4_096,
            )
            if error_item_id is None or error_message is None:
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid non-fatal error item.",
                    retryable=True,
                )
            continue
        if item_type not in _ALLOWED_CONTENT_ITEM_TYPES:
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned an unsupported item.",
                retryable=True,
            )
        if set(item) - {"id", "type", "text"} or _has_unsafe_nested_shape(item):
            raise CoachProviderError(
                "unsafe_provider_event",
                "The local Coach provider attempted an unsupported operation.",
                retryable=False,
            )
        item_text = item.get("text")
        if "text" in item and (
            not isinstance(item_text, str) or len(item_text) > 16_384
        ):
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned invalid item text.",
                retryable=True,
            )
        seen_content_item_event = True
        if item_type == "agent_message" and event_type == "item.completed":
            text = item_text
            if not isinstance(text, str) or final_text is not None:
                raise CoachProviderError(
                    "invalid_output",
                    "The local Coach provider returned an invalid final answer.",
                    retryable=True,
                )
            final_text = text
    if final_text is None or not seen_thread_started or not seen_turn_completed:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned no final answer.",
            retryable=True,
        )
    if final_output is not None:
        try:
            final_file_text = final_output.decode("utf-8", errors="strict").strip()
        except UnicodeDecodeError as exc:
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider returned invalid text encoding.",
                retryable=True,
            ) from exc
        if final_file_text != final_text.strip():
            raise CoachProviderError(
                "invalid_output",
                "The local Coach provider final answer was inconsistent.",
                retryable=True,
            )
    try:
        payload: Any = json.loads(final_text)
        output = CoachModelOutput.model_validate(payload)
    except (json.JSONDecodeError, ValidationError) as exc:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach provider returned an invalid answer.",
            retryable=True,
        ) from exc
    return CoachProviderResult(output=output, model_reported=model_reported)


def _has_unsafe_nested_shape(value: Any) -> bool:
    if isinstance(value, dict):
        for key, nested in value.items():
            lowered = str(key).lower()
            if any(part in lowered for part in _FORBIDDEN_EVENT_PARTS):
                return True
            if (
                key == "type"
                and isinstance(nested, str)
                and any(part in nested.lower() for part in _FORBIDDEN_EVENT_PARTS)
            ):
                return True
            if (
                key != "text" or not isinstance(nested, str)
            ) and _has_unsafe_nested_shape(nested):
                return True
    elif isinstance(value, list):
        return any(_has_unsafe_nested_shape(item) for item in value)
    return False


def _validated_event_text(
    value: Any,
    *,
    field: str,
    limit: int,
) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        normalized = value.strip()
        if normalized and len(normalized) <= limit:
            return normalized
    if _has_unsafe_nested_shape(value):
        raise CoachProviderError(
            "unsafe_provider_event",
            "The local Coach provider attempted an unsupported operation.",
            retryable=False,
        )
    raise CoachProviderError(
        "invalid_output",
        f"The local Coach provider returned an invalid {field}.",
        retryable=True,
    )


def mapped_process_failure(stdout: bytes, stderr: bytes) -> CoachProviderError:
    """Classify bounded machine errors without exposing their raw content."""

    fragments: list[str] = []
    for line in stdout.splitlines()[:_MAX_EVENTS]:
        try:
            event = json.loads(line.decode("utf-8", errors="strict"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
        if not isinstance(event, dict) or event.get("type") not in {
            "error",
            "turn.failed",
        }:
            continue
        message = event.get("message")
        if isinstance(message, str):
            fragments.append(message[:4_096])
        error = event.get("error")
        if isinstance(error, str):
            fragments.append(error[:4_096])
        elif isinstance(error, dict):
            for key in ("code", "message", "type"):
                value = error.get(key)
                if isinstance(value, str):
                    fragments.append(value[:4_096])
    structured = "\n".join(fragments).encode("utf-8")
    return mapped_failure(stderr + b"\n" + structured)


def mapped_failure(stderr: bytes) -> CoachProviderError:
    diagnostic = stderr.decode("utf-8", errors="replace").lower()
    if any(
        marker in diagnostic
        for marker in [
            "not logged in",
            "login required",
            "authentication required",
            "unauthorized",
        ]
    ):
        return CoachProviderError(
            "not_logged_in",
            "The local Codex CLI is not authenticated.",
            retryable=False,
        )
    if any(
        marker in diagnostic
        for marker in [
            "model not found",
            "unknown model",
            "unsupported model",
            "model is not supported",
            "model does not exist",
            "model unavailable",
            "model_not_found",
            "unsupported_model",
        ]
    ) or re.search(
        r"\bmodel\b.{0,160}\b(?:not supported|not available|does not exist)\b",
        diagnostic,
        flags=re.DOTALL,
    ):
        return CoachProviderError(
            "unavailable_model",
            "The explicitly configured Coach model is unavailable.",
            retryable=False,
        )
    if any(
        marker in diagnostic
        for marker in ["rate limit", "usage limit", "account limit", "quota"]
    ):
        return CoachProviderError(
            "account_limit",
            "The local Codex account limit has been reached.",
            retryable=True,
        )
    return CoachProviderError(
        "provider_failure",
        "The local Coach provider failed.",
        retryable=True,
    )


def validate_agent_event_line(line: bytes) -> None:
    try:
        event = json.loads(line.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach agent returned an invalid event.",
            retryable=True,
        ) from exc
    if not isinstance(event, dict):
        raise CoachProviderError(
            "invalid_output",
            "The local Coach agent returned an invalid event.",
            retryable=True,
        )
    event_type = event.get("type")
    if event_type in {"error", "turn.failed"}:
        raise mapped_process_failure(line, b"")
    if event_type not in _ALLOWED_EVENT_TYPES:
        raise CoachProviderError(
            "unsafe_provider_event",
            "The local Coach agent attempted an unsupported operation.",
            retryable=False,
        )
    item = event.get("item")
    if item is None:
        return
    if not isinstance(item, dict):
        raise CoachProviderError(
            "invalid_output",
            "The local Coach agent returned an invalid item.",
            retryable=True,
        )
    item_type = item.get("type")
    if item_type in {"reasoning", "agent_message", "error"}:
        return
    if item_type not in {"mcp_tool_call", "mcp_call"}:
        raise CoachProviderError(
            "unsafe_provider_event",
            "The local Coach agent attempted a non-MCP operation.",
            retryable=False,
        )
    server = item.get("server") or item.get("server_name")
    tool = item.get("tool") or item.get("name")
    if server not in {None, "coach_data"}:
        raise CoachProviderError(
            "unsafe_provider_event",
            "The local Coach agent attempted another MCP server.",
            retryable=False,
        )
    if isinstance(tool, str):
        normalized = tool.rsplit("__", 1)[-1]
    else:
        normalized = None
    if normalized not in AGENT_ALLOWED_TOOLS:
        raise CoachProviderError(
            "unsafe_provider_event",
            "The local Coach agent attempted an unsupported MCP tool.",
            retryable=False,
        )


def parse_agent_output(value: bytes) -> CoachAgentModelOutput:
    try:
        payload = json.loads(value.decode("utf-8", errors="strict"))
        return CoachAgentModelOutput.model_validate(payload)
    except (UnicodeDecodeError, json.JSONDecodeError, ValidationError) as exc:
        raise CoachProviderError(
            "invalid_output",
            "The local Coach agent returned an invalid answer.",
            retryable=True,
        ) from exc


def reported_model(stdout: bytes) -> str | None:
    reported: str | None = None
    try:
        lines = stdout.decode("utf-8", errors="strict").splitlines()
    except UnicodeDecodeError:
        return None
    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict) and isinstance(event.get("model"), str):
            candidate = event["model"].strip()
            if candidate:
                reported = candidate[:100]
    return reported
