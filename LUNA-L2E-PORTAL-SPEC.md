# Luna L2E Portal MVP — product spec

## Goal
Employee-side CHR-ETRS companion: Learn-to-Earn (L2E), spoon energy budget, HERO capital, EverStore/Chits, streak shield. Hebrew RTL UI. Works as a new tab in the existing Vite app AND as static GitHub Pages (client-side; no backend required for core UX).

## Product lock
**Luna is a standalone agent in her own right**, with her own L2E Portal surface. She is **not** merely a Sanctuary alias / skin / companion persona.

- **Luna** — named L2E agent; owns spoons, HERO, quests, EverStore, streak shield.
- **Sanctuary** — separate energy/wellbeing space (מחברת 02). Peer, not parent.
- **Dr. Cringe** remains the **sole named fiduciary / forensic agent**. Luna does not audit, does not hold fiduciary duty, does not replace Cringe.

## Tab name
**Luna / L2E** (Hebrew label: לנה · למד כדי להרוויח)  
Deep link: `#luna`

## Features (MVP)
1. **Spoon tray** — daily budget (default 12), expenditure vs investment spoons; simple log of today’s drains/gains; warning when low; Cuckoo-style “slow down” banner when budget ≤ 2 (organizational framing only, not medical).
2. **HERO panel** — four sliders 0–100: Hope, Efficacy, Resilience, Optimism; composite score; short Hebrew nudge.
3. **L2E quests** — 3–5 sample quests (e.g. meta-skill learning, deep work block, peer help); completing a quest awards **Chits**.
4. **EverStore preview** — spend Chits on 3 sample rewards (ergonomic upgrade, protected deep-work hour, recovery break); balance updates client-side.
5. **Streak shield** — day streak counter + one “shield” token that can protect a missed day (demo).
6. **Presets** — Healthy agency / Mid burn / Crisis (load sample spoon/HERO/Chits state).
7. **Assumptions** panel — Glass Box / privacy; Luna is a standalone L2E agent; Dr. Cringe is the sole named fiduciary/forensic agent; not clinical advice; static-preview banner on Pages.

## Tech
- Extend existing `/frontend` React+Vite Hebrew RTL app (same patterns as ChrIndexTab).
- Client-side state + localStorage.
- Graceful if API missing (Pages).
- Update README HE+EN.
- After merge to main, Pages workflow should republish; ensure `gh-pages` compatible (VITE_BASE).

## Out of scope
- Real biometrics/HRV, Slack, ZK vault, payments, clinical guidance.
- Fiduciary / forensic workflows (those belong to Dr. Cringe).

## Done when
- Luna’s own tab usable end-to-end; copy frames her as a standalone L2E agent (not a Sanctuary skin); build passes; README updated; PR or push to repo.
