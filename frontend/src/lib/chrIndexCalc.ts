/**
 * CHR Index + Happiness Debt calculator (client-side).
 * Organizational wellbeing / finance model for discussion — not clinical advice.
 * Aligned with finance_formulas.md shadow-accounting ideas where sensible.
 */

export type ChrIndexInputs = {
  /** Objective / material baseline 0–100 */
  O: number
  /** Social / belonging 0–100 */
  S: number
  /** Hedonic short-term wellbeing 0–100 */
  H: number
  /** Eudaimonic flourishing 0–100 */
  E: number
  wO: number
  wS: number
  wH: number
  wE: number
  /** 0–1; high = survey happiness diverges upward from lived CHR */
  masking: number

  headcount: number
  avgMonthlySalary: number
  ebitdaNominal: number
  /** Return on Happiness — economic upside (₪) */
  roh: number
  /** Deprivation Tax productivity haircut (default ~0.12) */
  dtPct: number
  /** Share of workforce in deprivation / burn cohort */
  deprivationPct: number

  /** Perceived effort–reward gap 0–1 */
  fairnessGap: number
  /** Actual weekly hours (nominal baseline 40) */
  actualWeeklyHours: number
  turnoverRate: number
  /** Replacement cost as multiple of annual salary (default 1.5 = 150%) */
  turnoverCostMultiple: number
  /** Fairness debt as fraction of payroll × gap (editable) */
  fairnessDebtFactor: number

  /** Declared culture score 0–100 */
  declaredCulture: number
  /** Flag happiness-washing below this (default 0.6) */
  integrityThreshold: number
}

export type ChrIndexResult = {
  weights: { wO: number; wS: number; wH: number; wE: number; sum: number }
  chrIndex: number
  surveyDisplayed: number
  maskingWarning: boolean
  payroll: number
  annualSalary: number
  numDeprived: number
  dt: number
  ebitdaAdjusted: number
  fairnessDebt: number
  dilutedBurden: number
  turnoverPremium: number
  happinessDebtIls: number
  happinessDebtSeverity: number
  dilutedWage: {
    nominalHourly: number
    dilutedHourly: number
    erosionPct: number
  }
  integrity: number
  happinessWashing: boolean
  livedChr: number
  summaryHe: string
}

export type PresetId = 'healthy' | 'golden' | 'crisis'

const NOMINAL_WEEKLY = 40
const WEEKS_PER_MONTH = 4.33

export function normalizeWeights(
  wO: number,
  wS: number,
  wH: number,
  wE: number,
): { wO: number; wS: number; wH: number; wE: number; sum: number } {
  const sum = wO + wS + wH + wE
  if (sum <= 0) {
    return { wO: 0.25, wS: 0.25, wH: 0.25, wE: 0.25, sum: 1 }
  }
  return { wO: wO / sum, wS: wS / sum, wH: wH / sum, wE: wE / sum, sum }
}

export function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n))
}

export function computeChrIndex(raw: ChrIndexInputs): ChrIndexResult {
  const weights = normalizeWeights(raw.wO, raw.wS, raw.wH, raw.wE)
  const O = clamp(raw.O, 0, 100)
  const S = clamp(raw.S, 0, 100)
  const H = clamp(raw.H, 0, 100)
  const E = clamp(raw.E, 0, 100)
  const masking = clamp(raw.masking, 0, 1)

  const chrIndex =
    weights.wO * O + weights.wS * S + weights.wH * H + weights.wE * E
  // High masking → displayed "survey happiness" washed toward 100
  const surveyDisplayed = chrIndex + masking * (100 - chrIndex)
  const maskingWarning = masking >= 0.3

  const headcount = Math.max(1, Math.round(raw.headcount))
  const avgMonthly = Math.max(0, raw.avgMonthlySalary)
  const annualSalary = avgMonthly * 12
  const payroll = headcount * annualSalary

  const deprivationPct = clamp(raw.deprivationPct, 0, 1)
  const dtPct = clamp(raw.dtPct, 0, 1)
  const numDeprived = Math.round(headcount * deprivationPct)
  // DT aligned with finance_formulas: num_deprived × annual × haircut
  const dt = numDeprived * annualSalary * dtPct
  const roh = raw.roh
  const ebitdaAdjusted = raw.ebitdaNominal + roh - dt

  const fairnessGap = clamp(raw.fairnessGap, 0, 1)
  const fairnessDebtFactor = clamp(raw.fairnessDebtFactor, 0, 1)
  const fairnessDebt = payroll * fairnessGap * fairnessDebtFactor

  const hours = Math.max(NOMINAL_WEEKLY, raw.actualWeeklyHours)
  const nominalHourly = avgMonthly / (NOMINAL_WEEKLY * WEEKS_PER_MONTH)
  const dilutedHourly = avgMonthly / (hours * WEEKS_PER_MONTH)
  const erosionPct =
    nominalHourly > 0 ? ((nominalHourly - dilutedHourly) / nominalHourly) * 100 : 0
  // Unpaid availability burden ≈ payroll × wage erosion
  const dilutedBurden = payroll * (erosionPct / 100)

  const turnoverRate = clamp(raw.turnoverRate, 0, 1)
  const turnoverCostMultiple = Math.max(0, raw.turnoverCostMultiple)
  const turnoverCostPer = annualSalary * turnoverCostMultiple
  const turnoverPremium = headcount * turnoverRate * turnoverCostPer

  const happinessDebtIls = fairnessDebt + dilutedBurden + turnoverPremium
  // Severity: debt as % of annual payroll, capped 0–100
  const happinessDebtSeverity = clamp(
    payroll > 0 ? (happinessDebtIls / payroll) * 100 : 0,
    0,
    100,
  )

  const livedChr = chrIndex / 100
  const declared = clamp(raw.declaredCulture, 0, 100) / 100
  const integrity = 1 - Math.abs(declared - livedChr)
  const happinessWashing = integrity < raw.integrityThreshold

  const summaryHe = buildSummaryHe({
    chrIndex,
    surveyDisplayed,
    maskingWarning,
    happinessDebtIls,
    happinessDebtSeverity,
    ebitdaAdjusted,
    ebitdaNominal: raw.ebitdaNominal,
    integrity,
    happinessWashing,
    dt,
    roh,
  })

  return {
    weights,
    chrIndex,
    surveyDisplayed,
    maskingWarning,
    payroll,
    annualSalary,
    numDeprived,
    dt,
    ebitdaAdjusted,
    fairnessDebt,
    dilutedBurden,
    turnoverPremium,
    happinessDebtIls,
    happinessDebtSeverity,
    dilutedWage: {
      nominalHourly,
      dilutedHourly,
      erosionPct,
    },
    integrity,
    happinessWashing,
    livedChr,
    summaryHe,
  }
}

function buildSummaryHe(p: {
  chrIndex: number
  surveyDisplayed: number
  maskingWarning: boolean
  happinessDebtIls: number
  happinessDebtSeverity: number
  ebitdaAdjusted: number
  ebitdaNominal: number
  integrity: number
  happinessWashing: boolean
  dt: number
  roh: number
}): string {
  const chr = p.chrIndex.toFixed(0)
  const debtSev = p.happinessDebtSeverity.toFixed(0)
  const integ = (p.integrity * 100).toFixed(0)
  const parts: string[] = []

  if (p.chrIndex >= 70) {
    parts.push(`מדד CHR משוקלל ≈ ${chr} — פרופיל ארגוני חזק יחסית.`)
  } else if (p.chrIndex >= 45) {
    parts.push(`מדד CHR משוקלל ≈ ${chr} — מצב ביניים; יש פערים ממדיים לשיפור.`)
  } else {
    parts.push(`מדד CHR משוקלל ≈ ${chr} — איתות לחץ ארגוני משמעותי (מודל דיון, לא אבחנה).`)
  }

  if (p.maskingWarning) {
    parts.push(
      `אזהרת Glass Box: גורם מיסוך גבוה — «אושר סקר» (~${p.surveyDisplayed.toFixed(0)}) מתרחק מ־CHR החי (~${chr}).`,
    )
  }

  parts.push(
    `חוב אושר ≈ ${Math.round(p.happinessDebtIls).toLocaleString('he-IL')} ₪ · חומרה ${debtSev}/100 (הוגנות + שכר מדולל + פרמיית תחלופה).`,
  )

  const delta = p.ebitdaAdjusted - p.ebitdaNominal
  parts.push(
    `EBITDA מותאם = נומינלי + RoH (−${Math.round(p.dt).toLocaleString('he-IL')} DT + ${Math.round(p.roh).toLocaleString('he-IL')} RoH) → ${Math.round(p.ebitdaAdjusted).toLocaleString('he-IL')} ₪ (Δ ${delta >= 0 ? '+' : ''}${Math.round(delta).toLocaleString('he-IL')}).`,
  )

  if (p.happinessWashing) {
    parts.push(
      `⚠ Happiness-washing: Integrity ${integ}% מתחת לסף — פער בין תרבות מוצהרת ל־CHR חי.`,
    )
  } else {
    parts.push(`Integrity ≈ ${integ}% — יישור סביר בין תרבות מוצהרת לחוויה חיה.`)
  }

  return parts.join(' ')
}

/** Default editable baseline (near Cos / finance_formulas scale). */
export const DEFAULT_INPUTS: ChrIndexInputs = {
  O: 62,
  S: 58,
  H: 55,
  E: 50,
  wO: 0.25,
  wS: 0.25,
  wH: 0.2,
  wE: 0.3,
  masking: 0.15,
  headcount: 500,
  avgMonthlySalary: 25000,
  ebitdaNominal: 45_000_000,
  roh: 2_000_000,
  dtPct: 0.12,
  deprivationPct: 0.2,
  fairnessGap: 0.25,
  actualWeeklyHours: 48,
  turnoverRate: 0.18,
  turnoverCostMultiple: 1.5,
  fairnessDebtFactor: 0.12,
  declaredCulture: 70,
  integrityThreshold: 0.6,
}

export const PRESETS: Record<
  PresetId,
  { labelHe: string; labelEn: string; inputs: ChrIndexInputs }
> = {
  healthy: {
    labelHe: 'Glass Box בריא',
    labelEn: 'Healthy Glass Box',
    inputs: {
      O: 78,
      S: 82,
      H: 74,
      E: 80,
      wO: 0.25,
      wS: 0.25,
      wH: 0.2,
      wE: 0.3,
      masking: 0.05,
      headcount: 500,
      avgMonthlySalary: 25000,
      ebitdaNominal: 45_000_000,
      roh: 5_500_000,
      dtPct: 0.12,
      deprivationPct: 0.06,
      fairnessGap: 0.08,
      actualWeeklyHours: 42,
      turnoverRate: 0.1,
      turnoverCostMultiple: 1.2,
      fairnessDebtFactor: 0.1,
      declaredCulture: 80,
      integrityThreshold: 0.6,
    },
  },
  golden: {
    labelHe: 'כלוב זהב',
    labelEn: 'Golden Cage',
    inputs: {
      O: 88,
      S: 42,
      H: 78,
      E: 35,
      wO: 0.25,
      wS: 0.25,
      wH: 0.2,
      wE: 0.3,
      masking: 0.55,
      headcount: 500,
      avgMonthlySalary: 28000,
      ebitdaNominal: 52_000_000,
      roh: 800_000,
      dtPct: 0.12,
      deprivationPct: 0.22,
      fairnessGap: 0.35,
      actualWeeklyHours: 52,
      turnoverRate: 0.16,
      turnoverCostMultiple: 1.5,
      fairnessDebtFactor: 0.12,
      declaredCulture: 90,
      integrityThreshold: 0.6,
    },
  },
  crisis: {
    labelHe: 'משבר / Burn',
    labelEn: 'Crisis Burn',
    inputs: {
      O: 38,
      S: 28,
      H: 32,
      E: 22,
      wO: 0.25,
      wS: 0.25,
      wH: 0.2,
      wE: 0.3,
      masking: 0.4,
      headcount: 500,
      avgMonthlySalary: 25000,
      ebitdaNominal: 45_000_000,
      roh: 0,
      dtPct: 0.12,
      deprivationPct: 0.4,
      fairnessGap: 0.65,
      actualWeeklyHours: 58,
      turnoverRate: 0.32,
      turnoverCostMultiple: 1.5,
      fairnessDebtFactor: 0.15,
      declaredCulture: 75,
      integrityThreshold: 0.6,
    },
  },
}

export const ASSUMPTIONS_HE: string[] = [
  'זהו מודל לדיון ארגוני־פיננסי (CHR / מאזן צללים) — לא אבחנה קלינית או רפואית.',
  'מדד CHR = ממוצע משוקלל של O/S/H/E (0–100); משקלים מנורמלים לסכום 1.',
  'גורם מיסוך (masking): «אושר סקר» = CHR + masking×(100−CHR). מעל ~0.3 מוצגת אזהרת Glass Box.',
  'מס קיפוח (DT) ≈ מספר מקופחים × שכר שנתי × שיעור haircut (ברירת מחדל 12%, כמו finance_formulas).',
  'EBITDA_Adjusted = EBITDA_Nominal + RoH − DT.',
  'חוב אושר (₪) = חוב הוגנות + נטל שכר מדולל + פרמיית תחלופה.',
  'שכר מדולל: נומינלי 40×4.33 שעות/חודש מול שעות בפועל; שחיקה = פער שעתי.',
  'עלות תחלופה לעובד = multiple × שכר שנתי (ברירת מחדל עד ~150% לתפקידים קריטיים — ניתן לעריכה).',
  'Integrity = 1 − |תרבות מוצהרת − CHR חי| (מנורמל 0–1); מתחת לסף (~0.6) → דגל happiness-washing.',
  'חומרת חוב אושר = (חוב / שכר שנתי כולל) × 100, מוגבל ל־0–100.',
]
