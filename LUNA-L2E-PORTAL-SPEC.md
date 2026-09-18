# Luna L2E — Sanctuary companion surface (MVP)

## Goal
Employee-side **Learn-to-Earn (L2E)** surface: spoon energy budget, HERO capital, EverStore/Chits, streak shield. Hebrew RTL UI. Works as a tab in the existing Vite app AND as static GitHub Pages (client-side; no backend required for core UX).

## Product lock (architecture Option 1)
**Luna is a product alias / skin / companion persona inside Sanctuary** (source-of-truth: architecture chapter 4). She is **not** a separate governance product and **not** a named fiduciary.

- Home product: **Sanctuary** (מרחב מקלט).
- Luna: companion persona for L2E, spoons, HERO, EverStore — a skin of Sanctuary, not a second OS.
- **Dr. Cringe** remains the **sole named fiduciary / forensic agent**. Luna does not audit, does not hold fiduciary duty, does not replace Cringe.

## Tab name
**מקלט · לנה (L2E)** — Hebrew heading: לנה · למד כדי להרוויח  
Deep link: `#luna` (from Sanctuary: `#welfare`).

## Features (MVP)
1. **Spoon tray** — daily budget (default 12), expenditure vs investment spoons; simple log of today’s drains/gains; warning when low; Cuckoo-style “slow down” banner when budget ≤ 2 (organizational framing only, not medical).
2. **HERO panel** — four sliders 0–100: Hope, Efficacy, Resilience, Optimism; composite score; short Hebrew nudge.
3. **L2E quests** — 3–5 sample quests (e.g. meta-skill learning, deep work block, peer help); completing a quest awards **Chits**.
4. **EverStore preview** — spend Chits on 3 sample rewards (ergonomic upgrade, protected deep-work hour, recovery break); balance updates client-side.
5. **Streak shield** — day streak counter + one “shield” token that can protect a missed day (demo).
6. **Presets** — Healthy agency / Mid burn / Crisis (load sample spoon/HERO/Chits state).
7. **Assumptions** panel — Glass Box / privacy; Sanctuary companion lock; Dr. Cringe is the sole named fiduciary; not clinical advice; static-preview banner on Pages.

## Tech
- Extend existing `/frontend` React+Vite Hebrew RTL app (same patterns as ChrIndexTab / SanctuaryTab).
- Client-side state + localStorage.
- Graceful if API missing (Pages).
- Update README HE+EN.
- After merge to main, Pages workflow should republish; ensure `gh-pages` compatible (VITE_BASE).

## Out of scope
- Real biometrics/HRV, Slack, ZK vault, payments, clinical guidance.
- Fiduciary / forensic workflows (those belong to Dr. Cringe).

## Done when
- Companion surface usable end-to-end; copy frames Luna inside Sanctuary; build passes; README updated; PR or push to repo.
