"""Domain exceptions mapped to the locked OpenAPI error dictionary."""
from __future__ import annotations


class ChrEtrsDomainError(Exception):
    error_code: str = "WORM_Ledger_Write_Failure"
    http_status: int = 500

    def __init__(self, message: str, logic_hash: str | None = None):
        self.message = message
        self.logic_hash = logic_hash
        super().__init__(message)


class InvalidTelemetryFormat(ChrEtrsDomainError):
    """400 — Invalid_Telemetry_Format."""

    error_code = "Invalid_Telemetry_Format"
    http_status = 400


class InvalidOAuthToken(ChrEtrsDomainError):
    """401 — Invalid_OAuth_Token."""

    error_code = "Invalid_OAuth_Token"
    http_status = 401


class JapaneseVeilViolation(ChrEtrsDomainError):
    """403 — Japanese_Veil_Violation (BR-05)."""

    error_code = "Japanese_Veil_Violation"
    http_status = 403


class CircuitBreakerDenied(ChrEtrsDomainError):
    """403 — task assign blocked by BR-01 / BR-02.

    The locked ErrorResponse enum has no dedicated circuit-breaker token.
    The Forbidden component is shared with Japanese Veil, but reusing that
    code would hide the breaker from Smart Pacing. MVP returns this code
    with HTTP 403 and the ErrorResponse shape (see README).
    """

    error_code = "Circuit_Breaker_Active"
    http_status = 403


class AntiGETException(ChrEtrsDomainError):
    """409 — Anti_GET_Exception (BR-03)."""

    error_code = "Anti_GET_Exception"
    http_status = 409


class SovereignVetoExpired(ChrEtrsDomainError):
    """422 — Sovereign_Veto_Expired (BR-06)."""

    error_code = "Sovereign_Veto_Expired"
    http_status = 422


class WormLedgerWriteFailure(ChrEtrsDomainError):
    """500 — WORM_Ledger_Write_Failure."""

    error_code = "WORM_Ledger_Write_Failure"
    http_status = 500


class RightToDisconnectViolation(ChrEtrsDomainError):
    """403 — Right_To_Disconnect_Violation (BR-07)."""

    error_code = "Right_To_Disconnect_Violation"
    http_status = 403


class EmotionRecognitionProhibited(ChrEtrsDomainError):
    """403 — Emotion_Recognition_Prohibited (BR-08 / EU AI Act)."""

    error_code = "Emotion_Recognition_Prohibited"
    http_status = 403


class TargetForbidden(ChrEtrsDomainError):
    """403 — caller is not allowed to act on this private-vault resource."""

    error_code = "Japanese_Veil_Violation"
    http_status = 403
