"""Dr. Cringe — sentiment patterns, Cuckoo trigger, circuit-breaker admin."""
from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, Depends

from app.routers.deps import require_bearer
from app.schemas.api import (
    AnalyzeSentimentRequest,
    AnalyzeSentimentResponse,
    CircuitBreakerRequest,
    CircuitBreakerResponse,
    TriggerCuckooPingRequest,
    TriggerCuckooPingResponse,
)
from app.services.exceptions import InvalidTelemetryFormat, SovereignVetoExpired
from app.services.store import CuckooAlert, new_id, sha256_hex, store, utcnow
from app.services.validators import (
    check_br02_biometric_braking,
    enforce_br03_anti_get,
    enforce_br08_emotion_recognition,
    task_assign_circuit_open,
)

router = APIRouter(
    prefix="/cringe",
    tags=["cringe"],
    dependencies=[Depends(require_bearer)],
)

_PRESSURE = ("חייב", "דחוף", "עכשיו", "משפחה", "תמיד", "urgent", "asap", "family")
_MASK = ("הכל בסדר", "מצוין", "אין בעיה", "great", "fine", "all good")


@router.post("/analyze-sentiment", response_model=AnalyzeSentimentResponse)
def analyze_sentiment(body: AnalyzeSentimentRequest) -> AnalyzeSentimentResponse:
    """Text-pattern analysis only (HeBERT/DictaBERT stand-in). Not emotion recognition."""
    enforce_br08_emotion_recognition()
    text = body.text_content.strip()
    if not text:
        raise InvalidTelemetryFormat(
            "Biometric parameters out of valid range (e.g. negative HRV or Spoons > 12)."
        )
    lowered = text.casefold()
    after_hours = bool(body.metadata and body.metadata.is_after_hours)
    pressure = after_hours or any(token in lowered for token in _PRESSURE)
    masking = pressure and any(token in lowered for token in _MASK)
    patterns: list[str] = []
    if pressure:
        patterns.append("Toxic_Positivity")
    if masking:
        patterns.append("Masking")
    confidence = 0.91 if pressure else 0.42
    action = "TRIGGER_CUCKOO_PING" if confidence >= 0.85 else "NONE"
    digest = sha256_hex(f"{body.user_id}|{body.source_channel}|{text}|{action}")
    return AnalyzeSentimentResponse(
        confidence_score=confidence,
        detected_patterns=patterns,  # type: ignore[arg-type]
        masking_penalty_score=3.85 if masking else (1.2 if pressure else 0.0),
        recommended_action=action,
        logic_hash=digest,
    )


@router.post("/trigger-cuckoo-ping", response_model=TriggerCuckooPingResponse)
def trigger_cuckoo_ping(body: TriggerCuckooPingRequest) -> TriggerCuckooPingResponse:
    requested = body.veto_window_minutes
    if requested < 1:
        raise SovereignVetoExpired(
            "Sovereign Veto attempted after the 60-minute Cuckoo Ping window expired."
        )
    # BR-06 locks the sovereign window at 60 minutes.
    window = min(requested, 60)
    expires = utcnow() + timedelta(minutes=window)
    alert_id = new_id("cuckoo")
    digest = sha256_hex(f"{alert_id}|{body.trigger_reason}|{expires.isoformat()}")
    store.ensure_defaults(body.target_user_id)
    store.alerts[alert_id] = CuckooAlert(
        alert_id=alert_id,
        manager_id=body.manager_id,
        target_user_id=body.target_user_id,
        trigger_reason=body.trigger_reason,
        sovereign_veto_window_expiry=expires,
        logic_hash=digest,
    )
    return TriggerCuckooPingResponse(
        alert_id=alert_id,
        status="VETO_WINDOW_ACTIVE",
        expires_at=expires,
        employee_private_ping_sent=True,
        manager_notified_anonymously=True,
    )


@router.post("/circuit-breaker", response_model=CircuitBreakerResponse)
def activate_circuit_breaker(body: CircuitBreakerRequest) -> CircuitBreakerResponse:
    store.ensure_defaults(body.target_user_id)
    metrics = body.trigger_metrics
    spoons = (
        metrics.spoons_remaining
        if metrics and metrics.spoons_remaining is not None
        else store.spoons[body.target_user_id].current_spoon_count
    )
    hrv = metrics.hrv_ms if metrics and metrics.hrv_ms is not None else store.latest_hrv_ms(
        body.target_user_id
    )
    avatar = store.avatars.get(body.target_user_id)
    role = avatar.base_role if avatar else None
    braking = hrv is not None and check_br02_biometric_braking(hrv, role)
    circuit_open = task_assign_circuit_open(spoons, hrv) or braking
    graded = "ALLOCATE_GRADED_TASK" in (body.enforcement_actions or [])
    enforce_br03_anti_get(
        circuit_breaker_active=circuit_open,
        attempt_graded_load_increase=graded,
    )
    now = utcnow()
    injected = 5 if circuit_open else 0
    if injected:
        store.inject_golden_spoons(body.target_user_id, injected)
    digest = sha256_hex(f"{body.target_user_id}|{body.circuit_breaker_type}|{now.isoformat()}")
    return CircuitBreakerResponse(
        circuit_breaker_status="ACTIVE" if circuit_open else "STANDBY",
        enforced_at=now,
        golden_spoons_injected=injected,
        eudaimonic_immunity_until=now + timedelta(days=2),
        jira_integration_status="READ_ONLY" if circuit_open else "OPEN",
        logic_hash=digest,
    )
