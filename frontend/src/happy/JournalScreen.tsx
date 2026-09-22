import { useCallback, useEffect, useState } from 'react'
import { createJournal, listJournal, type JournalEntry } from '../api/client'

export default function JournalScreen({ userId }: { userId: string }) {
  const [entries, setEntries] = useState<JournalEntry[]>([])
  const [mirror, setMirror] = useState('')
  const [offload, setOffload] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const refresh = useCallback(async () => {
    const res = await listJournal(userId)
    if (!res.ok) {
      setError(`HTTP ${res.status}`)
      setEntries([])
      return
    }
    setError(null)
    setEntries(res.data.entries)
  }, [userId])

  useEffect(() => {
    void refresh()
  }, [refresh])

  async function submit() {
    setBusy(true)
    const res = await createJournal({
      user_id: userId,
      hallway_mirror_response: mirror.trim(),
      relational_offloading_text: offload.trim() || undefined,
    })
    setBusy(false)
    if (!res.ok) {
      setError((res.data as { message?: string }).message ?? `HTTP ${res.status}`)
      return
    }
    setMirror('')
    setOffload('')
    await refresh()
  }

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <header className="glass rounded-2xl p-5">
        <p className="text-xs text-amber-300/80">מסך 5 · Happy Path</p>
        <h2 className="text-2xl font-bold text-amber-100 mt-1">יומן שביל</h2>
        <p className="text-sm text-slate-400 mt-2">
          כספת פרטית של העובד בלבד. הרשומות לא נחשפות בדשבורד המנהל. סיבת וטו ריבוני, אם ננעלה, נשארת חתומה.
        </p>
      </header>

      <section className="glass rounded-2xl p-5 space-y-3 border border-emerald-500/20">
        <h3 className="font-semibold">רשומה חדשה</h3>
        <label className="block text-sm space-y-1">
          <span className="text-slate-400">מראת מסדרון</span>
          <textarea
            value={mirror}
            onChange={(e) => setMirror(e.target.value)}
            rows={3}
            className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2"
            placeholder="מה ראיתי היום בלי לפתור את זה"
          />
        </label>
        <label className="block text-sm space-y-1">
          <span className="text-slate-400">פריקה יחסית (רשות)</span>
          <textarea
            value={offload}
            onChange={(e) => setOffload(e.target.value)}
            rows={2}
            className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2"
          />
        </label>
        <button
          type="button"
          disabled={busy || !mirror.trim()}
          onClick={() => void submit()}
          className="px-4 py-2 rounded-lg bg-emerald-600/90 hover:bg-emerald-500 disabled:opacity-50 text-sm font-medium"
        >
          {busy ? 'שומר…' : 'שמור בכספת'}
        </button>
        {error && <p className="text-sm text-red-300">{error}</p>}
      </section>

      <section className="space-y-2">
        {entries.length === 0 && <p className="text-sm text-slate-500">אין רשומות עדיין.</p>}
        {[...entries].reverse().map((entry) => (
          <article key={entry.entry_id} className="glass rounded-xl p-4 space-y-1">
            <div className="flex justify-between text-xs text-slate-500">
              <span>{new Date(entry.created_at).toLocaleString('he-IL')}</span>
              {entry.sealed && <span className="text-amber-300">חתום · הסיבה לא מוצגת</span>}
            </div>
            <p className="text-slate-100">{entry.hallway_mirror_response}</p>
            {entry.relational_offloading_text && (
              <p className="text-sm text-slate-400">{entry.relational_offloading_text}</p>
            )}
          </article>
        ))}
      </section>
    </div>
  )
}
