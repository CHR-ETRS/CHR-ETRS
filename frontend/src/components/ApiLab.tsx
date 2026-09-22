import { useState } from 'react'
import { analyzeSentiment, assignTask, getSpoonsBudget, managerDashboard } from '../api/client'

type Result = { label: string; status: number; body: unknown }

const ORG = '11111111-1111-4111-8111-111111111111'

export default function ApiLab() {
  const [open, setOpen] = useState(false)
  const [results, setResults] = useState<Result[]>([])
  const [busy, setBusy] = useState(false)

  async function runAll() {
    setBusy(true)
    const out: Result[] = []
    const spoons = await getSpoonsBudget('emp-hope')
    out.push({ label: 'GET /telemetry/spoons-budget/emp-hope', status: spoons.status, body: spoons.data })

    const sent = await analyzeSentiment({
      text_content: 'הכל בסדר, רק חייב עכשיו',
      source_channel: 'Slack',
      user_id: 'emp-hope',
    })
    out.push({ label: 'POST /cringe/analyze-sentiment', status: sent.status, body: sent.data })

    const task = await assignTask({
      assignee_id: 'emp-low',
      task_name: 'עומס',
      complexity_spoon_cost: 1,
      attempt_graded_load_increase: true,
    })
    out.push({ label: 'POST /tasks/assign (Anti-GET)', status: task.status, body: task.data })

    const veil = await managerDashboard(ORG, 'tiny')
    out.push({ label: 'GET /manager/dashboard tiny', status: veil.status, body: veil.data })

    const dash = await managerDashboard(ORG, 'rd-core')
    out.push({ label: 'GET /manager/dashboard rd-core', status: dash.status, body: dash.data })

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
        <span>מעבדה — נתיבי OpenAPI</span>
        <span>{open ? '▲' : '▼'}</span>
      </button>
      {open && (
        <div className="p-4 border-t border-slate-700/50 space-y-3">
          <button
            type="button"
            disabled={busy}
            onClick={() => void runAll()}
            className="px-4 py-2 rounded-lg bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-sm font-medium"
          >
            {busy ? 'רץ…' : 'הרץ בדיקת עשן'}
          </button>
          <div className="space-y-2 max-h-64 overflow-auto text-xs font-mono">
            {results.map((r) => (
              <div key={r.label} className="rounded-lg bg-slate-900/80 p-2 border border-slate-700">
                <div className="flex gap-2 mb-1">
                  <span className="text-amber-300">{r.label}</span>
                  <span className={r.status < 300 ? 'text-emerald-400' : 'text-amber-400'}>{r.status}</span>
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
