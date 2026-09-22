export const DEMO_USERS = [
  { id: 'emp-hope', label: 'אנרגיה תקינה', device: 'luna-hope' },
  { id: 'emp-low', label: 'כפיות נמוכות · HRV נמוך', device: 'luna-low' },
] as const

export type DemoUserId = (typeof DEMO_USERS)[number]['id']

export function deviceFor(userId: string) {
  return DEMO_USERS.find((u) => u.id === userId)?.device ?? `device-${userId}`
}
