# CHR-ETRS Sprint 1 Prototype

Hebrew RTL demo with Sanctuary UI, Capital (מחברת 04) shadow P&amp;L tab, **CHR Index / Happiness Debt calculator**, **Luna L2E Portal**, and mock API.

אב־טיפוס בעברית (RTL): מקדש רווחה, מאזן צללים, מחשבון מדד CHR / חוב אושר, ופורטל לנה · למד כדי להרוויח.

## Structure / מבנה

- `backend/` — FastAPI mock API
- `frontend/` — Vite React + TypeScript + Tailwind (RTL)
- `CHR-INDEX-CALCULATOR-SPEC.md` — product spec for the calculator MVP
- `LUNA-L2E-PORTAL-SPEC.md` — product spec for the Luna / Learn-to-Earn portal
- `chr-etrs-refs/` — formula notes and API brief excerpts

## How to run / הרצה

### Backend (port 8000)

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

### Frontend (port 5173)

```bash
cd frontend
npm install
npm run dev
```

Build check (including GitHub Pages base path):

```bash
cd frontend && npm install && npm run build
VITE_BASE=/CHR-ETRS/ npm run build
```

Open http://localhost:5173 — Sanctuary (מחברת 02) is default; **מחברת 04** for CapitalTab; **מדד CHR / חוב אושר** for the calculator; **לנה · למד כדי להרוויח** (`#luna`) for Luna / L2E.

After merge to `main`, the static preview is [https://chr-etrs.github.io/CHR-ETRS/](https://chr-etrs.github.io/CHR-ETRS/) — open the **לנה · למד כדי להרוויח** tab, or go directly to [https://chr-etrs.github.io/CHR-ETRS/#luna](https://chr-etrs.github.io/CHR-ETRS/#luna).

Swagger: http://localhost:8000/docs

## מדד CHR / חוב אושר (Calculator MVP)

Client-side calculator in `frontend/src/tabs/ChrIndexTab.tsx` + pure logic in `frontend/src/lib/chrIndexCalc.ts`. Optional mirror API: `POST|GET /api/v1/chr/index`.

### Formulas / נוסחאות

| Block | Formula |
|--------|---------|
| CHR Index 0–100 | `Σ (wᵢ · Dimᵢ)` for O/S/H/E; weights normalized to sum 1 |
| Survey / masking | `survey = CHR + masking × (100 − CHR)`; Glass Box warning if masking ≥ 0.3 |
| DT | `num_deprived × annual_salary × dt_pct` (default haircut ~12%) |
| EBITDA Adjusted | `EBITDA_Nominal + RoH − DT` |
| Happiness Debt ₪ | fairness debt + diluted-wage burden + turnover premium |
| Severity 0–100 | `(debt / payroll) × 100` capped |
| Integrity | `1 − \|Declared_Culture − Lived_CHR\|`; happiness-washing if &lt; ~0.6 |

Presets: **Glass Box בריא** / **כלוב זהב** / **משבר Burn**.

Assumptions panel in UI: organizational discussion model — **not clinical advice**.

Aligned with `chr-etrs-refs/finance_formulas.md` (deprivation tax 12%, diluted wage 40 vs actual hours, turnover cost as editable multiple of annual salary).

### Sample — preset «Glass Box בריא» (approx.)

- CHR Index ≈ **79**
- Happiness debt severity low–moderate; Integrity above threshold
- EBITDA Adjusted = Nominal + RoH − small DT

### Sample — preset «משבר / Burn» (approx.)

- CHR Index ≈ **30**
- High debt severity; masking + Integrity flags
- Large DT vs RoH=0 → Adjusted EBITDA well below nominal

## לנה · למד כדי להרוויח (Luna / L2E)

Employee-side companion in `frontend/src/tabs/LunaL2eTab.tsx` + state helpers in `frontend/src/lib/lunaL2e.ts`. Fully client-side: **no backend required**. State persists in `localStorage` (`chr-etrs-luna-l2e-v1`). GitHub Pages shows a static-preview banner (`VITE_BASE=/CHR-ETRS/`).

פורטל עובד בצד הלקוח בלבד (גם ב־GitHub Pages). שמירה ב־localStorage. מסגור רווחה ארגונית — **לא ייעוץ קליני/רפואי**.

| Block | What it does / מה יש |
|--------|------------------------|
| Spoon tray / מגש כפיות | Daily budget 12; expenditure vs investment vs recovery log; low-budget warning; Cuckoo «slow down» at ≤2 spoons |
| HERO panel / לוח HERO | Hope · Efficacy · Resilience · Optimism sliders 0–100 + composite + Hebrew nudge |
| L2E quests | 5 sample quests (meta-skill, deep work, peer help, knowledge share, calendar boundary) → **Chits** |
| EverStore | Spend Chits on ergonomic upgrade, protected deep-work hour, recovery break |
| Streak shield / מגן רצף | Day streak + one demo shield token that can protect a missed day |
| Presets | **סוכנות בריאה** / **שחיקה בינונית** / **משבר / עומס** |
| Assumptions | Glass Box / privacy (browser-only); not clinical advice |

Out of scope: real biometrics/HRV, Slack, ZK vault, payments.

## Sprint 1 — Capital tab

- UI: `frontend/src/tabs/CapitalTab.tsx` — מאזן צללים hero, mini-simulator, concepts, VOI button, source library.
- Formulas ported from Drive `chr_financial_simulator.py` (see `chr-etrs-refs/finance_formulas.md`).
- Defaults (500 emp × 25k ₪, turnover 22%, deprivation 20%) → shadow ≈ 16.85M, Pre-CHR EBITDA ≈ 28.15M, After ≈ 38.53M, ROI ≈ 2,968%, ROV ≈ 30.68x.

## API mocks

| Method | Path | Notes |
|--------|------|--------|
| POST | /api/v1/synthesize | Requires Authorization |
| POST | /api/v1/communication/sentiment | Fixed negative mock |
| GET | /api/v1/voi/{department_id} | Rule of 5: 102 OK, else 403 |
| POST | /api/v1/energy/circuit-breaker | Default 423; force_stamina≥40 approved |
| POST | /api/v1/biometrics/log | Optional HRV throttle |
| GET | /api/v1/energy/state | Spoon budget SHAY-09 |
| POST/GET | /api/v1/finance/simulate | Shadow P&amp;L; baseline or simulated |
| POST/GET | /api/v1/chr/index | CHR Index + Happiness Debt (optional API mirror) |

CORS for Vite origin. Hebrew UI; English identifiers.

## GitHub Pages / `VITE_BASE`

Project Pages URL: `https://chr-etrs.github.io/CHR-ETRS/` (assets under `/CHR-ETRS/`). `frontend/vite.config.ts` reads `VITE_BASE` at build time; local `npm run dev` stays at `/`.

```bash
cd frontend && VITE_BASE=/CHR-ETRS/ npm run build
```

`frontend/public/.nojekyll` is copied into `dist` so Pages does not skip files that start with `_`.

## Roadmap (next)

Meeting Load · Dr. Cringe — after Luna L2E MVP.
