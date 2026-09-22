"""Telemetry LSL, HRV ingest, and SpoonBudget."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.routers.deps import require_bearer
from app.schemas.api import (
    HrvSampleRequest,
    HrvSampleResponse,
    HrvStreamFrame,
    SpoonsBreakdown,
    SpoonsBudgetResponse,
)
from app.services.store import new_id, store, utcnow
from app.services.validators import (
    check_br02_biometric_braking,
    hrv_threshold_ms,
    validate_telemetry_ranges,
)

router = APIRouter(
    prefix="/telemetry",
    tags=["telemetry"],
    dependencies=[Depends(require_bearer)],
)

_DEVICE_USERS = {
    "luna-hope": "emp-hope",
    "luna-low": "emp-low",
}


@router.get("/hrv-stream", response_model=HrvStreamFrame)
def stream_hrv_telemetry(
    device_id: str = Query(...),
    sampling_rate_hz: float = Query(default=1),
) -> HrvStreamFrame:
    """JSON stand-in for the 1Hz LSL stream contract (single frame)."""
    if not device_id.strip():
        validate_telemetry_ranges(sampling_rate_hz=-1)
    validate_telemetry_ranges(sampling_rate_hz=sampling_rate_hz)
    user_id = _DEVICE_USERS.get(device_id)
    if user_id:
        sample = store.latest_hrv(user_id)
        if sample:
            return HrvStreamFrame(
                sample_id=sample.sample_id,
                timestamp=sample.sample_timestamp,
                hrv_baseline=sample.hrv_baseline,
                distal_skin_temp=sample.distal_skin_temp,
                vagal_tone_index=sample.vagal_tone_index,
            )
    return HrvStreamFrame(
        sample_id=new_id("stream"),
        timestamp=utcnow(),
        hrv_baseline=58.0,
        distal_skin_temp=33.1,
        vagal_tone_index=0.72,
    )


@router.post("/hrv-sample", response_model=HrvSampleResponse, status_code=201)
def ingest_hrv_sample(body: HrvSampleRequest) -> HrvSampleResponse:
    validate_telemetry_ranges(hrv_ms=body.hrv_baseline_ms)
    store.ensure_defaults(body.user_id)
    avatar = store.avatars.get(body.user_id)
    role = avatar.base_role if avatar else None
    triggered = check_br02_biometric_braking(body.hrv_baseline_ms, role)
    sample_id = new_id("smp")
    from app.services.store import HRVSample

    store.add_hrv(
        HRVSample(
            sample_id=sample_id,
            user_id=body.user_id,
            hrv_baseline=body.hrv_baseline_ms,
            distal_skin_temp=body.distal_skin_temp_celsius,
            vagal_tone_index=body.vagal_tone_index,
            cold_stim_recovery=body.cold_stim_recovery_seconds,
            sample_timestamp=body.sample_timestamp,
        )
    )
    violation = None
    if triggered:
        cut = hrv_threshold_ms(role)
        violation = f"HRV_BELOW_{int(cut)}MS_CUT"
    return HrvSampleResponse(
        status="ACCEPTED_TO_PRIVATE_VAULT",
        sample_id=sample_id,
        biometric_alert_triggered=triggered,
        threshold_violation=violation,
    )


@router.get("/spoons-budget/{userId}", response_model=SpoonsBudgetResponse)
def get_spoons_budget(userId: str) -> SpoonsBudgetResponse:
    store.ensure_defaults(userId)
    budget = store.spoons[userId]
    return SpoonsBudgetResponse(
        user_id=userId,
        daily_baseline_capacity=budget.daily_baseline_capacity,
        current_spoon_count=budget.current_spoon_count,
        available_capacity_pct=budget.available_capacity_pct,
        energy_state_indicator=budget.energy_state_indicator,
        breakdown=SpoonsBreakdown(
            sinks_expenditure=budget.sinks_expenditure,
            sources_recovery=budget.sources_recovery,
            golden_spoons_held=budget.golden_spoons_held,
        ),
        smart_pacing_status=budget.smart_pacing_status,
    )
