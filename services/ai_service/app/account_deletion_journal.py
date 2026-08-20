import base64
import hashlib
import hmac
import json
import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from collections.abc import Callable
from typing import Protocol
from urllib.parse import quote, urlsplit

import httpx

from app.core.config import Settings


DELETION_JOURNAL_CONTRACT_VERSION = "account-deletion-journal-v2"
DELETION_JOURNAL_RETENTION_DAYS = 45
_S3_HOST = re.compile(
    r"(?P<bucket>[a-z0-9][a-z0-9-]{1,61}[a-z0-9])\.s3\."
    r"(?P<region>[a-z0-9-]+)\.amazonaws\.com",
)
_KMS_KEY = re.compile(
    r"arn:aws:kms:(?P<region>[a-z0-9-]+):(?P<account>[0-9]{12}):key/"
    r"[0-9a-f-]{36}",
)


class DeletionJournalError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class DeletionJournalEnvelope:
    deletion_id: str
    user_id: str
    accepted_at: datetime

    def canonical_content(self) -> bytes:
        if self.accepted_at.tzinfo is None:
            raise DeletionJournalError("Deletion acceptance time is invalid.")
        value = {
            "accepted_at": _utc_text(self.accepted_at),
            "contract_version": DELETION_JOURNAL_CONTRACT_VERSION,
            "deletion_id": self.deletion_id,
            "user_id": self.user_id,
        }
        return json.dumps(
            value,
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("ascii")

    def payload_sha256(self) -> str:
        return hashlib.sha256(self.canonical_content()).hexdigest()

    def object_key(self) -> str:
        accepted = self.accepted_at.astimezone(UTC)
        return (
            f"deletions/v2/{accepted:%Y/%m}/{self.deletion_id}/"
            f"{self.payload_sha256()}.json"
        )


@dataclass(frozen=True, slots=True)
class DeletionJournalReceipt:
    object_key: str
    payload_sha256: str
    journaled_at: datetime
    replayed: bool


class DeletionJournalWriter(Protocol):
    async def append(
        self,
        envelope: DeletionJournalEnvelope,
    ) -> DeletionJournalReceipt: ...


class InMemoryDeletionJournalWriter:
    """Deterministic local/test writer; never used by a hosted environment."""

    def __init__(self, *, now: Callable[[], datetime] | None = None) -> None:
        self._now = now or (lambda: datetime.now(UTC))
        self._objects: dict[str, str] = {}

    async def append(
        self,
        envelope: DeletionJournalEnvelope,
    ) -> DeletionJournalReceipt:
        object_key = envelope.object_key()
        payload_sha256 = envelope.payload_sha256()
        existing = self._objects.get(object_key)
        if existing is not None and existing != payload_sha256:
            raise DeletionJournalError("Deletion journal identity conflicted.")
        self._objects[object_key] = payload_sha256
        return DeletionJournalReceipt(
            object_key=object_key,
            payload_sha256=payload_sha256,
            journaled_at=self._now(),
            replayed=existing is not None,
        )


class S3DeletionJournalWriter:
    """Single-object AWS SigV4 writer with KMS and compliance retention."""

    def __init__(
        self,
        *,
        bucket_url: str,
        region: str,
        access_key_id: str,
        secret_access_key: str,
        kms_key_arn: str,
        timeout_seconds: float = 10,
        http_client: httpx.AsyncClient | None = None,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        parsed = urlsplit(bucket_url)
        host_match = _S3_HOST.fullmatch(parsed.hostname or "")
        kms_match = _KMS_KEY.fullmatch(kms_key_arn)
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
        ):
            raise ValueError("Deletion journal S3 configuration is invalid.")
        self._bucket_url = bucket_url.rstrip("/")
        self._host = parsed.hostname or ""
        self._region = region
        self._access_key_id = access_key_id
        self._secret_access_key = secret_access_key
        self._kms_key_arn = kms_key_arn
        self._expected_bucket_owner = kms_match["account"]
        self._timeout_seconds = timeout_seconds
        self._http_client = http_client
        self._now = now or (lambda: datetime.now(UTC))

    @classmethod
    def from_settings(
        cls,
        settings: Settings,
        *,
        http_client: httpx.AsyncClient | None = None,
    ) -> "S3DeletionJournalWriter":
        return cls(
            bucket_url=settings.account_deletion_journal_s3_url,
            region=settings.account_deletion_journal_s3_region,
            access_key_id=settings.account_deletion_journal_s3_access_key_id,
            secret_access_key=(
                settings.account_deletion_journal_s3_secret_access_key
            ),
            kms_key_arn=settings.account_deletion_journal_s3_kms_key_arn,
            timeout_seconds=settings.account_deletion_journal_timeout_seconds,
            http_client=http_client,
        )

    async def append(
        self,
        envelope: DeletionJournalEnvelope,
    ) -> DeletionJournalReceipt:
        content = envelope.canonical_content()
        payload_sha256 = envelope.payload_sha256()
        object_key = envelope.object_key()
        for attempt in range(2):
            request_time = self._now().astimezone(UTC)
            headers = self._signed_headers(
                object_key=object_key,
                content=content,
                request_time=request_time,
                accepted_at=envelope.accepted_at,
            )
            try:
                if self._http_client is None:
                    async with httpx.AsyncClient(
                        timeout=self._timeout_seconds,
                    ) as client:
                        response = await client.put(
                            f"{self._bucket_url}/{quote(object_key, safe='/')}",
                            content=content,
                            headers=headers,
                        )
                else:
                    response = await self._http_client.put(
                        f"{self._bucket_url}/{quote(object_key, safe='/')}",
                        content=content,
                        headers=headers,
                    )
            except (httpx.HTTPError, OSError, TimeoutError) as exc:
                if attempt == 0:
                    continue
                raise DeletionJournalError(
                    "Deletion journal append outcome is unknown.",
                ) from exc
            if response.status_code == 409 and attempt == 0:
                continue
            if response.status_code == 412:
                return DeletionJournalReceipt(
                    object_key=object_key,
                    payload_sha256=payload_sha256,
                    journaled_at=request_time,
                    replayed=True,
                )
            if response.status_code != 200:
                raise DeletionJournalError("Deletion journal append failed.")
            if (
                response.headers.get("x-amz-server-side-encryption") != "aws:kms"
                or response.headers.get(
                    "x-amz-server-side-encryption-aws-kms-key-id",
                )
                != self._kms_key_arn
                or not response.headers.get("x-amz-version-id")
            ):
                raise DeletionJournalError(
                    "Deletion journal storage attestation is invalid.",
                )
            return DeletionJournalReceipt(
                object_key=object_key,
                payload_sha256=payload_sha256,
                journaled_at=request_time,
                replayed=False,
            )
        raise DeletionJournalError("Deletion journal append failed.")

    def _signed_headers(
        self,
        *,
        object_key: str,
        content: bytes,
        request_time: datetime,
        accepted_at: datetime,
    ) -> dict[str, str]:
        timestamp = request_time.strftime("%Y%m%dT%H%M%SZ")
        date = request_time.strftime("%Y%m%d")
        retain_until = max(
            accepted_at.astimezone(UTC),
            request_time,
        ) + timedelta(days=DELETION_JOURNAL_RETENTION_DAYS)
        content_sha256 = hashlib.sha256(content).hexdigest()
        headers = {
            "content-md5": base64.b64encode(hashlib.md5(content).digest()).decode(
                "ascii",
            ),
            "content-type": "application/json",
            "host": self._host,
            "if-none-match": "*",
            "x-amz-content-sha256": content_sha256,
            "x-amz-date": timestamp,
            "x-amz-expected-bucket-owner": self._expected_bucket_owner,
            "x-amz-object-lock-mode": "COMPLIANCE",
            "x-amz-object-lock-retain-until-date": _utc_text(retain_until),
            "x-amz-server-side-encryption": "aws:kms",
            "x-amz-server-side-encryption-aws-kms-key-id": self._kms_key_arn,
        }
        signed_headers = ";".join(sorted(headers))
        canonical_headers = "".join(
            f"{name}:{' '.join(headers[name].split())}\n"
            for name in sorted(headers)
        )
        canonical_uri = f"/{quote(object_key, safe='/-_.~')}"
        canonical_request = "\n".join(
            (
                "PUT",
                canonical_uri,
                "",
                canonical_headers,
                signed_headers,
                content_sha256,
            ),
        )
        scope = f"{date}/{self._region}/s3/aws4_request"
        string_to_sign = "\n".join(
            (
                "AWS4-HMAC-SHA256",
                timestamp,
                scope,
                hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
            ),
        )
        signing_key = _signature_key(
            self._secret_access_key,
            date,
            self._region,
        )
        signature = hmac.new(
            signing_key,
            string_to_sign.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        headers["authorization"] = (
            "AWS4-HMAC-SHA256 "
            f"Credential={self._access_key_id}/{scope},"
            f"SignedHeaders={signed_headers},Signature={signature}"
        )
        return headers


def deletion_journal_from_settings(settings: Settings) -> DeletionJournalWriter:
    if settings.is_hosted_environment:
        return S3DeletionJournalWriter.from_settings(settings)
    return InMemoryDeletionJournalWriter()


def _signature_key(secret: str, date: str, region: str) -> bytes:
    date_key = hmac.new(
        f"AWS4{secret}".encode("utf-8"),
        date.encode("ascii"),
        hashlib.sha256,
    ).digest()
    region_key = hmac.new(date_key, region.encode("ascii"), hashlib.sha256).digest()
    service_key = hmac.new(region_key, b"s3", hashlib.sha256).digest()
    return hmac.new(service_key, b"aws4_request", hashlib.sha256).digest()


def _utc_text(value: datetime) -> str:
    return (
        value.astimezone(UTC)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )
