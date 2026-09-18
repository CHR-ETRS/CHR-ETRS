import { useCallback, useEffect, useState } from 'react'
import { financeSimulate, voi, type FinanceSimulateResult } from '../api/client'

const ILS = (n: number, digits = 0) =>
  n.toLocaleString('he-IL', { maximumFractionDigits: digits, minimumFractionDigits: digits })

const pct = (n: number, digits = 2) =>
  `${n.toLocaleString('he-IL', { maximumFractionDigits: digits, minimumFractionDigits: digits })}%`

const CONCEPTS = [
  {
    title: 'Glass Box / שקיפות רדיקלית',
    body: 'הון אנושי גלוי במאזן — לא «עלויות שכר» בלבד, אלא צללים, החזר וערך.',
  },
  {
    title: 'CHR מול CSR',
    body: 'השקעה במנוע האנושי, לא חלוקת שאריות. CHR בונה תשתית; CSR מחלק אחרי המאזן.',
  },
  {
    title: 'OPEX → CAPEX',
    body: 'הון אנושי כהשקעה במאזן — CAPEX של CHR-OS במקום OPEX מתכלה של תחלופה ושחיקה.',
  },
  {
    title: 'VOI מול ROI',
    body: 'ROI מודד החזר כספי; VOI מודד ערך אנושי (אושר, eNPS, שחיקה) שמתורגם להשפעה פיננסית.',
  },
  {
    title: 'Rule of 5 — פרטיות',
    body: 'אין מדדי VOI מתחת ל־5 משיבים. ראי הדגמה במחלקה 102 למטה.',
  },
  {
    title: 'שכר שעתי מדולל',
    body: '25k → 144.34 ₪/שעה נומינלי (40×4.33) מול 104.98 מדולל ב־55 שעות; שחיקה 27.27%.',
  },
]

const SOURCES: { title: string; href: string }[] = [
  {
    title: 'תיקיית מחברת 04',
    href: 'https://drive.google.com/drive/folders/1FKjFVhGrcxVWwoW_yfaTpTqBZoYjjjPS',
  },
  {
    title: 'מודל הון אנושי (39 קבצים)',
    href: 'https://drive.google.com/drive/folders/1eAX8EGYE9EwhD0yTB3UagjGpHXliwkBp',
  },
  {
    title: 'המאזן הנסתר',
    href: 'https://docs.google.com/document/d/1KFAEd0tScORxmCQrcxdxl-KGvhxHn-TpuXVbrCppPe0/edit',
  },
  {
    title: 'CHR כמערכת הפעלה אקולוגית-פיננסית',
    href: 'https://docs.google.com/document/d/1lK74OiOEic9RTeZ7pcHxSMuImKTlljOwf4R8nWWQicI/edit',
  },
  {
    title: 'Glass Box Charter',
    href: 'https://docs.google.com/document/d/15lf8J6LAwohuYkYzOqjTmG9VDGjgReNo8ubt31fwknc/edit',
  },
  {
    title: 'ROI sheet',
    href: 'https://docs.google.com/spreadsheets/d/1hkaWRUQ51KbDoTbRZoQL42SJYqJwjAZKcG7vmCk5vAk/edit',
  },
  {
    title: 'ROI/VOI gate',
    href: 'https://docs.google.com/spreadsheets/d/1ltAAglCNHKUpB7SEA65V95U4Byk_io9owtpRXV_wayQ/edit',
  },
]

type VoiView = {
  happiness: number
  eNPS: number
  burnout: number
  voi_index: number
  estimated_savings_ils: number
  productivity_delta: number
} | null

export default function CapitalTab() {
  const [n, setN] = useState(500)
  const [salary, setSalary] = useState(25000)
  const [turnover, setTurnover] = useState(0.22)
  const [deprivation, setDeprivation] = useState(0.2)
  const [data, setData] = useState<FinanceSimulateResult | null>(null)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [voiBusy, setVoiBusy] = useState(false)
  const [voiData, setVoiData] = useState<VoiView>(null)
  const [voiErr, setVoiErr] = useState<string | null>(null)

  const runSim = useCallback(async () => {
    setBusy(true)
    setErr(null)
    // Scale org P&L with headcount vs Cos baseline of 500 so margins stay coherent
    const scale = n / 500
    const res = await financeSimulate({
      num_employees: n,
      avg_monthly_salary: salary,
      revenue: 300_000_000 * scale,
      non_payroll_opex: 105_000_000 * scale,
      turnover_rate: turnover,
      deprivation_pct: deprivation,
      baseline_turnover_rate: turnover,
      baseline_deprivation_pct: deprivation,
      capex: 350_000,
    })
    if (!res.ok) {
      setErr('לא הצלחתי להריץ סימולציה — בדקי שה־API רץ על פורט 8000.')
      setBusy(false)
      return
    }
    setData(res.data)
    setBusy(false)
  }, [n, salary, turnover, deprivation])

  useEffect(() => {
    void runSim()
  }, [runSim])

  async function loadVoi() {
    setVoiBusy(true)
    setVoiErr(null)
    const res = await voi('102')
    if (!res.ok) {
      setVoiErr('Rule of 5 או שגיאת רשת — לא ניתן לטעון VOI.')
      setVoiData(null)
      setVoiBusy(false)
      return
    }
    const d = res.data as {
      happiness: number
      eNPS: number
      burnout: number
      financial_impact: {
        voi_index: number
        estimated_savings_ils: number
        productivity_delta: number
      }
    }
    setVoiData({
      happiness: d.happiness,
      eNPS: d.eNPS,
      burnout: d.burnout,
      voi_index: d.financial_impact.voi_index,
      estimated_savings_ils: d.financial_impact.estimated_savings_ils,
      productivity_delta: d.financial_impact.productivity_delta,
    })
    setVoiBusy(false)
  }

  function resetDefaults() {
    setN(500)
    setSalary(25000)
    setTurnover(0.22)
    setDeprivation(0.2)
  }

  const d = data

  return (
    <div className="space-y-6">
      <header className="glass rounded-2xl p-5 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 className="text-2xl font-bold text-amber-100">מחברת 04 — הון אנושי ופיננסים</h2>
          <p className="text-slate-400 text-sm mt-1">
            מאזן צללים · סימולטור CHR-OS · מקורות Drive
          </p>
        </div>
        {d && (
          <span
            className={
              'text-xs px-2.5 py-1 rounded-full border ' +
              (d.mode === 'baseline'
                ? 'bg-emerald-950/50 border-emerald-500/40 text-emerald-300'
                : 'bg-amber-950/50 border-amber-500/40 text-amber-200')
            }
          >
            {d.mode === 'baseline' ? 'מצב Cos (ברירת מחדל)' : 'סימולציה חיה'}
          </span>
        )}
      </header>

      {/* A. Shadow P&L hero */}
      <section className="space-y-4">
        <h3 className="text-sm font-semibold text-slate-300 tracking-wide">מאזן צללים — גיבור P&amp;L</h3>
        {err && (
          <p className="text-sm text-red-400 glass rounded-xl px-4 py-3 border border-red-500/30">{err}</p>
        )}
        {d && (
          <>
            <div className="grid sm:grid-cols-3 gap-3">
              <HeroCard
                label="נומינלי"
                value={ILS(d.ebitda_nominal)}
                sub={`EBITDA · ${pct(d.ebitda_nominal_margin_pct)}`}
                accent="slate"
              />
              <HeroCard
                label="Pre-CHR"
                value={ILS(Math.round(d.ebitda_pre_chr))}
                sub={`EBITDA · ${pct(d.ebitda_pre_chr_margin_pct)}`}
                accent="amber"
              />
              <HeroCard
                label="After CHR-OS"
                value={ILS(Math.round(d.ebitda_after_chr))}
                sub={`EBITDA · ${pct(d.ebitda_after_chr_margin_pct)}`}
                accent="emerald"
              />
            </div>

            <div className="grid sm:grid-cols-4 gap-3">
              <MiniStat label="הכנסות" value={`${ILS(d.revenue)} ₪`} />
              <MiniStat label="מאזן צללים" value={`${ILS(Math.round(d.shadow_pre.total))} ₪`} warn />
              <MiniStat label="CHR-OS CAPEX" value={`${ILS(d.capex)} ₪`} />
              <MiniStat
                label="ROI / ROV"
                value={`≈ ${ILS(Math.round(d.roi_pct))}% · ${d.rov.toLocaleString('he-IL', { maximumFractionDigits: 2 })}x`}
              />
            </div>

            <div className="glass rounded-2xl overflow-hidden border border-slate-700/40">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-slate-400 border-b border-slate-700/60 bg-slate-900/50">
                      <th className="text-right font-medium px-4 py-3">סעיף</th>
                      <th className="text-left font-medium px-4 py-3">נומינלי</th>
                      <th className="text-left font-medium px-4 py-3">Pre-CHR</th>
                      <th className="text-left font-medium px-4 py-3">After CHR-OS</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/80">
                    <Row label="הכנסות (Revenue)" a={d.revenue} b={d.revenue} c={d.revenue} />
                    <Row label="שכר שנתי (Payroll)" a={-d.payroll} b={-d.payroll} c={-d.payroll} />
                    <Row
                      label="OPEX שאינו שכר"
                      a={-d.non_payroll_opex}
                      b={-d.non_payroll_opex}
                      c={-d.non_payroll_opex}
                    />
                    <Row
                      label="EBITDA נומינלי"
                      a={d.ebitda_nominal}
                      b={d.ebitda_nominal}
                      c={d.ebitda_nominal}
                      bold
                    />
                    <Row
                      label="מס קיפוח"
                      a={null}
                      b={-d.shadow_pre.deprivation_tax}
                      c={-d.shadow_post.deprivation_tax}
                      dim
                    />
                    <Row
                      label="חוב אמוציונלי / תחלופה"
                      a={null}
                      b={-d.shadow_pre.emotional_debt}
                      c={-d.shadow_post.emotional_debt}
                      dim
                    />
                    <Row
                      label="חוב שחיקה"
                      a={null}
                      b={-d.shadow_pre.burnout_liability}
                      c={-d.shadow_post.burnout_liability}
                      dim
                    />
                    <Row
                      label="סה״כ מאזן צללים"
                      a={null}
                      b={-d.shadow_pre.total}
                      c={-d.shadow_post.total}
                      warn
                    />
                    <Row label="השקעת CHR-OS (CAPEX)" a={null} b={null} c={-d.capex} dim />
                    <Row
                      label="EBITDA ממשי"
                      a={d.ebitda_nominal}
                      b={d.ebitda_pre_chr}
                      c={d.ebitda_after_chr}
                      bold
                      highlight
                    />
                  </tbody>
                </table>
              </div>
              <p className="text-xs text-slate-500 px-4 py-3 border-t border-slate-800">
                תחלופה בסיס {pct(d.turnover_rate * 100, 0)} · קיפוח {pct(d.deprivation_pct * 100, 0)} ·
                אחרי CHR: תחלופה {pct(d.post_turnover_rate * 100, 0)} · קיפוח {pct(d.post_deprivation_pct * 100, 0)} · שחיקה שיורית{' '}
                {pct(d.post_burnout_pct * 100, 0)}
                {busy ? ' · מעדכן…' : ''}
              </p>
            </div>
          </>
        )}
      </section>

      {/* B. Mini-simulator */}
      <section className="glass rounded-2xl p-5 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="font-semibold text-slate-200">סימולטור מיני</h3>
          <button
            type="button"
            onClick={resetDefaults}
            className="text-xs px-3 py-1.5 rounded-lg border border-slate-600 text-slate-300 hover:border-amber-500/40 hover:text-amber-200"
          >
            אפסי לברירת מחדל
          </button>
        </div>
        <div className="grid md:grid-cols-2 gap-5">
          <SliderField
            id="n"
            label="מספר עובדים"
            value={n}
            min={50}
            max={2000}
            step={10}
            display={ILS(n)}
            onChange={setN}
          />
          <SliderField
            id="salary"
            label="שכר חודשי ממוצע (₪)"
            value={salary}
            min={8000}
            max={50000}
            step={500}
            display={ILS(salary)}
            onChange={setSalary}
          />
          <SliderField
            id="turnover"
            label="שיעור תחלופה שנתי"
            value={turnover}
            min={0.05}
            max={0.5}
            step={0.01}
            display={pct(turnover * 100, 0)}
            onChange={setTurnover}
          />
          <SliderField
            id="deprivation"
            label="שיעור קיפוח (deprivation)"
            value={deprivation}
            min={0}
            max={0.5}
            step={0.01}
            display={pct(deprivation * 100, 0)}
            onChange={setDeprivation}
          />
        </div>
        {d && (
          <details className="text-xs text-slate-500">
            <summary className="cursor-pointer text-slate-400 hover:text-slate-300">הנחות מודל</summary>
            <ul className="mt-2 space-y-1 list-disc pr-5">
              {d.assumptions.map((a) => (
                <li key={a}>{a}</li>
              ))}
              <li>
                הכנסות ו־OPEX שאינו שכר מותאמים יחסית ל־N/500 כדי לשמור על מרווח ~15% נומינלי.
              </li>
            </ul>
          </details>
        )}
      </section>

      {/* C. Concepts */}
      <section className="space-y-3">
        <h3 className="text-sm font-semibold text-slate-300">מושגי ליבה</h3>
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {CONCEPTS.map((c) => (
            <article key={c.title} className="glass rounded-2xl p-4 border border-slate-700/40 space-y-1.5">
              <h4 className="text-sm font-semibold text-amber-200">{c.title}</h4>
              <p className="text-xs text-slate-400 leading-relaxed">{c.body}</p>
            </article>
          ))}
        </div>
        {d && (
          <div className="glass rounded-2xl p-4 flex flex-wrap gap-4 text-sm border border-emerald-500/20">
            <span className="text-slate-400">שכר שעתי:</span>
            <span className="text-emerald-300 font-mono">
              {d.diluted_wage.nominal_hourly.toLocaleString('he-IL', { maximumFractionDigits: 2 })} ₪ נומינלי
            </span>
            <span className="text-amber-300 font-mono">
              {d.diluted_wage.diluted_hourly.toLocaleString('he-IL', { maximumFractionDigits: 2 })} ₪ מדולל
            </span>
            <span className="text-slate-400">
              שחיקה {pct(d.diluted_wage.erosion_pct)}
            </span>
          </div>
        )}
      </section>

      {/* E. VOI */}
      <section className="glass rounded-2xl p-5 space-y-3">
        <h3 className="font-semibold text-slate-200">מדדי VOI</h3>
        <p className="text-sm text-slate-400">
          טעני מדדי Value of Intangibles למחלקה 102 (Rule of 5 מאושר).
        </p>
        <button
          type="button"
          disabled={voiBusy}
          onClick={() => void loadVoi()}
          className="px-4 py-2 rounded-lg bg-emerald-600/90 hover:bg-emerald-500 disabled:opacity-50 text-sm font-medium"
        >
          {voiBusy ? 'טוענת…' : 'טעני מדדי VOI (מחלקה 102)'}
        </button>
        {voiErr && <p className="text-sm text-red-400">{voiErr}</p>}
        {voiData && (
          <div className="grid sm:grid-cols-3 lg:grid-cols-6 gap-2">
            <MiniStat label="אושר" value={voiData.happiness.toFixed(2)} />
            <MiniStat label="eNPS" value={String(voiData.eNPS)} />
            <MiniStat label="שחיקה" value={voiData.burnout.toFixed(2)} warn />
            <MiniStat label="VOI index" value={voiData.voi_index.toFixed(2)} />
            <MiniStat label="חיסכון משוער" value={`${ILS(voiData.estimated_savings_ils)} ₪`} />
            <MiniStat label="Δ פרודוקטיביות" value={pct(voiData.productivity_delta * 100, 0)} />
          </div>
        )}
      </section>

      {/* D. Sources */}
      <section className="glass rounded-2xl p-5 space-y-3">
        <h3 className="font-semibold text-slate-200">ספריית מקורות</h3>
        <ul className="grid sm:grid-cols-2 gap-2">
          {SOURCES.map((s) => (
            <li key={s.href}>
              <a
                href={s.href}
                target="_blank"
                rel="noopener noreferrer"
                className="block rounded-xl px-3 py-2.5 text-sm border border-slate-700/60 bg-slate-900/40 hover:border-amber-500/40 hover:text-amber-100 text-slate-300 transition-colors"
              >
                {s.title} ↗
              </a>
            </li>
          ))}
        </ul>
        <p className="text-xs text-slate-500 pt-1">
          עוד ~124 מקורות בתיקיות המקוננות (חלקי ROI/מודלים) — לא מוטמעים באב־טיפוס
        </p>
      </section>
    </div>
  )
}

function HeroCard({
  label,
  value,
  sub,
  accent,
}: {
  label: string
  value: string
  sub: string
  accent: 'slate' | 'amber' | 'emerald'
}) {
  const ring =
    accent === 'emerald'
      ? 'border-emerald-500/40 bg-emerald-950/30'
      : accent === 'amber'
        ? 'border-amber-500/40 bg-amber-950/30'
        : 'border-slate-600/50 bg-slate-900/50'
  const num =
    accent === 'emerald' ? 'text-emerald-300' : accent === 'amber' ? 'text-amber-200' : 'text-slate-100'
  return (
    <div className={`glass rounded-2xl p-4 border ${ring}`}>
      <p className="text-xs text-slate-400 mb-1">{label}</p>
      <p className={`text-xl font-bold font-mono ${num}`}>{value} ₪</p>
      <p className="text-xs text-slate-500 mt-1">{sub}</p>
    </div>
  )
}

function MiniStat({ label, value, warn }: { label: string; value: string; warn?: boolean }) {
  return (
    <div className="rounded-xl bg-slate-900/60 border border-slate-700/50 px-3 py-2.5">
      <p className="text-[11px] text-slate-500">{label}</p>
      <p className={`text-sm font-mono mt-0.5 ${warn ? 'text-amber-300' : 'text-slate-200'}`}>{value}</p>
    </div>
  )
}

function Row({
  label,
  a,
  b,
  c,
  bold,
  dim,
  warn,
  highlight,
}: {
  label: string
  a: number | null
  b: number | null
  c: number | null
  bold?: boolean
  dim?: boolean
  warn?: boolean
  highlight?: boolean
}) {
  const cell = (v: number | null) =>
    v === null ? (
      <span className="text-slate-600">—</span>
    ) : (
      <span className="font-mono">{ILS(Math.round(v))} ₪</span>
    )
  return (
    <tr
      className={
        (highlight ? 'bg-emerald-950/20 ' : '') +
        (warn ? 'text-amber-200/90 ' : dim ? 'text-slate-400 ' : 'text-slate-200 ') +
        (bold ? 'font-semibold ' : '')
      }
    >
      <td className="px-4 py-2.5 text-right">{label}</td>
      <td className="px-4 py-2.5 text-left">{cell(a)}</td>
      <td className="px-4 py-2.5 text-left">{cell(b)}</td>
      <td className="px-4 py-2.5 text-left">{cell(c)}</td>
    </tr>
  )
}

function SliderField({
  id,
  label,
  value,
  min,
  max,
  step,
  display,
  onChange,
}: {
  id: string
  label: string
  value: number
  min: number
  max: number
  step: number
  display: string
  onChange: (v: number) => void
}) {
  return (
    <div>
      <div className="flex justify-between text-sm mb-2">
        <label htmlFor={id}>{label}</label>
        <span className="font-mono text-amber-200">{display}</span>
      </div>
      <input
        id={id}
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="w-full accent-emerald-500"
      />
    </div>
  )
}
