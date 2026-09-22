# CHR-ETRS

Hebrew RTL app: employee Happy Path (screens 1–5) on the locked OpenAPI, plus the existing CHR Index calculator and client-side shadow P&amp;L.

אב־טיפוס בעברית (RTL). המסלול העיקרי הוא חמשת מסכי העובד מול `/api/v1`.

## How to run / הרצה

### Backend (port 8000)

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Smoke tests:

```bash
cd backend && python -m pytest tests/test_openapi_smoke.py
```

Swagger: http://localhost:8000/docs

### Frontend (port 5173)

```bash
cd frontend
npm install
npm run dev
```

The Vite dev server proxies `/api` and `/health` to port 8000. Open http://localhost:5173.

Bearer for the mock API: `Authorization: Bearer demo-token` (any non-empty bearer is accepted; a missing token returns 401 `Invalid_OAuth_Token`).

## Happy Path screens → API

Switch the profile in the header. `emp-hope` is a healthy day. `emp-low` has 2 spoons and HRV 28ms, so task assign hits the circuit breaker.

| Screen | What you do | API |
|--------|-------------|-----|
| 1 · עוגנים | View and save a personal anchor next to the employee value asset | `GET` / `PUT /api/v1/anchors/{userId}` |
| 2 · מרכז יומי | Spoon budget and HRV snapshot; post a new sample | `GET /api/v1/telemetry/spoons-budget/{userId}`, `GET /api/v1/telemetry/hrv-stream`, `POST /api/v1/telemetry/hrv-sample` |
| 3 · מטריצת חוסן | HOPE / SHAY / NESS from spoons + latest HRV | `GET /api/v1/resilience/matrix/{userId}` |
| 4 · קצב חכם | Assign a task; 403 circuit breaker or 409 Anti-GET | `POST /api/v1/tasks/assign` |
| 5 · יומן שביל | Create and list private journal entries | `GET` / `POST /api/v1/journal/entries` |

Screens 6–7 (manager Glass Box and Cuckoo veto UI) are not in this pass. The endpoints exist and can be smoked from the lab drawer or Swagger.

Seeded manager check: org `11111111-1111-4111-8111-111111111111`, department `rd-core` (8 members, 200) and `tiny` (3 members, 403 Japanese Veil). Devices for the HRV stream: `luna-hope`, `luna-low`.

## Canonical files

- `openapi.yaml` — locked OpenAPI 3.0.3 (paths are mounted under `/api/v1`)
- `schema.sql` — 10 entities
- `business-rules.md` — BR-01…BR-08

In-memory models mirror those entities. No database is required.

## Locked routes (under `/api/v1`)

| Method | Path | Rule |
|--------|------|------|
| GET | `/telemetry/hrv-stream` | LSL frame; `device_id` required |
| POST | `/telemetry/hrv-sample` | 201 into the private vault; 400 if HRV &lt; 0 |
| POST | `/cringe/analyze-sentiment` | Text patterns only (Toxic_Positivity, Masking). Not emotion recognition |
| POST | `/cringe/trigger-cuckoo-ping` | 60-minute veto window |
| POST | `/cuckoo/veto` | 200 inside the window; 422 `Sovereign_Veto_Expired` after it. Reason stays in the journal vault |
| POST | `/tasks/assign` | 403 if spoons &lt; 3 or HRV &lt; 40ms; 409 `Anti_GET_Exception` on graded load while at risk; 403 `Right_To_Disconnect_Violation` between 19:00 and 07:00 Asia/Jerusalem |
| GET | `/manager/dashboard` | 403 `Japanese_Veil_Violation` when Member_Count &lt; 5. Alert level is RED/GREEN only |
| POST | `/manager/ledger/record` | 201, SHA-256, `COMMITTED_IMMUTABLE` |
| GET | `/telemetry/spoons-budget/{userId}` | SpoonBudget |
| POST | `/hris/worker-wellness-sync` | Dichotomous ERP sync |
| GET | `/audit/privacy-compliance` | Emotion recognition reported blocked |
| POST | `/cringe/circuit-breaker` | Admin helper; 409 if graded allocation is requested while the breaker is open |

### MVP clarification on task-assign 403

The locked `ErrorResponse` enum has no circuit-breaker token (the Forbidden component is shared with Japanese Veil). Task denial still returns HTTP 403 and the ErrorResponse shape (`error_code`, `http_status`, `message`, `timestamp`). `error_code` is `Circuit_Breaker_Active` so clients can tell it apart from `Japanese_Veil_Violation`. The message names the spoon or HRV breach.

### Extensions (not in `openapi.yaml`)

Documented here because the employee screens need them. They are employee-scoped and are not on the manager dashboard.

- `GET` / `PUT /api/v1/anchors/{userId}` — Anchor + Employee_Value_Asset
- `GET /api/v1/resilience/matrix/{userId}` — Avatar_State derived from SpoonBudget and the latest HRVSample
- `GET /api/v1/journal/entries?user_id=` and `POST /api/v1/journal/entries` — JournalEntry private vault. Sealed veto reasons are not returned in the list

Old `/api/v1/energy/*`, `/communication/*`, `/biometrics/*`, `/synthesize`, `/finance/*`, `/voi/*`, and `/chr/index` are removed. The shadow P&amp;L on מחברת 04 runs in the browser (`frontend/src/lib/financeSim.ts`). The CHR Index calculator stays client-side in `frontend/src/tabs/ChrIndexTab.tsx`.

## מדד CHR / חוב אושר

Client-side only. Formulas live in `frontend/src/lib/chrIndexCalc.ts` and `CHR-INDEX-CALCULATOR-SPEC.md`.

| Block | Formula |
|--------|---------|
| CHR Index 0–100 | `Σ (wᵢ · Dimᵢ)` for O/S/H/E; weights normalized to sum 1 |
| Survey / masking | `survey = CHR + masking × (100 − CHR)`; Glass Box warning if masking ≥ 0.3 |
| Happiness Debt ₪ | fairness debt + diluted-wage burden + turnover premium |

Organizational discussion model — not clinical advice.
