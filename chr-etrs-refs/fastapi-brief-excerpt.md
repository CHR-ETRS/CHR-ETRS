# CHR-ETRS FastAPI mock endpoints (from Drive brief)

POST /api/v1/synthesize — anonymize PII records → synthetic (needs Authorization header)
POST /api/v1/communication/sentiment — NLP sentiment + SDT topics
GET /api/v1/voi/{department_id} — Rule of 5; dept 102 has 8 users (ok), else 3 (403)
POST /api/v1/energy/circuit-breaker — block if team_stamina < 40 (mock stamina 32.4 → 423)

Archetypes: NESS (spoon 100), SHAY (35), Explorer (dynamic)
SHAY throttle HRV < 55ms; NESS < 35ms; braking < 40ms
