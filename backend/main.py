"""CHR-ETRS Sprint 0 — Mock FastAPI backend (in-memory)."""

from typing import Optional

from fastapi import FastAPI, Header, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from models import (
    BiometricLogRequest,
    BiometricLogResponse,
    ChrIndexRequest,
    ChrIndexResponse,
    CircuitBreakerRequest,
    CircuitBreakerResponse,
    DilutedWage,
    DilutedWageLite,
    EnergyStateResponse,
    FinanceSimulateRequest,
    FinanceSimulateResponse,
    FinancialImpact,
    SentimentRequest,
    SentimentResponse,
    ShadowBreakdown,
    SynthesizeRequest,
    SynthesizeResponse,
    SyntheticPerson,
    VOIResponse,
)

app = FastAPI(
    title="CHR-ETRS Mock API",
    description="Sprint 1 mock endpoints for CHR-ETRS prototype",
    version="0.3.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory state
ENERGY_STATE = {
    "SHAY-09": {"spoon_budget": 35.0, "max_spoons": 100.0},
    "NESS-03": {"spoon_budget": 42.0, "max_spoons": 100.0},
}

THRESHOLDS = {
    "SHAY-09": {"throttle": 55.0, "brake": 40.0},
    "NESS-03": {"throttle": 35.0, "brake": 25.0},
}


@app.get("/health")
def health():
    return {"status": "ok", "service": "chr-etrs-mock"}


@app.post("/api/v1/synthesize", response_model=SynthesizeResponse)
def synthesize(
    body: SynthesizeRequest,
    authorization: Optional[str] = Header(default=None),
):
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header required",
        )

    synthesized = []
    for idx, rec in enumerate(body.records):
        blurred = (
            "טקסט סקר מטושטש לפרטיות: "
            + (rec.raw_survey_text[:40] + "…" if len(rec.raw_survey_text) > 40 else rec.raw_survey_text)
        )
        synthesized.append(
            SyntheticPerson(
                synthetic_id=f"syn_user_8917{idx}",
                age_bracket="30-35",
                tenure_bracket="24-36",
                blurred_survey_text=blurred,
                adjusted_hrv=round(rec.biometric_hrv + 0.3, 2),
            )
        )

    return SynthesizeResponse(
        department_id=str(body.department_id),
        synthesized=synthesized,
        count=len(synthesized),
    )


@app.post("/api/v1/communication/sentiment", response_model=SentimentResponse)
def sentiment(body: SentimentRequest):
    return SentimentResponse(
        synthetic_id=body.synthetic_id,
        polarity="negative",
        score=0.88,
        topics=["Micromanagement/Autonomy", "Burnout/Competence"],
        masking_factor=1.20,
    )


@app.get("/api/v1/voi/{department_id}")
def voi(
    department_id: str,
    time_period: str = Query(default="quarterly"),
):
    # Rule of 5: dept 102 → 8 users OK; else → 3 users → 403
    if str(department_id) == "102":
        return VOIResponse(
            department_id=department_id,
            time_period=time_period,
            respondent_count=8,
            happiness=7.42,
            eNPS=52,
            burnout=0.35,
            financial_impact=FinancialImpact(
                voi_index=1.15,
                estimated_savings_ils=42800.0,
                productivity_delta=0.12,
            ),
        )

    return JSONResponse(
        status_code=status.HTTP_403_FORBIDDEN,
        content={
            "detail": "Insufficient respondent volume for Rule of 5 k-anonymity",
            "department_id": department_id,
            "respondent_count": 3,
            "minimum_required": 5,
        },
    )


@app.post("/api/v1/energy/circuit-breaker")
def circuit_breaker(body: CircuitBreakerRequest):
    critical_threshold = 40.0
    team_stamina = (
        body.force_stamina if body.force_stamina is not None else 32.4
    )

    if team_stamina < critical_threshold:
        return JSONResponse(
            status_code=423,
            content={
                "allowed": False,
                "team_stamina": team_stamina,
                "critical_threshold": critical_threshold,
                "recommendation": "Digital Silence",
                "message": (
                    f"מעגל נעול: סיבולת צוות {team_stamina} מתחת לסף {critical_threshold}. "
                    "מומלץ: שתיקה דיגיטלית (Digital Silence)."
                ),
                "requested_action": body.requested_action,
                "team_id": body.team_id,
            },
        )

    return CircuitBreakerResponse(
        allowed=True,
        team_stamina=team_stamina,
        critical_threshold=critical_threshold,
        recommendation="Proceed with caution",
        message=(
            f"אושר: סיבולת צוות {team_stamina} מעל הסף. "
            f"פעולה '{body.requested_action}' מאושרת."
        ),
    )


@app.post("/api/v1/biometrics/log", response_model=BiometricLogResponse)
def biometrics_log(body: BiometricLogRequest):
    arch = body.archetype if body.archetype in THRESHOLDS else "SHAY-09"
    th = THRESHOLDS[arch]
    hrv = body.hrv_ms

    if hrv < th["brake"]:
        status_label = "brake"
        spoon_delta = -8.0
        msg = "נעילה: HRV נמוך מדי — בלימת פעילות"
    elif hrv < th["throttle"]:
        status_label = "throttle"
        spoon_delta = -3.0
        msg = "האטה: HRV מתחת לסף — האטת קצב"
    else:
        status_label = "healthy"
        spoon_delta = 2.0
        msg = "תקין: HRV בטווח בריא"

    state = ENERGY_STATE.setdefault(arch, {"spoon_budget": 35.0, "max_spoons": 100.0})
    state["spoon_budget"] = max(0.0, min(state["max_spoons"], state["spoon_budget"] + spoon_delta))

    return BiometricLogResponse(
        archetype=arch,
        hrv_ms=hrv,
        status=status_label,
        spoon_delta=spoon_delta,
        message=msg,
    )


@app.get("/api/v1/energy/state", response_model=EnergyStateResponse)
def energy_state(archetype: str = Query(default="SHAY-09")):
    arch = archetype if archetype in ENERGY_STATE else "SHAY-09"
    state = ENERGY_STATE[arch]
    th = THRESHOLDS.get(arch, THRESHOLDS["SHAY-09"])
    spoons = state["spoon_budget"]
    if spoons < 20:
        st = "critical"
    elif spoons < 40:
        st = "low"
    else:
        st = "ok"
    return EnergyStateResponse(
        archetype=arch,
        spoon_budget=spoons,
        max_spoons=state["max_spoons"],
        status=st,
        hrv_threshold_throttle=th["throttle"],
        hrv_threshold_brake=th["brake"],
    )


TURNOVER_COST_PER_EMPLOYEE = 105_000  # 20k hire + 85k knowledge
DEFAULT_BASELINE = {
    "num_employees": 500,
    "avg_monthly_salary": 25000.0,
    "revenue": 300_000_000.0,
    "non_payroll_opex": 105_000_000.0,
    "turnover_rate": 0.22,
    "deprivation_pct": 0.20,
    "capex": 350_000.0,
}


def _shadow_costs(
    n: int,
    annual_salary: float,
    daily_wage: float,
    turnover_rate: float,
    deprivation_pct: float,
    burnout_pct: float | None = None,
) -> ShadowBreakdown:
    """Compute shadow P&L costs. Burnout defaults to deprivation cohort (pre-CHR)."""
    num_deprived = int(n * deprivation_pct)
    deprivation_tax = num_deprived * annual_salary * 0.12
    num_departures = int(n * turnover_rate)
    emotional_debt = num_departures * TURNOVER_COST_PER_EMPLOYEE
    if burnout_pct is None:
        num_burned = num_deprived
    else:
        num_burned = int(n * burnout_pct)
    burnout_liability = num_burned * 15 * daily_wage  # 1.25*12 sick days
    total = deprivation_tax + emotional_debt + burnout_liability
    return ShadowBreakdown(
        deprivation_tax=deprivation_tax,
        emotional_debt=emotional_debt,
        burnout_liability=burnout_liability,
        total=total,
        num_deprived=num_deprived,
        num_departures=num_departures,
        num_burned=num_burned,
    )


def run_finance_simulate(body: FinanceSimulateRequest) -> FinanceSimulateResponse:
    n = body.num_employees
    avg = body.avg_monthly_salary
    payroll = n * avg * 12
    annual_salary = avg * 12
    daily_wage = annual_salary / 264
    revenue = body.revenue
    non_payroll = body.non_payroll_opex
    capex = body.capex

    ebitda_nominal = revenue - (payroll + non_payroll)
    margin = lambda e: (e / revenue * 100) if revenue else 0.0

    shadow_pre = _shadow_costs(
        n, annual_salary, daily_wage, body.turnover_rate, body.deprivation_pct
    )
    ebitda_pre = ebitda_nominal - shadow_pre.total

    # Post CHR-OS recovery (user/Cos lock): half of *current* slider rates.
    # CAPEX stays fixed (default 350k) — do not scale with N.
    post_turnover = body.turnover_rate * 0.50
    post_deprivation_pct = body.deprivation_pct * 0.50
    post_burnout_pct = body.deprivation_pct * 0.20  # residual burnout vs current deprivation slider
    shadow_post = _shadow_costs(
        n,
        annual_salary,
        daily_wage,
        post_turnover,
        post_deprivation_pct,
        burnout_pct=post_burnout_pct,
    )
    ebitda_after = ebitda_nominal - shadow_post.total - capex

    savings = shadow_pre.total - shadow_post.total
    roi_pct = ((savings - capex) / capex * 100) if capex else 0.0
    rov = (savings / capex) if capex else 0.0

    nominal_hr = avg / (40 * 4.33)
    diluted_hr = avg / (55 * 4.33)
    erosion = ((nominal_hr - diluted_hr) / nominal_hr * 100) if nominal_hr else 0.0

    is_baseline = (
        n == DEFAULT_BASELINE["num_employees"]
        and abs(avg - DEFAULT_BASELINE["avg_monthly_salary"]) < 1e-6
        and abs(revenue - DEFAULT_BASELINE["revenue"]) < 1e-6
        and abs(non_payroll - DEFAULT_BASELINE["non_payroll_opex"]) < 1e-6
        and abs(body.turnover_rate - DEFAULT_BASELINE["turnover_rate"]) < 1e-9
        and abs(body.deprivation_pct - DEFAULT_BASELINE["deprivation_pct"]) < 1e-9
        and abs(capex - DEFAULT_BASELINE["capex"]) < 1e-6
    )

    assumptions = [
        "מודל מאזן צללים לפי chr_financial_simulator (מחברת 04).",
        f"עלות תחלופה לעובד: {TURNOVER_COST_PER_EMPLOYEE:,} ₪ (20k גיוס + 85k ידע).",
        "מס קיפוח: 12% מהשכר השנתי לכל עובד «מקופח» (deprivation_pct).",
        "חוב שחיקה: 15 ימי מחלה (1.25×12) × שכר יומי (שנה/264) לקוהורטת שחיקה.",
        "אחרי CHR-OS: תחלופה וקיפוח → 50% מערכי הסליידרים הנוכחיים; שחיקה שיורית → 20% מ־deprivation בסליידר. CAPEX קבוע 350k (לא נמדל עם N).",
        "CAPEX CHR-OS: 350,000 ₪ (ברירת מחדל).",
        "ROI = (חיסכון בצללים − CAPEX) / CAPEX; ROV = חיסכון / CAPEX.",
        "שכר שעתי מדולל: נומינלי 40×4.33 שעות/חודש מול 55×4.33 (שחיקה ~27%).",
    ]

    return FinanceSimulateResponse(
        mode="baseline" if is_baseline else "simulated",
        num_employees=n,
        avg_monthly_salary=avg,
        revenue=revenue,
        non_payroll_opex=non_payroll,
        payroll=payroll,
        daily_wage=daily_wage,
        turnover_rate=body.turnover_rate,
        deprivation_pct=body.deprivation_pct,
        capex=capex,
        ebitda_nominal=ebitda_nominal,
        ebitda_nominal_margin_pct=margin(ebitda_nominal),
        shadow_pre=shadow_pre,
        ebitda_pre_chr=ebitda_pre,
        ebitda_pre_chr_margin_pct=margin(ebitda_pre),
        post_turnover_rate=post_turnover,
        post_deprivation_pct=post_deprivation_pct,
        post_burnout_pct=post_burnout_pct,
        shadow_post=shadow_post,
        ebitda_after_chr=ebitda_after,
        ebitda_after_chr_margin_pct=margin(ebitda_after),
        shadow_savings=savings,
        roi_pct=roi_pct,
        rov=rov,
        diluted_wage=DilutedWage(
            nominal_hourly=nominal_hr,
            diluted_hourly=diluted_hr,
            erosion_pct=erosion,
        ),
        assumptions=assumptions,
    )


@app.post("/api/v1/finance/simulate", response_model=FinanceSimulateResponse)
def finance_simulate_post(body: FinanceSimulateRequest):
    return run_finance_simulate(body)


@app.get("/api/v1/finance/simulate", response_model=FinanceSimulateResponse)
def finance_simulate_get(
    num_employees: int = Query(default=500, ge=1, le=50000),
    avg_monthly_salary: float = Query(default=25000, gt=0),
    revenue: float = Query(default=300_000_000, ge=0),
    non_payroll_opex: float = Query(default=105_000_000, ge=0),
    turnover_rate: float = Query(default=0.22, ge=0, le=1),
    deprivation_pct: float = Query(default=0.20, ge=0, le=1),
    capex: float = Query(default=350_000, ge=0),
    baseline_turnover_rate: float = Query(default=0.22, ge=0, le=1),
    baseline_deprivation_pct: float = Query(default=0.20, ge=0, le=1),
):
    return run_finance_simulate(
        FinanceSimulateRequest(
            num_employees=num_employees,
            avg_monthly_salary=avg_monthly_salary,
            revenue=revenue,
            non_payroll_opex=non_payroll_opex,
            turnover_rate=turnover_rate,
            deprivation_pct=deprivation_pct,
            capex=capex,
            baseline_turnover_rate=baseline_turnover_rate,
            baseline_deprivation_pct=baseline_deprivation_pct,
        )
    )

def run_chr_index(body: ChrIndexRequest) -> ChrIndexResponse:
    """Client-parity CHR Index / Happiness Debt calculator (organizational model)."""
    w_sum = body.wO + body.wS + body.wH + body.wE
    if w_sum <= 0:
        wO = wS = wH = wE = 0.25
    else:
        wO, wS, wH, wE = body.wO / w_sum, body.wS / w_sum, body.wH / w_sum, body.wE / w_sum

    chr_index = wO * body.O + wS * body.S + wH * body.H + wE * body.E
    survey = chr_index + body.masking * (100 - chr_index)
    masking_warning = body.masking >= 0.3

    annual = body.avg_monthly_salary * 12
    payroll = body.headcount * annual
    num_deprived = int(body.headcount * body.deprivation_pct)
    dt = num_deprived * annual * body.dt_pct
    ebitda_adj = body.ebitda_nominal + body.roh - dt

    fairness_debt = payroll * body.fairness_gap * body.fairness_debt_factor

    nominal_hr = body.avg_monthly_salary / (40 * 4.33)
    diluted_hr = body.avg_monthly_salary / (body.actual_weekly_hours * 4.33)
    erosion = ((nominal_hr - diluted_hr) / nominal_hr * 100) if nominal_hr else 0.0
    diluted_burden = payroll * (erosion / 100)

    turnover_premium = body.headcount * body.turnover_rate * (annual * body.turnover_cost_multiple)
    debt_ils = fairness_debt + diluted_burden + turnover_premium
    severity = min(100.0, (debt_ils / payroll * 100) if payroll else 0.0)

    lived = chr_index / 100.0
    declared = body.declared_culture / 100.0
    integrity = 1.0 - abs(declared - lived)
    washing = integrity < body.integrity_threshold

    parts = []
    if chr_index >= 70:
        parts.append(f"מדד CHR משוקלל ≈ {chr_index:.0f} — פרופיל ארגוני חזק יחסית.")
    elif chr_index >= 45:
        parts.append(f"מדד CHR משוקלל ≈ {chr_index:.0f} — מצב ביניים; יש פערים ממדיים לשיפור.")
    else:
        parts.append(f"מדד CHR משוקלל ≈ {chr_index:.0f} — איתות לחץ ארגוני משמעותי (מודל דיון, לא אבחנה).")
    if masking_warning:
        parts.append(
            f"אזהרת Glass Box: גורם מיסוך גבוה — «אושר סקר» (~{survey:.0f}) מתרחק מ־CHR החי (~{chr_index:.0f})."
        )
    parts.append(
        f"חוב אושר ≈ {debt_ils:,.0f} ₪ · חומרה {severity:.0f}/100."
    )
    parts.append(
        f"EBITDA מותאם ≈ {ebitda_adj:,.0f} ₪ (נומינלי {body.ebitda_nominal:,.0f} + RoH {body.roh:,.0f} − DT {dt:,.0f})."
    )
    if washing:
        parts.append(f"⚠ Happiness-washing: Integrity {integrity*100:.0f}% מתחת לסף.")
    else:
        parts.append(f"Integrity ≈ {integrity*100:.0f}%.")

    return ChrIndexResponse(
        chr_index=round(chr_index, 2),
        survey_displayed=round(survey, 2),
        masking_warning=masking_warning,
        weights={"wO": round(wO, 4), "wS": round(wS, 4), "wH": round(wH, 4), "wE": round(wE, 4), "sum": 1.0},
        payroll=payroll,
        annual_salary=annual,
        num_deprived=num_deprived,
        dt=dt,
        ebitda_adjusted=ebitda_adj,
        fairness_debt=fairness_debt,
        diluted_burden=diluted_burden,
        turnover_premium=turnover_premium,
        happiness_debt_ils=debt_ils,
        happiness_debt_severity=round(severity, 2),
        diluted_wage=DilutedWageLite(
            nominal_hourly=round(nominal_hr, 2),
            diluted_hourly=round(diluted_hr, 2),
            erosion_pct=round(erosion, 2),
        ),
        integrity=round(integrity, 4),
        happiness_washing=washing,
        lived_chr=round(lived, 4),
        summary_he=" ".join(parts),
    )


@app.post("/api/v1/chr/index", response_model=ChrIndexResponse)
def chr_index_post(body: ChrIndexRequest):
    return run_chr_index(body)


@app.get("/api/v1/chr/index", response_model=ChrIndexResponse)
def chr_index_get():
    """Defaults matching frontend DEFAULT_INPUTS / Healthy-adjacent baseline."""
    return run_chr_index(ChrIndexRequest())

