"""Task assign — circuit breakers (403) and Anti-GET (409)."""
from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends

from app.routers.deps import require_bearer
from app.schemas.api import AssignTaskRequest, AssignTaskResponse
from app.services.exceptions import CircuitBreakerDenied, RightToDisconnectViolation
from app.services.store import Task, new_id, sha256_hex, store
from app.services.validators import (
    enforce_br03_anti_get,
    enforce_br07_right_to_disconnect,
    task_assign_circuit_open,
)

router = APIRouter(
    prefix="/tasks",
    tags=["tasks"],
    dependencies=[Depends(require_bearer)],
)


@router.post("/assign", response_model=AssignTaskResponse)
def assign_task(body: AssignTaskRequest) -> AssignTaskResponse:
    try:
        enforce_br07_right_to_disconnect()
    except RightToDisconnectViolation:
        store.record_disconnect_debt("mgr-glass", body.assignee_id)
        raise

    store.ensure_defaults(body.assignee_id)
    budget = store.spoons[body.assignee_id]
    hrv = store.latest_hrv_ms(body.assignee_id)
    pct = Decimal(str(budget.available_capacity_pct))
    circuit_open = task_assign_circuit_open(budget.current_spoon_count, hrv, pct)

    enforce_br03_anti_get(
        circuit_breaker_active=circuit_open,
        attempt_graded_load_increase=body.attempt_graded_load_increase,
    )

    if circuit_open:
        digest = sha256_hex(
            f"circuit|{body.assignee_id}|{budget.current_spoon_count}|{hrv}"
        )
        reason = []
        if budget.current_spoon_count < 3 or budget.available_capacity_pct < 14:
            reason.append("spoons < 3 or capacity < 14%")
        if hrv is not None and hrv < 40:
            reason.append("HRV < 40ms")
        detail = " and ".join(reason) or "risk threshold"
        raise CircuitBreakerDenied(
            f"Circuit breaker: task assignment blocked ({detail}).",
            logic_hash=digest,
        )

    task = Task(
        task_id=new_id("task"),
        assignee_id=body.assignee_id,
        task_name=body.task_name,
        complexity_spoon_cost=body.complexity_spoon_cost,
        is_chunkable=body.is_chunkable,
        pacing_status="Chunked" if body.is_chunkable else "Normal",
        is_blocked_by_circuit_breaker=False,
    )
    store.tasks.append(task)
    store.spend_spoons(body.assignee_id, body.complexity_spoon_cost)
    return AssignTaskResponse(
        task_id=task.task_id,
        is_blocked_by_circuit_breaker=False,
        pacing_status=task.pacing_status,
    )
