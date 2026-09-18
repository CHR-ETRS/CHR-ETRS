import { useEffect, useMemo, useState } from 'react'
import {
  ASSUMPTIONS_HE,
  CUCKOO_THRESHOLD,
  LOW_SPOON_WARN,
  PRESETS,
  QUESTS,
  QUICK_SPOONS,
  REWARDS,
  applySpoon,
  buyReward,
  checkInToday,
  completeQuest,
  heroComposite,
  heroNudgeHe,
  isStaticPagesPreview,
  loadState,
  saveState,
  simulateMissedDay,
  spoonTotals,
  type HeroScores,
  type LunaState,
  type PresetId,
  type SpoonKind,
} from '../lib/lunaL2e'

export default function LunaL2eTab() {
  const [state, setState] = useState<LunaState>(() =>
    typeof window === 'undefined' ? PRESETS.healthy.state : loadState(),
  )
  const [activePreset, setActivePreset] = useState<PresetId | 'custom'>('custom')
  const [storeNote, setStoreNote] = useState<string | null>(null)

  useEffect(() => {
    saveState(state)
  }, [state])

  const composite = useMemo(() => heroComposite(state.hero), [state.hero])
  const totals = useMemo(() => spoonTotals(state.log), [state.log])
  const used = Math.max(0, state.dailyBudget - state.remaining)
  const cuckoo = state.remaining <= CUCKOO_THRESHOLD
  const low = !cuckoo && state.remaining <= LOW_SPOON_WARN
  const pages = isStaticPagesPreview()

  function patch(next: LunaState | ((prev: LunaState) => LunaState)) {
    setActivePreset('custom')
    setState(next)
  }

  function loadPreset(id: PresetId) {
    setActivePreset(id)
    setStoreNote(null)
    setState({ ...PRESETS[id].state })
  }

  function patchHero(key: keyof HeroScores, value: number) {
    patch((prev) => ({ ...prev, hero: { ...prev.hero, [key]: value } }))
  }

  function onBuy(id: string) {
    setState((prev) => {
      const res = buyReward(prev, id)
      if (!res.ok) {
        setStoreNote(
          res.reason === 'funds'
            ? 'אין מספיק Chits לרכישה זו.'
            : res.reason === 'owned'
              ? 'הפריט כבר בארנק ההדגמה.'
              : 'לא ניתן לרכוש.',
        )
        return prev
      }
      setActivePreset('custom')
      setStoreNote('הרכישה נרשמה בארנק המקומי.')
      return res.state
    })
  }

  return (
    <div className="space-y-6">
      {pages && (
        <div className="rounded-2xl px-4 py-3 text-sm border border-sky-500/40 bg-sky-950/30 text-sky-100">
          <strong>תצוגה סטטית · GitHub Pages.</strong> פורטל לנה / L2E רץ בדפדפן בלבד (localStorage) — אין צורך
          ב־backend.
        </div>
      )}

      <header className="glass rounded-2xl p-5 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 className="text-2xl font-bold text-amber-100">לנה · למד כדי להרוויח</h2>
          <p className="text-slate-400 text-sm mt-1">
            Luna / L2E · תקציב כפיות · הון HERO · EverStore · מגן רצף · מודל ארגוני (לא ייעוץ קליני)
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {(Object.keys(PRESETS) as PresetId[]).map((id) => (
            <button
              key={id}
              type="button"
              onClick={() => loadPreset(id)}
              className={
                'text-xs px-3 py-1.5 rounded-lg border transition-colors ' +
                (activePreset === id
                  ? 'bg-amber-500/20 border-amber-500/50 text-amber-100'
                  : 'border-slate-600 text-slate-300 hover:border-amber-500/40 hover:text-amber-200')
              }
            >
              {PRESETS[id].labelHe}
            </button>
          ))}
        </div>
      </header>

      {cuckoo && (
        <div className="glass rounded-2xl px-4 py-3 border border-rose-500/40 bg-rose-950/30 text-sm text-rose-100">
          <strong>קוקייה · האטי.</strong> נותרו {state.remaining} כפיות מהתקציב היומי. דחי סגירת מעגלים לא-דחופים
          ובחרי השקעה קטנה (L2E) במקום עוד הוצאה. מסגור ארגוני בלבד — לא אזהרה רפואית.
        </div>
      )}
      {low && (
        <div className="glass rounded-2xl px-4 py-3 border border-amber-500/40 bg-amber-950/30 text-sm text-amber-100">
          <strong>עתודה נמוכה.</strong> נותרו {state.remaining} כפיות. העדיפי השקעה (למידה / עבודה עמוקה) על פני
          הוצאות פגישות.
        </div>
      )}

      <section className="grid sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <HeroStat
          label="כפיות שנותרו"
          value={`${state.remaining}/${state.dailyBudget}`}
          sub={`הוצאה ${totals.expenditure} · השקעה ${totals.investment} · התאוששות ${totals.gain}`}
          accent={cuckoo ? 'rose' : low ? 'amber' : 'emerald'}
        />
        <HeroStat
          label="הון HERO"
          value={composite.toFixed(0)}
          sub={heroNudgeHe(composite)}
          accent={composite >= 75 ? 'emerald' : composite >= 50 ? 'amber' : 'rose'}
        />
        <HeroStat
          label="ארנק Chits"
          value={String(state.chits)}
          sub="מטבע הדגמה מקומי · EverStore"
          accent="amber"
        />
        <HeroStat
          label="רצף יומי"
          value={`${state.streakDays} ימים`}
          sub={state.shieldTokens > 0 ? `מגן פעיל ×${state.shieldTokens}` : 'אין מגן רצף'}
          accent={state.streakDays >= 7 ? 'emerald' : state.streakDays > 0 ? 'amber' : 'rose'}
        />
      </section>

      <div className="grid lg:grid-cols-2 gap-6">
        <SpoonTray
          state={state}
          used={used}
          onQuick={(kind, amount, label) => patch((s) => applySpoon(s, kind, amount, label))}
        />
        <HeroPanel hero={state.hero} composite={composite} onChange={patchHero} />
      </div>

      <div className="grid lg:grid-cols-2 gap-6">
        <QuestsPanel
          completed={state.completedQuestIds}
          onComplete={(id) => patch((s) => completeQuest(s, id))}
        />
        <EverStorePanel
          chits={state.chits}
          purchased={state.purchasedRewardIds}
          note={storeNote}
          onBuy={onBuy}
        />
      </div>

      <StreakPanel
        state={state}
        onCheckIn={() => patch((s) => checkInToday(s))}
        onMiss={() => patch((s) => simulateMissedDay(s))}
      />

      <details className="glass rounded-2xl p-5 group">
        <summary className="cursor-pointer font-semibold text-slate-200 list-none flex items-center justify-between">
          <span>הנחות · Glass Box · פרטיות</span>
          <span className="text-xs text-slate-500 group-open:hidden">לחצי לפתיחה</span>
        </summary>
        <ul className="mt-3 space-y-2 text-sm text-slate-400 list-disc pr-5 leading-relaxed">
          {ASSUMPTIONS_HE.map((a) => (
            <li key={a}>{a}</li>
          ))}
        </ul>
        <p className="mt-3 text-xs text-slate-500">
          שמירה מקומית במפתח <span className="font-mono text-slate-400">chr-etrs-luna-l2e-v1</span>. איפוס דרך
          פרסט או ניקוי נתוני האתר בדפדפן.
        </p>
      </details>
    </div>
  )
}

function HeroStat({
  label,
  value,
  sub,
  accent,
}: {
  label: string
  value: string
  sub: string
  accent: 'emerald' | 'rose' | 'amber'
}) {
  const ring =
    accent === 'emerald'
      ? 'border-emerald-500/40 bg-emerald-950/20'
      : accent === 'rose'
        ? 'border-rose-500/40 bg-rose-950/20'
        : 'border-amber-500/40 bg-amber-950/20'
  const num =
    accent === 'emerald' ? 'text-emerald-300' : accent === 'rose' ? 'text-rose-300' : 'text-amber-200'
  return (
    <div className={`glass rounded-2xl p-4 border ${ring}`}>
      <p className="text-xs text-slate-400 mb-1">{label}</p>
      <p className={`text-xl font-bold font-mono ${num}`}>{value}</p>
      <p className="text-xs text-slate-500 mt-1 leading-snug">{sub}</p>
    </div>
  )
}

function SpoonTray({
  state,
  used,
  onQuick,
}: {
  state: LunaState
  used: number
  onQuick: (kind: SpoonKind, amount: number, label: string) => void
}) {
  return (
    <section className="glass rounded-2xl p-5 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="font-semibold text-slate-200">מגש כפיות</h3>
        <span className="text-xs font-mono text-slate-400">
          נותרו {state.remaining} · נוצלו {used}
        </span>
      </div>
      <div className="flex flex-wrap gap-1.5" role="img" aria-label={`תקציב ${state.dailyBudget} כפיות, נותרו ${state.remaining}`}>
        {Array.from({ length: state.dailyBudget }, (_, i) => {
          const filled = i < state.remaining
          return (
            <span
              key={i}
              title={filled ? 'כפית פנויה' : 'כפית שנוצלה'}
              className={
                'inline-block w-5 h-8 rounded-b-full rounded-t-md border ' +
                (filled
                  ? 'bg-amber-400/80 border-amber-300/50 shadow-[0_0_8px_rgba(251,191,36,0.35)]'
                  : 'bg-slate-800 border-slate-600 opacity-50')
              }
            />
          )
        })}
      </div>
      <div className="grid grid-cols-3 gap-2 text-xs">
        <MiniStat label="הוצאה" value={String(spoonTotals(state.log).expenditure)} warn />
        <MiniStat label="השקעה" value={String(spoonTotals(state.log).investment)} />
        <MiniStat label="התאוששות" value={String(spoonTotals(state.log).gain)} />
      </div>
      <div>
        <p className="text-xs text-slate-400 mb-2">רישום מהיר להיום</p>
        <div className="flex flex-wrap gap-2">
          {QUICK_SPOONS.map((q) => (
            <button
              key={q.id}
              type="button"
              onClick={() => onQuick(q.kind, q.amount, q.label)}
              className={
                'text-xs px-3 py-1.5 rounded-lg border transition-colors ' +
                (q.kind === 'gain'
                  ? 'border-emerald-500/40 text-emerald-200 hover:bg-emerald-950/40'
                  : q.kind === 'investment'
                    ? 'border-sky-500/40 text-sky-200 hover:bg-sky-950/40'
                    : 'border-slate-600 text-slate-300 hover:border-rose-500/40 hover:text-rose-200')
              }
            >
              {q.label} {q.kind === 'gain' ? '+' : '−'}
              {q.amount}
            </button>
          ))}
        </div>
      </div>
      <div className="space-y-1.5 max-h-40 overflow-auto">
        {state.log.length === 0 ? (
          <p className="text-xs text-slate-500">אין רישומים להיום — התקציב מלא.</p>
        ) : (
          state.log.map((e) => (
            <div
              key={e.id}
              className="flex items-center justify-between text-xs rounded-lg bg-slate-900/60 border border-slate-700/50 px-3 py-1.5"
            >
              <span className="text-slate-300">{e.label}</span>
              <span
                className={
                  'font-mono ' +
                  (e.kind === 'gain'
                    ? 'text-emerald-300'
                    : e.kind === 'investment'
                      ? 'text-sky-300'
                      : 'text-rose-300')
                }
              >
                {e.kind === 'gain' ? '+' : '−'}
                {e.amount} · {kindHe(e.kind)}
              </span>
            </div>
          ))
        )}
      </div>
    </section>
  )
}

function kindHe(kind: SpoonKind): string {
  if (kind === 'investment') return 'השקעה'
  if (kind === 'gain') return 'התאוששות'
  return 'הוצאה'
}

function HeroPanel({
  hero,
  composite,
  onChange,
}: {
  hero: HeroScores
  composite: number
  onChange: (key: keyof HeroScores, value: number) => void
}) {
  const rows: { key: keyof HeroScores; label: string }[] = [
    { key: 'hope', label: 'H — תקווה (Hope)' },
    { key: 'efficacy', label: 'E — מסוגלות (Efficacy)' },
    { key: 'resilience', label: 'R — חוסן (Resilience)' },
    { key: 'optimism', label: 'O — אופטימיות (Optimism)' },
  ]
  return (
    <section className="glass rounded-2xl p-5 space-y-4">
      <div className="flex items-center justify-between gap-2">
        <h3 className="font-semibold text-slate-200">לוח HERO</h3>
        <span className="text-xs font-mono text-amber-200">{composite.toFixed(0)}/100</span>
      </div>
      <div className="h-2 rounded-full bg-slate-800 overflow-hidden">
        <div
          className={
            'h-full rounded-full transition-all ' +
            (composite >= 75 ? 'bg-emerald-500' : composite >= 50 ? 'bg-amber-500' : 'bg-rose-500')
          }
          style={{ width: `${composite}%` }}
        />
      </div>
      <p className="text-sm text-slate-400 leading-relaxed">{heroNudgeHe(composite)}</p>
      {rows.map((r) => (
        <div key={r.key}>
          <div className="flex justify-between text-sm mb-1.5">
            <label htmlFor={`hero-${r.key}`}>{r.label}</label>
            <span className="font-mono text-amber-200">{hero[r.key].toFixed(0)}</span>
          </div>
          <input
            id={`hero-${r.key}`}
            type="range"
            min={0}
            max={100}
            step={1}
            value={hero[r.key]}
            onChange={(e) => onChange(r.key, Number(e.target.value))}
            className="w-full accent-emerald-500"
          />
        </div>
      ))}
    </section>
  )
}

function QuestsPanel({
  completed,
  onComplete,
}: {
  completed: string[]
  onComplete: (id: string) => void
}) {
  return (
    <section className="glass rounded-2xl p-5 space-y-3">
      <h3 className="font-semibold text-slate-200">משימות L2E → Chits</h3>
      <p className="text-sm text-slate-400">למידה והשקעה בצוות. השלמה מעניקה Chits בארנק המקומי.</p>
      <div className="space-y-2">
        {QUESTS.map((q) => {
          const done = completed.includes(q.id)
          return (
            <button
              key={q.id}
              type="button"
              disabled={done}
              onClick={() => onComplete(q.id)}
              className="w-full text-right px-3 py-2.5 rounded-lg border border-slate-700 bg-slate-900/50 hover:border-emerald-500/40 disabled:opacity-40 disabled:cursor-not-allowed flex justify-between items-start gap-3 text-sm"
            >
              <span>
                <span className="block text-slate-200">
                  {done ? '✓ ' : ''}
                  {q.title}
                </span>
                <span className="block text-xs text-slate-500 mt-0.5">{q.blurb}</span>
              </span>
              <span className="text-amber-400 font-mono shrink-0">+{q.chits}</span>
            </button>
          )
        })}
      </div>
    </section>
  )
}

function EverStorePanel({
  chits,
  purchased,
  note,
  onBuy,
}: {
  chits: number
  purchased: string[]
  note: string | null
  onBuy: (id: string) => void
}) {
  return (
    <section className="glass rounded-2xl p-5 space-y-3">
      <div className="flex items-center justify-between gap-2">
        <h3 className="font-semibold text-slate-200">EverStore — תצוגה</h3>
        <span className="text-xs font-mono text-amber-200">{chits} Chits</span>
      </div>
      <p className="text-sm text-slate-400">שלושה פריטי הדגמה. אין תשלום אמיתי.</p>
      <div className="space-y-2">
        {REWARDS.map((r) => {
          const owned = !r.consumable && purchased.includes(r.id)
          const cantAfford = chits < r.cost
          return (
            <div
              key={r.id}
              className="rounded-xl border border-slate-700/60 bg-slate-900/40 px-3 py-3 flex items-start justify-between gap-3"
            >
              <div>
                <p className="text-sm text-slate-200">{r.title}</p>
                <p className="text-xs text-slate-500 mt-0.5 leading-relaxed">{r.blurb}</p>
              </div>
              <button
                type="button"
                disabled={owned || cantAfford}
                onClick={() => onBuy(r.id)}
                className="shrink-0 text-xs px-3 py-1.5 rounded-lg border border-amber-500/40 text-amber-100 hover:bg-amber-950/40 disabled:opacity-40 disabled:cursor-not-allowed font-mono"
              >
                {owned ? 'בארנק' : `${r.cost}`}
              </button>
            </div>
          )
        })}
      </div>
      {note && <p className="text-xs text-slate-400">{note}</p>}
    </section>
  )
}

function StreakPanel({
  state,
  onCheckIn,
  onMiss,
}: {
  state: LunaState
  onCheckIn: () => void
  onMiss: () => void
}) {
  return (
    <section className="glass rounded-2xl p-5 space-y-3">
      <h3 className="font-semibold text-slate-200">מגן רצף</h3>
      <p className="text-sm text-slate-400">
        רצף של {state.streakDays} ימים
        {state.lastStreakDate ? ` · סימון אחרון ${state.lastStreakDate}` : ''}. אסימון מגן אחד יכול לשמור על הרצף
        אחרי יום שפוספס (הדגמה).
      </p>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={onCheckIn}
          className="px-4 py-2 rounded-lg bg-emerald-600/90 hover:bg-emerald-500 text-sm font-medium"
        >
          סימון נוכחות היום
        </button>
        <button
          type="button"
          onClick={onMiss}
          className="px-4 py-2 rounded-lg border border-slate-600 text-slate-200 hover:border-amber-500/40 hover:text-amber-100 text-sm"
        >
          הדגם יום שפוספס
        </button>
        <span
          className={
            'text-xs px-2.5 py-1.5 rounded-full border self-center ' +
            (state.shieldTokens > 0
              ? 'border-emerald-500/40 text-emerald-300 bg-emerald-950/30'
              : 'border-slate-600 text-slate-400')
          }
        >
          מגן ×{state.shieldTokens}
        </span>
      </div>
      {state.shieldMessage && (
        <p className="text-sm text-amber-100/90 rounded-xl border border-amber-500/30 bg-amber-950/20 px-3 py-2">
          {state.shieldMessage}
        </p>
      )}
    </section>
  )
}

function MiniStat({ label, value, warn }: { label: string; value: string; warn?: boolean }) {
  return (
    <div className="rounded-xl bg-slate-900/60 border border-slate-700/50 px-3 py-2">
      <p className="text-[11px] text-slate-500">{label}</p>
      <p className={`text-sm font-mono mt-0.5 ${warn ? 'text-amber-300' : 'text-slate-200'}`}>{value}</p>
    </div>
  )
}
