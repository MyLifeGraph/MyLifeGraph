import json
from collections.abc import AsyncIterator, Mapping, Sequence
from contextlib import asynccontextmanager
from decimal import Decimal
from typing import Any

import httpx

from app.core.config import Settings


QueryParams = Mapping[str, str] | Sequence[tuple[str, str]]


class SupabaseConfigurationError(RuntimeError):
    pass


class SupabaseResponseTooLargeError(RuntimeError):
    pass


class SupabaseRestClient:
    def __init__(
        self,
        *,
        url: str,
        service_role_key: str,
        timeout_seconds: float = 10,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        if not url.strip() or not service_role_key.strip():
            raise SupabaseConfigurationError(
                "Supabase URL and backend key are required for backend access.",
            )
        self._url = url.rstrip("/")
        self._service_role_key = service_role_key
        self._timeout_seconds = timeout_seconds
        self._http_client = http_client

    @classmethod
    def from_settings(
        cls,
        settings: Settings,
        *,
        http_client: httpx.AsyncClient | None = None,
    ) -> "SupabaseRestClient":
        try:
            url, backend_key = settings.supabase_backend_configuration()
            return cls(
                url=url,
                service_role_key=backend_key,
                timeout_seconds=settings.supabase_timeout_seconds,
                http_client=http_client,
            )
        except ValueError as exc:
            raise SupabaseConfigurationError(str(exc)) from exc

    @classmethod
    def pooled_from_settings(cls, settings: Settings) -> "SupabaseRestClient":
        client = cls.from_settings(settings)
        client._http_client = httpx.AsyncClient(
            timeout=settings.supabase_timeout_seconds,
        )
        return client

    async def aclose(self) -> None:
        client = self._http_client
        if client is not None:
            self._http_client = None
            await client.aclose()

    async def readiness_probe(self) -> None:
        """Bounded, body-free PostgREST reachability check."""

        async with self._request_client() as client:
            response = await client.head(
                f"{self._url}/rest/v1/profiles",
                params={"select": "id", "limit": "1"},
                headers=self._rest_headers(),
            )
        response.raise_for_status()

    async def pilot_participation_gate(self) -> dict[str, Any]:
        data = await self.rpc(
            "get_pilot_participation_gate_v1",
            params={},
        )
        if not isinstance(data, dict):
            raise ValueError("Expected pilot participation gate object.")
        return data

    async def hosted_database_contract(
        self,
        *,
        through_head: str,
    ) -> dict[str, Any]:
        data = await self.rpc(
            "get_hosted_database_contract_v1",
            params={"p_through_head": through_head},
        )
        if (
            not isinstance(data, dict)
            or set(data)
            != {
                "contract_version",
                "migration_head",
                "migration_count",
                "migration_identity_sha256",
                "prefix_head",
                "prefix_count",
                "prefix_identity_sha256",
                "prepared_deletion_pending_guard",
            }
            or not isinstance(data.get("migration_head"), str)
            or type(data.get("migration_count")) is not int
            or not isinstance(data.get("migration_identity_sha256"), str)
            or not isinstance(data.get("prefix_head"), str)
            or type(data.get("prefix_count")) is not int
            or not isinstance(data.get("prefix_identity_sha256"), str)
            or type(data.get("prepared_deletion_pending_guard")) is not bool
        ):
            raise ValueError("Expected hosted database contract object.")
        return data

    async def account_deletion_pending(self, *, user_id: str) -> bool:
        data = await self.rpc(
            "get_account_deletion_pending_v2",
            params={"p_user_id": user_id},
        )
        if (
            not isinstance(data, dict)
            or set(data) != {"contract_version", "pending"}
            or data.get("contract_version") != "account-deletion-pending-v2"
            or type(data.get("pending")) is not bool
        ):
            raise ValueError("Expected account deletion pending object.")
        return data["pending"]

    async def account_deletion_recovery_status(self) -> dict[str, Any]:
        data = await self.rpc(
            "get_account_deletion_recovery_status_v2",
            params={},
        )
        expected_keys = {
            "contract_version",
            "legacy_direct_delete_revoked",
            "pending_count",
            "oldest_pending_at",
        }
        if (
            not isinstance(data, dict)
            or set(data) != expected_keys
            or data.get("contract_version") != "account-deletion-recovery-v2"
            or type(data.get("legacy_direct_delete_revoked")) is not bool
            or type(data.get("pending_count")) is not int
            or data["pending_count"] < 0
            or (
                data.get("oldest_pending_at") is not None
                and not isinstance(data.get("oldest_pending_at"), str)
            )
            or (data["pending_count"] == 0) != (data["oldest_pending_at"] is None)
        ):
            raise ValueError("Expected account deletion recovery status object.")
        return data

    @asynccontextmanager
    async def _request_client(self) -> AsyncIterator[httpx.AsyncClient]:
        if self._http_client is not None:
            yield self._http_client
            return
        async with httpx.AsyncClient(timeout=self._timeout_seconds) as client:
            yield client

    async def select(
        self,
        table: str,
        *,
        params: QueryParams,
        max_response_bytes: int | None = None,
    ) -> list[dict[str, Any]]:
        if max_response_bytes is not None:
            return await self._select_bounded(
                table,
                params=params,
                max_response_bytes=max_response_bytes,
            )
        async with self._request_client() as client:
            response = await client.get(
                f"{self._url}/rest/v1/{table}",
                params=params,
                headers=self._rest_headers(),
            )
        response.raise_for_status()
        data = response.json()
        if not isinstance(data, list):
            raise ValueError(f"Expected list response from Supabase table {table}.")
        return data

    async def count_exact(
        self,
        table: str,
        *,
        params: QueryParams,
    ) -> int:
        """Return PostgREST's exact filtered row count without a response body."""

        async with self._request_client() as client:
            response = await client.head(
                f"{self._url}/rest/v1/{table}",
                params=params,
                headers={
                    **self._rest_headers(),
                    "Prefer": "count=exact",
                    "Range-Unit": "items",
                    "Range": "0-0",
                },
            )
        response.raise_for_status()
        preference_applied = response.headers.get("Preference-Applied", "")
        applied = {
            value.strip() for value in preference_applied.split(",") if value.strip()
        }
        if "count=exact" not in applied:
            raise ValueError(
                f"Supabase exact count for table {table} was not applied.",
            )
        content_range = response.headers.get("Content-Range")
        if content_range is None:
            raise ValueError(
                f"Supabase exact count for table {table} lacks Content-Range.",
            )
        _, separator, raw_total = content_range.rpartition("/")
        raw_total = raw_total.strip()
        if not separator or not raw_total.isdecimal():
            raise ValueError(
                f"Supabase exact count for table {table} is invalid.",
            )
        return int(raw_total)

    async def _select_bounded(
        self,
        table: str,
        *,
        params: QueryParams,
        max_response_bytes: int,
    ) -> list[dict[str, Any]]:
        if max_response_bytes <= 0:
            raise ValueError("max_response_bytes must be positive")
        body = bytearray()
        async with self._request_client() as client:
            async with client.stream(
                "GET",
                f"{self._url}/rest/v1/{table}",
                params=params,
                headers=self._rest_headers(),
            ) as response:
                response.raise_for_status()
                content_length = response.headers.get("Content-Length")
                if content_length is not None:
                    try:
                        declared_bytes = int(content_length)
                    except ValueError:
                        declared_bytes = None
                    if (
                        declared_bytes is not None
                        and declared_bytes > max_response_bytes
                    ):
                        raise SupabaseResponseTooLargeError(
                            "Supabase response exceeds the configured byte bound.",
                        )
                async for chunk in response.aiter_bytes(
                    chunk_size=min(64 * 1024, max_response_bytes + 1),
                ):
                    if len(body) + len(chunk) > max_response_bytes:
                        raise SupabaseResponseTooLargeError(
                            "Supabase response exceeds the configured byte bound.",
                        )
                    body.extend(chunk)
        try:
            data = json.loads(body, parse_float=Decimal)
        except RecursionError as exc:
            raise ValueError(
                f"Invalid JSON response from Supabase table {table}.",
            ) from exc
        if not isinstance(data, list):
            raise ValueError(f"Expected list response from Supabase table {table}.")
        return data

    async def insert(
        self,
        table: str,
        *,
        rows: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        if not rows:
            return []
        async with self._request_client() as client:
            response = await client.post(
                f"{self._url}/rest/v1/{table}",
                json=rows,
                headers={
                    **self._rest_headers(),
                    "Prefer": "return=representation",
                },
            )
        response.raise_for_status()
        data = response.json()
        if not isinstance(data, list):
            raise ValueError(f"Expected list response from Supabase table {table}.")
        return data

    async def upsert(
        self,
        table: str,
        *,
        rows: list[dict[str, Any]],
        on_conflict: str | None = None,
    ) -> list[dict[str, Any]]:
        if not rows:
            return []
        params = {"on_conflict": on_conflict} if on_conflict else None
        async with self._request_client() as client:
            response = await client.post(
                f"{self._url}/rest/v1/{table}",
                params=params,
                json=rows,
                headers={
                    **self._rest_headers(),
                    "Prefer": "resolution=merge-duplicates,return=representation",
                },
            )
        response.raise_for_status()
        data = response.json()
        if not isinstance(data, list):
            raise ValueError(f"Expected list response from Supabase table {table}.")
        return data

    async def update(
        self,
        table: str,
        *,
        values: dict[str, Any],
        params: dict[str, str],
    ) -> list[dict[str, Any]]:
        async with self._request_client() as client:
            response = await client.patch(
                f"{self._url}/rest/v1/{table}",
                params=params,
                json=values,
                headers={
                    **self._rest_headers(),
                    "Prefer": "return=representation",
                },
            )
        response.raise_for_status()
        data = response.json()
        if not isinstance(data, list):
            raise ValueError(f"Expected list response from Supabase table {table}.")
        return data

    async def delete(
        self,
        table: str,
        *,
        params: dict[str, str],
    ) -> list[dict[str, Any]]:
        async with self._request_client() as client:
            response = await client.delete(
                f"{self._url}/rest/v1/{table}",
                params=params,
                headers={
                    **self._rest_headers(),
                    "Prefer": "return=representation",
                },
            )
        response.raise_for_status()
        data = response.json()
        if not isinstance(data, list):
            raise ValueError(f"Expected list response from Supabase table {table}.")
        return data

    async def rpc(
        self,
        function: str,
        *,
        params: dict[str, Any],
    ) -> Any:
        async with self._request_client() as client:
            response = await client.post(
                f"{self._url}/rest/v1/rpc/{function}",
                json=params,
                headers=self._rest_headers(),
            )
        response.raise_for_status()
        return response.json()

    async def get_user_for_token(self, token: str) -> dict[str, Any] | None:
        async with self._request_client() as client:
            response = await client.get(
                f"{self._url}/auth/v1/user",
                headers={
                    "apikey": self._service_role_key,
                    "Authorization": f"Bearer {token}",
                },
            )
        if response.status_code in {401, 403}:
            return None
        response.raise_for_status()
        data = response.json()
        return data if isinstance(data, dict) else None

    def _rest_headers(self) -> dict[str, str]:
        headers = {
            "apikey": self._service_role_key,
            "Content-Type": "application/json",
        }
        if not self._service_role_key.startswith("sb_secret_"):
            # Legacy service_role keys are JWTs and retain the historical
            # bearer header during migration. Opaque sb_secret_ keys are API
            # keys only; sending one as a JWT makes PostgREST reject it.
            headers["Authorization"] = f"Bearer {self._service_role_key}"
        return headers
