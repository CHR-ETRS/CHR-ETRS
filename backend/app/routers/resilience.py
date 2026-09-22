"""Avatar_State resilience matrix fed by SpoonBudget + latest HRVSample."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.routers.deps import require_bearer
from app.schemas.api import ResilienceAxes, ResilienceMatrixResponse
from app.services.store import store

router = APIRouter(
    prefix="/resilience",
    tags=["resilience"],
    dependencies=[Depends(require_bearer)],
)


@router.get("/matrix/{userId}", response_model=ResilienceMatrixResponse)
def resilience_matrix(userId: str) -> ResilienceMatrixResponse:
    store.ensure_defaults(userId)
    avatar = store.avatars[userId]
    role = store.derived_role(userId)
    hrv = store.latest_hrv_ms(userId)
    budget = store.spoons[userId]
    contrast = role == "NESS"
    latency = int(max(0, round(80 - (hrv if hrv is not None else 40))))
    avatar.contrast_nullification_active = contrast
    avatar.bone_memory_latency = latency
    axes = store.resilience_axes(userId)
    return ResilienceMatrixResponse(
        avatar_id=avatar.avatar_id,
        user_id=userId,
        role_state=role,  # type: ignore[arg-type]
        bone_memory_latency=latency,
        contrast_nullification_active=contrast,
        current_spoon_count=budget.current_spoon_count,
        latest_hrv_ms=hrv,
        resilience_axes=ResilienceAxes(**axes),
    )
