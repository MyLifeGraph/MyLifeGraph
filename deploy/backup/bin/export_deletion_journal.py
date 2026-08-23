#!/usr/bin/env python3
"""Create a complete, bounded restore export from the object-locked S3 journal."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import re
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, HTTPSHandler, Request, build_opener
from uuid import UUID
from xml.etree import ElementTree


EXPORT_VERSION = "mylifegraph-deletion-journal-export-v1"
JOURNAL_VERSION = "account-deletion-journal-v2"
PREFIX = "deletions/v2/"
TIMESTAMP = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
S3_HOST = re.compile(
    r"(?P<bucket>[a-z0-9][a-z0-9-]{1,61}[a-z0-9])\.s3\."
    r"(?P<region>[a-z0-9-]+)\.amazonaws\.com"
)
KMS_KEY = re.compile(
    r"arn:aws:kms:(?P<region>[a-z0-9-]+):[0-9]{12}:key/[0-9a-f-]{36}"
)
OBJECT_KEY = re.compile(
    r"deletions/v2/(?P<year>[0-9]{4})/(?P<month>0[1-9]|1[0-2])/"
    r"(?P<deletion>[0-9a-f-]{36})/(?P<digest>[0-9a-f]{64})\.json"
)
DELETION_COPY = re.compile(
    r'^COPY (?:(?:"public"\."account_deletion_intents")|'
    r'(?:public\.account_deletion_intents)) '
    r'\((?P<columns>[^)]+)\) FROM stdin;$'
)
MAX_LIST_BYTES = 4 * 1024 * 1024
MAX_OBJECT_BYTES = 4096
MAX_OBJECTS = 100_000
MAX_PAGES = 1_000
MAX_RECOVERY_RANGE = timedelta(days=42)
RECOVERY_RTO = timedelta(hours=4)


class JournalExportError(ValueError):
    pass


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _parse_time(value: str, *, label: str) -> datetime:
    if TIMESTAMP.fullmatch(value) is None:
        raise JournalExportError(f"{label} must be an exact UTC-second timestamp")
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)


def _parse_s3_time(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise JournalExportError("deletion journal LastModified is invalid") from exc
    if parsed.tzinfo is None or parsed.utcoffset() != timedelta(0):
        raise JournalExportError("deletion journal LastModified is not UTC")
    return parsed.astimezone(UTC)


def _canonical_uuid(value: Any, *, label: str) -> str:
    if not isinstance(value, str):
        raise JournalExportError(f"{label} is invalid")
    try:
        parsed = UUID(value)
    except ValueError as exc:
        raise JournalExportError(f"{label} is invalid") from exc
    if str(parsed) != value or parsed.version != 4:
        raise JournalExportError(f"{label} must be a canonical UUIDv4")
    return value


def _signing_key(secret: str, date: str, region: str) -> bytes:
    date_key = hmac.new(
        f"AWS4{secret}".encode(), date.encode(), hashlib.sha256
    ).digest()
    region_key = hmac.new(date_key, region.encode(), hashlib.sha256).digest()
    service_key = hmac.new(region_key, b"s3", hashlib.sha256).digest()
    return hmac.new(service_key, b"aws4_request", hashlib.sha256).digest()


class S3JournalReader:
    def __init__(
        self,
        *,
        bucket_url: str,
        region: str,
        access_key_id: str,
        secret_access_key: str,
        kms_key_arn: str,
        session_token: str = "",
        opener=None,
        now=None,
    ) -> None:
        parsed = urlsplit(bucket_url)
        host_match = S3_HOST.fullmatch(parsed.hostname or "")
        kms_match = KMS_KEY.fullmatch(kms_key_arn)
        if (
            parsed.scheme != "https"
            or parsed.username is not None
            or parsed.password is not None
            or parsed.port is not None
            or parsed.path not in {"", "/"}
            or parsed.query
            or parsed.fragment
            or host_match is None
            or host_match["region"] != region
            or kms_match is None
            or kms_match["region"] != region
            or re.fullmatch(r"[A-Z0-9]{16,128}", access_key_id) is None
            or not 40 <= len(secret_access_key) <= 256
            or secret_access_key.strip() != secret_access_key
            or len(session_token) > 4096
        ):
            raise JournalExportError("deletion journal read configuration is invalid")
        self.bucket_url = bucket_url.rstrip("/")
        self.host = parsed.hostname or ""
        self.region = region
        self.access_key_id = access_key_id
        self.secret_access_key = secret_access_key
        self.kms_key_arn = kms_key_arn
        self.session_token = session_token
        self.opener = opener or build_opener(HTTPSHandler(), _NoRedirect())
        self.now = now or (lambda: datetime.now(UTC))

    def _request(
        self,
        *,
        path: str,
        query: dict[str, str],
    ) -> tuple[bytes, dict[str, str]]:
        request_time = self.now().astimezone(UTC)
        date = request_time.strftime("%Y%m%d")
        timestamp = request_time.strftime("%Y%m%dT%H%M%SZ")
        canonical_query = urlencode(sorted(query.items()), quote_via=quote, safe="-_.~")
        canonical_uri = "/" + quote(path, safe="/-_.~") if path else "/"
        payload_sha256 = hashlib.sha256(b"").hexdigest()
        headers = {
            "host": self.host,
            "x-amz-content-sha256": payload_sha256,
            "x-amz-date": timestamp,
        }
        if self.session_token:
            headers["x-amz-security-token"] = self.session_token
        signed_headers = ";".join(sorted(headers))
        canonical_headers = "".join(
            f"{name}:{headers[name]}\n" for name in sorted(headers)
        )
        canonical_request = "\n".join(
            (
                "GET",
                canonical_uri,
                canonical_query,
                canonical_headers,
                signed_headers,
                payload_sha256,
            )
        )
        scope = f"{date}/{self.region}/s3/aws4_request"
        string_to_sign = "\n".join(
            (
                "AWS4-HMAC-SHA256",
                timestamp,
                scope,
                hashlib.sha256(canonical_request.encode()).hexdigest(),
            )
        )
        signature = hmac.new(
            _signing_key(self.secret_access_key, date, self.region),
            string_to_sign.encode(),
            hashlib.sha256,
        ).hexdigest()
        headers["authorization"] = (
            "AWS4-HMAC-SHA256 "
            f"Credential={self.access_key_id}/{scope},"
            f"SignedHeaders={signed_headers},Signature={signature}"
        )
        url = self.bucket_url + canonical_uri
        if canonical_query:
            url += "?" + canonical_query
        request = Request(url, headers=headers, method="GET")
        try:
            with self.opener.open(request, timeout=20) as response:
                if response.status != 200 or response.geturl() != url:
                    raise JournalExportError("deletion journal S3 response changed URL")
                content_length = response.headers.get("Content-Length")
                limit = MAX_LIST_BYTES if not path else MAX_OBJECT_BYTES
                if content_length and int(content_length) > limit:
                    raise JournalExportError("deletion journal S3 response is too large")
                body = response.read(limit + 1)
                response_headers = {
                    name.lower(): value for name, value in response.headers.items()
                }
        except (HTTPError, URLError, TimeoutError, OSError, ValueError) as exc:
            raise JournalExportError("deletion journal S3 request failed") from exc
        if len(body) > (MAX_LIST_BYTES if not path else MAX_OBJECT_BYTES):
            raise JournalExportError("deletion journal S3 response is too large")
        return body, response_headers

    def list_objects(self) -> tuple[dict[str, object], ...]:
        results: list[dict[str, object]] = []
        key_marker = ""
        version_marker = ""
        for _ in range(MAX_PAGES):
            query = {"versions": "", "prefix": PREFIX}
            if key_marker:
                query["key-marker"] = key_marker
            if version_marker:
                query["version-id-marker"] = version_marker
            body, _ = self._request(path="", query=query)
            try:
                root = ElementTree.fromstring(body)
            except ElementTree.ParseError as exc:
                raise JournalExportError("deletion journal listing is invalid") from exc
            namespace = {"s3": "http://s3.amazonaws.com/doc/2006-03-01/"}
            if root.tag != "{http://s3.amazonaws.com/doc/2006-03-01/}ListVersionsResult":
                raise JournalExportError("deletion journal listing contract is invalid")
            if root.findall("s3:DeleteMarker", namespace):
                raise JournalExportError(
                    "deletion journal contains a forbidden delete marker"
                )
            for item in root.findall("s3:Version", namespace):
                key = item.findtext("s3:Key", default="", namespaces=namespace)
                etag = item.findtext("s3:ETag", default="", namespaces=namespace)
                version_id = item.findtext(
                    "s3:VersionId", default="", namespaces=namespace
                )
                is_latest = item.findtext(
                    "s3:IsLatest", default="", namespaces=namespace
                )
                size_text = item.findtext("s3:Size", default="", namespaces=namespace)
                modified = item.findtext(
                    "s3:LastModified", default="", namespaces=namespace
                )
                if (
                    OBJECT_KEY.fullmatch(key) is None
                    or not etag
                    or len(etag) > 128
                    or not version_id
                    or len(version_id) > 1024
                    or is_latest != "true"
                    or not size_text.isdigit()
                    or not 1 <= int(size_text) <= MAX_OBJECT_BYTES
                    or not modified
                ):
                    raise JournalExportError("deletion journal listing entry is invalid")
                _parse_s3_time(modified)
                results.append(
                    {
                        "key": key,
                        "etag": etag,
                        "version_id": version_id,
                        "size": int(size_text),
                        "last_modified": modified,
                    }
                )
                if len(results) > MAX_OBJECTS:
                    raise JournalExportError("deletion journal object count is too large")
            truncated = root.findtext(
                "s3:IsTruncated", default="", namespaces=namespace
            )
            if truncated == "false":
                break
            if truncated != "true":
                raise JournalExportError("deletion journal pagination is invalid")
            next_key_marker = root.findtext(
                "s3:NextKeyMarker", default="", namespaces=namespace
            )
            next_version_marker = root.findtext(
                "s3:NextVersionIdMarker", default="", namespaces=namespace
            )
            if (
                not next_key_marker
                or len(next_key_marker) > 4096
                or len(next_version_marker) > 4096
                or (next_key_marker, next_version_marker)
                == (key_marker, version_marker)
            ):
                raise JournalExportError("deletion journal pagination token is invalid")
            key_marker = next_key_marker
            version_marker = next_version_marker
        else:
            raise JournalExportError("deletion journal pagination did not terminate")
        keys = [str(item["key"]) for item in results]
        if keys != sorted(keys) or len(keys) != len(set(keys)):
            raise JournalExportError("deletion journal listing is not unique and sorted")
        return tuple(results)

    def get_object(
        self,
        key: str,
        version_id: str,
        *,
        recovery_cutoff: datetime,
    ) -> bytes:
        body, headers = self._request(
            path=key,
            query={"versionId": version_id},
        )
        retain_until = headers.get("x-amz-object-lock-retain-until-date", "")
        if (
            headers.get("x-amz-version-id") != version_id
            or headers.get("x-amz-server-side-encryption") != "aws:kms"
            or headers.get("x-amz-server-side-encryption-aws-kms-key-id")
            != self.kms_key_arn
            or headers.get("x-amz-object-lock-mode") != "COMPLIANCE"
            or not retain_until
            or _parse_s3_time(retain_until) < recovery_cutoff + RECOVERY_RTO
        ):
            raise JournalExportError(
                "deletion journal version retention attestation is invalid"
            )
        return body


def _canonical_entry(raw: bytes, key: str) -> tuple[datetime, str, bytes]:
    if not raw or len(raw) > MAX_OBJECT_BYTES or raw.endswith(b"\n"):
        raise JournalExportError("deletion journal object framing is invalid")
    try:
        text = raw.decode("ascii")
        value = json.loads(text)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise JournalExportError("deletion journal object is invalid") from exc
    if not isinstance(value, dict) or set(value) != {
        "accepted_at",
        "contract_version",
        "deletion_id",
        "user_id",
    }:
        raise JournalExportError("deletion journal object shape is invalid")
    canonical = json.dumps(
        value, ensure_ascii=True, separators=(",", ":"), sort_keys=True
    ).encode("ascii")
    if raw != canonical or value["contract_version"] != JOURNAL_VERSION:
        raise JournalExportError("deletion journal object is not canonical")
    accepted_at = _parse_time(value["accepted_at"], label="accepted_at")
    deletion_id = _canonical_uuid(value["deletion_id"], label="deletion_id")
    _canonical_uuid(value["user_id"], label="user_id")
    match = OBJECT_KEY.fullmatch(key)
    digest = hashlib.sha256(raw).hexdigest()
    if (
        match is None
        or match["deletion"] != deletion_id
        or match["digest"] != digest
        or f"{accepted_at:%Y}" != match["year"]
        or f"{accepted_at:%m}" != match["month"]
    ):
        raise JournalExportError("deletion journal object identity is invalid")
    return accepted_at, deletion_id, canonical


def _snapshot_pending_deletions(path: Path) -> dict[str, str]:
    columns: list[str] | None = None
    pending: dict[str, str] = {}
    in_section = False
    seen_section = False
    try:
        with path.open("r", encoding="utf-8", errors="strict") as handle:
            for raw_line in handle:
                line = raw_line.rstrip("\n")
                if not in_section:
                    match = DELETION_COPY.fullmatch(line)
                    if match is None:
                        continue
                    if seen_section:
                        raise JournalExportError(
                            "snapshot contains duplicate deletion intent sections"
                        )
                    seen_section = True
                    in_section = True
                    columns = [
                        value.strip().strip('"')
                        for value in match.group("columns").split(",")
                    ]
                    if (
                        len(columns) != len(set(columns))
                        or "deletion_id" not in columns
                        or "state" not in columns
                    ):
                        raise JournalExportError(
                            "snapshot deletion intent columns are invalid"
                        )
                    continue
                if line == r"\.":
                    in_section = False
                    continue
                assert columns is not None
                values = line.split("\t")
                if len(values) != len(columns):
                    raise JournalExportError(
                        "snapshot deletion intent row is malformed"
                    )
                row = dict(zip(columns, values, strict=True))
                state = row["state"]
                deletion_id = row["deletion_id"]
                if state in {"prepared", "appending", "accepted"}:
                    checked = _canonical_uuid(
                        deletion_id,
                        label="snapshot deletion_id",
                    )
                    if checked in pending:
                        raise JournalExportError(
                            "snapshot deletion intent identity is duplicate"
                        )
                    pending[checked] = state
    except (OSError, UnicodeError) as exc:
        raise JournalExportError("snapshot data dump is unreadable") from exc
    if in_section:
        raise JournalExportError("snapshot deletion intent section is incomplete")
    return pending


def export_journal(
    reader: S3JournalReader,
    *,
    required_from: datetime,
    recovery_cutoff: datetime,
    snapshot_pending: dict[str, str],
    output: Path,
) -> None:
    if (
        recovery_cutoff < required_from
        or recovery_cutoff - required_from > MAX_RECOVERY_RANGE
        or recovery_cutoff > datetime.now(UTC) + timedelta(minutes=5)
    ):
        raise JournalExportError("deletion journal recovery range is invalid")
    first = reader.list_objects()
    second = reader.list_objects()
    if first != second:
        raise JournalExportError("deletion journal changed during complete listing")
    inventory_bytes = json.dumps(
        first, ensure_ascii=True, separators=(",", ":"), sort_keys=True
    ).encode("ascii")
    selected: list[tuple[datetime, str, bytes]] = []
    selected_ids: set[str] = set()
    for descriptor in first:
        last_modified = _parse_s3_time(str(descriptor["last_modified"]))
        # A deletion becomes durable only when this immutable S3 version is
        # written. Versions older than the backup boundary are still covered
        # by both complete inventory passes, but replaying this snapshot cannot
        # require them and their normal retention may legitimately be near its
        # end. Snapshot-pending identities are the exception: an S3 Put can
        # precede the dump while DB acceptance/completion follows it, so those
        # exact versions remain selected regardless of LastModified.
        match = OBJECT_KEY.fullmatch(str(descriptor["key"]))
        if match is None:
            raise JournalExportError("deletion journal object key is invalid")
        snapshot_requires_object = match["deletion"] in snapshot_pending
        if (
            (last_modified < required_from and not snapshot_requires_object)
            or last_modified > recovery_cutoff
        ):
            continue
        accepted_at, deletion_id, canonical = _canonical_entry(
            reader.get_object(
                str(descriptor["key"]),
                str(descriptor["version_id"]),
                recovery_cutoff=recovery_cutoff,
            ),
            str(descriptor["key"]),
        )
        if last_modified < accepted_at:
            raise JournalExportError(
                "deletion journal object predates its acceptance identity"
            )
        selected.append((accepted_at, deletion_id, canonical))
        selected_ids.add(deletion_id)
    missing_accepted = {
        deletion_id
        for deletion_id, state in snapshot_pending.items()
        if state == "accepted" and deletion_id not in selected_ids
    }
    if missing_accepted:
        raise JournalExportError(
            "snapshot accepted deletion lacks a retained journal object"
        )
    selected.sort(key=lambda item: (item[0], item[1]))
    entries = b"".join(item[2] + b"\n" for item in selected)

    if output.exists():
        raise JournalExportError("deletion journal export output already exists")
    output.mkdir(mode=0o700, parents=False)
    entries_path = output / "entries.jsonl"
    entries_path.write_bytes(entries)
    entries_path.chmod(0o600)
    def timestamp(value: datetime) -> str:
        return value.isoformat().replace("+00:00", "Z")

    manifest = {
        "schema_version": EXPORT_VERSION,
        "contract_version": JOURNAL_VERSION,
        "captured_from_utc": timestamp(required_from),
        "captured_through_utc": timestamp(recovery_cutoff),
        "entry_count": len(selected),
        "entries_file": "entries.jsonl",
        "entries_sha256": hashlib.sha256(entries).hexdigest(),
        "list_pass_count": 2,
        "source_bucket_url": reader.bucket_url,
        "source_kms_key_arn": reader.kms_key_arn,
        "source_inventory_sha256": hashlib.sha256(inventory_bytes).hexdigest(),
        "source_object_count": len(first),
        "source_objects_through_cutoff": len(selected),
    }
    manifest_path = output / "journal-export.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    manifest_path.chmod(0o600)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket-url", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--kms-key-arn", required=True)
    parser.add_argument("--required-from-utc", required=True)
    parser.add_argument("--recovery-cutoff-utc", required=True)
    parser.add_argument("--snapshot-data-sql", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        access_key_id = os.environ.pop("DELETION_JOURNAL_READ_ACCESS_KEY_ID", "")
        secret_access_key = os.environ.pop(
            "DELETION_JOURNAL_READ_SECRET_ACCESS_KEY", ""
        )
        session_token = os.environ.pop("DELETION_JOURNAL_READ_SESSION_TOKEN", "")
        if not access_key_id or not secret_access_key:
            raise JournalExportError("deletion journal read credentials are missing")
        reader = S3JournalReader(
            bucket_url=args.bucket_url,
            region=args.region,
            access_key_id=access_key_id,
            secret_access_key=secret_access_key,
            kms_key_arn=args.kms_key_arn,
            session_token=session_token,
        )
        export_journal(
            reader,
            required_from=_parse_time(
                args.required_from_utc, label="required-from-utc"
            ),
            recovery_cutoff=_parse_time(
                args.recovery_cutoff_utc, label="recovery-cutoff-utc"
            ),
            snapshot_pending=_snapshot_pending_deletions(
                Path(args.snapshot_data_sql)
            ),
            output=Path(args.output),
        )
    except (JournalExportError, OSError, UnicodeError, TypeError, ValueError) as exc:
        print(f"deletion journal export error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
