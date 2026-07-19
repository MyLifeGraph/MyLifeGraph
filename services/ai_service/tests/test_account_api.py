import asyncio
from datetime import UTC, datetime, timedelta

import httpx

from app.api.deps.auth import Principal
from app.main import create_app
from app.models.account import (
    ACCOUNT_EXPORT_MAX_JSON_BYTES,
    ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
    ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
    ACCOUNT_EXPORT_OMITTED_TABLES,
    ACCOUNT_EXPORT_SANITIZED_TABLES,
    ACCOUNT_EXPORT_TABLE_NAMES,
    AccountExportLedgerPolicy,
    AccountExportLimits,
    AccountExportResponse,
    AccountPreparationBudgetResponse,
    AccountProfileResponse,
)
from app.repositories.account_repository import (
    AccountDeletionOutcomeUnknownError,
    AccountNotFoundError,
    AccountPersistenceError,
    AccountPreparationBudgetUpdateOutcomeUnknownError,
    AccountProfileUpdateOutcomeUnknownError,
)
from app.services.account_service import (
    AccountExportTooLargeError,
    InvalidAccountTimezoneError,
    InvalidPreparationBudgetError,
    PreparedAccountExport,
)


USER_ID = "account-owner"
NOW = datetime(2026, 7, 13, 12, tzinfo=UTC)


class Verifier:
    def __init__(self, authenticated_at: datetime | None = None) -> None:
        self._authenticated_at = authenticated_at or datetime.now(UTC)

    async def verify(self, token: str):
        return (
            Principal(
                user_id=USER_ID,
                authenticated_at=self._authenticated_at,
            )
            if token == "valid-account-token"
            else None
        )


class ExplicitAuthenticationTimeVerifier:
    def __init__(self, authenticated_at: datetime | None) -> None:
        self._authenticated_at = authenticated_at

    async def verify(self, token: str):
        if token != "valid-account-token":
            return None
        return Principal(
            user_id=USER_ID,
            authenticated_at=self._authenticated_at,
        )


class Service:
    def __init__(self) -> None:
        self.calls = []
        self.profile_error: Exception | None = None
        self.preparation_budget_error: Exception | None = None
        self.export_error: Exception | None = None
        self.delete_error: Exception | None = None

    async def update_timezone(self, *, user_id: str, timezone: str):
        self.calls.append(("profile", user_id, timezone))
        if self.profile_error is not None:
            raise self.profile_error
        return AccountProfileResponse(timezone=timezone)

    async def update_preparation_budget(self, *, user_id: str, minutes: int | None):
        self.calls.append(("preparation_budget", user_id, minutes))
        if self.preparation_budget_error is not None:
            raise self.preparation_budget_error
        return AccountPreparationBudgetResponse(
            daily_preparation_budget_minutes=minutes,
        )

    async def export_account(self, *, user_id: str):
        self.calls.append(("export", user_id))
        if self.export_error is not None:
            raise self.export_error
        data = {name: [] for name in ACCOUNT_EXPORT_TABLE_NAMES}
        data["profiles"] = [{"id": USER_ID, "timezone": "Europe/Berlin"}]
        record_counts = {name: len(rows) for name, rows in data.items()}
        envelope = AccountExportResponse(
            contract_version="account-export-v1",
            exported_at=NOW,
            data=data,
            record_counts=record_counts,
            ledger_policy=AccountExportLedgerPolicy(
                sanitized_tables=list(ACCOUNT_EXPORT_SANITIZED_TABLES),
                omitted_tables=dict(ACCOUNT_EXPORT_OMITTED_TABLES),
            ),
            limits=AccountExportLimits(
                max_rows_per_table=ACCOUNT_EXPORT_MAX_ROWS_PER_TABLE,
                max_total_rows=ACCOUNT_EXPORT_MAX_TOTAL_ROWS,
                max_json_bytes=ACCOUNT_EXPORT_MAX_JSON_BYTES,
            ),
        )
        return PreparedAccountExport(
            envelope=envelope,
            content=envelope.model_dump_json().encode("utf-8"),
        )

    async def delete_account(self, *, user_id: str, confirmation: str):
        self.calls.append(("delete", user_id, confirmation))
        if self.delete_error is not None:
            raise self.delete_error


async def _request(
    method: str,
    path: str,
    *,
    json=None,
    authenticated: bool = True,
    authenticated_at: datetime | None = None,
    service: Service | None = None,
):
    app = create_app()
    account_service = service or Service()
    app.state.token_verifier = Verifier(authenticated_at)
    app.state.account_service = account_service
    headers = (
        {"Authorization": "Bearer valid-account-token"}
        if authenticated
        else {}
    )
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.request(method, path, headers=headers, json=json)
    return response, account_service


def test_patch_profile_is_strict_authenticated_and_owner_derived() -> None:
    response, service = asyncio.run(
        _request(
            "PATCH",
            "/v1/account/profile",
            json={"timezone": "America/New_York"},
        ),
    )

    assert response.status_code == 200
    assert response.json() == {"timezone": "America/New_York"}
    assert service.calls == [("profile", USER_ID, "America/New_York")]

    unknown, unknown_service = asyncio.run(
        _request(
            "PATCH",
            "/v1/account/profile",
            json={"timezone": "UTC", "user_id": "other"},
        ),
    )
    assert unknown.status_code == 422
    assert unknown_service.calls == []


def test_patch_maps_timezone_missing_and_persistence_errors_safely() -> None:
    cases = [
        (InvalidAccountTimezoneError("timezone must be a valid IANA name"), 422),
        (AccountNotFoundError("internal owner detail"), 404),
        (AccountProfileUpdateOutcomeUnknownError("internal outcome"), 502),
        (AccountPersistenceError("internal upstream detail"), 503),
    ]
    for error, expected_status in cases:
        service = Service()
        service.profile_error = error
        response, _ = asyncio.run(
            _request(
                "PATCH",
                "/v1/account/profile",
                json={"timezone": "Europe/Berlin"},
                service=service,
            ),
        )
        assert response.status_code == expected_status
        assert "internal" not in response.text


def test_patch_preparation_budget_is_strict_owner_derived_and_nullable() -> None:
    for minutes in (120, None):
        response, service = asyncio.run(
            _request(
                "PATCH",
                "/v1/account/preparation-budget",
                json={"daily_preparation_budget_minutes": minutes},
            ),
        )

        assert response.status_code == 200
        assert response.json() == {
            "daily_preparation_budget_minutes": minutes,
        }
        assert service.calls == [("preparation_budget", USER_ID, minutes)]

    for invalid_body in [
        {"daily_preparation_budget_minutes": 24},
        {"daily_preparation_budget_minutes": 26},
        {"daily_preparation_budget_minutes": 481},
        {"daily_preparation_budget_minutes": True},
        {"daily_preparation_budget_minutes": "120"},
        {"daily_preparation_budget_minutes": 120, "user_id": "other"},
        {},
    ]:
        invalid, invalid_service = asyncio.run(
            _request(
                "PATCH",
                "/v1/account/preparation-budget",
                json=invalid_body,
            ),
        )
        assert invalid.status_code == 422
        assert invalid_service.calls == []


def test_patch_preparation_budget_maps_failures_without_leaking_details() -> None:
    cases = [
        (InvalidPreparationBudgetError("invalid rule"), 422),
        (AccountNotFoundError("private owner"), 404),
        (AccountPreparationBudgetUpdateOutcomeUnknownError("private result"), 502),
        (AccountPersistenceError("private upstream"), 503),
    ]
    for error, expected_status in cases:
        service = Service()
        service.preparation_budget_error = error
        response, _ = asyncio.run(
            _request(
                "PATCH",
                "/v1/account/preparation-budget",
                json={"daily_preparation_budget_minutes": 120},
                service=service,
            ),
        )
        assert response.status_code == expected_status
        assert "private" not in response.text


def test_export_returns_download_ready_versioned_json_and_maps_limits() -> None:
    response, service = asyncio.run(_request("GET", "/v1/account/export"))

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/json")
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["content-disposition"] == (
        'attachment; filename="mylifegraph-account-export.json"'
    )
    assert response.json()["contract_version"] == "account-export-v1"
    assert response.json()["data"]["profiles"][0]["id"] == USER_ID
    assert service.calls == [("export", USER_ID)]

    limited_service = Service()
    limited_service.export_error = AccountExportTooLargeError("V1 bound reached")
    limited, _ = asyncio.run(
        _request("GET", "/v1/account/export", service=limited_service),
    )
    assert limited.status_code == 413
    assert limited.json() == {"detail": "V1 bound reached"}

    failed_service = Service()
    failed_service.export_error = AccountPersistenceError("private upstream detail")
    failed, _ = asyncio.run(
        _request("GET", "/v1/account/export", service=failed_service),
    )
    assert failed.status_code == 503
    assert "private" not in failed.text


def test_delete_requires_exact_confirmation_and_returns_no_content() -> None:
    response, service = asyncio.run(
        _request("DELETE", "/v1/account", json={"confirmation": "DELETE"}),
    )

    assert response.status_code == 204
    assert response.content == b""
    assert service.calls == [("delete", USER_ID, "DELETE")]

    for invalid_body in [
        {"confirmation": "delete"},
        {"confirmation": " DELETE "},
        {"confirmation": "DELETE", "user_id": "other"},
        {},
    ]:
        invalid, invalid_service = asyncio.run(
            _request("DELETE", "/v1/account", json=invalid_body),
        )
        assert invalid.status_code == 422
        assert invalid_service.calls == []


def test_delete_maps_atomic_failure_without_leaking_details() -> None:
    cases = [
        (AccountNotFoundError("private"), 404),
        (AccountDeletionOutcomeUnknownError("private"), 502),
        (AccountPersistenceError("private"), 503),
    ]
    for error, expected_status in cases:
        service = Service()
        service.delete_error = error
        response, _ = asyncio.run(
            _request(
                "DELETE",
                "/v1/account",
                json={"confirmation": "DELETE"},
                service=service,
            ),
        )
        assert response.status_code == expected_status
        assert "private" not in response.text


def test_delete_requires_recent_authentication_before_service_call() -> None:
    cases = [
        None,
        datetime.now(UTC) - timedelta(minutes=16),
        datetime.now(UTC) + timedelta(minutes=2),
    ]
    for authenticated_at in cases:
        service = Service()
        app = create_app()
        app.state.token_verifier = ExplicitAuthenticationTimeVerifier(
            authenticated_at,
        )
        app.state.account_service = service

        async def request_delete():
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app),
                base_url="http://test",
            ) as client:
                return await client.request(
                    "DELETE",
                    "/v1/account",
                    headers={"Authorization": "Bearer valid-account-token"},
                    json={"confirmation": "DELETE"},
                )

        response = asyncio.run(request_delete())

        assert response.status_code == 403
        assert response.json() == {
            "detail": "Recent authentication is required before account deletion.",
        }
        assert service.calls == []


def test_delete_accepts_small_clock_skew_for_recent_authentication() -> None:
    response, service = asyncio.run(
        _request(
            "DELETE",
            "/v1/account",
            json={"confirmation": "DELETE"},
            authenticated_at=datetime.now(UTC) + timedelta(seconds=30),
        ),
    )

    assert response.status_code == 204
    assert service.calls == [("delete", USER_ID, "DELETE")]


def test_account_routes_require_authentication_before_service_calls() -> None:
    requests = [
        ("PATCH", "/v1/account/profile", {"timezone": "UTC"}),
        ("GET", "/v1/account/export", None),
        ("DELETE", "/v1/account", {"confirmation": "DELETE"}),
    ]
    for method, path, body in requests:
        response, service = asyncio.run(
            _request(
                method,
                path,
                json=body,
                authenticated=False,
            ),
        )
        assert response.status_code == 401
        assert service.calls == []
