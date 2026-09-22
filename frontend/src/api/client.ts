const BASE = import.meta.env.VITE_API_URL ?? ''

export type ApiResult<T> = { ok: boolean; status: number; data: T }

export type ApiErrorBody = {
  error_code?: string
  http_status?: number
  message?: string
  timestamp?: string
  logic_hash?: string
}

async function request<T>(path: string, init?: RequestInit): Promise<ApiResult<T>> {
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer demo-token',
      ...(init?.headers ?? {}),
    },
  })
  let data: T
  try {
    data = (await res.json()) as T
  } catch {
    data = {} as T
  }
  return { ok: res.ok, status: res.status, data }
}

export type SpoonsBudget = {
  user_id: string
  daily_baseline_capacity: number
  current_spoon_count: number
  available_capacity_pct: number
  energy_state_indicator: string
  breakdown: {
    sinks_expenditure: number
    sources_recovery: number
    golden_spoons_held: number
  }
  smart_pacing_status: string
}

export type HrvStreamFrame = {
  sample_id: string
  timestamp: string
  hrv_baseline: number
  distal_skin_temp?: number
  vagal_tone_index?: number
}

export type HrvSampleResult = {
  status: string
  sample_id: string
  biometric_alert_triggered: boolean
  threshold_violation: string | null
}

export function getSpoonsBudget(userId: string) {
  return request<SpoonsBudget>(`/api/v1/telemetry/spoons-budget/${encodeURIComponent(userId)}`)
}

export function getHrvStream(deviceId: string, samplingRateHz = 1) {
  const q = new URLSearchParams({
    device_id: deviceId,
    sampling_rate_hz: String(samplingRateHz),
  })
  return request<HrvStreamFrame>(`/api/v1/telemetry/hrv-stream?${q}`)
}

export function postHrvSample(body: {
  user_id: string
  sample_timestamp: string
  hrv_baseline_ms: number
  distal_skin_temp_celsius?: number
  vagal_tone_index?: number
}) {
  return request<HrvSampleResult>('/api/v1/telemetry/hrv-sample', {
    method: 'POST',
    body: JSON.stringify(body),
  })
}

export type Anchor = {
  anchor_id?: string
  user_id?: string
  type_lighting: 'Authority' | 'Soft' | 'Task'
  territory_schema?: string | null
  exposure_gate: 'Closed' | 'Filtered' | 'Open'
  created_at?: string
}

export type AnchorsPayload = {
  user_id: string
  employee_value_asset: {
    employee_id: string
    direct_cost_opex: number
    asset_value_capex: number
    productivity_alpha_factor: number
    happiness_debt_liability: number
  }
  anchors: Anchor[]
}

export function getAnchors(userId: string) {
  return request<AnchorsPayload>(`/api/v1/anchors/${encodeURIComponent(userId)}`)
}

export function putAnchors(userId: string, anchors: Anchor[]) {
  return request<AnchorsPayload>(`/api/v1/anchors/${encodeURIComponent(userId)}`, {
    method: 'PUT',
    body: JSON.stringify({
      anchors: anchors.map((a) => ({
        type_lighting: a.type_lighting,
        territory_schema: a.territory_schema ?? '',
        exposure_gate: a.exposure_gate,
      })),
    }),
  })
}

export type ResilienceMatrix = {
  avatar_id: string
  user_id: string
  role_state: 'HOPE' | 'NESS' | 'SHAY'
  bone_memory_latency: number
  contrast_nullification_active: boolean
  current_spoon_count: number
  latest_hrv_ms: number | null
  resilience_axes: {
    hope: number
    efficacy: number
    resilience: number
    optimism: number
  }
}

export function getResilienceMatrix(userId: string) {
  return request<ResilienceMatrix>(`/api/v1/resilience/matrix/${encodeURIComponent(userId)}`)
}

export type AssignTaskResult = {
  task_id?: string
  is_blocked_by_circuit_breaker?: boolean
  pacing_status?: string
} & ApiErrorBody

export function assignTask(body: {
  assignee_id: string
  task_name: string
  complexity_spoon_cost: number
  is_chunkable?: boolean
  attempt_graded_load_increase?: boolean
}) {
  return request<AssignTaskResult>('/api/v1/tasks/assign', {
    method: 'POST',
    body: JSON.stringify(body),
  })
}

export type JournalEntry = {
  entry_id: string
  user_id: string
  hallway_mirror_response: string
  relational_offloading_text: string | null
  created_at: string
  sealed: boolean
}

export function listJournal(userId: string) {
  return request<{ user_id: string; private_vault: boolean; entries: JournalEntry[] }>(
    `/api/v1/journal/entries?user_id=${encodeURIComponent(userId)}`,
  )
}

export function createJournal(body: {
  user_id: string
  hallway_mirror_response: string
  relational_offloading_text?: string
}) {
  return request<JournalEntry>('/api/v1/journal/entries', {
    method: 'POST',
    body: JSON.stringify(body),
  })
}

export function analyzeSentiment(body: {
  text_content: string
  source_channel: 'Slack' | 'Teams' | 'Outlook'
  user_id: string
  metadata?: { is_after_hours?: boolean; sender_role?: string }
}) {
  return request('/api/v1/cringe/analyze-sentiment', {
    method: 'POST',
    body: JSON.stringify(body),
  })
}

export function managerDashboard(orgId: string, departmentId: string) {
  const q = new URLSearchParams({ org_id: orgId, department_id: departmentId })
  return request(`/api/v1/manager/dashboard?${q}`)
}
