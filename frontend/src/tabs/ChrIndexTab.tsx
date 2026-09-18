import { useMemo, useState } from 'react'
import {
  ASSUMPTIONS_HE,
  DEFAULT_INPUTS,
  PRESETS,
  computeChrIndex,
  normalizeWeights,
  type ChrIndexInputs,
  type PresetId,
} from '../lib/chrIndexCalc'

const ILS = (n: number, digits = 0) =>
  n.toLocaleString('he-IL', { maximumFractionDigits: digits, minimumFractionDigits: digits })

const pct = (n: number, digits = 0) =>
  `${n.toLocaleString('he-IL', { maximumFractionDigits: digits, minimumFractionDigits: digits })}%`

export default function ChrIndexTab() {
  const [inputs, setInputs] = useState<ChrIndexInputs>({ ...DEFAULT_INPUTS })
  const [activePreset, setActivePreset] = useState<PresetId | 'custom'>('custom')

  const result = useMemo(() => computeChrIndex(inputs), [inputs])
  const weightSum = inputs.wO + inputs.wS + inputs.wH + inputs.wE
  const weightsOk = Math.abs(weightSum - 1) < 0.02

  function patch(partial: Partial<ChrIndexInputs>) {
    setActivePreset('custom')
    setInputs((prev) => ({ ...prev, ...partial }))
  }

  function loadPreset(id: PresetId) {
    setActivePreset(id)
    setInputs({ ...PRESETS[id].inputs })
  }

  function normalizeWeightsNow() {
    const w = normalizeWeights(inputs.wO, inputs.wS, inputs.wH, inputs.wE)
    patch({ wO: round4(w.wO), wS: round4(w.wS), wH: round4(w.wH), wE: round4(w.wE) })
  }

  return (
    <div className="space-y-6">
      <header className="glass rounded-2xl p-5 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 className="text-2xl font-bold text-amber-100">מדד CHR / חוב אושר</h2>
          <p className="text-slate-400 text-sm mt-1">
            מחשבון אישי־צוותי · EBITDA מותאם · Integrity · מודל לדיון (לא ייעוץ קליני)
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

      {/* Outputs hero */}
      <section className="grid sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <GaugeCard
          label="מדד CHR"
          value={result.chrIndex}
          max={100}
          suffix="/100"
          accent={result.chrIndex >= 70 ? 'emerald' : result.chrIndex >= 45 ? 'amber' : 'rose'}
        />
        <GaugeCard
          label="חוב אושר — חומרה"
          value={result.happinessDebtSeverity}
          max={100}
          suffix="/100"
          accent={
            result.happinessDebtSeverity <= 25
              ? 'emerald'
              : result.happinessDebtSeverity <= 50
                ? 'amber'
                : 'rose'
          }
          sub={`${ILS(Math.round(result.happinessDebtIls))} ₪`}
        />
        <HeroStat
          label="EBITDA מותאם"
          value={`${ILS(Math.round(result.ebitdaAdjusted))} ₪`}
          sub={`נומינלי ${ILS(Math.round(inputs.ebitdaNominal))} · RoH ${ILS(Math.round(inputs.roh))} · DT −${ILS(Math.round(result.dt))}`}
          accent="emerald"
        />
        <HeroStat
          label="Integrity"
          value={`${(result.integrity * 100).toFixed(0)}%`}
          sub={
            result.happinessWashing
              ? `⚠ Happiness-washing (סף ${(inputs.integrityThreshold * 100).toFixed(0)}%)`
              : `מעל סף ${(inputs.integrityThreshold * 100).toFixed(0)}%`
          }
          accent={result.happinessWashing ? 'rose' : 'emerald'}
        />
      </section>

      {(result.maskingWarning || result.happinessWashing) && (
        <div className="glass rounded-2xl px-4 py-3 border border-amber-500/40 bg-amber-950/30 text-sm text-amber-100 space-y-1">
          {result.maskingWarning && (
            <p>
              <strong>Glass Box / מיסוך:</strong> אושר סקר מוצג ≈ {result.surveyDisplayed.toFixed(0)} מול CHR חי ≈{' '}
              {result.chrIndex.toFixed(0)} — סיכון happiness-washing בסקרים.
            </p>
          )}
          {result.happinessWashing && (
            <p>
              <strong>Integrity נמוך:</strong> פער בין תרבות מוצהרת ({inputs.declaredCulture}) ל־CHR חי (
              {(result.livedChr * 100).toFixed(0)}).
            </p>
          )}
        </div>
      )}

      <p className="glass rounded-2xl px-4 py-3 text-sm text-slate-300 leading-relaxed border border-slate-700/40">
        {result.summaryHe}
      </p>

      <div className="grid lg:grid-cols-2 gap-6">
        {/* Dimensions + weights */}
        <section className="glass rounded-2xl p-5 space-y-4">
          <h3 className="font-semibold text-slate-200">ממדי CHR (O / S / H / E)</h3>
          <DimSlider id="O" label="O — אובייקטיבי / חומרי" value={inputs.O} onChange={(v) => patch({ O: v })} />
          <DimSlider id="S" label="S — חברתי / שייכות" value={inputs.S} onChange={(v) => patch({ S: v })} />
          <DimSlider id="H" label="H — הדוני (קצר טווח)" value={inputs.H} onChange={(v) => patch({ H: v })} />
          <DimSlider id="E" label="E — אודאימוני / משמעות" value={inputs.E} onChange={(v) => patch({ E: v })} />

          <div className="pt-2 border-t border-slate-800 space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h4 className="text-sm text-slate-300">משקלים (סכום → 1)</h4>
              <div className="flex items-center gap-2">
                <span
                  className={
                    'text-xs font-mono px-2 py-0.5 rounded border ' +
                    (weightsOk
                      ? 'border-emerald-500/40 text-emerald-300'
                      : 'border-amber-500/40 text-amber-200')
                  }
                >
                  Σ {weightSum.toFixed(2)}
                </span>
                {!weightsOk && (
                  <button
                    type="button"
                    onClick={normalizeWeightsNow}
                    className="text-xs px-2 py-1 rounded border border-slate-600 hover:border-amber-500/40 text-slate-300"
                  >
                    נרמל ל־1
                  </button>
                )}
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <NumField label="wO" value={inputs.wO} step={0.05} min={0} max={1} onChange={(v) => patch({ wO: v })} />
              <NumField label="wS" value={inputs.wS} step={0.05} min={0} max={1} onChange={(v) => patch({ wS: v })} />
              <NumField label="wH" value={inputs.wH} step={0.05} min={0} max={1} onChange={(v) => patch({ wH: v })} />
              <NumField label="wE" value={inputs.wE} step={0.05} min={0} max={1} onChange={(v) => patch({ wE: v })} />
            </div>
            <WeightBars weights={result.weights} />
          </div>

          <DimSlider
            id="masking"
            label="גורם מיסוך (masking) 0–1"
            value={inputs.masking * 100}
            onChange={(v) => patch({ masking: v / 100 })}
            display={`${inputs.masking.toFixed(2)}`}
          />
          <DimSlider
            id="declared"
            label="תרבות מוצהרת (Declared Culture)"
            value={inputs.declaredCulture}
            onChange={(v) => patch({ declaredCulture: v })}
          />
          <NumField
            label="סף Integrity"
            value={inputs.integrityThreshold}
            step={0.05}
            min={0}
            max={1}
            onChange={(v) => patch({ integrityThreshold: v })}
          />
        </section>

        {/* Finance / debt params */}
        <section className="glass rounded-2xl p-5 space-y-4">
          <h3 className="font-semibold text-slate-200">פיננסים וחוב אושר</h3>
          <SliderField
            id="headcount"
            label="מספר עובדים"
            value={inputs.headcount}
            min={10}
            max={2000}
            step={10}
            display={ILS(inputs.headcount)}
            onChange={(v) => patch({ headcount: v })}
          />
          <SliderField
            id="salary"
            label="שכר חודשי ממוצע (₪)"
            value={inputs.avgMonthlySalary}
            min={8000}
            max={50000}
            step={500}
            display={ILS(inputs.avgMonthlySalary)}
            onChange={(v) => patch({ avgMonthlySalary: v })}
          />
          <NumField
            label="EBITDA נומינלי (₪)"
            value={inputs.ebitdaNominal}
            step={100000}
            min={0}
            max={500000000}
            onChange={(v) => patch({ ebitdaNominal: v })}
          />
          <NumField
            label="RoH — Return on Happiness (₪)"
            value={inputs.roh}
            step={100000}
            min={0}
            max={100000000}
            onChange={(v) => patch({ roh: v })}
          />
          <SliderField
            id="dtPct"
            label="DT % (מס קיפוח / haircut פרודוקטיביות)"
            value={inputs.dtPct}
            min={0}
            max={0.4}
            step={0.01}
            display={pct(inputs.dtPct * 100)}
            onChange={(v) => patch({ dtPct: v })}
          />
          <SliderField
            id="deprivation"
            label="שיעור קיפוח (deprivation)"
            value={inputs.deprivationPct}
            min={0}
            max={0.6}
            step={0.01}
            display={pct(inputs.deprivationPct * 100)}
            onChange={(v) => patch({ deprivationPct: v })}
          />
          <SliderField
            id="fairness"
            label="פער הוגנות (effort–reward)"
            value={inputs.fairnessGap}
            min={0}
            max={1}
            step={0.01}
            display={inputs.fairnessGap.toFixed(2)}
            onChange={(v) => patch({ fairnessGap: v })}
          />
          <SliderField
            id="hours"
            label="שעות שבועיות בפועל"
            value={inputs.actualWeeklyHours}
            min={40}
            max={70}
            step={1}
            display={String(inputs.actualWeeklyHours)}
            onChange={(v) => patch({ actualWeeklyHours: v })}
          />
          <SliderField
            id="turnover"
            label="שיעור תחלופה שנתי"
            value={inputs.turnoverRate}
            min={0}
            max={0.5}
            step={0.01}
            display={pct(inputs.turnoverRate * 100)}
            onChange={(v) => patch({ turnoverRate: v })}
          />
          <NumField
            label="עלות תחלופה × שכר שנתי"
            value={inputs.turnoverCostMultiple}
            step={0.1}
            min={0}
            max={3}
            onChange={(v) => patch({ turnoverCostMultiple: v })}
          />
          <NumField
            label="מקדם חוב הוגנות"
            value={inputs.fairnessDebtFactor}
            step={0.01}
            min={0}
            max={0.5}
            onChange={(v) => patch({ fairnessDebtFactor: v })}
          />
        </section>
      </div>

      {/* Charts */}
      <section className="grid md:grid-cols-2 gap-4">
        <div className="glass rounded-2xl p-5 space-y-3">
          <h3 className="font-semibold text-slate-200">מפל EBITDA מותאם</h3>
          <WaterfallChart
            items={[
              { label: 'נומינלי', value: inputs.ebitdaNominal, base: true },
              { label: '+ RoH', value: inputs.roh, positive: true },
              { label: '− DT', value: -result.dt, positive: false },
              { label: 'מותאם', value: result.ebitdaAdjusted, base: true },
            ]}
          />
        </div>
        <div className="glass rounded-2xl p-5 space-y-3">
          <h3 className="font-semibold text-slate-200">פירוק חוב אושר (₪)</h3>
          <DebtBars
            items={[
              { label: 'הוגנות', value: result.fairnessDebt },
              { label: 'שכר מדולל', value: result.dilutedBurden },
              { label: 'תחלופה', value: result.turnoverPremium },
            ]}
          />
          <div className="grid grid-cols-3 gap-2 text-xs pt-2">
            <MiniStat label="שעתי נומינלי" value={`${result.dilutedWage.nominalHourly.toFixed(1)} ₪`} />
            <MiniStat label="שעתי מדולל" value={`${result.dilutedWage.dilutedHourly.toFixed(1)} ₪`} />
            <MiniStat label="שחיקת שכר" value={pct(result.dilutedWage.erosionPct)} warn />
          </div>
        </div>
      </section>

      <details className="glass rounded-2xl p-5 group">
        <summary className="cursor-pointer font-semibold text-slate-200 list-none flex items-center justify-between">
          <span>הנחות המודל</span>
          <span className="text-xs text-slate-500 group-open:hidden">לחצי לפתיחה</span>
        </summary>
        <ul className="mt-3 space-y-2 text-sm text-slate-400 list-disc pr-5 leading-relaxed">
          {ASSUMPTIONS_HE.map((a) => (
            <li key={a}>{a}</li>
          ))}
        </ul>
      </details>
    </div>
  )
}

function round4(n: number) {
  return Math.round(n * 10000) / 10000
}

function GaugeCard({
  label,
  value,
  max,
  suffix,
  accent,
  sub,
}: {
  label: string
  value: number
  max: number
  suffix: string
  accent: 'emerald' | 'amber' | 'rose'
  sub?: string
}) {
  const pctW = Math.min(100, Math.max(0, (value / max) * 100))
  const bar =
    accent === 'emerald' ? 'bg-emerald-500' : accent === 'amber' ? 'bg-amber-500' : 'bg-rose-500'
  const text =
    accent === 'emerald' ? 'text-emerald-300' : accent === 'amber' ? 'text-amber-200' : 'text-rose-300'
  return (
    <div className="glass rounded-2xl p-4 border border-slate-700/40 space-y-2">
      <p className="text-xs text-slate-400">{label}</p>
      <p className={`text-2xl font-bold font-mono ${text}`}>
        {value.toFixed(0)}
        <span className="text-sm text-slate-500 font-normal"> {suffix}</span>
      </p>
      <div className="h-2 rounded-full bg-slate-800 overflow-hidden">
        <div className={`h-full rounded-full ${bar} transition-all`} style={{ width: `${pctW}%` }} />
      </div>
      {sub && <p className="text-xs text-slate-500 font-mono">{sub}</p>}
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
  const num = accent === 'emerald' ? 'text-emerald-300' : accent === 'rose' ? 'text-rose-300' : 'text-amber-200'
  return (
    <div className={`glass rounded-2xl p-4 border ${ring}`}>
      <p className="text-xs text-slate-400 mb-1">{label}</p>
      <p className={`text-xl font-bold font-mono ${num}`}>{value}</p>
      <p className="text-xs text-slate-500 mt-1 leading-snug">{sub}</p>
    </div>
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

function DimSlider({
  id,
  label,
  value,
  onChange,
  display,
}: {
  id: string
  label: string
  value: number
  onChange: (v: number) => void
  display?: string
}) {
  return (
    <div>
      <div className="flex justify-between text-sm mb-1.5">
        <label htmlFor={id}>{label}</label>
        <span className="font-mono text-amber-200">{display ?? value.toFixed(0)}</span>
      </div>
      <input
        id={id}
        type="range"
        min={0}
        max={100}
        step={1}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="w-full accent-emerald-500"
      />
    </div>
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
      <div className="flex justify-between text-sm mb-1.5">
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

function NumField({
  label,
  value,
  step,
  min,
  max,
  onChange,
}: {
  label: string
  value: number
  step: number
  min: number
  max: number
  onChange: (v: number) => void
}) {
  return (
    <label className="block text-sm space-y-1">
      <span className="text-slate-400">{label}</span>
      <input
        type="number"
        value={value}
        step={step}
        min={min}
        max={max}
        onChange={(e) => onChange(Number(e.target.value))}
        className="w-full rounded-lg bg-slate-900/80 border border-slate-700 px-3 py-2 font-mono text-slate-100 text-sm focus:outline-none focus:border-amber-500/50"
      />
    </label>
  )
}

function WeightBars({
  weights,
}: {
  weights: { wO: number; wS: number; wH: number; wE: number }
}) {
  const rows = [
    { k: 'O', v: weights.wO, c: 'bg-sky-500' },
    { k: 'S', v: weights.wS, c: 'bg-violet-500' },
    { k: 'H', v: weights.wH, c: 'bg-amber-500' },
    { k: 'E', v: weights.wE, c: 'bg-emerald-500' },
  ]
  return (
    <div className="space-y-1.5">
      {rows.map((r) => (
        <div key={r.k} className="flex items-center gap-2 text-xs">
          <span className="w-4 text-slate-500">{r.k}</span>
          <div className="flex-1 h-2 rounded-full bg-slate-800 overflow-hidden">
            <div className={`h-full ${r.c}`} style={{ width: `${r.v * 100}%` }} />
          </div>
          <span className="w-10 text-left font-mono text-slate-400">{(r.v * 100).toFixed(0)}%</span>
        </div>
      ))}
    </div>
  )
}

function WaterfallChart({
  items,
}: {
  items: { label: string; value: number; base?: boolean; positive?: boolean }[]
}) {
  const maxAbs = Math.max(...items.map((i) => Math.abs(i.value)), 1)
  return (
    <div className="space-y-2">
      {items.map((item) => {
        const w = Math.min(100, (Math.abs(item.value) / maxAbs) * 100)
        const color = item.base
          ? 'bg-slate-400'
          : item.positive
            ? 'bg-emerald-500'
            : item.value < 0
              ? 'bg-rose-500'
              : 'bg-amber-500'
        return (
          <div key={item.label} className="flex items-center gap-3 text-sm">
            <span className="w-20 text-slate-400 shrink-0">{item.label}</span>
            <div className="flex-1 h-6 rounded bg-slate-900/80 overflow-hidden flex items-center">
              <div className={`h-full ${color} opacity-90`} style={{ width: `${w}%` }} />
            </div>
            <span className="w-28 text-left font-mono text-xs text-slate-300 shrink-0">
              {ILS(Math.round(item.value))} ₪
            </span>
          </div>
        )
      })}
    </div>
  )
}

function DebtBars({ items }: { items: { label: string; value: number }[] }) {
  const max = Math.max(...items.map((i) => i.value), 1)
  const colors = ['bg-amber-500', 'bg-violet-500', 'bg-rose-500']
  return (
    <div className="space-y-2">
      {items.map((item, idx) => (
        <div key={item.label} className="flex items-center gap-3 text-sm">
          <span className="w-24 text-slate-400 shrink-0">{item.label}</span>
          <div className="flex-1 h-6 rounded bg-slate-900/80 overflow-hidden">
            <div
              className={`h-full ${colors[idx % colors.length]} opacity-90`}
              style={{ width: `${(item.value / max) * 100}%` }}
            />
          </div>
          <span className="w-28 text-left font-mono text-xs text-slate-300 shrink-0">
            {ILS(Math.round(item.value))} ₪
          </span>
        </div>
      ))}
    </div>
  )
}
