/** Client-side shadow P&L. The retired /api/v1/finance/simulate route is not in the locked OpenAPI. */

export type FinanceSimulateParams = {
  num_employees?: number
  avg_monthly_salary?: number
  revenue?: number
  non_payroll_opex?: number
  turnover_rate?: number
  deprivation_pct?: number
  capex?: number
  baseline_turnover_rate?: number
  baseline_deprivation_pct?: number
}

export type ShadowBreakdown = {
  deprivation_tax: number
  emotional_debt: number
  burnout_liability: number
  total: number
  num_deprived: number
  num_departures: number
  num_burned: number
}

export type FinanceSimulateResult = {
  mode: string
  num_employees: number
  avg_monthly_salary: number
  revenue: number
  non_payroll_opex: number
  payroll: number
  daily_wage: number
  turnover_rate: number
  deprivation_pct: number
  capex: number
  ebitda_nominal: number
  ebitda_nominal_margin_pct: number
  shadow_pre: ShadowBreakdown
  ebitda_pre_chr: number
  ebitda_pre_chr_margin_pct: number
  post_turnover_rate: number
  post_deprivation_pct: number
  post_burnout_pct: number
  shadow_post: ShadowBreakdown
  ebitda_after_chr: number
  ebitda_after_chr_margin_pct: number
  shadow_savings: number
  roi_pct: number
  rov: number
  diluted_wage: {
    nominal_hourly: number
    diluted_hourly: number
    erosion_pct: number
    hours_nominal: number
    hours_diluted: number
  }
  assumptions: string[]
}

const TURNOVER_COST_PER_EMPLOYEE = 105_000
const DEFAULT_BASELINE = {
  num_employees: 500,
  avg_monthly_salary: 25000,
  revenue: 300_000_000,
  non_payroll_opex: 105_000_000,
  turnover_rate: 0.22,
  deprivation_pct: 0.2,
  capex: 350_000,
}

function shadowCosts(
  n: number,
  annualSalary: number,
  dailyWage: number,
  turnoverRate: number,
  deprivationPct: number,
  burnoutPct?: number,
): ShadowBreakdown {
  const numDeprived = Math.trunc(n * deprivationPct)
  const deprivationTax = numDeprived * annualSalary * 0.12
  const numDepartures = Math.trunc(n * turnoverRate)
  const emotionalDebt = numDepartures * TURNOVER_COST_PER_EMPLOYEE
  const numBurned = burnoutPct === undefined ? numDeprived : Math.trunc(n * burnoutPct)
  const burnoutLiability = numBurned * 15 * dailyWage
  const total = deprivationTax + emotionalDebt + burnoutLiability
  return {
    deprivation_tax: deprivationTax,
    emotional_debt: emotionalDebt,
    burnout_liability: burnoutLiability,
    total,
    num_deprived: numDeprived,
    num_departures: numDepartures,
    num_burned: numBurned,
  }
}

export function financeSimulate(body: FinanceSimulateParams = {}): FinanceSimulateResult {
  const n = body.num_employees ?? 500
  const avg = body.avg_monthly_salary ?? 25000
  const payroll = n * avg * 12
  const annualSalary = avg * 12
  const dailyWage = annualSalary / 264
  const revenue = body.revenue ?? 300_000_000
  const nonPayroll = body.non_payroll_opex ?? 105_000_000
  const capex = body.capex ?? 350_000
  const turnover = body.turnover_rate ?? 0.22
  const deprivation = body.deprivation_pct ?? 0.2
  const margin = (e: number) => (revenue ? (e / revenue) * 100 : 0)

  const ebitdaNominal = revenue - (payroll + nonPayroll)
  const shadowPre = shadowCosts(n, annualSalary, dailyWage, turnover, deprivation)
  const ebitdaPre = ebitdaNominal - shadowPre.total

  const postTurnover = turnover * 0.5
  const postDeprivation = deprivation * 0.5
  const postBurnout = deprivation * 0.2
  const shadowPost = shadowCosts(n, annualSalary, dailyWage, postTurnover, postDeprivation, postBurnout)
  const ebitdaAfter = ebitdaNominal - shadowPost.total - capex
  const savings = shadowPre.total - shadowPost.total
  const roiPct = capex ? ((savings - capex) / capex) * 100 : 0
  const rov = capex ? savings / capex : 0

  const nominalHr = avg / (40 * 4.33)
  const dilutedHr = avg / (55 * 4.33)
  const erosion = nominalHr ? ((nominalHr - dilutedHr) / nominalHr) * 100 : 0

  const isBaseline =
    n === DEFAULT_BASELINE.num_employees &&
    Math.abs(avg - DEFAULT_BASELINE.avg_monthly_salary) < 1e-6 &&
    Math.abs(revenue - DEFAULT_BASELINE.revenue) < 1e-6 &&
    Math.abs(nonPayroll - DEFAULT_BASELINE.non_payroll_opex) < 1e-6 &&
    Math.abs(turnover - DEFAULT_BASELINE.turnover_rate) < 1e-9 &&
    Math.abs(deprivation - DEFAULT_BASELINE.deprivation_pct) < 1e-9 &&
    Math.abs(capex - DEFAULT_BASELINE.capex) < 1e-6

  return {
    mode: isBaseline ? 'baseline' : 'simulated',
    num_employees: n,
    avg_monthly_salary: avg,
    revenue,
    non_payroll_opex: nonPayroll,
    payroll,
    daily_wage: dailyWage,
    turnover_rate: turnover,
    deprivation_pct: deprivation,
    capex,
    ebitda_nominal: ebitdaNominal,
    ebitda_nominal_margin_pct: margin(ebitdaNominal),
    shadow_pre: shadowPre,
    ebitda_pre_chr: ebitdaPre,
    ebitda_pre_chr_margin_pct: margin(ebitdaPre),
    post_turnover_rate: postTurnover,
    post_deprivation_pct: postDeprivation,
    post_burnout_pct: postBurnout,
    shadow_post: shadowPost,
    ebitda_after_chr: ebitdaAfter,
    ebitda_after_chr_margin_pct: margin(ebitdaAfter),
    shadow_savings: savings,
    roi_pct: roiPct,
    rov,
    diluted_wage: {
      nominal_hourly: nominalHr,
      diluted_hourly: dilutedHr,
      erosion_pct: erosion,
      hours_nominal: 40 * 4.33,
      hours_diluted: 55 * 4.33,
    },
    assumptions: [
      'מודל מאזן צללים רץ בצד הלקוח. נתיב /api/v1/finance/simulate הוסר — אינו במפרט OpenAPI הנעול.',
      `עלות תחלופה לעובד: ${TURNOVER_COST_PER_EMPLOYEE.toLocaleString('he-IL')} ₪ (20k גיוס + 85k ידע).`,
      'מס קיפוח: 12% מהשכר השנתי לכל עובד «מקופח» (BR-04).',
      'אחרי CHR-OS: תחלופה וקיפוח → 50% מהסליידרים; שחיקה שיורית → 20% מ־deprivation. CAPEX קבוע 350k.',
    ],
  }
}
