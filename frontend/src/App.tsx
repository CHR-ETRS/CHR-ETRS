import { useState } from 'react'
import ApiLab from './components/ApiLab'
import AnchorsScreen from './happy/AnchorsScreen'
import DailyHubScreen from './happy/DailyHubScreen'
import { DEMO_USERS, type DemoUserId } from './happy/demoUsers'
import JournalScreen from './happy/JournalScreen'
import ResilienceScreen from './happy/ResilienceScreen'
import SmartPacingScreen from './happy/SmartPacingScreen'
import CapitalTab from './tabs/CapitalTab'
import ChrIndexTab from './tabs/ChrIndexTab'
import PlaceholderTab from './tabs/PlaceholderTab'
import SanctuaryTab from './tabs/SanctuaryTab'

type TabId =
  | 'anchors'
  | 'hub'
  | 'resilience'
  | 'pacing'
  | 'journal'
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

const HAPPY: { id: TabId; label: string }[] = [
  { id: 'anchors', label: '1 · עוגנים' },
  { id: 'hub', label: '2 · מרכז יומי' },
  { id: 'resilience', label: '3 · מטריצת חוסן' },
  { id: 'pacing', label: '4 · קצב חכם' },
  { id: 'journal', label: '5 · יומן שביל' },
]

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

export default function App() {
  const [tab, setTab] = useState<TabId>('anchors')
  const [userId, setUserId] = useState<DemoUserId>('emp-hope')

  return (
    <div dir="rtl" className="min-h-screen bg-slate-950 text-slate-100">
      <div className="border-b border-slate-800/80 bg-slate-950/90 sticky top-0 z-20 backdrop-blur">
        <div className="max-w-6xl mx-auto px-4 py-3 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-lg font-bold tracking-tight text-amber-100">CHR-ETRS</h1>
            <p className="text-xs text-slate-500">Happy Path · OpenAPI 1.1</p>
          </div>
          <label className="text-xs text-slate-400 flex items-center gap-2">
            פרופיל
            <select
              value={userId}
              onChange={(e) => setUserId(e.target.value as DemoUserId)}
              className="bg-slate-900 border border-slate-700 rounded-md px-2 py-1 text-slate-200"
            >
              {DEMO_USERS.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.label}
                </option>
              ))}
            </select>
          </label>
        </div>
        <nav className="max-w-6xl mx-auto px-2 pb-2 overflow-x-auto space-y-1">
          <ul className="flex gap-1 min-w-max">
            {HAPPY.map((t) => (
              <li key={t.id}>
                <button
                  type="button"
                  onClick={() => setTab(t.id)}
                  className={
                    'px-3 py-1.5 rounded-lg text-xs whitespace-nowrap transition-colors ' +
                    (tab === t.id
                      ? 'bg-emerald-500/20 text-emerald-200 border border-emerald-500/40'
                      : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/60 border border-transparent')
                  }
                >
                  {t.label}
                </button>
              </li>
            ))}
          </ul>
          <ul className="flex gap-1 min-w-max">
            {TABS.map((t) => (
              <li key={t.id}>
                <button
                  type="button"
                  onClick={() => setTab(t.id)}
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
        {tab === 'anchors' && <AnchorsScreen userId={userId} />}
        {tab === 'hub' && <DailyHubScreen userId={userId} />}
        {tab === 'resilience' && <ResilienceScreen userId={userId} />}
        {tab === 'pacing' && <SmartPacingScreen userId={userId} />}
        {tab === 'journal' && <JournalScreen userId={userId} />}
        {tab === 'welfare' && <SanctuaryTab />}
        {tab === 'knowledge' && <PlaceholderTab title="מחברת 01 - ידע ומדיה" notebookHint="ידע ארגוני, מדיה ותוכן" />}
        {tab === 'core' && <PlaceholderTab title="מחברת 03 - ליבה וארכיטקטורה" notebookHint="ארכיטקטורת CHR-ETRS" />}
        {tab === 'capital' && <CapitalTab />}
        {tab === 'chrIndex' && <ChrIndexTab />}
        {tab === 'journey' && <PlaceholderTab title="מחברת 05 - מסע עובד והתפתחות" notebookHint="מסלולי התפתחות" />}
        {tab === 'ops' && <PlaceholderTab title="מחברת 06 - תפעול ו־Playbooks" notebookHint="Playbooks" />}
        {tab === 'philosophy' && <PlaceholderTab title="מחברת 07 - פילוסופיה ואתיקה" notebookHint="אתיקה ופרטיות" />}
        {tab === 'market' && <PlaceholderTab title="מחברת 08 - שוק ו־Case Studies" notebookHint="שוק ומקרי בוחן" />}
        {tab === 'health' && <PlaceholderTab title="מחברת 10 - מוצר ובריאות (HealthHarbor)" notebookHint="HealthHarbor" />}
        {tab === 'sources' && <PlaceholderTab title="מחברת 11 - ספריית מקורות" notebookHint="מקורות" />}
      </main>
    </div>
  )
}
