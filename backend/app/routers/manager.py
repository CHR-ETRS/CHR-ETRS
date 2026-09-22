"""Glass Box dashboard (Japanese Veil) and WORM manager ledger."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.routers.deps import require_bearer
from app.schemas.api import (
    LedgerRecordRequest,
    LedgerRecordResponse,
    ManagerDashboardResponse,
)
from app.services.store import store
from app.services.validators import enforce_br05_japanese_veil

router = APIRouter(
    prefix="/manager",
    tags=["manager"],
    dependencies=[Depends(require_bearer)],
)


@router.get("/dashboard", response_model=ManagerDashboardResponse)
def manager_dashboard(
    org_id: str = Query(...),
    department_id: str = Query(...),
) -> ManagerDashboardResponse:
    team = store.teams.get((org_id, department_id))
    member_count = team.member_count if team else 0
    enforce_br05_japanese_veil(member_count)
    assert team is not None
    level = team.dichotomous_alert_level
    if team.team_spoon_avg < 4:
        level = "RED"
    return ManagerDashboardResponse(
        team_spoon_avg=team.team_spoon_avg,
        deprivation_tax_sum=team.deprivation_tax_sum,
        dichotomous_alert_level=level,  # type: ignore[arg-type]
        member_count=team.member_count,
        japanese_veil_applied=True,
    )


@router.post("/ledger/record", response_model=LedgerRecordResponse, status_code=201)
def record_manager_ledger(body: LedgerRecordRequest) -> LedgerRecordResponse:
    row = store.commit_ledger(
        manager_id=body.manager_id,
        action_type=body.action_type,
        cost_impact=body.cost_impact,
        event_description=body.event_description,
        system_justification=body.system_justification
        or "WORM append recorded by manager ledger API.",
        restoration_status="COMMITTED_IMMUTABLE",
    )
    return LedgerRecordResponse(
        ledger_id=row.ledger_id,
        logic_hash_sha256=row.logic_hash,
        worm_storage_status="COMMITTED_IMMUTABLE",
    )
