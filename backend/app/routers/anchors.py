"""Employee anchors + value asset. Extension — not in locked OpenAPI."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.routers.deps import require_bearer
from app.schemas.api import (
    AnchorView,
    AnchorsResponse,
    AnchorsUpdateRequest,
    EmployeeValueAssetView,
)
from app.services.store import Anchor, new_id, store

router = APIRouter(
    prefix="/anchors",
    tags=["anchors"],
    dependencies=[Depends(require_bearer)],
)


def _view(user_id: str) -> AnchorsResponse:
    store.ensure_defaults(user_id)
    asset = store.assets[user_id]
    return AnchorsResponse(
        user_id=user_id,
        employee_value_asset=EmployeeValueAssetView(
            employee_id=asset.employee_id,
            direct_cost_opex=asset.direct_cost_opex,
            asset_value_capex=asset.asset_value_capex,
            productivity_alpha_factor=asset.productivity_alpha_factor,
            happiness_debt_liability=asset.happiness_debt_liability,
        ),
        anchors=[
            AnchorView(
                anchor_id=row.anchor_id,
                user_id=row.user_id,
                type_lighting=row.type_lighting,  # type: ignore[arg-type]
                territory_schema=row.territory_schema,
                exposure_gate=row.exposure_gate,  # type: ignore[arg-type]
                created_at=row.created_at,
            )
            for row in store.anchors.get(user_id, [])
        ],
    )


@router.get("/{userId}", response_model=AnchorsResponse)
def get_anchors(userId: str) -> AnchorsResponse:
    return _view(userId)


@router.put("/{userId}", response_model=AnchorsResponse)
def put_anchors(userId: str, body: AnchorsUpdateRequest) -> AnchorsResponse:
    store.ensure_defaults(userId)
    store.anchors[userId] = [
        Anchor(
            anchor_id=new_id("anchor"),
            user_id=userId,
            type_lighting=item.type_lighting,
            territory_schema=item.territory_schema,
            exposure_gate=item.exposure_gate,
        )
        for item in body.anchors
    ]
    return _view(userId)
