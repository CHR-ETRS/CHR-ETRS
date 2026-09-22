"""Request and response models — field names follow openapi.yaml."""
from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class ErrorResponse(BaseModel):
    error_code: str
    http_status: int
    message: str
    timestamp: datetime
    logic_hash: Optional[str] = None


class HrvStreamFrame(BaseModel):
    sample_id: str
    timestamp: datetime
    hrv_baseline: float
    distal_skin_temp: Optional[float] = None
    vagal_tone_index: Optional[float] = None


class HrvSampleRequest(BaseModel):
    user_id: str
    sample_timestamp: datetime
    hrv_baseline_ms: float
    distal_skin_temp_celsius: Optional[float] = None
    vagal_tone_index: Optional[float] = None
    cold_stim_recovery_seconds: Optional[int] = None


class HrvSampleResponse(BaseModel):
    status: str
    sample_id: str
    biometric_alert_triggered: bool
    threshold_violation: Optional[str] = None


class SentimentMetadata(BaseModel):
    sender_role: Optional[str] = None
    is_after_hours: Optional[bool] = None


class AnalyzeSentimentRequest(BaseModel):
    text_content: str
    source_channel: Literal["Slack", "Teams", "Outlook"]
    user_id: str
    org_id: Optional[str] = None
    timestamp: Optional[datetime] = None
    metadata: Optional[SentimentMetadata] = None


class AnalyzeSentimentResponse(BaseModel):
    confidence_score: float
    detected_patterns: list[Literal["Toxic_Positivity", "Masking"]]
    masking_penalty_score: float
    recommended_action: str
    logic_hash: str


class TriggerCuckooPingRequest(BaseModel):
    target_user_id: str
    manager_id: str
    trigger_reason: Literal[
        "Spoon_Bankruptcy",
        "Contract_Fragility",
        "Accelerated_Depreciation",
        "Toxic_Positivity_AfterHours",
        "HRV_Safety_Cut",
    ]
    veto_window_minutes: int = 60


class TriggerCuckooPingResponse(BaseModel):
    alert_id: str
    status: str
    expires_at: datetime
    employee_private_ping_sent: bool
    manager_notified_anonymously: bool


class SovereignVetoRequest(BaseModel):
    alert_id: str
    encrypted_reason_note: str


class SovereignVetoResponse(BaseModel):
    status: str
    manager_ledger_credited: bool
    logic_hash: str


class AssignTaskRequest(BaseModel):
    assignee_id: str
    task_name: str
    complexity_spoon_cost: int = Field(ge=1)
    is_chunkable: bool = True
    attempt_graded_load_increase: bool = False


class AssignTaskResponse(BaseModel):
    task_id: str
    is_blocked_by_circuit_breaker: bool
    pacing_status: str


class ManagerDashboardResponse(BaseModel):
    team_spoon_avg: float
    deprivation_tax_sum: float
    dichotomous_alert_level: Literal["GREEN", "RED"]
    member_count: int
    japanese_veil_applied: bool


class LedgerRecordRequest(BaseModel):
    manager_id: str
    action_type: str
    cost_impact: float
    event_description: str
    system_justification: Optional[str] = None


class LedgerRecordResponse(BaseModel):
    ledger_id: str
    logic_hash_sha256: str
    worm_storage_status: str


class CircuitBreakerMetrics(BaseModel):
    hrv_ms: Optional[float] = None
    spoons_remaining: Optional[int] = None
    contract_fragility_units: Optional[float] = None


class CircuitBreakerRequest(BaseModel):
    target_user_id: str
    circuit_breaker_type: str
    trigger_metrics: Optional[CircuitBreakerMetrics] = None
    enforcement_actions: list[str] = Field(default_factory=list)


class CircuitBreakerResponse(BaseModel):
    circuit_breaker_status: str
    enforced_at: datetime
    golden_spoons_injected: int
    eudaimonic_immunity_until: datetime
    jira_integration_status: str
    logic_hash: str


class SpoonsBreakdown(BaseModel):
    sinks_expenditure: int = 0
    sources_recovery: int = 0
    golden_spoons_held: int = 0


class SpoonsBudgetResponse(BaseModel):
    user_id: str
    daily_baseline_capacity: int
    current_spoon_count: int
    available_capacity_pct: float
    energy_state_indicator: str
    breakdown: SpoonsBreakdown
    smart_pacing_status: str


class ChrMetrics(BaseModel):
    spoons_remaining: int
    spoons_baseline: int
    capacity_percentage: float
    biometric_debt_hours: Optional[float] = None


class SystemEnforcement(BaseModel):
    dichotomous_alert_level: Literal["GREEN", "RED"]
    circuit_breaker_active: bool
    halt_task_allocation: bool
    overtime_approval_blocked: bool
    manager_visibility: str


class WorkerWellnessSyncRequest(BaseModel):
    worker_id: str
    org_tenant_id: str
    sync_timestamp: datetime
    chr_metrics: ChrMetrics
    system_enforcement: SystemEnforcement


class WorkerWellnessSyncResponse(BaseModel):
    sync_status: str
    erp_reference_id: str
    applied_enforcement: str
    audit_proof_token: str


class PrivacyComplianceBlock(BaseModel):
    zkp_protocol_status: str
    encryption_standard: str
    zen_gate_shield: str


class RegulatoryExposure(BaseModel):
    eu_ai_act_risk_category: str
    emotion_recognition_blocked: bool
    biometric_retention_local: bool
    turnover_penalty_exposure: bool


class PrivacyComplianceResponse(BaseModel):
    audit_request_id: str
    privacy_compliance: PrivacyComplianceBlock
    regulatory_exposure: RegulatoryExposure


# --- Employee Happy Path extensions (not in locked OpenAPI; see README) ---


class AnchorWrite(BaseModel):
    type_lighting: Literal["Authority", "Soft", "Task"] = "Authority"
    territory_schema: Optional[str] = None
    exposure_gate: Literal["Closed", "Filtered", "Open"] = "Filtered"


class AnchorView(AnchorWrite):
    anchor_id: str
    user_id: str
    created_at: datetime


class EmployeeValueAssetView(BaseModel):
    employee_id: str
    direct_cost_opex: float
    asset_value_capex: float
    productivity_alpha_factor: float
    happiness_debt_liability: float


class AnchorsResponse(BaseModel):
    user_id: str
    employee_value_asset: EmployeeValueAssetView
    anchors: list[AnchorView]


class AnchorsUpdateRequest(BaseModel):
    anchors: list[AnchorWrite]


class ResilienceAxes(BaseModel):
    hope: float
    efficacy: float
    resilience: float
    optimism: float


class ResilienceMatrixResponse(BaseModel):
    avatar_id: str
    user_id: str
    role_state: Literal["HOPE", "NESS", "SHAY"]
    bone_memory_latency: int
    contrast_nullification_active: bool
    current_spoon_count: int
    latest_hrv_ms: Optional[float] = None
    resilience_axes: ResilienceAxes


class JournalCreateRequest(BaseModel):
    user_id: str
    hallway_mirror_response: str = Field(min_length=1)
    relational_offloading_text: Optional[str] = None


class JournalEntryView(BaseModel):
    entry_id: str
    user_id: str
    hallway_mirror_response: str
    relational_offloading_text: Optional[str] = None
    created_at: datetime
    sealed: bool = False


class JournalListResponse(BaseModel):
    user_id: str
    private_vault: bool = True
    entries: list[JournalEntryView]
