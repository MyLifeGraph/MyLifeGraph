import json
from datetime import UTC, datetime
from decimal import Decimal


def lossless_json_text(value: object, *, depth: int = 0) -> str:
    if depth > 64:
        raise ValueError("JSON nesting is too deep.")
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, Decimal):
        if not value.is_finite():
            raise ValueError("JSON contains a non-finite number.")
        return str(value)
    if isinstance(value, float):
        return json.dumps(value, allow_nan=False, separators=(",", ":"))
    if isinstance(value, datetime):
        if value.tzinfo is None:
            raise ValueError("JSON contains a naive timestamp.")
        timestamp = value.isoformat()
        if value.utcoffset() == UTC.utcoffset(value):
            timestamp = timestamp.replace("+00:00", "Z")
        return json.dumps(timestamp, ensure_ascii=False)
    if isinstance(value, (list, tuple)):
        return (
            "["
            + ",".join(lossless_json_text(item, depth=depth + 1) for item in value)
            + "]"
        )
    if isinstance(value, dict):
        chunks: list[str] = []
        for key, item in value.items():
            if not isinstance(key, str):
                raise TypeError("JSON keys must be strings.")
            chunks.append(
                f"{json.dumps(key, ensure_ascii=False)}:"
                f"{lossless_json_text(item, depth=depth + 1)}",
            )
        return "{" + ",".join(chunks) + "}"
    raise TypeError("Value is not JSON-compatible.")
