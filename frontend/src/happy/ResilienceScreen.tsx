import { useEffect, useState } from 'react'
import { getResilienceMatrix, type ResilienceMatrix } from '../api/client'

const ROLES = ['HOPE', 'SHAY', 'NESS'] as const

const COPY: Record<(typeof ROLES)[number], { title: string; body: string }> = {
  HOPE: { title: 'HOPE', body: 'כפיות ו־HRV מעל הסף. אפשר לנוע בקצב רגיל.' },
  SHAY: { title: 'SHAY', body: 'אזור האטה. עומס כבד עדיין אפשרי, אבל לא כדאי לדחוף.' },
  NESS: { title: 'NESS', body: 'בלימה. מעגל המגן פתוח — ניגודיות מנוטרלת, אין הקצאת עומס.' },
}

export default function ResilienceScreen({ userId }: { userId: string }) {
  const [matrix, setMatrix] = useState<ResilienceMatrix | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    void getResilienceMatrix(userId).then((res) => {
      if (cancelled) return
      if (!res.ok) {
        setError(`HTTP ${res.status}`)
        setMatrix(null)
        return
      }
      setError(null)
      setMatrix(res.data)
    })
    return () => {
      cancelled = true
    }
  }, [userId])

  const axes = matrix?.resilience_axes

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <header className="glass rounded-2xl p-5">
        <p className="text-xs text-amber-300/80">מסך 3 · Happy Path</p>
        <h2 className="text-2xl font-bold text-amber-100 mt-1">מטריצת חוסן</h2>
        <p className="text-sm text-slate-400 mt-2">
          מצב האווטאר נגזר מתקציב הכפיות ומדגימת ה־HRV האחרונה. HOPE כשהמדדים רגועים, SHAY בהאטה, NESS כשהמעגל נעול.
        </p>
      </header>

      {error && <p className="text-sm text-red-300">{error}</p>}

      <section className="grid md:grid-cols-3 gap-3">
        {ROLES.map((role) => {
          const active = matrix?.role_state === role
          return (
            <article
              key={role}
              className={
                'rounded-2xl p-4 border ' +
                (active
                  ? 'bg-amber-500/15 border-amber-400/50'
                  : 'glass border-slate-700/40 opacity-70')
              }
            >
              <h3 className="font-bold text-lg">{COPY[role].title}</h3>
              <p className="text-sm text-slate-300 mt-2">{COPY[role].body}</p>
              {active && <p className="text-xs text-amber-200 mt-3">מצב פעיל</p>}
            </article>
          )
        })}
      </section>

      {matrix && (
        <section className="glass rounded-2xl p-5 space-y-4">
          <div className="flex flex-wrap gap-4 text-sm text-slate-300">
            <span>כפיות {matrix.current_spoon_count}</span>
            <span>HRV {matrix.latest_hrv_ms ?? '—'} ms</span>
            <span>השהיית זיכרון עצם {matrix.bone_memory_latency}</span>
            <span>
              {matrix.contrast_nullification_active ? 'ניגודיות מנוטרלת' : 'ניגודיות פעילה'}
            </span>
          </div>
          {axes && (
            <div className="space-y-2">
              <Bar label="Hope" value={axes.hope} />
              <Bar label="Efficacy" value={axes.efficacy} />
              <Bar label="Resilience" value={axes.resilience} />
              <Bar label="Optimism" value={axes.optimism} />
            </div>
          )}
        </section>
      )}
    </div>
  )
}

function Bar({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <div className="flex justify-between text-xs text-slate-400 mb-1">
        <span>{label}</span>
        <span className="font-mono">{value.toFixed(0)}</span>
      </div>
      <div className="h-2 rounded-full bg-slate-800 overflow-hidden">
        <div className="h-full bg-amber-400/80" style={{ width: `${Math.max(0, Math.min(100, value))}%` }} />
      </div>
    </div>
  )
}
