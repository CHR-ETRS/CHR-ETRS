import { useState } from 'react'
import { synthesize, sentiment, voi, circuitBreaker } from '../api/client'

type Result = { label: string; status: number; body: unknown }

export default function ApiLab() {
  const [open, setOpen] = useState(false)
  const [results, setResults] = useState<Result[]>([])
  const [busy, setBusy] = useState(false)

  async function runAll() {
    setBusy(true)
    const out: Result[] = []

    const syn = await synthesize([
      {
        employee_name: 'דנה כהן',
        age: 32,
        gender: 'F',
        tenure_months: 28,
        raw_survey_text: 'אני מרגישה עומס אבל יש תמיכה מהצוות',
        biometric_hrv: 48.5,
      },
    ])
    out.push({ label: 'POST /synthesize', status: syn.status, body: syn.data })

    const sent = await sentiment('syn_user_89170', 'המנהל שולט בכל פרט קטן')
    out.push({ label: 'POST /sentiment', status: sent.status, body: sent.data })

    const voiOk = await voi('102')
    out.push({ label: 'GET /voi/102', status: voiOk.status, body: voiOk.data })

    const voiFail = await voi('1')
    out.push({ label: 'GET /voi/1 (Rule of 5)', status: voiFail.status, body: voiFail.data })

    const cb = await circuitBreaker({
      team_id: 'team-alpha',
      requested_action: 'schedule_standup',
      meeting_duration_minutes: 30,
      participants_count: 6,
    })
    out.push({ label: 'POST /circuit-breaker', status: cb.status, body: cb.data })

    const cbOk = await circuitBreaker({
      team_id: 'team-alpha',
      requested_action: 'schedule_standup',
      meeting_duration_minutes: 30,
      participants_count: 6,
      force_stamina: 55,
    })
    out.push({ label: 'POST /circuit-breaker (force_stamina=55)', status: cbOk.status, body: cbOk.data })

    setResults(out)
    setBusy(false)
  }

  return (
    <div className="glass rounded-xl border border-emerald-500/20 overflow-hidden">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="w-full px-4 py-2 flex items-center justify-between text-sm text-emerald-300 hover:bg-slate-800/50"
      >
        <span>🧪 מעבדה — הדגמת API (4 endpoints)</span>
        <span>{open ? '▲' : '▼'}</span>
      </button>
      {open && (
        <div className="p-4 border-t border-slate-700/50 space-y-3">
          <button
            type="button"
            disabled={busy}
            onClick={runAll}
            className="px-4 py-2 rounded-lg bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-sm font-medium"
          >
            {busy ? 'רץ…' : 'הרץ את כל ה־endpoints'}
          </button>
          <div className="space-y-2 max-h-64 overflow-auto text-xs font-mono">
            {results.map((r) => (
              <div key={r.label} className="rounded-lg bg-slate-900/80 p-2 border border-slate-700">
                <div className="flex gap-2 mb-1">
                  <span className="text-amber-300">{r.label}</span>
                  <span className={r.status === 0 ? 'text-slate-400' : r.status < 300 ? 'text-emerald-400' : r.status === 423 || r.status === 403 ? 'text-amber-400' : 'text-red-400'}>
                    {r.status}
                  </span>
                </div>
                <pre className="whitespace-pre-wrap text-slate-400">{JSON.stringify(r.body, null, 2)}</pre>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
