import { useState } from 'react'
import { assignTask, type AssignTaskResult } from '../api/client'

type Panel = { status: number; body: AssignTaskResult }

export default function SmartPacingScreen({ userId }: { userId: string }) {
  const [name, setName] = useState('סקירת מסמך קצרה')
  const [cost, setCost] = useState(1)
  const [chunkable, setChunkable] = useState(true)
  const [graded, setGraded] = useState(false)
  const [busy, setBusy] = useState(false)
  const [panel, setPanel] = useState<Panel | null>(null)

  async function submit() {
    setBusy(true)
    const res = await assignTask({
      assignee_id: userId,
      task_name: name,
      complexity_spoon_cost: cost,
      is_chunkable: chunkable,
      attempt_graded_load_increase: graded,
    })
    setBusy(false)
    setPanel({ status: res.status, body: res.data })
  }

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <header className="glass rounded-2xl p-5">
        <p className="text-xs text-amber-300/80">מסך 4 · Happy Path</p>
        <h2 className="text-2xl font-bold text-amber-100 mt-1">קצב חכם / Anti-GET</h2>
        <p className="text-sm text-slate-400 mt-2">
          הקצאת משימה דרך POST /tasks/assign. מתחת ל־3 כפיות או HRV מתחת ל־40ms חוזר 403. ניסיון להגדיל עומס
          הדרגתית בזמן סיכון חוזר 409 Anti-GET — והמערכת דורשת פירוק למיקרו-יחידות.
        </p>
      </header>

      <section className="glass rounded-2xl p-5 space-y-4">
        <label className="block text-sm space-y-1">
          <span className="text-slate-400">שם משימה</span>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2"
          />
        </label>
        <label className="block text-sm space-y-1">
          <span className="text-slate-400">עלות בכפיות ({cost})</span>
          <input
            type="range"
            min={1}
            max={6}
            value={cost}
            onChange={(e) => setCost(Number(e.target.value))}
            className="w-full accent-amber-500"
          />
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={chunkable} onChange={(e) => setChunkable(e.target.checked)} />
          המשימה ניתנת לפירוק (chunkable)
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={graded} onChange={(e) => setGraded(e.target.checked)} />
          נסה הגדלת עומס הדרגתית (Anti-GET)
        </label>
        <button
          type="button"
          disabled={busy || !name.trim()}
          onClick={() => void submit()}
          className="px-4 py-2 rounded-lg bg-amber-600/90 hover:bg-amber-500 disabled:opacity-50 text-sm font-medium"
        >
          {busy ? 'שולח…' : 'הקצה משימה'}
        </button>
        <p className="text-xs text-slate-500">
          כדי לראות 403/409 בחרו בפרופיל «כפיות נמוכות». פרופיל האנרגיה התקינה אמור לעבור ב־200 בשעות העבודה.
        </p>
      </section>

      {panel && <ResultPanel status={panel.status} body={panel.body} />}
    </div>
  )
}

function ResultPanel({ status, body }: { status: number; body: AssignTaskResult }) {
  if (status === 200) {
    return (
      <section className="rounded-2xl p-5 border border-emerald-500/40 bg-emerald-950/40 space-y-1">
        <h3 className="font-semibold text-emerald-200">המשימה שויכה · 200</h3>
        <p className="text-sm text-slate-300">קצב: {body.pacing_status}. מזהה {body.task_id}.</p>
      </section>
    )
  }
  if (status === 409) {
    return (
      <section className="rounded-2xl p-5 border border-amber-500/50 bg-amber-950/40 space-y-2">
        <h3 className="font-semibold text-amber-200">Anti-GET · 409</h3>
        <p className="text-sm text-slate-200">
          אסור לדחוף עומס הדרגתי כשהכפיות או ה־HRV מתחת לסף. פרקו את העבודה למיקרו-יחידות וחזרו כשהמעגל נסגר.
        </p>
        <p className="text-xs font-mono text-slate-400">{body.error_code}: {body.message}</p>
      </section>
    )
  }
  if (status === 403) {
    const disconnect = body.error_code === 'Right_To_Disconnect_Violation'
    return (
      <section className="rounded-2xl p-5 border border-red-500/40 bg-red-950/40 space-y-2">
        <h3 className="font-semibold text-red-200">
          {disconnect ? 'זכות הניתוק · 403' : 'מעגל מגן · 403'}
        </h3>
        <p className="text-sm text-slate-200">
          {disconnect
            ? 'בין 19:00 ל־07:00 אסור לדחוף משימה. החריגה נרשמת כלדג׳ר ומפעילה מס קיפוח.'
            : 'ההקצאה נחסמה: כפיות מתחת ל־3 או HRV מתחת ל־40ms. אין עקיפה מכיוון המנהל.'}
        </p>
        <p className="text-xs font-mono text-slate-400">{body.error_code}: {body.message}</p>
      </section>
    )
  }
  return (
    <section className="glass rounded-2xl p-5 text-sm">
      HTTP {status}
      <pre className="mt-2 text-xs text-slate-400 whitespace-pre-wrap">{JSON.stringify(body, null, 2)}</pre>
    </section>
  )
}
