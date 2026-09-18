from typing import List, Optional
from pydantic import BaseModel, Field


class SurveyRecord(BaseModel):
    employee_name: str
    age: int
    gender: str
    tenure_months: int
    raw_survey_text: str
    biometric_hrv: float


class SynthesizeRequest(BaseModel):
    department_id: str | int
    records: List[SurveyRecord]


class SyntheticPerson(BaseModel):
    synthetic_id: str
    age_bracket: str
    tenure_bracket: str
    blurred_survey_text: str
    adjusted_hrv: float


class SynthesizeResponse(BaseModel):
    department_id: str
    synthesized: List[SyntheticPerson]
    count: int


class SentimentRequest(BaseModel):
    synthetic_id: str
    text: str


class SentimentResponse(BaseModel):
    synthetic_id: str
    polarity: str
    score: float
    topics: List[str]
    masking_factor: float


class FinancialImpact(BaseModel):
    voi_index: float
    estimated_savings_ils: float
    productivity_delta: float


class VOIResponse(BaseModel):
    department_id: str
    time_period: str
    respondent_count: int
    happiness: float
    eNPS: int
    burnout: float
    financial_impact: FinancialImpact


class CircuitBreakerRequest(BaseModel):
    team_id: str
    requested_action: str
    meeting_duration_minutes: int
    participants_count: int
    force_stamina: Optional[float] = None


class CircuitBreakerResponse(BaseModel):
    allowed: bool
    team_stamina: float
    critical_threshold: float
    recommendation: str
    message: str


class BiometricLogRequest(BaseModel):
    archetype: str = "SHAY-09"
    hrv_ms: float
    timestamp: Optional[str] = None


class BiometricLogResponse(BaseModel):
    archetype: str
    hrv_ms: float
    status: str  # healthy | throttle | brake
    spoon_delta: float
    message: str


class EnergyStateResponse(BaseModel):
    archetype: str
    spoon_budget: float
    max_spoons: float
    status: str
    hrv_threshold_throttle: float
    hrv_threshold_brake: float


class FinanceSimulateRequest(BaseModel):
    num_employees: int = Field(default=500, ge=1, le=50000)
    avg_monthly_salary: float = Field(default=25000, gt=0)
    revenue: float = Field(default=300_000_000, ge=0)
    non_payroll_opex: float = Field(default=105_000_000, ge=0)
    turnover_rate: float = Field(default=0.22, ge=0, le=1)
    deprivation_pct: float = Field(default=0.20, ge=0, le=1)
    capex: float = Field(default=350_000, ge=0)
    # baseline rates used for post-CHR recovery model
    baseline_turnover_rate: float = Field(default=0.22, ge=0, le=1)
    baseline_deprivation_pct: float = Field(default=0.20, ge=0, le=1)


class ShadowBreakdown(BaseModel):
    deprivation_tax: float
    emotional_debt: float
    burnout_liability: float
    total: float
    num_deprived: int
    num_departures: int
    num_burned: int


class DilutedWage(BaseModel):
    nominal_hourly: float
    diluted_hourly: float
    erosion_pct: float
    hours_nominal: float = 40 * 4.33
    hours_diluted: float = 55 * 4.33


class FinanceSimulateResponse(BaseModel):
    mode: str  # "baseline" | "simulated"
    num_employees: int
    avg_monthly_salary: float
    revenue: float
    non_payroll_opex: float
    payroll: float
    daily_wage: float
    turnover_rate: float
    deprivation_pct: float
    capex: float

    ebitda_nominal: float
    ebitda_nominal_margin_pct: float

    shadow_pre: ShadowBreakdown
    ebitda_pre_chr: float
    ebitda_pre_chr_margin_pct: float

    post_turnover_rate: float
    post_deprivation_pct: float
    post_burnout_pct: float
    shadow_post: ShadowBreakdown
    ebitda_after_chr: float
    ebitda_after_chr_margin_pct: float

    shadow_savings: float
    roi_pct: float
    rov: float

    diluted_wage: DilutedWage
    assumptions: list[str]


class ChrIndexRequest(BaseModel):
    O: float = Field(default=62, ge=0, le=100)
    S: float = Field(default=58, ge=0, le=100)
    H: float = Field(default=55, ge=0, le=100)
    E: float = Field(default=50, ge=0, le=100)
    wO: float = Field(default=0.25, ge=0)
    wS: float = Field(default=0.25, ge=0)
    wH: float = Field(default=0.2, ge=0)
    wE: float = Field(default=0.3, ge=0)
    masking: float = Field(default=0.15, ge=0, le=1)
    headcount: int = Field(default=500, ge=1, le=50000)
    avg_monthly_salary: float = Field(default=25000, gt=0)
    ebitda_nominal: float = Field(default=45_000_000)
    roh: float = Field(default=2_000_000, ge=0)
    dt_pct: float = Field(default=0.12, ge=0, le=1)
    deprivation_pct: float = Field(default=0.20, ge=0, le=1)
    fairness_gap: float = Field(default=0.25, ge=0, le=1)
    actual_weekly_hours: float = Field(default=48, ge=40, le=80)
    turnover_rate: float = Field(default=0.18, ge=0, le=1)
    turnover_cost_multiple: float = Field(default=1.5, ge=0, le=5)
    fairness_debt_factor: float = Field(default=0.12, ge=0, le=1)
    declared_culture: float = Field(default=70, ge=0, le=100)
    integrity_threshold: float = Field(default=0.6, ge=0, le=1)


class DilutedWageLite(BaseModel):
    nominal_hourly: float
    diluted_hourly: float
    erosion_pct: float


class ChrIndexResponse(BaseModel):
    chr_index: float
    survey_displayed: float
    masking_warning: bool
    weights: dict
    payroll: float
    annual_salary: float
    num_deprived: int
    dt: float
    ebitda_adjusted: float
    fairness_debt: float
    diluted_burden: float
    turnover_premium: float
    happiness_debt_ils: float
    happiness_debt_severity: float
    diluted_wage: DilutedWageLite
    integrity: float
    happiness_washing: bool
    lived_chr: float
    summary_he: str
