const BASE = import.meta.env.VITE_API_URL ?? ''

async function request<T>(path: string, init?: RequestInit): Promise<{ ok: boolean; status: number; data: T }> {
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  })
  let data: T
  try {
    data = await res.json()
  } catch {
    data = {} as T
  }
  return { ok: res.ok, status: res.status, data }
}

export async function synthesize(records: unknown[], token = 'Bearer demo-token') {
  return request('/api/v1/synthesize', {
    method: 'POST',
    headers: { Authorization: token },
    body: JSON.stringify({ department_id: '102', records }),
  })
}

export async function sentiment(synthetic_id: string, text: string) {
  return request('/api/v1/communication/sentiment', {
    method: 'POST',
    body: JSON.stringify({ synthetic_id, text }),
  })
}

export async function voi(department_id: string, time_period = 'quarterly') {
  return request(`/api/v1/voi/${department_id}?time_period=${time_period}`)
}

export async function circuitBreaker(payload: {
  team_id: string
  requested_action: string
  meeting_duration_minutes: number
  participants_count: number
  force_stamina?: number
}) {
  return request('/api/v1/energy/circuit-breaker', {
    method: 'POST',
    body: JSON.stringify(payload),
  })
}

export async function energyState(archetype = 'SHAY-09') {
  return request(`/api/v1/energy/state?archetype=${archetype}`)
}

export async function biometricsLog(hrv_ms: number, archetype = 'SHAY-09') {
  return request('/api/v1/biometrics/log', {
    method: 'POST',
    body: JSON.stringify({ archetype, hrv_ms }),
  })
}

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
  shadow_pre: {
    deprivation_tax: number
    emotional_debt: number
    burnout_liability: number
    total: number
    num_deprived: number
    num_departures: number
    num_burned: number
  }
  ebitda_pre_chr: number
  ebitda_pre_chr_margin_pct: number
  post_turnover_rate: number
  post_deprivation_pct: number
  post_burnout_pct: number
  shadow_post: {
    deprivation_tax: number
    emotional_debt: number
    burnout_liability: number
    total: number
    num_deprived: number
    num_departures: number
    num_burned: number
  }
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

export async function financeSimulate(params: FinanceSimulateParams = {}) {
  return request<FinanceSimulateResult>('/api/v1/finance/simulate', {
    method: 'POST',
    body: JSON.stringify(params),
  })
}

/** Optional server mirror of the client-side CHR Index calculator. */
export async function chrIndexCalculate(body: Record<string, unknown> = {}) {
  return request('/api/v1/chr/index', {
    method: 'POST',
    body: JSON.stringify(body),
  })
}
