# CHR Index Calculator MVP — product spec

## Context
CHR-ETRS is an organizational OS for Corporate Happiness Responsibility (CHR), based on Dr. Shay Tzaban's model: treat human capital / happiness as a measurable balance-sheet asset, not soft HR.

This MVP is a **web calculator** (not the full OS): compute a personal/team CHR index and related **happiness debt** / shadow-accounting figures for demos and board conversations.

Language: UI in **Hebrew (RTL)** with English technical labels where useful (CHR, RoH, DT, VOI).

## Core formulas (implement these; document assumptions in UI)

### 1) Adjusted EBITDA (truth-aligned waterfall)
```
EBITDA_Adjusted = EBITDA_Nominal + RoH - DT
```
- **RoH (Return on Happiness)**: estimated economic upside from improved productivity / retention / sales lift attributable to CHR interventions (user inputs or presets).
- **DT (Deprivation Tax / operational deprivation tax)**: estimated loss from unmanaged burnout / fairness debt (default illustration: ~12% productivity haircut when burn is high — make this an editable parameter, not a hard-coded claim presented as universal law).

### 2) Happiness Debt (shadow liability)
Approximate as a function of:
- Fairness debt (perceived effort vs reward gap)
- Diluted wage / after-hours availability burden
- Turnover risk premium (cost of replacing talent; default range up to ~150% annual salary for critical roles — editable)
Output both **ILS** and a unitless severity score 0–100.

### 3) Personal CHR Index (0–100 composite)
Weighted blend of four dimensions (weights editable, sum to 1):
- **O** — Objective / material baseline (pay, benefits, workload fairness)
- **S** — Social / belonging (psychological safety, trust)
- **H** — Hedonic short-term wellbeing (comfort, immediate satisfaction)
- **E** — Eudaimonic flourishing (autonomy, meaning, growth / Learn-to-Earn)
Optional **masking** factor (0–1): when high, displayed "survey happiness" diverges from underlying CHR (Glass Box integrity warning).

### 4) Integrity Score
```
Integrity = 1 - |Declared_Culture - Lived_CHR|  (normalized)
```
Flag **happiness-washing** when Integrity < threshold (default 0.6).

## UX requirements
- Clean single-page app, mobile-friendly
- Inputs: sliders + numeric fields for the dimensions, salary, headcount, EBITDA nominal, RoH drivers, DT %, masking
- Outputs: CHR Index gauge, Happiness Debt (₪), EBITDA Adjusted waterfall (simple chart), Integrity Score, short plain-language Hebrew summary
- Presets: "Healthy Glass Box", "Golden Cage", "Crisis Burn" (load sample inputs)
- "Assumptions" expandable panel listing defaults and that this is a model for discussion, not clinical advice
- No auth, no backend required for MVP (client-side calc); optional localStorage save
- Accessible RTL Hebrew UI

## Tech
- Modern TypeScript + React (Vite) or Next.js — pick one and keep it simple
- Charts: lightweight (e.g. Recharts)
- Deployable as static site
- README in Hebrew + English: how to run, formula notes, roadmap (Meeting Load, Luna, Dr. Cringe next)

## Out of scope for MVP
- Biometric / medical diagnosis
- Slack/Graph live integrations
- Real employee PII vault
- Full L2E marketplace

## Done when
- `npm install && npm run build` succeeds
- Calculator implements the four formula blocks above with editable weights
- Hebrew RTL UI with presets and assumptions panel
- README explains formulas and how to run locally
