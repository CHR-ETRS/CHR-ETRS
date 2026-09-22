"""ERP/HRIS dichotomous wellness sync (RED/GREEN only)."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.routers.deps import require_bearer
from app.schemas.api import WorkerWellnessSyncRequest, WorkerWellnessSyncResponse
from app.services.store import new_id, sha256_hex

router = APIRouter(
    prefix="/hris",
    tags=["hris"],
    dependencies=[Depends(require_bearer)],
)


@router.post("/worker-wellness-sync", response_model=WorkerWellnessSyncResponse)
def worker_wellness_sync(body: WorkerWellnessSyncRequest) -> WorkerWellnessSyncResponse:
    enforcement = body.system_enforcement
    if enforcement.halt_task_allocation or enforcement.circuit_breaker_active:
        applied = "TASK_BLOCKING_ENFORCED_DICHOTOMOUS_" + enforcement.dichotomous_alert_level
    else:
        applied = "NO_ENFORCEMENT_" + enforcement.dichotomous_alert_level
    token = sha256_hex(
        f"{body.worker_id}|{body.org_tenant_id}|{body.sync_timestamp.isoformat()}|{applied}"
    )
    return WorkerWellnessSyncResponse(
        sync_status="SUCCESS",
        erp_reference_id=f"WD-{new_id('upd')}",
        applied_enforcement=applied,
        audit_proof_token=token,
    )
