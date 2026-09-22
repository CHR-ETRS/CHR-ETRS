"""Sovereign Veto — employee-only, 60-minute window (BR-06)."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.routers.deps import require_bearer
from app.schemas.api import SovereignVetoRequest, SovereignVetoResponse
from app.services.exceptions import TargetForbidden
from app.services.store import JournalEntry, new_id, store
from app.services.validators import enforce_br06_sovereign_veto_window

router = APIRouter(
    prefix="/cuckoo",
    tags=["cuckoo"],
    dependencies=[Depends(require_bearer)],
)


@router.post("/veto", response_model=SovereignVetoResponse)
def sovereign_veto(body: SovereignVetoRequest) -> SovereignVetoResponse:
    alert = store.alerts.get(body.alert_id)
    if alert is None or alert.is_vetoed_by_employee:
        raise TargetForbidden(
            "Sovereign veto is authorized only for the target employee, "
            "and only on an open Cuckoo alert."
        )
    enforce_br06_sovereign_veto_window(alert.sovereign_veto_window_expiry)
    alert.is_vetoed_by_employee = True
    # Reason stays in the employee private vault. The ledger line is anonymous.
    store.journal.setdefault(alert.target_user_id, []).append(
        JournalEntry(
            entry_id=new_id("journal"),
            user_id=alert.target_user_id,
            hallway_mirror_response="הווטו הריבוני ננעל בכספת. הסיבה אינה גלויה למנהל.",
            relational_offloading_text=None,
            encrypted_blob=body.encrypted_reason_note,
            sealed=True,
        )
    )
    row = store.commit_ledger(
        manager_id=alert.manager_id,
        action_type="Sovereign_Veto",
        cost_impact=0.0,
        event_description=(
            "Employee exercised Sovereign Veto inside the Cuckoo window. "
            "Reason sealed in the private vault and omitted from this ledger."
        ),
        system_justification="BR-06 Cuckoo / Sovereign Veto (60 min). Manager credited anonymously.",
        restoration_status="Veto_Honored",
    )
    return SovereignVetoResponse(
        status="VETOED_BY_EMPLOYEE",
        manager_ledger_credited=True,
        logic_hash=row.logic_hash,
    )
