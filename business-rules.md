# CHR-ETRS Business Rules — BR-01…BR-08

**Source:** Gold SoT `1_frkn_u7r_LQWR1pW-bo0mcwVTJwYww5Hh6J8xSCc34` §6.2 + Excel 06 sheet `חוקי עסק`  
**Generated:** 2026-09-22 Asia/Jerusalem  
**Numbering:** Notebook 6 / Excel 06 / Gold SoT (BR-08 = Emotion Recognition / EU AI Act — NOT Meeting Waste)

---

## BR-01: פשיטת רגל אנרגטית (Spoon Bankruptcy)

| | |
|---|---|
| **Trigger / תנאי כניסה** | יתרת כפיות < 3 (מתוך 12) או מלאי אנרגיה זמין < 14% |
| **Action / פעולה** | הפעלת Circuit Breaker: חסימת יצירת משימות ב-API (POST Blocking), העברת הרשאות Jira ל-Read-Only, והזרקת "חסינות אאודמונית" |
| **Forbidden / מה אסור** | אסור למנהל להקצות משימות חדשות או לעקוף את הנעילה במערכת המשימות |
| **Entities** | SpoonBudget, Task, Dr. Cringe Agent |

---

## BR-02: בלימה ביומטרית (Biometric Braking)

| | |
|---|---|
| **Trigger / תנאי כניסה** | HRV < 40ms (כללי), HRV < 35ms (NESS), HRV < 55ms (SHAY) |
| **Action / פעולה** | הפעלת עצירה כפויה (Cooling-off), הקפאת מדדי KPI/Streaks, והזרקת כפיות מוזהבות מוגנות |
| **Forbidden / מה אסור** | אסור לפגוע בדירוג ה-KPI או להפעיל סנקציות שכר/תפוקה על העובד |
| **Entities** | HRVSample, Avatar_State, Task, SpoonBudget |

---

## BR-03: איסור גורף על Anti-GET (Smart Pacing)

| | |
|---|---|
| **Trigger / תנאי כניסה** | ניסיון להגדיל עומס משימות באופן הדרגתי (Graded Exercise Therapy) כאשר ה-HRV/Spoons נמוכים מסף הסיכון |
| **Action / פעולה** | המערכת זורקת `Anti_GET_Exception`, חוסמת את הקצאת המשימה ב-API, ומכריחה פריסת משימות למיקרו-יחידות (Chunking) |
| **Forbidden / מה אסור** | איסור מוחלט על דחיפת עומס הדרגתית קשיחה (Anti-GET) |
| **Entities** | Task, HRVSample, SpoonBudget |

---

## BR-04: מס קיפוח תפעולי (Deprivation Tax)

| | |
|---|---|
| **Trigger / תנאי כניסה** | דיסוננס ערכי / הפרת החוזה הפסיכולוגי / חריגת שעות תקן |
| **Action / פעולה** | הטלת היטל פחת פריון מיידי של **12%** המשוקלל ב-P&L של המחלקה: `Tax = 0.12 × Mean_Salary × N_Deprived` |
| **Forbidden / מה אסור** | אסור למנהל לגלגל את עלות מס הקיפוח אל העובד או להסתירו מדוח הדירקטוריון |
| **Entities** | Employee_Value_Asset, TeamAggregate, Manager_Ledger |

---

## BR-05: הפרגוד היפני (Japanese Veil / Rule of 5+)

| | |
|---|---|
| **Trigger / תנאי כניסה** | שאילתת תצוגה בדשבורד מנהל / דירקטוריון לקבלת נתוני סנטימנט, מפות חום או טלמטריה |
| **Action / פעולה** | אכיפת N ≥ 5 עובדים בקבוצה; אם N < 5, התצוגה נחסמת אקטיבית ומוחזרת שגיאה **403 Forbidden** |
| **Forbidden / מה אסור** | אסור לחשוף נתונים אגרגטיביים או פרטניים בצוות המונה פחות מ-5 עובדים למניעת מתקפות הצלבה (Linkage Attacks) |
| **Entities** | TeamAggregate, Users, Manager_Dashboard |

---

## BR-06: שיטת הקוקייה והווטו הריבוני (Cuckoo / Sovereign Veto)

| | |
|---|---|
| **Trigger / תנאי כניסה** | התראת שחיקה קריטית / זיהוי מצוקה במנוע הניטור |
| **Action / פעולה** | השהיית סנקציות ניהוליות ל-**60 דקות** ומשלוח private Cuckoo Ping לעובד; הפעלת הווטו ע״י העובד מזכה את המנהל בלדג׳ר ונועלת את הסיבה בכספת |
| **Forbidden / מה אסור** | אסור למערכת או למנהל לחשוף את סיבת הווטו או לבטל את זכות הווטו של העובד |
| **Entities** | CuckooAlert, Users, JournalEntry, Manager_Ledger |

---

## BR-07: זכות הניתוק החוקתית (Right to Disconnect)

| | |
|---|---|
| **Trigger / תנאי כניסה** | תקשורת ארגונית או דרישת משימה בין השעות **19:00** בערב ל-**07:00** בבוקר |
| **Action / פעולה** | איסור מוחלט על העברת הודעות/משימות כפויות; חריגה רושמת חוב אמוציונלי ומפעילה מס קיפוח תפעולי |
| **Forbidden / מה אסור** | אסור לשלוח משימות שוחקות או דרישות זמינות מחוץ לשעות התקן |
| **Entities** | Tasks, Dr. Cringe Agent, Manager_Ledger |

---

## BR-08: איסור זיהוי רגשות (EU AI Act Prohibition)

| | |
|---|---|
| **Trigger / תנאי כניסה** | ניסיון לעבד נתוני וידאו, תווי פנים או טון דיבור לזיהוי רגשות במקום העבודה |
| **Action / פעולה** | חסימה הרמטית של רכיבי Emotion Recognition ומעבר לניתוח דפוסים פיזיו-התנהגותיים אובייקטיביים בלבד |
| **Forbidden / מה אסור** | איסור מוחלט על ניטור רגשות פולשני לפי סעיף 13 ב-EU AI Act |
| **Entities** | HRVSample, Dr. Cringe Agent, EU_AI_Act_Module |

---

## Locked constants (all notebooks)

- 12 spoons daily baseline; Circuit Breaker at spoons < 3 or capacity < 14%
- HRV hard cut 40ms (NESS 35 / SHAY 55)
- Deprivation Tax **12%**; Happiness Debt base **105,000 ILS**
- Cuckoo Sovereign Veto window **60 minutes**
- Japanese Veil **N ≥ 5**
- ERP visibility: dichotomous **RED/GREEN** only
- Dr. Cringe: HeBERT / DictaBERT (text patterns — not emotion recognition)
