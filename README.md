# CHR-ETRS Sprint 1 Prototype

Hebrew RTL demo with Sanctuary UI, Capital (מחברת 04) shadow P&amp;L tab, **CHR Index / Happiness Debt calculator**, and mock API.

אב־טיפוס בעברית (RTL): מקדש רווחה, מאזן צללים, ומחשבון מדד CHR / חוב אושר.

## איך לראות בלי להתקין / How to view

**Public preview (no install):** [https://chr-etrs.github.io/CHR-ETRS/#chrIndex](https://chr-etrs.github.io/CHR-ETRS/#chrIndex)

המחשבון רץ בדפדפן (RTL, עברית) — אין צורך ב־Node, Python או שרת. קריאות API הן נתיבים יחסיים; אם ה־mock לא זמין, מדד CHR / חוב אושר ממשיך לעבוד במלואו.

The CHR Index Calculator is fully client-side. Other tabs that call the mock FastAPI will show a static/offline notice.

If the URL 404s, the repo owner needs **one Settings toggle**:

1. GitHub → **Settings → Pages** → Build and deployment → Source: **GitHub Actions**
2. Then **Actions → Deploy GitHub Pages → Re-run** (or push to `main`)
3. If the repo is **private** on GitHub Free, also **Settings → General → Change visibility → Public** so anyone with the link can open it (Pages on a private repo is not a public URL)

## Structure / מבנה

- `backend/` — FastAPI mock API
- `frontend/` — Vite React + TypeScript + Tailwind (RTL)
- `CHR-INDEX-CALCULATOR-SPEC.md` — product spec for the calculator MVP
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

Build check:

```bash
cd frontend && npm install && npm run build
```

Open http://localhost:5173 — default tab is **מדד CHR / חוב אושר** (`#chrIndex`); **מחברת 02** for Sanctuary; **מחברת 04** for CapitalTab.

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

## Roadmap (next)

Meeting Load · Luna · Dr. Cringe — after this calculator MVP.
