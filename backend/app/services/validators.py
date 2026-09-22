"""
BR-01..BR-08 validators — business-rules.md (notebook 6 numbering).

BR-08 = Emotion Recognition prohibition (EU AI Act), not meeting waste.
"""
from __future__ import annotations

from datetime import datetime, time, timezone
from decimal import Decimal
from typing import Optional
from zoneinfo import ZoneInfo

from app.services.clock import now_utc
from app.services.exceptions import (
    AntiGETException,
    EmotionRecognitionProhibited,
    InvalidTelemetryFormat,
    JapaneseVeilViolation,
    RightToDisconnectViolation,
    SovereignVetoExpired,
)

SPOON_BANKRUPTCY_COUNT = 3
SPOON_BANKRUPTCY_PCT = Decimal("14.0")
HRV_HARD_CUT_MS = 40.0
HRV_NESS_CUT_MS = 35.0
HRV_SHAY_CUT_MS = 55.0
JAPANESE_VEIL_MIN_MEMBERS = 5
SOVEREIGN_VETO_WINDOW_MINUTES = 60
MAX_SPOONS = 12
DEPRIVATION_TAX_RATE = Decimal("0.12")
TALENT_REPLACEMENT_COST_NIS = Decimal("105000")
DISCONNECT_START = time(19, 0)
DISCONNECT_END = time(7, 0)
DEFAULT_TZ = ZoneInfo("Asia/Jerusalem")


def check_br01_spoon_bankruptcy(
    current_spoon_count: int,
    available_capacity_pct: Optional[Decimal] = None,
    daily_baseline: int = 12,
) -> bool:
    """BR-01 — spoons < 3 (of 12) or available capacity < 14%."""
    if current_spoon_count < SPOON_BANKRUPTCY_COUNT:
        return True
    if available_capacity_pct is None and daily_baseline:
        available_capacity_pct = (
            Decimal(current_spoon_count) / Decimal(daily_baseline) * Decimal("100")
        )
    if available_capacity_pct is not None and available_capacity_pct < SPOON_BANKRUPTCY_PCT:
        return True
    return False


def hrv_threshold_ms(avatar_role: Optional[str] = None) -> float:
    """BR-02 role cuts. General hard cut is 40ms; NESS 35; SHAY 55."""
    if avatar_role == "NESS":
        return HRV_NESS_CUT_MS
    if avatar_role == "SHAY":
        return HRV_SHAY_CUT_MS
    return HRV_HARD_CUT_MS


def check_br02_biometric_braking(
    hrv_ms: float,
    avatar_role: Optional[str] = None,
) -> bool:
    """BR-02 — biometric braking at the role threshold."""
    return hrv_ms < hrv_threshold_ms(avatar_role)


def task_assign_circuit_open(
    current_spoon_count: int,
    hrv_ms: Optional[float],
    available_capacity_pct: Optional[Decimal] = None,
) -> bool:
    """OpenAPI task gate: 403 when spoons < 3 or HRV < 40ms (also BR-01 capacity)."""
    if check_br01_spoon_bankruptcy(current_spoon_count, available_capacity_pct):
        return True
    if hrv_ms is not None and hrv_ms < HRV_HARD_CUT_MS:
        return True
    return False


def enforce_br03_anti_get(
    *,
    circuit_breaker_active: bool,
    attempt_graded_load_increase: bool = True,
) -> None:
    """BR-03 — graded load while at risk raises Anti_GET_Exception (409)."""
    if attempt_graded_load_increase and circuit_breaker_active:
        raise AntiGETException(
            "Graded task allocation blocked while Circuit Breaker is active. "
            "Chunk the work into micro-units (Anti-GET / Smart Pacing)."
        )


def calculate_br04_deprivation_tax(
    mean_salary: Decimal,
    n_deprived: int,
) -> Decimal:
    """BR-04 — Tax = 0.12 × Mean_Salary × N_Deprived."""
    return (DEPRIVATION_TAX_RATE * mean_salary * Decimal(n_deprived)).quantize(
        Decimal("0.01")
    )


def enforce_br05_japanese_veil(member_count: int) -> None:
    """BR-05 — N < 5 → 403 Japanese_Veil_Violation."""
    if member_count < JAPANESE_VEIL_MIN_MEMBERS:
        raise JapaneseVeilViolation(
            "Access denied: Target group contains fewer than 5 employees "
            "(Rule of 5+ enforcement)."
        )


def enforce_br06_sovereign_veto_window(
    veto_window_expiry: datetime,
    *,
    now: Optional[datetime] = None,
) -> None:
    """BR-06 — veto after the 60-minute window → 422."""
    now = now or now_utc()
    expiry = veto_window_expiry
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=timezone.utc)
    if now > expiry:
        raise SovereignVetoExpired(
            "Sovereign Veto attempted after the 60-minute Cuckoo Ping window expired."
        )


def is_in_disconnect_window(
    when: Optional[datetime] = None,
    *,
    tz: ZoneInfo = DEFAULT_TZ,
) -> bool:
    """True when local time is in [19:00, 24:00) ∪ [00:00, 07:00)."""
    when = when or now_utc().astimezone(tz)
    if when.tzinfo is None:
        when = when.replace(tzinfo=tz)
    else:
        when = when.astimezone(tz)
    t = when.time()
    return t >= DISCONNECT_START or t < DISCONNECT_END


def enforce_br07_right_to_disconnect(
    when: Optional[datetime] = None,
    *,
    tz: ZoneInfo = DEFAULT_TZ,
    force_task_or_message: bool = True,
) -> None:
    """BR-07 — forced tasks/messages forbidden 19:00–07:00 Asia/Jerusalem."""
    if force_task_or_message and is_in_disconnect_window(when, tz=tz):
        raise RightToDisconnectViolation(
            "Right to Disconnect: forced tasks/messages forbidden between "
            "19:00 and 07:00 (Asia/Jerusalem)."
        )


def enforce_br08_emotion_recognition(
    *,
    video_emotion: bool = False,
    facial_emotion: bool = False,
    voice_tone_emotion: bool = False,
) -> None:
    """BR-08 — block workplace emotion recognition (EU AI Act)."""
    if video_emotion or facial_emotion or voice_tone_emotion:
        raise EmotionRecognitionProhibited(
            "Emotion Recognition is prohibited under EU AI Act Art. 13 "
            "(workplace video/face/voice emotion processing). Use objective "
            "physio-behavioral patterns only."
        )


def validate_telemetry_ranges(
    *,
    hrv_ms: Optional[float] = None,
    spoon_count: Optional[int] = None,
    sampling_rate_hz: Optional[float] = None,
) -> None:
    """400 Invalid_Telemetry_Format — negative HRV, spoons outside 0–12, bad rate."""
    if hrv_ms is not None and hrv_ms < 0:
        raise InvalidTelemetryFormat(
            "Biometric parameters out of valid range (e.g. negative HRV or Spoons > 12)."
        )
    if spoon_count is not None and (spoon_count < 0 or spoon_count > MAX_SPOONS):
        raise InvalidTelemetryFormat(
            "Biometric parameters out of valid range (e.g. negative HRV or Spoons > 12)."
        )
    if sampling_rate_hz is not None and (sampling_rate_hz <= 0 or sampling_rate_hz > 1000):
        raise InvalidTelemetryFormat(
            "Biometric parameters out of valid range (e.g. negative HRV or Spoons > 12)."
        )
