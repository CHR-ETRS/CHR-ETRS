import { useCallback, useEffect, useState } from 'react'
import {
  getHrvStream,
  getSpoonsBudget,
  postHrvSample,
  type HrvStreamFrame,
  type SpoonsBudget,
} from '../api/client'
import { deviceFor } from './demoUsers'

export default function DailyHubScreen({ userId }: { userId: string }) {
  const [spoons, setSpoons] = useState<SpoonsBudget | null>(null)
  const [frame, setFrame] = useState<HrvStreamFrame | null>(null)
  const [hrv, setHrv] = useState(58)
  const [note, setNote] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    setError(null)
    const [budget, stream] = await Promise.all([
      getSpoonsBudget(userId),
      getHrvStream(deviceFor(userId)),
    ])
    if (!budget.ok) setError(`תקציב כפיות: HTTP ${budget.status}`)
    else setSpoons(budget.data)
    if (!stream.ok) setError(`זרם HRV: HTTP ${stream.status}`)
    else {
      setFrame(stream.data)
      setHrv(Math.round(stream.data.hrv_baseline))
    }
  }, [userId])

  useEffect(() => {
    void refresh()
  }, [refresh])

  async function ingest() {
    setBusy(true)
    setNote(null)
    const res = await postHrvSample({
      user_id: userId,
      sample_timestamp: new Date().toISOString(),
      hrv_baseline_ms: hrv,
      vagal_tone_index: Math.round((hrv / 80) * 1000) / 1000,
    })
    setBusy(false)
    if (!res.ok) {
      const msg = (res.data as { message?: string }).message
      setNote(msg ?? `דגימה נדחתה (${res.status})`)
      return
    }
    setNote(
      res.data.biometric_alert_triggered
        ? `בלימה ביומטרית · ${res.data.threshold_violation ?? 'HRV מתחת לסף'}`
        : 'הדגימה נשמרה בכספת הפרטית.',
    )
    await refresh()
  }

  const pct = spoons?.available_capacity_pct ?? 0
  const critical = (spoons?.current_spoon_count ?? 12) < 3

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <header className="glass rounded-2xl p-5">
        <p className="text-xs text-amber-300/80">מסך 2 · Happy Path</p>
        <h2 className="text-2xl font-bold text-amber-100 mt-1">מרכז יומי</h2>
        <p className="text-sm text-slate-400 mt-2">
          יתרת כפיות מתוך 12, וצילום HRV מהזרם. הסף הקשיח למשימות הוא 40ms; מתחת ל־3 כפיות המעגל ננעל.
        </p>
      </header>

      {error && <p className="text-sm text-red-300">{error}</p>}

      <section className="grid md:grid-cols-2 gap-4">
        <article className="glass rounded-2xl p-5 space-y-3">
          <h3 className="font-semibold">תקציב כפיות</h3>
          <p className="text-4xl font-mono text-amber-200">
            {spoons ? spoons.current_spoon_count : '—'}
            <span className="text-lg text-slate-500"> / {spoons?.daily_baseline_capacity ?? 12}</span>
          </p>
          <div className="h-3 rounded-full bg-slate-800 overflow-hidden">
            <div
              className={`h-full ${critical ? 'bg-red-500' : 'bg-emerald-500'}`}
              style={{ width: `${Math.max(0, Math.min(100, pct))}%` }}
            />
          </div>
          <dl className="text-sm text-slate-400 space-y-1">
            <div className="flex justify-between">
              <dt>קיבולת</dt>
              <dd className="font-mono text-slate-200">{pct.toFixed(1)}%</dd>
            </div>
            <div className="flex justify-between">
              <dt>מצב אנרגיה</dt>
              <dd>{spoons?.energy_state_indicator ?? '—'}</dd>
            </div>
            <div className="flex justify-between">
              <dt>קצב חכם</dt>
              <dd>{spoons?.smart_pacing_status ?? '—'}</dd>
            </div>
            <div className="flex justify-between">
              <dt>כפיות מוזהבות מוגנות</dt>
              <dd className="font-mono">{spoons?.breakdown.golden_spoons_held ?? 0}</dd>
            </div>
          </dl>
        </article>

        <article className="glass rounded-2xl p-5 space-y-3">
          <h3 className="font-semibold">צילום HRV</h3>
          <p className="text-4xl font-mono text-emerald-200">
            {frame ? frame.hrv_baseline.toFixed(1) : '—'}
            <span className="text-lg text-slate-500"> ms</span>
          </p>
          <p className="text-xs text-slate-500 font-mono">
            {frame?.sample_id} · מכשיר {deviceFor(userId)}
          </p>
          <label className="block text-sm space-y-2">
            <span className="flex justify-between text-slate-400">
              <span>דגימה חדשה</span>
              <span className="font-mono text-amber-200">{hrv} ms</span>
            </span>
            <input
              type="range"
              min={20}
              max={90}
              value={hrv}
              onChange={(e) => setHrv(Number(e.target.value))}
              className="w-full accent-emerald-500"
            />
          </label>
          <button
            type="button"
            disabled={busy}
            onClick={() => void ingest()}
            className="px-4 py-2 rounded-lg bg-emerald-600/90 hover:bg-emerald-500 disabled:opacity-50 text-sm font-medium"
          >
            {busy ? 'שולח…' : 'שמור דגימת HRV'}
          </button>
          {note && <p className="text-sm text-slate-300">{note}</p>}
        </article>
      </section>
    </div>
  )
}
