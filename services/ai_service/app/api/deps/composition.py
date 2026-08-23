from fastapi import Request

from app.clients.supabase import SupabaseConfigurationError
from app.composition import ApplicationComposition


def get_application_composition(request: Request) -> ApplicationComposition:
    composition = getattr(request.app.state, "composition", None)
    if not isinstance(composition, ApplicationComposition):
        raise SupabaseConfigurationError(
            "Application services are not configured.",
        )
    return composition
