# CHR-ETRS Sprint 1 Prototype

Hebrew RTL demo with Sanctuary UI, Capital (מחברת 04) shadow P&amp;L tab, **CHR Index / Happiness Debt calculator**, and mock API.

אב־טיפוס בעברית (RTL): מקדש רווחה, מאזן צללים, ומחשבון מדד CHR / חוב אושר.

## Public preview / תצוגה ציבורית (ללא התקנה)

**Live app:** [https://chr-etrs.github.io/CHR-ETRS/](https://chr-etrs.github.io/CHR-ETRS/?tab=chrIndex)

מחשבון מדד CHR / חוב אושר רץ כולו בדפדפן (סטטי). אין צורך ב־`npm`, Python, או סוכן.

The CHR Index / Happiness Debt calculator is fully client-side. Open the HTTPS link in a normal browser — no local setup.

| | |
|---|---|
| **Calculator** | [https://chr-etrs.github.io/CHR-ETRS/?tab=chrIndex](https://chr-etrs.github.io/CHR-ETRS/?tab=chrIndex) |
| **App home** | [https://chr-etrs.github.io/CHR-ETRS/](https://chr-etrs.github.io/CHR-ETRS/) |

GitHub Pages hosts only the static frontend. Mock FastAPI routes (מעבדה / מאזן צללים) are not on this URL; use local run below if you need them.

### If the link 404s — one-time owner toggle / אם הקישור לא נפתח

Repo owner, once:

1. Merge this Pages workflow to `main` (or run **Actions → Deploy GitHub Pages → Run workflow**).
2. Open **Settings → Pages**.
3. Under **Build and deployment → Source** choose either:
   - **GitHub Actions**, or
   - **Deploy from a branch** → `gh-pages` / `/ (root)`.
4. This repository is **private**. For *anyone with the URL* (no GitHub login):
   - **Pages → Visibility → Public** (GitHub Pro), **or**
   - make the repository public (**Settings → General → Danger zone → Change repository visibility**).
   On GitHub Free, Pages for a private repo is not published publicly until the repo is public.
5. Wait a minute, then open the URL above. If the first Actions run failed with a Pages 404, re-run **Deploy GitHub Pages** after step 3.

The `github-pages` environment may ask the owner to **Approve** the first deployment.

## Structure / מבנה

- `backend/` — FastAPI mock API
- `frontend/` — Vite React + TypeScript + Tailwind (RTL)
- `CHR-INDEX-CALCULATOR-SPEC.md` — product spec for the calculator MVP
- `chr-etrs-refs/` — formula notes and API brief excerpts

## How to run / הרצה

לא צריך להתקין כלום כדי לראות את המחשבון — ראו [תצוגה ציבורית](#public-preview--תצוגה-ציבורית-ללא-התקנה) למעלה.
To view the calculator without installing, use the [public preview](#public-preview--תצוגה-ציבורית-ללא-התקנה) link above.

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

Open http://localhost:5173 — Sanctuary (מחברת 02) is default; **מחברת 04** for CapitalTab; **מדד CHR / חוב אושר** for the calculator.

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
