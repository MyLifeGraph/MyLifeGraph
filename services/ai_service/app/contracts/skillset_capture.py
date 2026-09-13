"""Optional check-in extension; never replaces existing Capture evidence."""

SKILLSET_CAPTURE_VERSION = "skillset-capture-v1"


def valid_skillset_signals(raw: object, *, morning: bool) -> bool:
    if not isinstance(raw, dict) or raw.get("version") != SKILLSET_CAPTURE_VERSION:
        return False
    allowed = {"motivation"} if morning else {"sport", "social"}
    return not (raw.keys() - allowed - {"version"}) and all(
        value is None or type(value) is int and 0 <= value <= 2
        for key, value in raw.items()
        if key != "version"
    )
