from fastapi import HTTPException, Request, status

from app.api.deps.composition import get_application_composition
from app.clients.supabase import SupabaseConfigurationError
from app.composition import CoachServices
from app.services.coach_agent_service import CoachAgentService
from app.services.coach_service import CoachService


async def get_coach_services(request: Request) -> CoachServices:
    try:
        return get_application_composition(request).coach_services
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "provider_unavailable",
                "message": "Coach persistence is not configured.",
                "retryable": False,
            },
        ) from exc


async def get_coach_service(request: Request) -> CoachService:
    return (await get_coach_services(request)).legacy


async def get_coach_agent_service(request: Request) -> CoachAgentService:
    return (await get_coach_services(request)).current
