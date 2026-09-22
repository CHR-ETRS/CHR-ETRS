import { useMemo, useState, type CSSProperties } from 'react'

type AlertState = 'healthy' | 'throttle' | 'brake'

const QUESTS = [
  { id: 'q1', title: 'נשימה מודעת — 3 דקות', chits: 15 },
  { id: 'q2', title: 'הליכה קצרה מחוץ למסך', chits: 20 },
  { id: 'q3', title: 'רשום דבר טוב אחד מהיום', chits: 10 },
]

function hrvToSpoons(hrv: number): number {
  // Mid HRV (~50) → ~35 for SHAY; higher HRV → more spoons
  const spoons = 10 + ((hrv - 25) / 50) * 70
  return Math.round(Math.max(5, Math.min(100, spoons)))
}

function alertFromHrv(hrv: number): AlertState {
  if (hrv < 40) return 'brake'
  if (hrv < 55) return 'throttle'
  return 'healthy'
}

const ALERT_HE = { healthy: 'תקין', throttle: 'האטה', brake: 'נעילה' } as const

const MICRO: Record<AlertState, string> = {
  healthy: 'המערכת רגועה. אפשר להמשיך במשימות ובמפגשים בקצב טבעי.',
  throttle: 'זוהתה ירידה באנרגיה. האט/י את הקצב — משימות כבדות נעולות זמנית.',
  brake: 'מצב בלימה. שמור/י על שתיקה דיגיטלית ואל תתזמן/י פגישות חדשות.',
}

export default function SanctuaryTab() {
  const [hrv, setHrv] = useState(52)
  const [chits, setChits] = useState(120)
  const [done, setDone] = useState<Record<string, boolean>>({})

  const alert = useMemo(() => alertFromHrv(hrv), [hrv])
  const spoons = useMemo(() => hrvToSpoons(hrv), [hrv])
  const throttled = alert !== 'healthy'

  const orbVars = useMemo(() => {
    if (alert === 'healthy')
      return { '--orb-light': '#6ee7b7', '--orb-mid': '#10b981', '--orb-dark': '#064e3b', '--orb-glow': 'rgba(16,185,129,0.45)' }
    if (alert === 'throttle')
      return { '--orb-light': '#fcd34d', '--orb-mid': '#f59e0b', '--orb-dark': '#78350f', '--orb-glow': 'rgba(245,158,11,0.45)' }
    return { '--orb-light': '#fca5a5', '--orb-mid': '#ef4444', '--orb-dark': '#7f1d1d', '--orb-glow': 'rgba(239,68,68,0.5)' }
  }, [alert])

  function completeQuest(id: string, reward: number) {
    if (throttled || done[id]) return
    setDone((d) => ({ ...d, [id]: true }))
    setChits((c) => c + reward)
  }

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      {/* Header */}
      <header className="glass rounded-2xl p-5 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 className="text-2xl font-bold text-amber-100">מרחב מקלט (Sanctuary)</h2>
          <p className="text-slate-400 text-sm mt-1">פרופיל אנרגיה: <span className="text-emerald-300 font-mono">SHAY-09</span></p>
        </div>
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-900/80 border border-emerald-500/30">
          <span className="relative flex h-2.5 w-2.5">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
            <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-emerald-400" />
          </span>
          <span className="text-xs text-emerald-300">Zen-Gate · פרטיות פעילה</span>
        </div>
      </header>

      <div className="grid md:grid-cols-2 gap-6">
        {/* Energy core */}
        <section className="glass rounded-2xl p-6 flex flex-col items-center gap-4">
          <div
            className={`orb w-40 h-40 animate-spin-slow ${alert === 'brake' ? 'animate-pulse' : 'animate-pulse-slow'}`}
            style={orbVars as CSSProperties}
          />
          <div className="text-center space-y-1">
            <p className="text-sm text-slate-400">ליבת אנרגיה</p>
            <p className={`text-xl font-bold ${alert === 'healthy' ? 'text-emerald-300' : alert === 'throttle' ? 'text-amber-300' : 'text-red-400'}`}>
              {ALERT_HE[alert]}
            </p>
            <p className="text-slate-400 text-sm px-2">{MICRO[alert]}</p>
          </div>

          <div className="w-full space-y-2 mt-2">
            <div className="flex justify-between text-sm">
              <span>סוללת כפיות (Spoons)</span>
              <span className="font-mono text-amber-200">{spoons}%</span>
            </div>
            <div className="h-3 rounded-full bg-slate-800 overflow-hidden">
              <div
                className={`h-full transition-all duration-300 ${alert === 'healthy' ? 'bg-emerald-500' : alert === 'throttle' ? 'bg-amber-500' : 'bg-red-500'}`}
                style={{ width: `${spoons}%` }}
              />
            </div>
          </div>
        </section>

        {/* Controls */}
        <section className="glass rounded-2xl p-6 space-y-5">
          <div>
            <div className="flex justify-between text-sm mb-2">
              <label htmlFor="hrv">טייס HRV (מ״ש)</label>
              <span className="font-mono text-amber-200">{hrv} ms</span>
            </div>
            <input
              id="hrv"
              type="range"
              min={25}
              max={75}
              value={hrv}
              onChange={(e) => setHrv(Number(e.target.value))}
              className="w-full accent-emerald-500"
            />
            <div className="flex justify-between text-xs text-slate-500 mt-1">
              <span>25 · נעילה</span>
              <span>40 · האטה</span>
              <span>55 · תקין</span>
              <span>75</span>
            </div>
          </div>

          <div className="flex items-center justify-between rounded-xl bg-slate-900/60 px-4 py-3 border border-amber-500/20">
            <span className="text-sm">ארנק צ׳יטים (Chits)</span>
            <span className="text-2xl font-bold text-amber-300 font-mono">{chits}</span>
          </div>

          <div className="space-y-2">
            <h3 className="text-sm font-semibold text-slate-300">משימות יומיות</h3>
            {QUESTS.map((q) => (
              <button
                key={q.id}
                type="button"
                disabled={throttled || !!done[q.id]}
                onClick={() => completeQuest(q.id, q.chits)}
                className="w-full text-right px-3 py-2.5 rounded-lg border border-slate-700 bg-slate-900/50 hover:border-emerald-500/40 disabled:opacity-40 disabled:cursor-not-allowed flex justify-between items-center text-sm"
              >
                <span>{done[q.id] ? '✓ ' : ''}{q.title}</span>
                <span className="text-amber-400 font-mono">+{q.chits}</span>
              </button>
            ))}
            {throttled && (
              <p className="text-xs text-amber-400/80">משימות מושהות במצב {ALERT_HE[alert]}</p>
            )}
          </div>
        </section>
      </div>

      <section className="glass rounded-2xl p-5 space-y-2">
        <h3 className="font-semibold text-slate-200">מעגל מגן</h3>
        <p className="text-sm text-slate-400">
          הקצאת משימות ומעגל המגן עברו למסך «קצב חכם» וקוראים ל־POST /api/v1/tasks/assign.
          המסך הזה נשאר הדגמה מקומית של אורב האנרגיה, בלי קריאות לנתיבים הישנים.
        </p>
      </section>
    </div>
  )
}
