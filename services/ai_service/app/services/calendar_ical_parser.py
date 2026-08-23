import hashlib
import json
import re
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Literal
from uuid import UUID, uuid5
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.calendar_integrations import CalendarImportCounts


MAX_CALENDAR_BYTES = 512 * 1024
MAX_VEVENTS = 2_000
MAX_ACCEPTED_EVENTS = 500
EVENT_NAMESPACE = UUID("855784cd-0e0f-4c89-a689-edf8c6776270")
_DATE = re.compile(r"^\d{8}$")
_DATE_TIME = re.compile(r"^\d{8}T\d{6}$")
_UTC_DATE_TIME = re.compile(r"^\d{8}T\d{6}Z$")


class CalendarParseError(ValueError):
    pass


class CalendarEnvelopeError(CalendarParseError):
    pass


class CalendarImportLimitError(CalendarParseError):
    pass


class CalendarDuplicateConflictError(CalendarParseError):
    pass


class _InvalidComponent(ValueError):
    pass


@dataclass(frozen=True)
class ParsedCalendarEvent:
    id: UUID
    source_event_key: str
    source_fingerprint: str
    title: str
    location: str | None
    event_kind: Literal["timed", "all_day"]
    busy_status: Literal["busy", "free"]
    event_status: Literal["confirmed", "tentative"]
    event_timezone: str
    timezone_source: Literal["utc", "event", "profile"]
    starts_at: datetime | None
    ends_at: datetime | None
    local_starts_at: datetime | None
    local_ends_at: datetime | None
    starts_on: date | None
    ends_on: date | None
    last_modified_at: datetime | None
    sort_date: date
    sort_time: time

    def persistence_payload(self) -> dict[str, object]:
        return {
            "id": str(self.id),
            "source_event_key": self.source_event_key,
            "source_fingerprint": self.source_fingerprint,
            "title": self.title,
            "location": self.location,
            "event_kind": self.event_kind,
            "busy_status": self.busy_status,
            "event_status": self.event_status,
            "event_timezone": self.event_timezone,
            "timezone_source": self.timezone_source,
            "starts_at": _iso(self.starts_at),
            "ends_at": _iso(self.ends_at),
            "local_starts_at": _iso(self.local_starts_at),
            "local_ends_at": _iso(self.local_ends_at),
            "starts_on": _iso(self.starts_on),
            "ends_on": _iso(self.ends_on),
            "last_modified_at": _iso(self.last_modified_at),
            "sort_date": self.sort_date.isoformat(),
            "sort_time": self.sort_time.isoformat(),
        }


@dataclass(frozen=True)
class ParsedCalendarSnapshot:
    events: tuple[ParsedCalendarEvent, ...]
    cancelled_source_keys: tuple[str, ...]
    counts: CalendarImportCounts
    source_fingerprint: str
    input_fingerprint: str


@dataclass(frozen=True)
class _Property:
    name: str
    params: dict[str, str]
    value: str


@dataclass(frozen=True)
class _Temporal:
    kind: Literal["timed", "all_day"]
    aware: datetime | None
    local: datetime | None
    day: date | None
    timezone: str
    timezone_source: Literal["utc", "event", "profile"]


def parse_ical_snapshot(
    *,
    calendar_text: str,
    connection_id: UUID,
    profile_timezone: str,
    starts_on: date,
    ends_before: date,
) -> ParsedCalendarSnapshot:
    encoded = calendar_text.encode("utf-8")
    if len(encoded) > MAX_CALENDAR_BYTES:
        raise CalendarImportLimitError("iCalendar input exceeds 512 KiB.")
    try:
        profile_zone = ZoneInfo(profile_timezone)
    except ZoneInfoNotFoundError as exc:
        raise CalendarEnvelopeError("Profile timezone is invalid.") from exc
    if ends_before.toordinal() - starts_on.toordinal() != 105:
        raise CalendarEnvelopeError("Calendar import window is invalid.")

    components = _parse_calendar_components(calendar_text)
    if len(components) > MAX_VEVENTS:
        raise CalendarImportLimitError("iCalendar input exceeds 2,000 VEVENTs.")

    events_by_key: dict[str, ParsedCalendarEvent] = {}
    cancelled_keys: set[str] = set()
    out_of_window = 0
    unsupported_recurring = 0
    invalid = 0
    window_starts_at = datetime.combine(
        starts_on,
        time.min,
        tzinfo=profile_zone,
    ).astimezone(UTC)
    window_ends_at = datetime.combine(
        ends_before,
        time.min,
        tzinfo=profile_zone,
    ).astimezone(UTC)

    for component in components:
        try:
            properties = _properties_by_name(component)
            recurrence_id = _single(properties, "RECURRENCE-ID", required=False)
            if (
                any(name in properties for name in ("RRULE", "RDATE", "EXDATE"))
                and recurrence_id is None
            ):
                unsupported_recurring += 1
                continue
            uid_property = _single(properties, "UID", required=True)
            assert uid_property is not None
            uid = _unescape_text(uid_property.value)
            if (
                not uid
                or uid != uid.strip()
                or len(uid.encode("utf-8")) > 1_024
            ):
                raise _InvalidComponent("VEVENT UID is invalid")
            recurrence_key = (
                _recurrence_key(recurrence_id, profile_zone)
                if recurrence_id is not None
                else "single"
            )
            source_event_key = _digest(
                {
                    "contract": "calendar-import-v1",
                    "connection_id": str(connection_id),
                    "uid": uid,
                    "occurrence": recurrence_key,
                },
            )
            event_id = uuid5(
                EVENT_NAMESPACE,
                f"{connection_id}:{uid}:{recurrence_key}",
            )
            status_property = _single(properties, "STATUS", required=False)
            raw_status = (
                status_property.value.strip().upper()
                if status_property is not None
                else "CONFIRMED"
            )
            if raw_status not in {"CONFIRMED", "TENTATIVE", "CANCELLED"}:
                raise _InvalidComponent("VEVENT STATUS is invalid")
            if raw_status == "CANCELLED":
                if source_event_key in events_by_key:
                    raise CalendarDuplicateConflictError(
                        "Conflicting duplicate VEVENT identity.",
                    )
                cancelled_keys.add(source_event_key)
                continue
            if source_event_key in cancelled_keys:
                raise CalendarDuplicateConflictError(
                    "Conflicting duplicate VEVENT identity.",
                )

            start_property = _single(properties, "DTSTART", required=True)
            end_property = _single(properties, "DTEND", required=False)
            assert start_property is not None
            parsed_start = _parse_temporal(start_property, profile_zone)
            parsed_end = (
                _parse_temporal(end_property, profile_zone)
                if end_property is not None
                else None
            )
            if parsed_start.kind == "timed":
                if parsed_end is None or parsed_end.kind != "timed":
                    raise _InvalidComponent("Timed VEVENT requires DTEND")
                _require_coherent_temporals(parsed_start, parsed_end)
                assert parsed_start.aware is not None and parsed_end.aware is not None
                if parsed_end.aware <= parsed_start.aware:
                    raise _InvalidComponent("VEVENT interval is not positive")
                if not (
                    parsed_end.aware > window_starts_at
                    and parsed_start.aware < window_ends_at
                ):
                    out_of_window += 1
                    continue
                profile_local_start = parsed_start.aware.astimezone(profile_zone)
                sort_date = profile_local_start.date()
                sort_time = profile_local_start.time().replace(tzinfo=None)
                starts_at = parsed_start.aware.astimezone(UTC)
                ends_at = parsed_end.aware.astimezone(UTC)
                starts_on_value = None
                ends_on_value = None
            else:
                if parsed_end is None:
                    assert parsed_start.day is not None
                    parsed_end = _Temporal(
                        kind="all_day",
                        aware=None,
                        local=None,
                        day=parsed_start.day + timedelta(days=1),
                        timezone=profile_timezone,
                        timezone_source="profile",
                    )
                if parsed_end.kind != "all_day":
                    raise _InvalidComponent("All-day VEVENT requires date DTEND")
                assert parsed_start.day is not None and parsed_end.day is not None
                if parsed_end.day <= parsed_start.day:
                    raise _InvalidComponent("VEVENT interval is not positive")
                if not (
                    parsed_end.day > starts_on and parsed_start.day < ends_before
                ):
                    out_of_window += 1
                    continue
                sort_date = parsed_start.day
                sort_time = time.min
                starts_at = None
                ends_at = None
                starts_on_value = parsed_start.day
                ends_on_value = parsed_end.day

            summary_property = _single(properties, "SUMMARY", required=False)
            location_property = _single(properties, "LOCATION", required=False)
            transparency_property = _single(properties, "TRANSP", required=False)
            transparency = (
                transparency_property.value.strip().upper()
                if transparency_property is not None
                else "OPAQUE"
            )
            if transparency not in {"OPAQUE", "TRANSPARENT"}:
                raise _InvalidComponent("VEVENT TRANSP is invalid")
            last_modified_property = _single(
                properties,
                "LAST-MODIFIED",
                required=False,
            )
            last_modified = (
                _parse_utc_timestamp(last_modified_property.value)
                if last_modified_property is not None
                else None
            )
            title = _bounded_text(summary_property, maximum=200) or "Busy"
            location = _bounded_text(location_property, maximum=300)
            fingerprint_payload = {
                "title": title,
                "location": location,
                "event_kind": parsed_start.kind,
                "busy_status": "free" if transparency == "TRANSPARENT" else "busy",
                "event_status": raw_status.lower(),
                "event_timezone": parsed_start.timezone,
                "timezone_source": parsed_start.timezone_source,
                "starts_at": _iso(starts_at),
                "ends_at": _iso(ends_at),
                "local_starts_at": _iso(parsed_start.local),
                "local_ends_at": _iso(parsed_end.local),
                "starts_on": _iso(starts_on_value),
                "ends_on": _iso(ends_on_value),
                "last_modified_at": _iso(last_modified),
            }
            event = ParsedCalendarEvent(
                id=event_id,
                source_event_key=source_event_key,
                source_fingerprint=_digest(fingerprint_payload),
                title=title,
                location=location,
                event_kind=parsed_start.kind,
                busy_status="free" if transparency == "TRANSPARENT" else "busy",
                event_status="tentative" if raw_status == "TENTATIVE" else "confirmed",
                event_timezone=parsed_start.timezone,
                timezone_source=parsed_start.timezone_source,
                starts_at=starts_at,
                ends_at=ends_at,
                local_starts_at=parsed_start.local,
                local_ends_at=parsed_end.local,
                starts_on=starts_on_value,
                ends_on=ends_on_value,
                last_modified_at=last_modified,
                sort_date=sort_date,
                sort_time=sort_time,
            )
            existing = events_by_key.get(source_event_key)
            if existing is not None:
                if existing.source_fingerprint != event.source_fingerprint:
                    raise CalendarDuplicateConflictError(
                        "Conflicting duplicate VEVENT identity.",
                    )
                continue
            events_by_key[source_event_key] = event
            if len(events_by_key) > MAX_ACCEPTED_EVENTS:
                raise CalendarImportLimitError(
                    "iCalendar input exceeds 500 accepted events.",
                )
        except CalendarParseError:
            raise
        except (_InvalidComponent, ValueError, OverflowError):
            invalid += 1

    ordered_events = tuple(
        sorted(
            events_by_key.values(),
            key=lambda item: (
                item.sort_date,
                item.sort_time,
                str(item.id),
            ),
        ),
    )
    ordered_cancelled = tuple(sorted(cancelled_keys))
    counts = CalendarImportCounts(
        accepted=len(ordered_events),
        cancelled=len(ordered_cancelled),
        out_of_window=out_of_window,
        unsupported_recurring=unsupported_recurring,
        invalid=invalid,
    )
    source_fingerprint = _digest(
        {
            "events": [
                {
                    "source_event_key": event.source_event_key,
                    "source_fingerprint": event.source_fingerprint,
                }
                for event in ordered_events
            ],
            "cancelled_source_keys": ordered_cancelled,
            "counts": counts.model_dump(mode="json"),
        },
    )
    return ParsedCalendarSnapshot(
        events=ordered_events,
        cancelled_source_keys=ordered_cancelled,
        counts=counts,
        source_fingerprint=source_fingerprint,
        input_fingerprint=hashlib.sha256(encoded).hexdigest(),
    )


def _parse_calendar_components(text: str) -> list[list[_Property]]:
    lines = _unfold_lines(text)
    stack: list[str] = []
    calendars = 0
    version_found = False
    current_event: list[_Property] | None = None
    events: list[list[_Property]] = []
    for line in lines:
        if not line:
            continue
        prop = _parse_content_line(line)
        if prop.name == "BEGIN":
            component = prop.value.strip().upper()
            if not stack:
                if component != "VCALENDAR" or calendars:
                    raise CalendarEnvelopeError("Expected one VCALENDAR envelope.")
                calendars += 1
            elif component == "VCALENDAR":
                raise CalendarEnvelopeError("Nested VCALENDAR is invalid.")
            elif stack[-1] == "VCALENDAR" and component == "VEVENT":
                if current_event is not None:
                    raise CalendarEnvelopeError("Nested VEVENT is invalid.")
                current_event = []
                if len(events) + 1 > MAX_VEVENTS:
                    raise CalendarImportLimitError(
                        "iCalendar input exceeds 2,000 VEVENTs.",
                    )
            stack.append(component)
            continue
        if prop.name == "END":
            component = prop.value.strip().upper()
            if not stack or stack[-1] != component:
                raise CalendarEnvelopeError("iCalendar component nesting is invalid.")
            if component == "VEVENT":
                if current_event is None:
                    raise CalendarEnvelopeError("VEVENT state is invalid.")
                events.append(current_event)
                current_event = None
            stack.pop()
            continue
        if not stack:
            raise CalendarEnvelopeError("Content exists outside VCALENDAR.")
        if stack == ["VCALENDAR"] and prop.name == "VERSION":
            if version_found or prop.value.strip() != "2.0":
                raise CalendarEnvelopeError("VCALENDAR VERSION must be 2.0.")
            version_found = True
        if current_event is not None and stack[-1] == "VEVENT":
            current_event.append(prop)
    if stack or calendars != 1 or not version_found or current_event is not None:
        raise CalendarEnvelopeError("VCALENDAR envelope is incomplete.")
    return events


def _unfold_lines(text: str) -> list[str]:
    if "\x00" in text:
        raise CalendarEnvelopeError("iCalendar input contains a NUL byte.")
    physical = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    unfolded: list[str] = []
    for line in physical:
        if line.startswith((" ", "\t")):
            if not unfolded:
                raise CalendarEnvelopeError("Orphan iCalendar folded line.")
            unfolded[-1] += line[1:]
        else:
            unfolded.append(line)
    return unfolded


def _parse_content_line(line: str) -> _Property:
    delimiter = _outside_quotes_index(line, ":")
    if delimiter <= 0:
        raise CalendarEnvelopeError("Malformed iCalendar content line.")
    head = line[:delimiter]
    value = line[delimiter + 1 :]
    pieces = _split_outside_quotes(head, ";")
    raw_name = pieces[0].rsplit(".", 1)[-1].strip().upper()
    if not re.fullmatch(r"[A-Z0-9-]+", raw_name):
        raise CalendarEnvelopeError("Malformed iCalendar property name.")
    params: dict[str, str] = {}
    for raw_param in pieces[1:]:
        if "=" not in raw_param:
            raise CalendarEnvelopeError("Malformed iCalendar parameter.")
        key, raw_value = raw_param.split("=", 1)
        key = key.strip().upper()
        if not re.fullmatch(r"[A-Z0-9-]+", key) or key in params:
            raise CalendarEnvelopeError("Malformed iCalendar parameter.")
        raw_value = raw_value.strip()
        if len(raw_value) >= 2 and raw_value[0] == raw_value[-1] == '"':
            raw_value = raw_value[1:-1]
        params[key] = raw_value
    return _Property(name=raw_name, params=params, value=value)


def _outside_quotes_index(value: str, needle: str) -> int:
    quoted = False
    escaped = False
    for index, char in enumerate(value):
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            quoted = not quoted
        elif char == needle and not quoted:
            return index
    return -1


def _split_outside_quotes(value: str, delimiter: str) -> list[str]:
    pieces: list[str] = []
    start = 0
    while True:
        relative = _outside_quotes_index(value[start:], delimiter)
        if relative < 0:
            pieces.append(value[start:])
            return pieces
        index = start + relative
        pieces.append(value[start:index])
        start = index + 1


def _properties_by_name(properties: list[_Property]) -> dict[str, list[_Property]]:
    result: dict[str, list[_Property]] = {}
    for prop in properties:
        result.setdefault(prop.name, []).append(prop)
    return result


def _single(
    properties: dict[str, list[_Property]],
    name: str,
    *,
    required: bool,
) -> _Property | None:
    values = properties.get(name, [])
    if len(values) > 1 or (required and not values):
        raise _InvalidComponent(f"VEVENT {name} cardinality is invalid")
    return values[0] if values else None


def _parse_temporal(prop: _Property, profile_zone: ZoneInfo) -> _Temporal:
    value_kind = prop.params.get("VALUE", "DATE-TIME").upper()
    tzid = prop.params.get("TZID")
    if value_kind == "DATE":
        if tzid is not None or not _DATE.fullmatch(prop.value):
            raise _InvalidComponent("iCalendar date is invalid")
        return _Temporal(
            kind="all_day",
            aware=None,
            local=None,
            day=datetime.strptime(prop.value, "%Y%m%d").date(),
            timezone=profile_zone.key,
            timezone_source="profile",
        )
    if value_kind != "DATE-TIME":
        raise _InvalidComponent("Unsupported iCalendar VALUE kind")
    if _UTC_DATE_TIME.fullmatch(prop.value):
        if tzid is not None:
            raise _InvalidComponent("UTC date-time cannot carry TZID")
        aware = datetime.strptime(prop.value, "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
        return _Temporal(
            kind="timed",
            aware=aware,
            local=aware.replace(tzinfo=None),
            day=None,
            timezone="UTC",
            timezone_source="utc",
        )
    if not _DATE_TIME.fullmatch(prop.value):
        raise _InvalidComponent("iCalendar date-time is invalid")
    local = datetime.strptime(prop.value, "%Y%m%dT%H%M%S")
    if tzid is not None:
        try:
            zone = ZoneInfo(tzid)
        except ZoneInfoNotFoundError as exc:
            raise _InvalidComponent("VEVENT TZID is invalid") from exc
        source: Literal["event", "profile"] = "event"
    else:
        zone = profile_zone
        source = "profile"
    aware = _resolve_unambiguous_local(local, zone)
    return _Temporal(
        kind="timed",
        aware=aware,
        local=local,
        day=None,
        timezone=zone.key,
        timezone_source=source,
    )


def _resolve_unambiguous_local(value: datetime, zone: ZoneInfo) -> datetime:
    candidates: list[datetime] = []
    for fold in (0, 1):
        candidate = value.replace(tzinfo=zone, fold=fold)
        round_trip = candidate.astimezone(UTC).astimezone(zone)
        if round_trip.replace(tzinfo=None) == value and round_trip.fold == fold:
            candidates.append(candidate)
    unique_offsets = {candidate.utcoffset() for candidate in candidates}
    if not candidates:
        raise _InvalidComponent("VEVENT local time does not exist")
    if len(unique_offsets) > 1:
        raise _InvalidComponent("VEVENT local time is ambiguous")
    return candidates[0]


def _require_coherent_temporals(start: _Temporal, end: _Temporal) -> None:
    if (
        start.timezone != end.timezone
        or start.timezone_source != end.timezone_source
    ):
        raise _InvalidComponent("VEVENT start/end timezone is incoherent")


def _recurrence_key(prop: _Property, profile_zone: ZoneInfo) -> str:
    parsed = _parse_temporal(prop, profile_zone)
    if parsed.kind == "all_day":
        assert parsed.day is not None
        return f"date:{parsed.day.isoformat()}"
    assert parsed.aware is not None and parsed.local is not None
    if parsed.timezone_source == "utc":
        return f"instant:{parsed.aware.astimezone(UTC).isoformat()}"
    if parsed.timezone_source == "event":
        return f"tzid:{parsed.timezone}:{parsed.local.isoformat()}"
    return f"local:{parsed.local.isoformat()}"


def _parse_utc_timestamp(value: str) -> datetime:
    if not _UTC_DATE_TIME.fullmatch(value):
        raise _InvalidComponent("LAST-MODIFIED must be UTC")
    return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)


def _bounded_text(prop: _Property | None, *, maximum: int) -> str | None:
    if prop is None:
        return None
    value = " ".join(_unescape_text(prop.value).split()).strip()
    if not value:
        return None
    return value[:maximum]


def _unescape_text(value: str) -> str:
    return re.sub(
        r"\\([nN,;\\])",
        lambda match: "\n"
        if match.group(1).lower() == "n"
        else match.group(1),
        value,
    )


def _digest(value: object) -> str:
    canonical = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _iso(value: object | None) -> str | None:
    if value is None:
        return None
    if isinstance(value, (date, datetime, time)):
        return value.isoformat()
    raise TypeError("Unsupported calendar canonical value")
