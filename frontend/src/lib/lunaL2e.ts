/**
 * Luna L2E Portal — client-side state helpers for Luna’s own surface.
 * Organizational wellbeing / Learn-to-Earn demo — not clinical advice.
 * Luna is a standalone L2E agent. Dr. Cringe remains the sole named fiduciary/forensic agent.
 */

export const STORAGE_KEY = 'chr-etrs-luna-l2e-v1'
export const DEFAULT_BUDGET = 12
export const LOW_SPOON_WARN = 4
export const CUCKOO_THRESHOLD = 2

export type SpoonKind = 'expenditure' | 'investment' | 'gain'

export type SpoonLogEntry = {
  id: string
  kind: SpoonKind
  amount: number
  label: string
  at: string
}

export type HeroScores = {
  hope: number
  efficacy: number
  resilience: number
  optimism: number
}

export type LunaState = {
  dateKey: string
  dailyBudget: number
  remaining: number
  log: SpoonLogEntry[]
  hero: HeroScores
  chits: number
  completedQuestIds: string[]
  purchasedRewardIds: string[]
  streakDays: number
  lastStreakDate: string | null
  shieldTokens: number
  shieldMessage: string | null
}

export type PresetId = 'healthy' | 'mid' | 'crisis'

export type Quest = {
  id: string
  title: string
  blurb: string
  chits: number
  minutes: number
}

export type Reward = {
  id: string
  title: string
  blurb: string
  cost: number
  /** Consumable rewards can be bought more than once. */
  consumable: boolean
  restoreSpoons?: number
}

export const QUESTS: Quest[] = [
  {
    id: 'meta-skill',
    title: 'מיומנות-על — 30 דק׳ למידה',
    blurb: 'בלוק קצר של למידה מכוונת (שפה, כלי, מודל) שמגדיל הון אנושי.',
    chits: 25,
    minutes: 30,
  },
  {
    id: 'deep-work',
    title: 'בלוק עבודה עמוקה',
    blurb: '90 דק׳ בלי התראות — השקעת כפיות, לא בזבוז.',
    chits: 40,
    minutes: 90,
  },
  {
    id: 'peer-help',
    title: 'עזרה לעמית',
    blurb: 'ליווי קצר / unblock למישהו בצוות. L2E חברתי.',
    chits: 20,
    minutes: 20,
  },
  {
    id: 'share-knowledge',
    title: 'שיתוף ידע בצוות',
    blurb: 'הערה, תבנית או הדגמה קצרה שנשארת אחרי הפגישה.',
    chits: 18,
    minutes: 15,
  },
  {
    id: 'boundary',
    title: 'גבול מגן — בלי פגישות בבלוק',
    blurb: 'סימון שעה מוגנת ביומן. סוכנות על הקשב, לא «עוד משימה».',
    chits: 15,
    minutes: 5,
  },
]

export const REWARDS: Reward[] = [
  {
    id: 'ergo',
    title: 'שדרוג ארגונומי',
    blurb: 'כיסא / מעמד מסך / תאורה — השקעה חד-פעמית בנוחות עבודה.',
    cost: 80,
    consumable: false,
  },
  {
    id: 'protected-hour',
    title: 'שעת עבודה עמוקה מוגנת',
    blurb: 'שעה חסומה ביומן הארגוני — בלי שיבוץ פגישות.',
    cost: 45,
    consumable: false,
  },
  {
    id: 'recovery',
    title: 'הפסקת התאוששות',
    blurb: 'הפסקה קצרה שמחזירה כפיות להיום (הדגמה מקומית).',
    cost: 25,
    consumable: true,
    restoreSpoons: 2,
  },
]

export const QUICK_SPOONS: { id: string; label: string; kind: SpoonKind; amount: number }[] = [
  { id: 'meeting', label: 'פגישה', kind: 'expenditure', amount: 2 },
  { id: 'slack', label: 'הקשרים / סלאק', kind: 'expenditure', amount: 1 },
  { id: 'learn', label: 'למידה', kind: 'investment', amount: 1 },
  { id: 'focus', label: 'עבודה עמוקה', kind: 'investment', amount: 2 },
  { id: 'recover', label: 'התאוששות', kind: 'gain', amount: 2 },
]

export function todayKey(now = new Date()): string {
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, '0')
  const d = String(now.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

export function addDays(dateKey: string, delta: number): string {
  const [y, m, d] = dateKey.split('-').map(Number)
  const dt = new Date(y, m - 1, d)
  dt.setDate(dt.getDate() + delta)
  return todayKey(dt)
}

export function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n))
}

export function newId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`
}

export function heroComposite(hero: HeroScores): number {
  return (hero.hope + hero.efficacy + hero.resilience + hero.optimism) / 4
}

export function heroNudgeHe(score: number): string {
  if (score >= 75) {
    return 'הון HERO גבוה — סוכנות טובה ללמידה ולהשקעת כפיות. זה זמן טוב למשימת L2E.'
  }
  if (score >= 50) {
    return 'בסיס ביניים. בלוק עמוק קצר או עזרה לעמית יכולים להחזיר תחושת מסוגלות.'
  }
  return 'הקצב גבוה ביחס לעתודה. בחרי משימת L2E קלה והאטי — מסגור ארגוני, לא ייעוץ רפואי.'
}

export function defaultHero(): HeroScores {
  return { hope: 62, efficacy: 58, resilience: 55, optimism: 60 }
}

export function emptyDay(partial?: Partial<LunaState>): LunaState {
  const dateKey = todayKey()
  return {
    dateKey,
    dailyBudget: DEFAULT_BUDGET,
    remaining: DEFAULT_BUDGET,
    log: [],
    hero: defaultHero(),
    chits: 80,
    completedQuestIds: [],
    purchasedRewardIds: [],
    streakDays: 1,
    lastStreakDate: dateKey,
    shieldTokens: 1,
    shieldMessage: null,
    ...partial,
  }
}

export const PRESETS: Record<PresetId, { labelHe: string; labelEn: string; state: LunaState }> = {
  healthy: {
    labelHe: 'סוכנות בריאה',
    labelEn: 'Healthy agency',
    state: emptyDay({
      remaining: 10,
      log: [
        {
          id: 'p-h1',
          kind: 'investment',
          amount: 2,
          label: 'בלוק למידה בוקר',
          at: new Date().toISOString(),
        },
      ],
      hero: { hope: 82, efficacy: 78, resilience: 80, optimism: 84 },
      chits: 160,
      completedQuestIds: ['meta-skill'],
      purchasedRewardIds: [],
      streakDays: 14,
      lastStreakDate: todayKey(),
      shieldTokens: 1,
      shieldMessage: null,
    }),
  },
  mid: {
    labelHe: 'שחיקה בינונית',
    labelEn: 'Mid burn',
    state: emptyDay({
      remaining: 5,
      log: [
        {
          id: 'p-m1',
          kind: 'expenditure',
          amount: 2,
          label: 'סטנד-אפ + סנכרון',
          at: new Date().toISOString(),
        },
        {
          id: 'p-m2',
          kind: 'expenditure',
          amount: 3,
          label: 'שרשור מיילים',
          at: new Date().toISOString(),
        },
        {
          id: 'p-m3',
          kind: 'investment',
          amount: 2,
          label: 'עבודה עמוקה חלקית',
          at: new Date().toISOString(),
        },
      ],
      hero: { hope: 52, efficacy: 48, resilience: 50, optimism: 46 },
      chits: 70,
      completedQuestIds: [],
      purchasedRewardIds: [],
      streakDays: 4,
      lastStreakDate: todayKey(),
      shieldTokens: 1,
      shieldMessage: null,
    }),
  },
  crisis: {
    labelHe: 'משבר / עומס',
    labelEn: 'Crisis',
    state: emptyDay({
      remaining: 2,
      log: [
        {
          id: 'p-c1',
          kind: 'expenditure',
          amount: 3,
          label: 'פגישות רצופות',
          at: new Date().toISOString(),
        },
        {
          id: 'p-c2',
          kind: 'expenditure',
          amount: 4,
          label: 'כיבוי שריפות',
          at: new Date().toISOString(),
        },
        {
          id: 'p-c3',
          kind: 'expenditure',
          amount: 3,
          label: 'הקשרים דחופים',
          at: new Date().toISOString(),
        },
      ],
      hero: { hope: 28, efficacy: 32, resilience: 30, optimism: 24 },
      chits: 18,
      completedQuestIds: [],
      purchasedRewardIds: [],
      streakDays: 0,
      lastStreakDate: addDays(todayKey(), -3),
      shieldTokens: 0,
      shieldMessage: 'אין מגן — הרצף נשבר בהדגמת המשבר.',
    }),
  },
}

export const ASSUMPTIONS_HE: string[] = [
  'לנה היא סוכנת L2E עצמאית עם פורטל משלה — לא alias/skin ולא פרסונת ליווי של מקלט (Sanctuary).',
  'Dr. Cringe הוא הנאמן/פורנזי היחיד בשם ב־CHR-ETRS. לנה לא מחזיקה fiduciary ולא מבצעת forensic.',
  'זהו מודל לדיון ברווחה ארגונית ולמידת-כדי-להרוויח (L2E) — לא אבחנה קלינית, לא ייעוץ רפואי, לא טיפול.',
  'כפיות (Spoons) הן מטאפורה לתקציב אנרגיה יומי בעבודה. ברירת מחדל: 12. הוצאה מול השקעה הן קטגוריות ארגוניות.',
  'קוקייה (Cuckoo) מופיעה כשנותרו ≤2 כפיות: המלצה ארגונית להאט — לא אזהרה רפואית.',
  'HERO = Hope / Efficacy / Resilience / Optimism (הון פסיכולוגי ארגוני). הציון המשוקלל הוא ממוצע פשוט 0–100.',
  'משימות L2E מעניקות Chits בהדגמה מקומית. אין תשלום, אין ביומטריה, אין Slack.',
  'EverStore הוא תצוגת חנות בפורטל לנה: יתרה מתעדכנת בדפדפן בלבד.',
  'מגן רצף (Streak Shield) הוא אסימון הדגמה אחד שיכול לשמור רצף יומי אחרי «יום שפוספס».',
  'Glass Box / פרטיות: מצב לנה נשמר ב־localStorage במכשיר זה. הפורטל לא שולח נתונים לשרת.',
]

export function spoonTotals(log: SpoonLogEntry[]): {
  expenditure: number
  investment: number
  gain: number
} {
  return log.reduce(
    (acc, e) => {
      acc[e.kind] += e.amount
      return acc
    },
    { expenditure: 0, investment: 0, gain: 0 },
  )
}

export function applySpoon(state: LunaState, kind: SpoonKind, amount: number, label: string): LunaState {
  const qty = Math.max(1, Math.round(amount))
  let applied = qty
  let remaining = state.remaining
  if (kind === 'gain') {
    applied = Math.min(qty, state.dailyBudget - state.remaining)
    if (applied <= 0) return state
    remaining = state.remaining + applied
  } else {
    applied = Math.min(qty, state.remaining)
    if (applied <= 0) return state
    remaining = state.remaining - applied
  }
  const entry: SpoonLogEntry = {
    id: newId(),
    kind,
    amount: applied,
    label,
    at: new Date().toISOString(),
  }
  return { ...state, remaining, log: [entry, ...state.log].slice(0, 24), shieldMessage: null }
}

export function completeQuest(state: LunaState, questId: string): LunaState {
  const quest = QUESTS.find((q) => q.id === questId)
  if (!quest || state.completedQuestIds.includes(questId)) return state
  return {
    ...state,
    chits: state.chits + quest.chits,
    completedQuestIds: [...state.completedQuestIds, questId],
    shieldMessage: null,
  }
}

export function buyReward(state: LunaState, rewardId: string): { state: LunaState; ok: boolean; reason?: string } {
  const reward = REWARDS.find((r) => r.id === rewardId)
  if (!reward) return { state, ok: false, reason: 'unknown' }
  if (!reward.consumable && state.purchasedRewardIds.includes(rewardId)) {
    return { state, ok: false, reason: 'owned' }
  }
  if (state.chits < reward.cost) return { state, ok: false, reason: 'funds' }

  let remaining = state.remaining
  if (reward.restoreSpoons) {
    remaining = clamp(remaining + reward.restoreSpoons, 0, state.dailyBudget)
  }
  const purchased = reward.consumable
    ? state.purchasedRewardIds
    : [...state.purchasedRewardIds, rewardId]
  return {
    ok: true,
    state: {
      ...state,
      chits: state.chits - reward.cost,
      remaining,
      purchasedRewardIds: purchased,
      shieldMessage: null,
    },
  }
}

export function checkInToday(state: LunaState): LunaState {
  const today = todayKey()
  if (state.lastStreakDate === today) {
    return { ...state, shieldMessage: 'כבר סומנה נוכחות היום.' }
  }
  const yesterday = addDays(today, -1)
  if (state.lastStreakDate === yesterday || state.streakDays === 0) {
    return {
      ...state,
      lastStreakDate: today,
      streakDays: state.streakDays + 1,
      shieldMessage: 'נוכחות נרשמה. הרצף נמשך.',
    }
  }
  // Missed at least one day
  if (state.shieldTokens > 0) {
    return {
      ...state,
      lastStreakDate: today,
      streakDays: state.streakDays + 1,
      shieldTokens: state.shieldTokens - 1,
      shieldMessage: 'מגן הרצף שמר על הרצף אחרי יום שפוספס.',
    }
  }
  return {
    ...state,
    lastStreakDate: today,
    streakDays: 1,
    shieldMessage: 'הרצף אופס — לא היה מגן. מתחילים מחדש מהיום.',
  }
}

/** Demo: pretend yesterday was missed. Next check-in / shield decides the outcome. */
export function simulateMissedDay(state: LunaState): LunaState {
  const today = todayKey()
  if (state.shieldTokens > 0) {
    return {
      ...state,
      lastStreakDate: today,
      shieldTokens: state.shieldTokens - 1,
      shieldMessage: 'הדגמה: יום שפוספס — המגן שמר על הרצף.',
    }
  }
  return {
    ...state,
    streakDays: 0,
    lastStreakDate: addDays(today, -2),
    shieldMessage: 'הדגמה: יום שפוספס בלי מגן — הרצף נשבר.',
  }
}

export function rolloverIfNeeded(state: LunaState): LunaState {
  const today = todayKey()
  if (state.dateKey === today) return state
  return {
    ...state,
    dateKey: today,
    remaining: state.dailyBudget,
    log: [],
    completedQuestIds: [],
    shieldMessage: 'יום חדש — מגש הכפיות והמשימות אופסו. רצף, מגן ו־Chits נשמרו.',
  }
}

function isHero(v: unknown): v is HeroScores {
  if (!v || typeof v !== 'object') return false
  const h = v as HeroScores
  return [h.hope, h.efficacy, h.resilience, h.optimism].every((n) => typeof n === 'number')
}

export function parseState(raw: unknown): LunaState | null {
  if (!raw || typeof raw !== 'object') return null
  const s = raw as Partial<LunaState>
  if (typeof s.dailyBudget !== 'number' || typeof s.remaining !== 'number') return null
  if (!Array.isArray(s.log) || !isHero(s.hero)) return null
  if (typeof s.chits !== 'number') return null
  return rolloverIfNeeded({
    dateKey: typeof s.dateKey === 'string' ? s.dateKey : todayKey(),
    dailyBudget: clamp(s.dailyBudget, 1, 24),
    remaining: clamp(s.remaining, 0, 24),
    log: s.log as SpoonLogEntry[],
    hero: {
      hope: clamp(s.hero.hope, 0, 100),
      efficacy: clamp(s.hero.efficacy, 0, 100),
      resilience: clamp(s.hero.resilience, 0, 100),
      optimism: clamp(s.hero.optimism, 0, 100),
    },
    chits: Math.max(0, Math.round(s.chits)),
    completedQuestIds: Array.isArray(s.completedQuestIds) ? (s.completedQuestIds as string[]) : [],
    purchasedRewardIds: Array.isArray(s.purchasedRewardIds) ? (s.purchasedRewardIds as string[]) : [],
    streakDays: typeof s.streakDays === 'number' ? Math.max(0, s.streakDays) : 0,
    lastStreakDate: typeof s.lastStreakDate === 'string' ? s.lastStreakDate : null,
    shieldTokens: typeof s.shieldTokens === 'number' ? clamp(s.shieldTokens, 0, 3) : 0,
    shieldMessage: typeof s.shieldMessage === 'string' ? s.shieldMessage : null,
  })
}

export function loadState(): LunaState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return emptyDay()
    const parsed = parseState(JSON.parse(raw) as unknown)
    return parsed ?? emptyDay()
  } catch {
    return emptyDay()
  }
}

export function saveState(state: LunaState): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
  } catch {
    // Quota / private mode — UI still works in-memory.
  }
}

/** True on GitHub Pages project sites (`VITE_BASE=/CHR-ETRS/`). */
export function isStaticPagesPreview(): boolean {
  const base = import.meta.env.BASE_URL || '/'
  if (base !== '/') return true
  if (typeof window === 'undefined') return false
  return window.location.hostname.endsWith('github.io')
}
