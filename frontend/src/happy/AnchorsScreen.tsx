import { useEffect, useState } from 'react'
import { getAnchors, putAnchors, type Anchor, type AnchorsPayload } from '../api/client'

const LIGHTING: Anchor['type_lighting'][] = ['Authority', 'Soft', 'Task']
const GATES: Anchor['exposure_gate'][] = ['Closed', 'Filtered', 'Open']

const LIGHT_HE: Record<Anchor['type_lighting'], string> = {
  Authority: 'Authority · נברשת',
  Soft: 'Soft · כתר',
  Task: 'Task · משימה',
}

export default function AnchorsScreen({ userId }: { userId: string }) {
  const [data, setData] = useState<AnchorsPayload | null>(null)
  const [lighting, setLighting] = useState<Anchor['type_lighting']>('Authority')
  const [territory, setTerritory] = useState('')
  const [gate, setGate] = useState<Anchor['exposure_gate']>('Filtered')
  const [status, setStatus] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let cancelled = false
    setStatus(null)
    void getAnchors(userId).then((res) => {
      if (cancelled) return
      if (!res.ok) {
        setStatus(`שגיאה ${res.status}`)
        setData(null)
        return
      }
      setData(res.data)
      const first = res.data.anchors[0]
      if (first) {
        setLighting(first.type_lighting)
        setTerritory(first.territory_schema ?? '')
        setGate(first.exposure_gate)
      } else {
        setTerritory('')
      }
    })
    return () => {
      cancelled = true
    }
  }, [userId])

  async function save() {
    setBusy(true)
    setStatus(null)
    const res = await putAnchors(userId, [
      { type_lighting: lighting, territory_schema: territory, exposure_gate: gate },
    ])
    setBusy(false)
    if (!res.ok) {
      setStatus(`שמירה נכשלה (${res.status})`)
      return
    }
    setData(res.data)
    setStatus('העוגן נשמר במרחב האישי.')
  }

  const asset = data?.employee_value_asset

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <header className="glass rounded-2xl p-5">
        <p className="text-xs text-amber-300/80">מסך 1 · Happy Path</p>
        <h2 className="text-2xl font-bold text-amber-100 mt-1">עוגנים</h2>
        <p className="text-sm text-slate-400 mt-2">
          כיול עוגן אישי — תאורה, טריטוריה ושער חשיפה — לצד נכס הערך של העובד. הנתונים פרטיים לעובד.
        </p>
      </header>

      {asset && (
        <section className="grid sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <Stat label="שווי נכס (CAPEX)" value={`${asset.asset_value_capex.toLocaleString('he-IL')} ₪`} />
          <Stat label="עלות ישירה" value={`${asset.direct_cost_opex.toLocaleString('he-IL')} ₪`} />
          <Stat label="מקדם אלפא" value={asset.productivity_alpha_factor.toFixed(2)} />
          <Stat label="חוב אושר" value={`${asset.happiness_debt_liability.toLocaleString('he-IL')} ₪`} />
        </section>
      )}

      <section className="glass rounded-2xl p-5 space-y-4">
        <h3 className="font-semibold text-slate-100">עריכת עוגן</h3>
        <label className="block text-sm space-y-1">
          <span className="text-slate-400">סוג תאורה</span>
          <select
            value={lighting}
            onChange={(e) => setLighting(e.target.value as Anchor['type_lighting'])}
            className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2"
          >
            {LIGHTING.map((v) => (
              <option key={v} value={v}>
                {LIGHT_HE[v]}
              </option>
            ))}
          </select>
        </label>
        <label className="block text-sm space-y-1">
          <span className="text-slate-400">סכמת טריטוריה</span>
          <textarea
            value={territory}
            onChange={(e) => setTerritory(e.target.value)}
            rows={3}
            className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2"
            placeholder="איפה הגוף נרגע — חדר, אור, מרחק מהמסדרון"
          />
        </label>
        <label className="block text-sm space-y-1">
          <span className="text-slate-400">שער חשיפה</span>
          <select
            value={gate}
            onChange={(e) => setGate(e.target.value as Anchor['exposure_gate'])}
            className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2"
          >
            {GATES.map((v) => (
              <option key={v} value={v}>
                {v}
              </option>
            ))}
          </select>
        </label>
        <button
          type="button"
          disabled={busy}
          onClick={() => void save()}
          className="px-4 py-2 rounded-lg bg-amber-600/90 hover:bg-amber-500 disabled:opacity-50 text-sm font-medium"
        >
          {busy ? 'שומר…' : 'שמור עוגן'}
        </button>
        {status && <p className="text-sm text-emerald-300">{status}</p>}
      </section>

      <section className="space-y-2">
        <h3 className="text-sm text-slate-400">עוגנים שמורים</h3>
        {(data?.anchors ?? []).map((a) => (
          <article key={a.anchor_id} className="glass rounded-xl px-4 py-3 text-sm flex justify-between gap-3">
            <div>
              <p className="text-amber-100">{LIGHT_HE[a.type_lighting]}</p>
              <p className="text-slate-400">{a.territory_schema || '—'}</p>
            </div>
            <span className="text-xs text-slate-500">{a.exposure_gate}</span>
          </article>
        ))}
        {data && data.anchors.length === 0 && <p className="text-sm text-slate-500">אין עוגנים עדיין.</p>}
      </section>
    </div>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="glass rounded-xl p-3">
      <p className="text-xs text-slate-500">{label}</p>
      <p className="font-mono text-amber-100 mt-1">{value}</p>
    </div>
  )
}
