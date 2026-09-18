import { useEffect, useState } from 'react'
import { health } from './api/client'
import ApiLab from './components/ApiLab'
import CapitalTab from './tabs/CapitalTab'
import ChrIndexTab from './tabs/ChrIndexTab'
import PlaceholderTab from './tabs/PlaceholderTab'
import SanctuaryTab from './tabs/SanctuaryTab'

type TabId =
  | 'knowledge'
  | 'welfare'
  | 'core'
  | 'capital'
  | 'chrIndex'
  | 'journey'
  | 'ops'
  | 'philosophy'
  | 'market'
  | 'health'
  | 'sources'

const TABS: { id: TabId; label: string }[] = [
  { id: 'knowledge', label: 'מחברת 01 - ידע ומדיה' },
  { id: 'welfare', label: 'מחברת 02 - רווחה / נפש / חוסן' },
  { id: 'core', label: 'מחברת 03 - ליבה וארכיטקטורה' },
  { id: 'capital', label: 'מחברת 04 - הון אנושי ופיננסים' },
  { id: 'chrIndex', label: 'מדד CHR / חוב אושר' },
  { id: 'journey', label: 'מחברת 05 - מסע עובד והתפתחות' },
  { id: 'ops', label: 'מחברת 06 - תפעול ו־Playbooks' },
  { id: 'philosophy', label: 'מחברת 07 - פילוסופיה ואתיקה' },
  { id: 'market', label: 'מחברת 08 - שוק ו־Case Studies' },
  { id: 'health', label: 'מחברת 10 - מוצר ובריאות (HealthHarbor)' },
  { id: 'sources', label: 'מחברת 11 - ספריית מקורות' },
]

const TAB_IDS = new Set<string>(TABS.map((t) => t.id))
const DEFAULT_TAB: TabId = 'chrIndex'

function tabFromHash(): TabId {
  const raw = decodeURIComponent(window.location.hash.replace(/^#/, ''))
  return TAB_IDS.has(raw) ? (raw as TabId) : DEFAULT_TAB
}

export default function App() {
  const [tab, setTab] = useState<TabId>(tabFromHash)
  const [apiOnline, setApiOnline] = useState<boolean | null>(null)

  useEffect(() => {
    if (!window.location.hash) {
      history.replaceState(null, '', `#${DEFAULT_TAB}`)
    }
    const onHash = () => setTab(tabFromHash())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  useEffect(() => {
    const ac = new AbortController()
    void health().then((res) => {
      if (!ac.signal.aborted) setApiOnline(res.ok)
    })
    return () => ac.abort()
  }, [])

  function selectTab(id: TabId) {
    setTab(id)
    if (window.location.hash.replace(/^#/, '') !== id) {
      history.replaceState(null, '', `#${id}`)
    }
  }

  return (
    <div dir="rtl" className="min-h-screen bg-slate-950 text-slate-100">
      <div className="border-b border-slate-800/80 bg-slate-950/90 sticky top-0 z-20 backdrop-blur">
        <div className="max-w-6xl mx-auto px-4 py-3 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-lg font-bold tracking-tight text-amber-100">CHR-ETRS</h1>
            <p className="text-xs text-slate-500">Sprint 1 Prototype</p>
          </div>
          <span className="text-xs px-2 py-1 rounded-md bg-slate-800 text-slate-400 border border-slate-700">
            {apiOnline === false ? 'client-only · מחשבון בדפדפן' : 'mock · in-memory'}
          </span>
        </div>
        <nav className="max-w-6xl mx-auto px-2 pb-2 overflow-x-auto">
          <ul className="flex gap-1 min-w-max">
            {TABS.map((t) => (
              <li key={t.id}>
                <button
                  type="button"
                  onClick={() => selectTab(t.id)}
                  className={
                    'px-3 py-1.5 rounded-lg text-xs whitespace-nowrap transition-colors ' +
                    (tab === t.id
                      ? 'bg-amber-500/20 text-amber-200 border border-amber-500/40'
                      : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/60 border border-transparent')
                  }
                >
                  {t.label}
                </button>
              </li>
            ))}
          </ul>
        </nav>
      </div>

      <main className="max-w-6xl mx-auto px-4 py-6 space-y-4">
        <ApiLab />
        {tab === 'welfare' && <SanctuaryTab />}
        {tab === 'knowledge' && <PlaceholderTab title="מחברת 01 - ידע ומדיה" notebookHint="ידע ארגוני, מדיה ותוכן" />}
        {tab === 'core' && <PlaceholderTab title="מחברת 03 - ליבה וארכיטקטורה" notebookHint="ארכיטקטורת CHR-ETRS" />}
        {tab === 'capital' && <CapitalTab />}
        {tab === 'chrIndex' && <ChrIndexTab />}
        {tab === 'journey' && <PlaceholderTab title="מחברת 05 - מסע עובד והתפתחות" notebookHint="מסלולי התפתחות" />}
        {tab === 'ops' && <PlaceholderTab title="מחברת 06 - תפעול ו־Playbooks" notebookHint="תפעול ו־Playbooks" />}
        {tab === 'philosophy' && <PlaceholderTab title="מחברת 07 - פילוסופיה ואתיקה" notebookHint="אתיקה ופרטיות" />}
        {tab === 'market' && <PlaceholderTab title="מחברת 08 - שוק ו־Case Studies" notebookHint="שוק ומקרי בוחן" />}
        {tab === 'health' && <PlaceholderTab title="מחברת 10 - מוצר ובריאות (HealthHarbor)" notebookHint="HealthHarbor" />}
        {tab === 'sources' && <PlaceholderTab title="מחברת 11 - ספריית מקורות" notebookHint="מקורות" />}
      </main>
    </div>
  )
}
