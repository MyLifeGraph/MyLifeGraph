import asyncio
import json
from datetime import UTC, datetime

import httpx
import pytest

from app.account_deletion_journal import (
    DeletionJournalEnvelope,
    DeletionJournalError,
    S3DeletionJournalWriter,
)


NOW = datetime(2026, 8, 20, 12, tzinfo=UTC)
KMS_ARN = (
    "arn:aws:kms:eu-central-1:123456789012:key/"
    "11111111-2222-4333-8444-555555555555"
)


def _writer(handler) -> S3DeletionJournalWriter:
    return S3DeletionJournalWriter(
        bucket_url=(
            "https://mylifegraph-deletion-journal."
            "s3.eu-central-1.amazonaws.com"
        ),
        region="eu-central-1",
        access_key_id="A" * 20,
        secret_access_key="s" * 40,
        kms_key_arn=KMS_ARN,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        now=lambda: NOW,
    )


def _envelope() -> DeletionJournalEnvelope:
    return DeletionJournalEnvelope(
        deletion_id="11111111-2222-4333-8444-555555555555",
        user_id="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        accepted_at=NOW,
    )


def test_s3_append_is_canonical_signed_kms_locked_and_content_bound() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            headers={
                "x-amz-server-side-encryption": "aws:kms",
                "x-amz-server-side-encryption-aws-kms-key-id": KMS_ARN,
                "x-amz-version-id": "immutable-version-1",
            },
        )

    writer = _writer(handler)
    receipt = asyncio.run(writer.append(_envelope()))
    asyncio.run(writer._http_client.aclose())  # type: ignore[union-attr]

    request = requests[0]
    body = json.loads(request.content)
    assert set(body) == {
        "accepted_at",
        "contract_version",
        "deletion_id",
        "user_id",
    }
    assert body["contract_version"] == "account-deletion-journal-v2"
    assert request.headers["if-none-match"] == "*"
    assert request.headers["x-amz-object-lock-mode"] == "COMPLIANCE"
    assert request.headers["x-amz-object-lock-retain-until-date"] == (
        "2026-10-04T12:00:00Z"
    )
    assert request.headers["x-amz-server-side-encryption"] == "aws:kms"
    assert request.headers["x-amz-expected-bucket-owner"] == "123456789012"
    assert request.headers["content-md5"]
    assert request.headers["authorization"].startswith("AWS4-HMAC-SHA256 ")
    assert receipt.object_key.endswith(f"/{receipt.payload_sha256}.json")
    assert "aaaaaaaa-bbbb" not in receipt.object_key
    assert receipt.replayed is False


def test_s3_exact_conditional_replay_is_accepted_without_read_authority() -> None:
    writer = _writer(lambda request: httpx.Response(412))

    receipt = asyncio.run(writer.append(_envelope()))
    asyncio.run(writer._http_client.aclose())  # type: ignore[union-attr]

    assert receipt.replayed is True
    assert receipt.payload_sha256 == _envelope().payload_sha256()


def test_s3_append_rejects_missing_kms_attestation_and_bad_target() -> None:
    writer = _writer(lambda request: httpx.Response(200, headers={}))
    with pytest.raises(DeletionJournalError, match="attestation"):
        asyncio.run(writer.append(_envelope()))
    asyncio.run(writer._http_client.aclose())  # type: ignore[union-attr]

    with pytest.raises(ValueError, match="configuration"):
        S3DeletionJournalWriter(
            bucket_url="http://localhost:9000/bucket",
            region="eu-central-1",
            access_key_id="A" * 20,
            secret_access_key="s" * 40,
            kms_key_arn=KMS_ARN,
        )
