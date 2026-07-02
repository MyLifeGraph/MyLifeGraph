from collections.abc import Mapping, Sequence
from typing import Any

import httpx

from app.core.config import Settings


QueryParams = Mapping[str, str] | Sequence[tuple[str, str]]


class SupabaseConfigurationError(RuntimeError):
    pass


class SupabaseRestClient:
    def __init__(
        self,
        *,
        url: str,
        service_role_key: str,
        timeout_seconds: float = 10,
    ) -> None:
        if not url.strip() or not service_role_key.strip():
            raise SupabaseConfigurationError(
                "Supabase URL and service-role key are required for backend access.",
            )
        self._url = url.rstrip("/")
        self._service_role_key = service_role_key
        self._timeout_seconds = timeout_seconds

    @classmethod
    def from_settings(cls, settings: Settings) -> "SupabaseRestClient":
        return cls(
            url=settings.supabase_url,
            service_role_key=settings.supabase_service_role_key,
            timeout_seconds=settings.supabase_timeout_seconds,
        )

    async def select(
        self,
        table: str,
        *,
        params: QueryParams,
    ) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(timeout=self._timeout_seconds) as client:
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

    async def insert(
        self,
        table: str,
        *,
        rows: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        if not rows:
            return []
        async with httpx.AsyncClient(timeout=self._timeout_seconds) as client:
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
        async with httpx.AsyncClient(timeout=self._timeout_seconds) as client:
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
        async with httpx.AsyncClient(timeout=self._timeout_seconds) as client:
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

    async def get_user_for_token(self, token: str) -> dict[str, Any] | None:
        async with httpx.AsyncClient(timeout=self._timeout_seconds) as client:
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
        return {
            "apikey": self._service_role_key,
            "Authorization": f"Bearer {self._service_role_key}",
            "Content-Type": "application/json",
        }
