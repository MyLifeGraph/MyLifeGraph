from fastapi import Request

from app.api.deps.composition import get_application_composition
from app.clients.supabase import SupabaseConfigurationError, SupabaseRestClient


def get_supabase_client(request: Request) -> SupabaseRestClient:
    try:
        return get_application_composition(request).supabase_client
    except SupabaseConfigurationError as exc:
        raise SupabaseConfigurationError(
            "Supabase persistence is not configured for this application.",
        ) from exc
