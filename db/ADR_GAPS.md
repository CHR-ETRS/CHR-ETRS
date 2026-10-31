<!-- CHR-ETRS MVP v1 · ADR_GAPS.md · Version: 1.6.19-mvp (2026-10-31) — supersedes the 1.6.18-mvp ADR_GAPS (2026-10-31), the 1.6.17-mvp ADR_GAPS (2026-10-31), the 1.6.16-mvp ADR_GAPS (2026-10-30), the 1.6.13-mvp ADR_GAPS (2026-10-25), the 1.6.12-mvp ADR_GAPS (2026-10-24), the 1.6.11-mvp ADR_GAPS (2026-10-24), the 1.6.10-mvp ADR_GAPS (2026-10-21), the 1.6.9-mvp ADR_GAPS (2026-10-21), the 1.6.8-mvp ADR_GAPS (2026-10-21), the 1.6.7-mvp ADR_GAPS (2026-10-20), the 1.6.6-mvp ADR_GAPS (2026-10-20), the 1.6.5-mvp ADR_GAPS (2026-10-20), the 1.6.4-mvp ADR_GAPS (2026-10-20), the 1.6.3-mvp ADR_GAPS (2026-10-20), the 1.6.2-mvp ADR_GAPS (2026-10-20), the 1.6.1-mvp ADR_GAPS (2026-10-20), the 1.6.0-mvp ADR_GAPS (2026-10-20), the 1.5 ADR_GAPS of 2026-10-20 (morning), the 1.4 ADR_GAPS of 2026-10-06 and the Drive ADR_GAPS of 2026-10-12 -->
# ADR Gaps — CHR-ETRS MVP v1.6.19 Code Pack

**Date:** 2026-10-31 · **Pack version:** `1.6.19-mvp` — aggregate leaver list + batched memo line, A-3 and A-10 closed, verification levels / 'תיק אימות', report layers, sources (see *Resolved in v1.6.19*); v1.6.18 closed A-12, A-13, A-14 (see *Resolved in v1.6.18*); v1.6.17 closed A-5, A-8, A-11 / J-3 / J-15 (see *Resolved in v1.6.17*). v1.6.16 encodes agents-bot-instructions-v3 (single source of truth for the agents; v3 wins over earlier decisions) and Karin's closed values of 30.10 (see *Resolved in v1.6.16*). Earlier (1.6.13): encodes Karin's locked EverStore expansion, Golden Spoons non-expiration / conversion policy, and time-benefit voucher redemption privacy (`נעילת הפרגוד`) of 2026-10-25.  
**Rule:** Open items are TODO in schema / rpc / openapi. **Do not invent locked numbers.**  
**Precedence:** Karin's clarifications of 2026-10-20 override the Drive ADR_GAPS of 2026-10-12 where they differ:
- team averages are regular data at **N≥5**; only **Cuckoo, Shadow Balance and emergency mode** need **N≥10** (the 12.10 "N≥10 everywhere" is overridden);
- gold `#FAAF00` stays in the palette;
- the store is live (no "in development" badge);
- the HRV table stays, marked v2;
- the rejected fixed salary literal is removed everywhere, including comments.

---

## Closed and encoded (v1.5 + v1.6 + v1.6.1 + v1.6.2 + v1.6.3 + v1.6.4 + v1.6.5 + v1.6.6 + v1.6.7 + v1.6.8 + v1.6.9 + v1.6.10 + v1.6.11 + v1.6.12 + v1.6.13 + v1.6.16 + v1.6.17 + v1.6.18 + v1.6.19)

| Item | Resolution | Where encoded |
|------|------------|---------------|
| Turnover cost | Tiers: junior 30–50 %, mid 100–150 %, senior 200–400 % of annual salary. Range results only. 1.5× default, 0.5–2.0 multiplier, `role_cost_config` removed | `turnover_tier_config` (+CHECK), `employee_value_asset.turnover_tier`, `employee_turnover_cost_range_v`, `team_aggregate.turnover_cost_min_sum/max_sum` |
| Deprivation tax | `deprived_count × avg_annual_salary × 0.12` (Oswald 2015 doi:10.1086/681096; Bellet/De Neve/Ward 2024 doi:10.1287/mnsc.2023.4766). No 13–14 %. System-computed only | `rpc_team_aggregate_refresh`, `employee_value_asset.is_deprived` (system path `rpc_set_deprivation_flag`) |
| Privacy thresholds (#3, **locked by Karin 20.10**) | N = distinct employees whose data ACTUALLY feeds the aggregate in that period, never team size. Regular N≥5; project N≥5; Cuckoo / Shadow Balance / emergency N≥10; board N≥20; below → 403 `aggregation_privacy_threshold` | `privacy_threshold_config` (+CHECK), `contributor_count` columns + triggers + RLS, `fn_team_aggregate_contributors`, `fn_team_activity_contributors`, `fn_group_wellbeing` |
| Cuckoo | Employee first; 60-second veto; then direct manager, pseudonym only, no medical details; real user id never visible to the manager | `cuckoo_alert` (target-only RLS), `cuckoo_alert_manager_v`, `fn_cuckoo_raise`, `rpc_cuckoo_veto`, `rpc_cuckoo_commit_expired_job` |
| Spoons (#1 **locked by Karin 20.10**) | 12 hard max; Fighting blocked at 4–5; ≤3 → ALL tasks blocked, Farming included, → home; log only 'יציאה מוקדמת מאושרת' + time; full workday; no sick-day deduction; `<3 / <14 %` rule removed; CB never locks questionnaires or shop | `spoon_budget.day_status`, `fn_cb_check_task`, `early_leave_log`, `rpc_log_go_home`, `early_leave_manager_v` |
| PSC-12 → TPS-12 | Renamed everywhere | `tps_team_avg`, `tps_12_score` |
| Questionnaires | Generic definitions + WORM submissions, once per period in employee timezone. PCQ-12 monthly 10; Cantril monthly 2.5; IHS quarterly score/10; TPS-12 quarterly score/10 (**v1.6.16: rewards are participation-only from agent_settings — monthly 10, short 2, quarterly לא הוגדר; score/10 removed**; **v1.6.17 (Karin 31.10): Cantril monthly 10, TPS-12 / IHS quarterly 10 (adjustable)**); TPS score (sum−12)/48×100, reverse 1/3/5/11, all 12 required, 30-day rule; rounding 0–2 down / 3–5 → 5 / 6–9 up; HR future questionnaires daily..monthly, 0.5–2.5 (v1.6.16: no per-questionnaire amount) | `questionnaire_definition`, `questionnaire_submission`, `rpc_submit_questionnaire`, `fn_tps12_score`, `fn_reward_score_div10`, `fn_tps_band` |
| TPS-12 bands | < 52 low · 52–60 medium · > 60 good | `fn_tps_band` |
| Golden spoons | Fractional numeric(10,1) | `avatar_state.golden_spoons` |
| Golden → CHR | 1 golden = 50 CHR, one-way only | `rpc_convert_golden_to_chr`, `golden_chr_conversion` (rate CHECK = 50) |
| Dutch auction | Removed from v1 (v2) | `shop_tier_enum` = basic, advanced |
| Ledger | SHA-256 chain, pseudonym only, crypto-shredding, WORM 403 `ledger_immutable` | `manager_ledger`, `fn_ledger_chain`, `fn_ledger_verify_chain`, `pseudonym_key`, `rpc_crypto_shred_pseudonym_key` |
| Red team alert (#4, **locked by Karin 20.10**) | Kept: team average spoons < 3 → RED. Team-level trend only (no names, pseudonyms or individual scores). Only when ≥5 employees actually reported spoons in the period; otherwise no alert / 403 `aggregation_privacy_threshold` | `spoon_budget.reported_at`, `fn_team_spoon_reports`, `team_aggregate.spoon_reporter_count` + CHECK `chk_spoon_alert_respondents`, `rpc_team_spoon_alert` |
| Shop access (#6, **locked by Karin 20.10**) | Every user with an employee interface (managers at every tier, CEO, VPs). Governance-only roles without an employee profile → 403. Ex-employees → 403 | `users.has_employee_profile`, `fn_has_employee_profile`, `rpc_everstore_purchase`, `rpc_convert_golden_to_chr` |
| Crypto-shredding (#7, **locked by Karin 20.10**) | Only (1) the employee herself, own data; (2) automatically on offboarding. HR / managers / CEO → 403 `crypto_shred_forbidden` | `rpc_crypto_shred_pseudonym_key` (self), `users.employment_ended_at`, `rpc_offboard_employee` (service_role), `trg_users_offboarding_shred` |
| Pseudonyms (#8, **locked by Karin 20.10**) | System-assigned random colour + animal, unique per company, never from name / id; employee cannot choose or edit; self-set RPC removed | `fn_generate_pseudonym`, `trg_users_pseudonym` (403 `pseudonym_immutable`), `uq_users_company_pseudonym` |
| TPS-12 30-day rule (#5, **locked by Karin 20.10**) | Counts from the day she joined her CURRENT team; new hire = start date; internal transfer resets to the transfer time | `users.team_joined_at`, `trg_users_team_joined`, `rpc_submit_questionnaire` |
| TPS rounding (#2) | Fractional TPS score rounded to a whole number (half-up), then the last-digit rule (0–2 down, 3–5 → 5, 6–9 up, ÷10). **Implemented as proposed; approved by Chief of Drive, awaiting Karin's explicit confirmation** — **superseded in v1.6.16** (no reward from a score; `fn_reward_score_div10` dropped) | `fn_round_score_last_digit` |
| Scrim opacity (#9, prototype, **locked by Karin 20.10**) | `--scrim: rgba(5,10,48,0.5)` approved; no code change | prototype `styles/base.css` (v8.3) |
| B1 Role tree | `org_role` tiers 1–5 (Karin's mapping, Q8 — see the table below) with 14 seeds; `reports_to` (solid) + optional `dotted_line_to`; recursive subtree on the solid line only; cycle / cross-company guard | `org_role`, `users.reports_to`, `fn_solid_subtree` |
| B2 Access | Employees no management access; managers solid subtree; CEO & owners averages only; direct managers pseudonyms only; CHRO named data only with a reason; every view audited (WORM) | `rpc_subtree_summary`, `rpc_company_averages`, `rpc_direct_reports_pseudonyms`, `rpc_chro_named_view`, `access_audit_log`, `fn_audit_view`, `fn_viewer_may_see_pseudonyms` |
| B3 Project manager (v1.6.3, **locked by Karin 20.10**) | Project-level aggregates only — PEWI / AIDB / TRR / M_SPOF — at N≥5 actual respondents (else 403), every view audited; no journals, questionnaires, feedback, individual data or comparisons. The v1.6.2 NULL load index and spoon burnout alert are **removed** | `rpc_project_workload`, `fn_is_pm_of`, `access_audit_log` |
| B4 Board | Quarterly / annual company or division macro trends, N≥20, closed periods only, no drill-down | `rpc_board_macro_trends` |
| B5 Safety & emergency | Only the safety & emergency manager declares / ends; 3 types **locked by Karin 13.10**: `health_or_life_danger` (danger to an employee's health or life), `work_stopping_disaster` (fault / disaster that stops work: fire, flood, systems down), `war_or_security` (war or a security situation); immediate roster while active; CHRO HR review after; misuse rule | `emergency_event`, `emergency_safe_report`, `rpc_emergency_*`, `fn_is_safety_manager_of` |
| B6 Distress button | Employee-only manual press; 60 s grace → cancel = silent log; dispatch to safety manager (name, phone, last location, time) + CHRO awareness (no PII); no NLP; no team access; safety manager closes with enum; PII removed; read-only; WORM audit; CHRO silent notice; false alarms excluded from analytics | `distress_event` (+CHECKs, read-only trigger), `distress_silent_log`, `notification`, `distress_analytics_v`, `rpc_distress_*` |
| Workload indices (v1.6.3, **locked 20.10**; B_t + P>5 replaced in v1.6.4) | EPWI_time = Σ(T_standard×D)/W_effective (target 0.75–0.90; overload > 1.00); EPWI_cognitive = EPWI_time/(1−L(P)), L = 0/20/40/60/75 % for P = 1–5 and **P > 5 counts as 5 → 0.75 (Karin, Q3)** (target 1.10; overload > 1.50); **B_t = 0.41·S + 0.37·O + 0.22·D (Karin 20.10, linear; the sigmoid is removed)** — S = (stress 1–5 − 1)/4, D = (productivity drop 1–5 − 1)/4 (positive weight), O = min(weekly overtime h / 10, 1) clamped at 0; bands low < 0.35, medium 0.35 ≤ B < 0.65, high ≥ 0.65; any input missing → NULL; Likert must be an integer 1–5 and overtime ≥ 0 (400); AIDB = (1−σ_w/μ_w)×100 % (target > 80 %; < 65 % selective burnout risk); TRR = N_reassigned/N_total×100 % (> 18 % planning failure); M_SPOF = 1 + K_critical_single/K_total | `fn_epwi_time`, `fn_epwi_cognitive`, `fn_context_switch_loss` (LEAST(P, 5)), `fn_b_t`, `fn_likert_unit`, `fn_overtime_unit`, `fn_assert_likert_1to5`, `fn_assert_overtime_hours`, `fn_aidb`, `fn_aidb_of`, `fn_trr`, `fn_m_spof`, `fn_*_band` |
| Personal indices employee-only (lock 1, 20.10) | EPWI_time, EPWI_cognitive, B_t visible only to the employee: RLS own rows on `workload_self_report`; `rpc_my_workload_indices` has no user parameter. Managers, PM, CHRO, CEO see nothing | `workload_report_own` policy, `rpc_my_workload_indices` |
| v1 data source (lock 2, 20.10; period Q6; week v1.6.5) | **Weekly** employee self-report only (contract hours, hours worked, overtime, parallel projects, stress 1–5, productivity drop 1–5) in its own table + endpoint, **separate from the daily spoons check-in** (never merged). **Keyed by `week_start_date` (DATE), never an ISO week number; unique (employee, week_start_date); duplicate → rejected (409), not update-in-place**; WORM. The week = the 7-day company week (start = `companies.week_start_dow`) containing **`work_date`** — the start date of the work / shift (a night shift crossing midnight counts toward the day it started), not the submission time. v2 adapter stub (Jira / Asana / Monday) does nothing | `workload_self_report` (`work_date`, `week_start_date`, `uq_workload_report_week`, `chk_workload_week_7_days`), `trg_workload_report_week`, `fn_week_start_for`, `fn_week_last_day`, `fn_local_week_start`, `rpc_submit_workload_self_report(p_work_date)`, `rpc_workload_integration_sync` |
| Soft WIP limit (lock 3, 20.10; core owner Q4) | > 2 **core** projects → alert to the employee and the PM; never blocks; PM alert = assignment count only. **Core = a project property the PM sets explicitly on create (`project.is_core` NOT NULL, no default)**; only the PM of that project (project_manager role + ownership) may change it; switching to core re-checks the limit | `project.is_core`, `rpc_project_create`, `rpc_project_set_core`, `trg_project_member_wip`, `trg_project_core_wip`, `wip_alert`, `rpc_project_assign_member` |
| SPOF / bottleneck (lock 1, 20.10) | Task / project level only; no employee id anywhere | `project_spof_item` (no user columns), `rpc_project_workload.spof_alert` |
| Cuckoo window (**locked by Karin 20.10**) | N≥10 counts distinct reporters over a rolling 30-day window (day 30 in, day 31 out) | `fn_cuckoo_window`, `fn_cuckoo_recent_reporters`, `fn_cuckoo_raise` |
| Safety & emergency manager (**locked by Karin 20.10**) | Separate role OUTSIDE the 5 tiers (least privilege): tier NULL; reports to nobody and nobody reports (solid or dotted) to her; excluded from every subtree; access only to emergency / distress events and only while open; no load / EPWI, wellbeing, climate / questionnaire or team data | `org_role.tier` NULL + `chk_org_role_tier`, `fn_users_reports_to_guard`, `fn_solid_subtree`, `rpc_emergency_roster` (ACTIVE only), `rpc_distress_safety_inbox` (DISPATCHED only) |
| Distress delivery (**locked by Karin 20.10, option a**) | The 60 s cancel window stays; when it ends, push AND SMS are dispatched together immediately — two delivery rows, same transaction, same timestamp, independent; SMS provider stub | `distress_alert_delivery`, `fn_distress_queue_deliveries`, `fn_push_send`, `fn_sms_provider_send`, `rpc_distress_delivery_job` |
| Emergency misuse (Q5, **locked 13.10**; co-signer Q7) | Applies to the declarer. Close (safety manager, `rpc_emergency_end`) → notify (CHRO review MISUSE) → talk. After a second MISUSE she loses the right to open alone: the declaration waits for **the CHRO's co-approval only (Karin, Q7)**. The CHRO never closes and is not needed to close; v1.6.3 `rpc_emergency_misuse_close` removed | `rpc_emergency_end`, `rpc_emergency_hr_review`, `fn_emergency_apply_misuse`, `rpc_emergency_misuse_talk`, `chk_emergency_misuse_sequence`, `fn_emergency_may_open_alone`, `PENDING_COSIGN`, `rpc_emergency_cosign` (CHRO only) |
| CHRO legal reason (Q6, **locked 12.10**) | Any reason permitted under labour law; free text allowed but required (non-empty); every view audited | `rpc_chro_named_view` (400 `reason_required`), CHECK `chk_audit_chro_reason` |
| Company calendar (v1.6.5 Karin; v1.6.6 Chief of Drive) | `country` (ISO 3166-1 alpha-2) required; `week_start_dow` defaults to **CLDR supplemental weekData `firstDay`** of the country (v1.6.6, generated reference table — no hand-coded countries); **IL pinned to Sunday** as an explicit override; a country CLDR does not list → CLDR world default **001 = Monday**; each company may override. `last_workday_dow` and `timezone` (IANA) required on create, no default; day of week 0–6 = Sunday … Saturday; a week is always 7 days | `ref_country_calendar` (+ `_source`), `tools/gen_ref_country_calendar.py`, `fn_ref_country_calendar`, `fn_default_week_start_dow`, `trg_companies_week_start`, `trg_companies_timezone` |
| Upgrade backfill (v1.6.6, Chief of Drive, O-39) | Legacy companies only (NULL values): week start as above; **last workday = day before the CLDR weekend** (`weekendStart` − 1; IL Fri → **Thu**, 001 Sat → **Fri**); **timezone = the country's first zone in IANA `zone.tab`** (IL **Asia/Jerusalem**). Explicit values are never overwritten; each filled value → `access_audit_log` action `company_calendar_autofill`, scope `{field, value, auto_filled: true, cldr_source, tz_source}`. Columns become NOT NULL once complete | `fn_backfill_company_calendar`, `fn_backfill_company_field`, `fn_company_calendar_lock_not_null`, `fn_default_last_workday_dow`, `fn_default_timezone` |
| Work date range (v1.6.6, Chief of Drive, O-40) | `work_date` within **employee-local today − 14 … today + 1** (her own timezone, O-42); outside → **HTTP 422 `work_date_out_of_range`** (Error Contract shape; SQLSTATE `PT422`). Checked on submit (RPC); direct table writes are not granted to clients | `fn_assert_work_date_in_range`, `rpc_submit_workload_self_report` |
| Weekly reminder (v1.6.5, **Karin 20.10**) | On the company's last workday at `reminder_time`, **default 14:00 (locked)**, company-local; each company may change it. Not a submission rule. Sender job = stub | `companies.reminder_time`, `fn_company_reminder_at`, `rpc_company_settings`, `rpc_company_settings_update`, `rpc_workload_reminder_job` (stub). v1.6.4 `workload_reminder_setting` removed |
| HRV | v2 only; table kept, unused, no client grant | `hrv_sample` |
| Carried from 1.4 | N-1 local-midnight reset; N-4 timezone; N-2 catalog 8 items @ 10/20; RPC naming; 403 codes; consent default FALSE; ciphertext-only journal/anchor; Task Cost matrix | unchanged |

---

## Still OPEN (TODO in code — do not invent)

| # | Item | Status in v1.6 |
|---|------|----------------|
| O-1 | ~~Turnover: which point inside the tier range is used~~ | **Resolved (Karin 24.10)** — tier midpoint: junior 40 % (0.40), mid 125 % (1.25), senior 300 % (3.00); min/max range kept alongside `midpoint_pct` |
| O-2 | ~~What decides an employee's tier~~ | **Resolved (Karin 24.10)** — defaults automatically from `org_role.tier` (1→junior, 2–3→mid, 4→senior, 5/outside→NULL excluded unless overridden); CHRO (`vp_hr`) may override per employee |
| O-3 | ~~What marks an employee "deprived"~~ | **Resolved (Karin 24.10)** — deprived in a week when weekly average available spoons < 5 OR weekly burnout score `B_t >= 0.65` (`fn_is_employee_deprived`) |
| O-4 | ~~`avg_annual_salary` definition~~ | **Resolved (Karin 24.10)** — company-wide average annual salary of employees in that turnover tier group (`fn_company_tier_avg_salary`), never individual or small-team salary averages |
| O-5 | ~~Morning / noon check-in scoring → spoons~~ | **Resolved (Karin 24.10)** — `rpc_morning_checkin` (simple average of 0–10 scales, half-points floored in employee's favor, sets `reported_at`) & `rpc_midday_checkin` (12:00–15:00 local, integer delta −4..+4, capped 0..12) |
| O-6 | ~~IHS score source~~ | **Resolved (Karin 24.10)** — 1–5 anonymous questionnaire answers converted linearly to 0–100 (`(mean - 1) / 4 * 100`, `fn_ihs_score`); IHS submission enabled (`scoring_not_locked` removed); `ihs_team_avg` at N≥5 respondents. Note: exact IHS item wording/count in UI remains TODO להשלמה |
| O-7 | ~~PCQ-12 answer scale~~ | **Resolved (Karin 24.10)** — locked as 1–6 (Luthans original scale, 12 items, all required), converted linearly to 0–100 (`(mean - 1) / 5.0 * 100`, `fn_pcq12_score`, `questionnaire_submission.pcq12_score`) |
| O-8 | ~~TPS fractional scores (e.g. 66.67) before last-digit rounding~~ | **Resolved (Karin 24.10)** — confirmed as built: round to nearest integer first, then apply last-digit rounding (to 0 or 5) |
| O-9 | ~~"30 days in team" start date~~ | **Resolved (#5)** — `team_joined_at` |
| O-10 | ~~Farming tasks at ≤3 spoons~~ | **Resolved (#1, Karin 20.10)** — ALL tasks blocked at ≤3, Farming included |
| O-11 | ~~Team definition for N~~ | **Resolved (#3, Karin 20.10)** — N = actual contributors in the period, never team size. The offboarded-members TODO is answered: membership does not decide N. The Cuckoo contribution window is a question for Karin (Q-K1 below) |
| O-12 | ~~Red alert rule~~ | **Resolved (#4 + O-5)** — respondent-based N≥5; `rpc_morning_checkin`, `rpc_midday_checkin` and `rpc_log_go_home` all set `spoon_budget.reported_at` |
| O-13 | ~~Ledger chain scope; genesis record; broken-chain response~~ | **Resolved (Chief of Drive 24.10)** — one ledger chain per company (`org_id`), genesis record (`event_type = 'GENESIS'`) seeded on company creation, and `fn_ledger_verify_chain` writes an audit alert (`ledger_chain_broken`) + blocks writes (`403 ledger_chain_broken`) on a broken chain |
| O-14 | ~~Who may shred & offboarding retention period~~ | **Resolved (#7 + Karin 24.10)** — self-request (`rpc_request_crypto_shred`) executes immediate crypto-shredding (0-day wait); automatic offboarding (`rpc_offboard_employee`) revokes access & vault immediately and schedules crypto-shredding for `terminated_at + 30 days` (cancellable via `rpc_revert_offboarding` within 30 days); `rpc_run_scheduled_crypto_shred` shreds elapsed keys |
| O-15 | ~~Pseudonym assignment~~ | **Resolved (#8)** — system-assigned, unique per company, immutable |
| O-16 | ~~Currencies & EverStore in v1~~ | **Resolved (Karin 24.10 & 25.10)** — only Golden Spoons active in v1 (0.5 daily, 2 per shift, 10 at signup; **never expire** while active); `rpc_convert_golden_to_chr` stays active on server in v1 (UI button hidden until v2; **superseded in v1.6.16: blocked, 422 `chr_coins_deferred_to_v2`**); `shop_item_catalog` expanded to 8 categories with any positive `price_golden_spoons > 0`, `provider`, `cosmetic_only` true/false (`real_money_purchase_allowed=false` and `affects_daily_energy_spoons=false` locked), and `time_benefit` voucher redemption privacy (`נעילת הפרגוד`: `approved_absence_entry` / `approved_absence_manager_v`) |
| O-17 | ~~Emergency mode~~ | **Resolved (B5, Q5, Q7)** — 3 type names locked; misuse sequence close → notify → talk; co-signer = CHRO only (O-35) |
| O-18 | ~~Shadow Balance / happiness debt / 12 % deprivation tax / CHR Real EBITDA~~ | **Resolved (Karin 24.10)** — encoded in `shadow_balance_aggregate` + `rpc_shadow_balance_refresh` at N≥10 respondents (`chr_real_ebitda = gaap_reported_ebitda - happiness_debt_balance - deprivation_tax_amount`) |
| O-19 | ~~RBAC v3 & manager vault rules~~ | **Resolved (Chief of Drive 24.10)** — direct manager only (`is_management` and not `averages_only`), requires office-network + company-device flags (`is_office_network = true AND is_company_device = true`) + inactivity timeout check (`<= 15 min` default), and immediate wipe on manager transfer/dismissal or employee transfer/offboarding (`manager_vault_session`, `manager_vault_entry`, `rpc_manager_vault_*`) |
| O-20 | ~~Shop access & governance-only provisioning~~ | **Resolved (#6 + Chief of Drive 24.10)** — CHRO (`vp_hr`) provisions governance-only users via `rpc_provision_governance_user`, defaulting `has_employee_profile = false` for tier 5 roles unless explicitly marked as also an employee |
| O-21 | Upgrade migration from a live 1.4 database | Fresh install only |
| O-22 | Avatar weights / immunity, Contrast Nullification, Dutch auction, sensors/HRV | v2 |
| O-23 | Mobile wireframe designer approval | Not in backend |
| O-24 | ~~Project load-index formula~~ | **Replaced (v1.6.3)** by the locked workload formulas; the v1.6.2 NULL load index and burnout flag are removed. PEWI (project-level aggregate) is named in the doc §6.2 but has **no formula** → `pewi` NULL, TODO להשלמה |
| O-25 | ~~Board / Tier 5 metrics~~ | **Resolved (Karin 24.10)** — tier 5 governance roles (`board_chair`, `board_member`, `owner_shareholder`) see all company-wide organizational averages at the whole-company level only (`rpc_get_board_macro_metrics`, `rpc_company_averages`: TPS-12, spoons, workload / EPWI / PEWI, IHS at N≥5; Happiness Debt, deprivation tax, CHR Real EBITDA at N≥10), and never any team or individual breakdown (`403`) |
| O-26 | Distress transport | **Resolved (20.10, option a)** — push + SMS together right after the 60 s window. TODO להשלמה: SMS and push provider adapters (stubs return `PROVIDER_NOT_CONFIGURED`); job cadence |
| O-28 | ~~B_t inputs O_t, D_t, S_t~~ | **Resolved (Karin 20.10)** — linear B_t from stress, overtime, productivity drop (see *B_t provenance* below) |
| O-29 | ~~P > 5 parallel projects~~ | **Resolved (Karin, Q3)** — P > 5 counts as 5 → L = 0.75 |
| O-30 | ~~EPWI_cognitive "target 1.10"~~ | **Resolved (Chief of Drive 24.10)** — confirmed: `<= 1.10` is `target`, `> 1.10` and `<= 1.50` is `above_target`, `> 1.50` is `overload` (danger) |
| O-31 | ~~AIDB σ: population vs sample~~ | **Resolved (Chief of Drive 24.10)** — confirmed: population standard deviation σ (`stddev_pop`) |
| O-32 | ~~Who classifies a project as core / migration~~ | **Resolved** — the PM, explicitly on create (Q4); **migration (Karin 20.10): existing projects → `is_core = false` until their PM marks them** (`fn_migrate_project_is_core`: UPDATE legacy NULL rows, then NOT NULL, no default). New projects still have no default |
| O-33 | ~~Pressure question scale~~ | **Resolved (Karin, Q5)** — integer Likert 1–5; the v1.6.3 `pressure` field is now `stress_1to5` (S), plus `productivity_drop_1to5` (D) |
| O-34 | ~~Self-report period / week start / reminder~~ | **Resolved** — weekly (Q6); week start per company by country (v1.6.5; the ISO-Monday vs Sun–Thu question is answered); reminder last workday 14:00 company-local. Remaining TODOs listed below |
| O-35 | ~~Who may co-sign~~ | **Resolved (Karin, Q7)** — the CHRO (HR VP) only; another safety manager is rejected; the CHRO never closes |
| O-27 | Prototype border `--line #E8EBF1` matches the page background (v8.4) | **Question for Karin** — no change made |

---

## v1.6.3 — formula inputs: self-report proxy or v2 (lock 2)

| Formula | Input | v1 source | Status |
|---------|-------|-----------|--------|
| EPWI_time | Σ(T_standard × D) — standard time × demand | `hours_worked` (self-reported hours actually worked this week, incl. overtime) | **Proxy** (true T_standard and D come from task tools → v2) |
| EPWI_time | W_effective — effective capacity | `contract_hours` (self-reported contracted weekly hours) | **Proxy** (non-productive time not deducted; v2) |
| EPWI_cognitive | P — parallel projects | `parallel_projects` (self-report) | **Direct** (self-report) |
| EPWI_cognitive | L(P) | locked table 0/20/40/60/75 % | Locked; P > 5 counts as 5 (Q3) |
| B_t | S, O, D | `stress_1to5`, `overtime_hours`, `productivity_drop_1to5` (weekly self-report) | **Direct** (Karin 20.10); any one missing → `b_t` NULL |
| AIDB | w (per-member load), σ_w, μ_w | `hours_worked` of each respondent of the project that week | **Proxy** (doc: action items per member → v2) |
| TRR | N_reassigned, N_total | — | **v2** (task reassignment history); `trr` NULL |
| M_SPOF | K_critical_single, K_total | `project_spof_item` filled by the v2 adapter only | **v2**; `m_spof` NULL until items exist |
| PEWI | EPWI of each reporting member | `hours_worked` / `contract_hours` → EPWI_time per member | **Resolved v1.6.7 (Karin):** mean EPWI_time of the project's members who reported in the company week; see *Resolved in v1.6.7* |
| Soft WIP | core project count | `project_member` × `project.is_core` (PM toggle) | Direct |
| (unused) | — | — | All self-report fields now feed a locked formula |

## v1.6.4 — B_t provenance (recorded honestly)

| Element | Source |
|---------|--------|
| Weights 0.41 / 0.37 / 0.22 | Karin's decision (20.10): the research doc's §5.3 SEM standardized betas — work–life imbalance β = 0.382, workload β = 0.345, autonomy β = −0.203 (abs. value) — normalized to sum to 1 and mapped to **stress (0.41), overtime (0.37), productivity drop (0.22)**. Used exactly as given, not recomputed |
| Construct gap | The mapped inputs are **different constructs** from the study variables (work–life imbalance → stress; workload → overtime; autonomy → productivity drop). Autonomy was *protective* (negative β) in the study; productivity drop has a *positive* weight here by Karin's decision. The §5.3 paragraph has no inline citation in the doc |
| 10-hour overtime cap | Karin's number (20.10); not in the doc |
| Bands 0.35 / 0.65 | The infographic (only place they appear); not in the doc text |
| Scales | Stress and productivity drop: integer Likert 1–5 (Karin, Q5); overtime: weekly hours |
| Calibration | v2 — the doc itself (§6.3) calls calibration of the index parameters future work |
| Removed | v1.6.3 sigmoid `σ(0.50·O − 0.30·D + 0.20·S)` (`fn_sigmoid`). The "D_t inversion" and "contract-hours cap" named in the 20.10 instruction were **not present** in the v1.6.3 pack (B_t was NULL there), so there was nothing further to remove |

## v1.6.4 — role → tier mapping (Karin, Q8; tiers 2 ↔ 3 swapped in v1.6.5) — **for Karin's review**

For **access**, the tier is a **label only** (no access function reads `org_role.tier`, tested). Since v1.6.11 (**O-2**, Karin 24.10), `org_role.tier` supplies the automatic default for `employee_value_asset.turnover_tier` (tier 1 → `junior`, tiers 2–3 → `mid`, tier 4 → `senior`, tier 5 / outside → excluded unless overridden by the CHRO).

| Role code | Hebrew name (schema) | Tier |
|-----------|----------------------|------|
| employee | עובד/ת | 1 |
| direct_manager | מנהל/ת ישיר/ה | 1 |
| functional_manager | מנהל/ת פונקציונלי/ת (solid line) | 2 |
| project_manager | מנהל/ת פרויקט (dotted line) | 2 |
| department_manager | מנהל/ת מחלקה | 3 |
| division_manager | מנהל/ת חטיבה | 3 |
| director | דירקטור/ית תפעולי/ת | 3 |
| vp | סמנכ"ל/ית (CHRO = `app_role` vp_hr; COO / CFO / CTO share this role) | 4 |
| evp | סמנכ"ל/ית בכיר/ה | 4 |
| ceo | מנכ"ל/ית | 4 |
| board_chair | יו"ר דירקטוריון | 5 |
| board_member | חבר/ת דירקטוריון | 5 |
| owner_shareholder | בעלים / בעל/ת מניות | 5 |
| safety_emergency_manager | מנהל/ת בטיחות וחירום | — (outside the tiers) |

Notes: all 13 tiered schema roles fit Karin's list; no listed role is missing. "Product manager" has no separate role — it is covered by `project_manager`. CHRO / COO / CFO / CTO are one `vp` role (the CHRO is distinguished by `app_role`). v1.6.5: tier 2 = functional / project manager, tier 3 = department / division manager, director (Karin's swap); the direct manager stays on tier 1 with employees. Labels only — no access follows from them (tested: no access function reads `org_role.tier`).

## Resolved in v1.6.6 (Chief of Drive, 20.10)

| # | Resolution |
|---|-----------|
| O-37 | ~~Week-start country exceptions~~ — CLDR 48 weekData `firstDay` (cldr-core 48.2.0), generated table; IL pinned Sunday; unknown → 001 Monday. Values: **IL sun (0), US sun (0), DE mon (1)** |
| O-39 | ~~Legacy companies need explicit values~~ — backfilled from CLDR `weekendStart` − 1 and IANA tzdata 2026c `zone.tab` (first zone), audited as auto-filled. Values: **IL Thu (4) / Asia/Jerusalem; DE Fri (5) / Europe/Berlin; US Fri (5) / America/New_York** |
| O-40 | ~~work_date range~~ — today − 14 … today + 1, employee-local; else 422 `work_date_out_of_range` |
| O-42 | ~~Employee tz for the week key vs company tz for the reminder~~ — **OK as built** (Chief of Drive) |

### Data notes from the generator (for review)
- **CLDR vs ruling ("Monday-start → Friday"):** one disagreement — **UG** (Uganda): CLDR has no `firstDay` (→ 001 Monday) but `weekendStart = sun`, so the derived last workday is **Saturday**, not Friday. Also outside the ruling's two cases: Sunday-start **IN** (weekendStart sun → Saturday), and Saturday / Sunday-start Gulf / Middle-East countries (e.g. AF Wed, others Thu). The pack uses the CLDR-derived value everywhere (no hand-coded exception) — confirm.
- **zone1970.tab vs zone.tab:** the generator uses **zone.tab** (one country per row). In zone1970.tab the *first* row containing DE is `CH,DE,LI → Europe/Zurich`, which would make Germany Zurich; zone1970.tab merges countries that share a zone since 1970, so its "first entry" is not a country's main zone for 99 countries. zone.tab gives DE → Europe/Berlin. IL and US agree in both.
- **No zone in zone.tab:** **XK** (Kosovo; CLDR lists it) and **AN** (obsolete Netherlands Antilles) — ~~kept NULL~~ **v1.6.7: explicit overrides XK → Europe/Belgrade, AN → America/Curacao** (Chief of Drive, O-43), recorded in the generator and in `ref_country_calendar.main_timezone_source`.
- **Multi-zone countries (O-39 flag; the backfill picks the FIRST zone.tab zone — confirm per real company):** 31 in v1.6.7, **30 since v1.6.8** (DE single-zone, see the exclusion list) — AQ (10), AR (12), AU (12), BR (16), CA (23), CD (2), CL (4), CN (2), CY (2), DE (2), EC (2), ES (3), FM (3), GL (4), ID (4), KI (3), KZ (7), MH (2), MN (2), MX (12), MY (2), NZ (2), PF (3), PG (2), PS (2), PT (3), RU (26), UA (2), UM (2), **US (29 → America/New_York)**, UZ (2).

## Resolved in v1.6.7 (Karin + Chief of Drive, 20.10)

| # | Resolution |
|---|-----------|
| O-36 | ~~Who may change company settings~~ — **only the CHRO (`app_role = vp_hr`)**; there is no system-admin role (Karin). Refusal tests kept (employee / manager → 403) |
| O-41 | ~~Changing `week_start_dow` after reports exist~~ — implemented (Karin) — **transition rule replaced in v1.6.8 (bridge, see below)**: takes effect at the **next week boundary**; never blocked; stored reports immutable, never recalculated; setting stored with `effective_from` (`company_week_start_history`, append-only); each report's week resolves against the rule in force on its `work_date`; every change audited (`company_week_start_change`); no overlap, no gap. **Rule needs Karin's confirmation — see the conflict below** |
| O-43 | ~~Multi-zone / zone-less countries~~ — multi-zone backfill keeps the first `zone.tab` zone with `timezone_status = needs_review` (API: `rpc_company_settings`; CHRO clears it with `rpc_company_timezone_confirm`, audited). XK → Europe/Belgrade, AN → America/Curacao (documented overrides, next to the IL pin). A legacy company **without a country** gets no backfill: `needs_review` + **reminders on hold** (audit `reminders_on_hold`) until a country is set, which releases them (audit `reminders_released`) |
| O-44 | ~~CLDR-derived last workday (UG Sat, IN Sat, AF Wed …)~~ — CLDR values **approved** (Chief of Drive) |
| — | `zone.tab` (not `zone1970.tab`) as the zone source — **approved** (Chief of Drive) |
| C-3 / PEWI | ~~PEWI formula~~ — **PEWI = average EPWI of the employees assigned to the project** who reported in the window, only at **≥ 5 actual reporters** (`fn_privacy_min_n('project')`); below → `pewi` NULL with `suppressed = true` (`rpc_project_pewi`, not 403). Every view audited (`project_pewi_view`); no individual values. TRR and M_SPOF stay v2 stubs |

### O-41 — transition rule of v1.6.7 (SUPERSEDED in v1.6.8)
- v1.6.7 stretched the final old week to 8–13 days. **Replaced** by Karin's locked bridge rule of 21.10 (next section). The 1.6.7 report check (`chk_workload_week_span`, +12 days) is dropped; the 7-day check `chk_workload_week_7_days` is back.

### PEWI — choices made
- "EPWI" = **EPWI_time** (hours_worked / contract_hours) — **resolved v1.6.8 (Chief of Drive 21.10: OK as built)**.
- **Window:** the existing **company week** (`week_start_date` of the PM's current company week, or the requested week) — no separate EPWI window exists in the pack. Reporters = assigned members (`project_member`) with a self-report keyed to that week.
- **Two response shapes below 5 reporters — kept on purpose (Chief of Drive 21.10):** `rpc_project_workload` answers **403** `aggregation_privacy_threshold` (locked B3 contract for the whole aggregate set), while `rpc_project_pewi` answers **200 with `pewi: null, suppressed: true`** (the PEWI-only view must not fail). Same threshold (N_project = 5), same audit (every call), no individual values in either. A client must handle both.

### Timezone status — notes (honest)
- **DE:** zone.tab lists Europe/Berlin and Europe/Busingen. v1.6.7 flagged DE `needs_review`; **v1.6.8: Busingen is excluded (exclave, Chief of Drive 21.10) → DE single-zone, `confirmed`.** IL (1 zone) → confirmed; US (29) → needs_review; XK / AN (override) → confirmed.
- When a held company gets its country: timezone from the reference table; `confirmed` if one zone, `needs_review` if several. **v1.6.8: an unknown (well-formed) code is refused with 422 `unknown_country`, so the hold stays** (a malformed code still fails the column CHECK → 400).
- An explicit `p_timezone` from the CHRO in `rpc_company_settings_update` counts as confirmation.

## Resolved in v1.6.8 (Karin + Chief of Drive, 21.10)

| # | Resolution |
|---|-----------|
| O-41 | **Short bridge** (Karin, locked 21.10). The last old week stays a full **7 days**; from its end up to the day before the first new start day is a **bridge of 1–6 days**: no week, no load report (**422 `bridge_period`**, SQLSTATE PT422), no reminder. After the bridge every week is exactly 7 days; old week → bridge → new week never overlap and leave no gap. The change and the bridge dates are audited (`company_week_start_change`: `final_old_week_start/end/days = 7`, `bridge_start`, `bridge_end`, `bridge_days`). Stored reports immutable |
| O-49 | **TPS 30-day wait** = `team_joined_at` (employee-local date) → `hire_date` (new, nullable, no default) → **exempt**. The insert-day / start_date fallback for `team_joined_at` is removed (fresh inserts and the migration). The source used is audited per user (`tps_wait_source`: team_join / hire / exempt — on insert, on every change of source or start date, plus a one-off backfill for existing users) |
| PEWI | Time-based EPWI — **OK as built** (Chief of Drive) |
| PEWI-a | Both response shapes kept: 403 in `rpc_project_workload` (B3), null + suppressed in `rpc_project_pewi` — documented above |
| Unknown country | **422 `unknown_country`**, the hold is kept (Chief of Drive) |
| DE zones | **DE single-zone** — documented manual zone **exclusion list** (generator `ZONE_EXCLUSIONS`, table column `tz_zones_excluded`): only `Europe/Busingen` (ruling 21.10) |
| O-45 | The 7 `legacy_v1_4_*` tables stay **frozen, read-only, never dropped** (Chief of Drive): no write grant for anon / authenticated / service_role, and row + TRUNCATE triggers (`fn_legacy_read_only` → `legacy_read_only`) refuse writes for every role, the owner included |
| O-46, O-47 | OK as built (Chief of Drive) |
| O-48 | OK as built; empty `reported_at` of migrated days is marked: `spoon_budget.row_source = 'legacy_v1_4'` (new rows `'app'`) |

### O-41 bridge — examples (change made Wed 2026-10-21)
- **Sun → Mon:** last old week **Sun 2026-10-18 … Sat 2026-10-24** (7 days) · bridge **Sun 2026-10-25** (1 day) · first new week **Mon 2026-10-26 … Sun 2026-11-01**.
- **Mon → Sun:** last old week **Mon 2026-10-19 … Sun 2026-10-25** (7 days) · bridge **Mon 2026-10-26 … Sat 2026-10-31** (6 days) · first new week **Sun 2026-11-01 … Sat 2026-11-07**.
- Rule: `effective_from` = first new start day ≥ (current week start + 7), current week taken at the latest of company-local today / latest stored `work_date` / latest scheduled change (unchanged from 1.6.7). Bridge = `old week start + 7 … effective_from − 1`, length `(new − old) mod 7` days.
- **"No bridge" case:** the bridge would be empty only if the new start day fell exactly on the end of the last full old week (= old week start + 7). That day always has the OLD start day, so it happens only when the day does not change — which is a no-op (nothing scheduled, nothing audited). **For every real change the bridge is 1–6 days** (tested for all 42 pairs).
- Bridge days have no week key: `fn_company_week_start` → NULL, `fn_company_bridge_at` → (start, end); `fn_company_reminder_at` → NULL for them, and no week's reminder falls on one. 409 duplicate check unchanged in normal weeks.
- **Upgrade note (honest):** a 1.6.7 database may already hold a report on a stretched 8th–13th day. Reports are immutable, so it is kept; the 7-day check is then added `NOT VALID` (new rows still checked) and a notice is printed. Checked manually (not in the automated suite) by upgrading a database loaded with the 1.6.7 pack and its tests: 1 such row, kept; the check was added NOT VALID. **v1.6.9 (Chief of Drive 21.10, rule 5): OK** — the old report is kept and the constraint stays NOT VALID. Known affected rows and the query that finds them: see "Resolved in v1.6.9 → NOT VALID rows" below.

### Zone exclusion list — effect (Chief of Drive 21.10, rule 4)
- v1.6.8 listed **Europe/Busingen** only. Effect: **DE 2 → 1 zones (needs_review → confirmed)**. Multi-zone countries: 31 → 30. **v1.6.9 adds five more (O-51) → 25** — see "Resolved in v1.6.9".
- v1.6.8 report (since ruled in v1.6.9): 2-zone countries whose second zone has the same UTC offset as the first in Jan and Jul 2026 — **CY** (Famagusta), **MH** (Kwajalein), **MY** (Kuching), **PS** (Hebron), **UZ** (Samarkand/Tashkent). Also note **UA**: zone.tab lists Europe/Simferopol **before** Europe/Kyiv, so a backfilled UA company gets Simferopol (flagged needs_review) — confirm per real company.

### TPS wait — notes
- ~~`users.start_date` (DEFAULT CURRENT_DATE) kept next to `hire_date`~~ — **v1.6.9 (O-50): merged**, see below.
- Migrated v1.4 users: `hire_date` ← v1.4 `start_date`, the only v1.4 employment-start field. ~~Caveat: not distinguishable from the insert-day default~~ — **v1.6.9: a start_date equal to the record's creation date is treated as unknown** (rule below). `team_joined_at` stays NULL (v1.4 has no team-join field — none invented).

## Resolved in v1.6.9 (Chief of Drive, 21.10)

| # | Resolution |
|---|-----------|
| O-50 | **`hire_date` is the single source.** `users.start_date` = deprecated **read-only alias**: `GENERATED ALWAYS AS (hire_date) STORED` (chosen as the simplest correct option: always equal, no trigger, any write refused by PostgreSQL with SQLSTATE 428C9 / PostgREST 400). No 'today' default; `hire_date` nullable, no default. **Removal planned for v1.7** (openapi `deprecated: true`, README). Nothing in schema / rpc / openapi read start_date (checked); the test fixtures that wrote it now write `hire_date`. A user with no hire_date has start_date NULL and no TPS wait |
| O-50 migration rule | A v1.4 `start_date` equal to the record's creation date → **unknown**: `hire_date` NULL (TPS exempt), audited **`start_date_untrusted`** (`scope`: user_id, start_date, created_at_date, compared_in = UTC; viewer NULL). **v1.4 has the column:** `users.created_at timestamptz NOT NULL DEFAULT clock_timestamp()` (real v1.4 schema, tests/fixtures/v1_4_schema.sql) — nothing invented. **Comparison:** date portion of `created_at` **in UTC** (`fn_start_date_untrusted`) — the v1.4 default `CURRENT_DATE` is evaluated in the database session's zone, which is UTC on Supabase. Implemented once in the schema (`fn_users_merge_start_date`), so it applies to the v1.4 migration and to an in-place 1.6.7 / 1.6.8 upgrade alike |
| O-51 | Zone exclusion list extended (each excluded zone = the country's **second** zone.tab entry; kept = first entry, unchanged): **CY** Asia/Famagusta (kept Asia/Nicosia) · **MH** Pacific/Kwajalein (kept Pacific/Majuro) · **MY** Asia/Kuching (kept Asia/Kuala_Lumpur) · **PS** Asia/Hebron (kept Asia/Gaza) · **UZ** Asia/Tashkent (kept Asia/Samarkand). **UA** pinned to **Europe/Kyiv** (`TZ_OVERRIDES`, `main_timezone_source` = 'override: Chief of Drive 21.10 (O-51, UA pinned Kyiv)') |
| Rule 4 | DROP / ALTER of `legacy_v1_4_*` blocked by **event triggers** (`migrations/legacy_ddl_guard.sql`, installed by the runner with a superuser) — see README for lifting |
| Rule 5 | NOT VALID 7-day check with the old report kept — **OK** (rows below) |

### O-51 — same-offset check (generator `verify_exclusions`, re-run on every generation; generation aborts on a mismatch)
| Country | Excluded | Kept | Same UTC offset every hour 2026-01-01 … 2038-01-01 (UTC, tzdata 2026c) | Last hour they differed (since 1970) |
|---|---|---|---|---|
| CY | Asia/Famagusta | Asia/Nicosia | yes | 2017-03-26 00:00 UTC |
| DE | Europe/Busingen | Europe/Berlin | yes | 1980-09-28 00:00 UTC |
| MH | Pacific/Kwajalein | Pacific/Majuro | yes | 1993-08-21 11:00 UTC |
| MY | Asia/Kuching | Asia/Kuala_Lumpur | yes | 1981-12-31 15:00 UTC |
| PS | Asia/Hebron | Asia/Gaza | yes | 2011-09-29 20:00 UTC |
| UZ | Asia/Tashkent | Asia/Samarkand | yes | 1991-03-30 20:00 UTC |
- Effect: CY, MH, MY, PS, UZ 2 → 1 zones → backfill `confirmed`. **Multi-zone countries: 30 → 25** (AQ, AR, AU, BR, CA, CD, CL, CN, EC, ES, FM, GL, ID, KI, KZ, MN, MX, NZ, PF, PG, PT, RU, UA, UM, US). US (29) still needs_review.
- **UA:** main zone Kyiv by override, but Europe/Simferopol is **not** excluded (it was not ruled, and its offset differs from Kyiv's today) → UA still counts 2 zones → backfill `needs_review` (Kyiv).
- Note: for **UZ** the kept zone is zone.tab's first entry, Asia/Samarkand, not the capital's Asia/Tashkent; offsets identical, so no behavioural effect — swap only if the Chief of Drive wants the capital's zone name. **→ v1.6.10: swapped (Tashkent kept, Samarkand excluded); UA confirmed by the pin rule.**

### NOT VALID rows after a 1.6.7 → 1.6.8+ upgrade (rule 5)
- Known affected rows: **none known in any real database** (the pack has no access to one). The only instance seen is in the 1.6.7 **test** data: 1 row — company `00000000-0000-0000-0000-0000000000e1`, `week_start_date` 2026-10-18, `work_date` 2026-10-25 (day index 7, the stretched day), found by upgrading a database loaded with the 1.6.7 pack + its tests to 1.6.9 (checked 21.10; the upgrade prints `1 stored 1.6.7 report(s) lie on a stretched day; 7-day check added NOT VALID`).
- Query that lists them on any database:
  ```sql
  SELECT report_id, user_id, company_id, week_start_date, work_date, work_date - week_start_date AS day_index
    FROM workload_self_report
   WHERE NOT (work_date BETWEEN week_start_date AND week_start_date + 6)
   ORDER BY company_id, work_date;
  -- constraint state: SELECT convalidated FROM pg_constraint WHERE conname = 'chk_workload_week_7_days';
  ```
- Once the list is empty (it cannot become empty by itself — reports are immutable), `ALTER TABLE workload_self_report VALIDATE CONSTRAINT chk_workload_week_7_days` would make it valid. TODO להשלמה only if such a row is ever found in a real database.

### O-50 — upgrade results (checked 21.10, scratch databases)
- v1.4 fixture (migration): 10 users → 8 hire dates from start_date, 1 untrusted (u1: start 2025-09-14 = created 2025-09-14 10:00 UTC), 1 without start_date.
- Database with the 1.6.8 pack + its tests, upgraded in place: 108 users, 104 with a start_date; 100 copied into hire_date, **1 untrusted** (audited), 7 already had a hire_date.
- Database with the 1.6.7 pack + its tests, upgraded in place: 102 users → 101 hire dates, 1 untrusted.
- **Edge (honest):** UTC is the comparison zone. A v1.4 row created between local midnight and UTC midnight (e.g. 01:30 Asia/Jerusalem = 22:30 UTC the day before) whose start_date was defaulted in a *non-UTC* session would not be caught; the fixture keeps such a row (u3) to show it is treated as trusted under the UTC rule.

## Resolved in v1.6.10 (Chief of Drive, 21.10) — final cleanup, backend frozen

| # | Resolution |
|---|-----------|
| O-54 UA | **Pin is final.** Generic rule (`schema.sql fn_country_tz_needs_review`): a country is needs_review only if `tz_zone_count > 1` **and** its zone is not an explicit pin (`main_timezone_source LIKE 'override:%'`). Used by the backfill and the release trigger. UA → Europe/Kyiv **confirmed**. `tz_zone_count` itself is unchanged (UA still lists 2 zones) |
| O-54 UZ | **Capital kept:** UZ main zone = **Asia/Tashkent**; **Asia/Samarkand excluded** instead (`ZONE_EXCLUSIONS`). Same-offset check re-run by the generator: identical every hour 2026-01-01 … 2038-01-01; last differed 1991-03-30 20:00 UTC |
| O-53 | **No superuser → fallback, not failure.** The runner tries the event-trigger guard; when refused it applies `migrations/legacy_lockdown_fallback.sql` as the app owner: REVOKE ALL on every `legacy_v1_4_*` table from every grantee (PUBLIC, anon, authenticated, service_role, the app owner, any other ACL entry); tables (and the legacy enum type) moved to schema **`legacy_v1_4`**; owner → dedicated **NOLOGIN** role **`legacy_v1_4_owner`**; loud WARNING; audit row **`legacy_guard_fallback`** (scope: owner, schema, tables, moved, installed_by, reason; only when something moved). Replaces the v1.6.9 refusal. Tested with a LOGIN CREATEDB CREATEROLE BYPASSRLS non-superuser (`chr_app_owner`) |
| Rule 4 (tz) | **Source timezone preflight** (`migrations/preflight_tz.sql`, run by the runner before the backup and inside the migration): `current_setting('TimeZone')` of the source DB must be UTC (UTC / Etc/UTC / GMT / UCT / Zulu / Universal / Greenwich aliases); otherwise the run **stops** with a clear message unless `--source-tz <zone>` (psql `-v source_tz=<zone>`) is given — then the trust rule compares dates in that zone (`fn_mig_source_tz`; `compared_in` in the audit). Users whose `created_at` is within 1 hour of local midnight (23:00–01:00 inclusive, in the zone used) are audited **`tz_edge_review`** — flag only, no behaviour change |

### O-53 fallback — why the schema move (found by the v1.6.10 tests)
- The app owner of a database owns schema `public` through `pg_database_owner`, and **a schema owner may DROP any table in it** even when it does not own the table. Ownership transfer alone therefore did not block `DROP TABLE` (test failed); the tables are moved to schema `legacy_v1_4`, owned by `legacy_v1_4_owner`, with no USAGE for anyone. The legacy enum type moves too (otherwise `DROP TYPE … CASCADE` by its owner would drop the dependent column).
- In fallback mode the frozen tables are read as `legacy_v1_4.legacy_v1_4_<name>` (with a temporary membership, see the file header); in guard mode they stay in `public`.

### Gaps (honest) — v1.6.10
- **Fallback is weaker than the event trigger.** PostgreSQL 16+: the role that creates `legacy_v1_4_owner` (CREATEROLE) keeps **ADMIN OPTION** on it and could deliberately grant itself the role again; a superuser can do anything; the database owner can still `DROP DATABASE`; the owner of the public function `fn_legacy_read_only` could `DROP FUNCTION … CASCADE` and remove the row triggers (the tables stay inaccessible through ownership + no privileges). The audit row and the WARNING make the mode visible.
- **Host not verified:** the managed-host role attributes (e.g. Supabase `postgres`: not superuser, CREATEROLE, BYPASSRLS assumed) are **not verified against a real project** — the test uses a local role with those attributes. TODO להשלמה at go-live.
- The tz preflight is **enforced only while a v1.x `start_date` is waiting to be merged** (plain column). On an already-migrated DB it only notes the zone. An explicit `--source-tz` overrides even a UTC source (operator's responsibility).
- Results on the fixture (12 users): UTC source → 10 hire dates, 1 untrusted (u1), 2 without, 1 `tz_edge_review` (u4, 23:40 UTC). Same data on an Asia/Jerusalem source with `--source-tz Asia/Jerusalem` → 9 hire dates, 2 untrusted (u1, u3), 3 without, 1 `tz_edge_review` (u5, 00:30 local). Multi-zone countries: **25 by zone count; 24 need review** (UA pinned).

## Migration v1.4 → v1.6.10 (Karin, 20.10; updated 21.10)

- **Source of the v1.4 structure (not guessed):** the real v1.4 files — Drive hot-fix `schema.20261013.sql` (= v1.4 `schema.sql` with the cuckoo veto default 60 s instead of 60 min) and v1.4 `rpc.sql` — copied to `tests/fixtures/v1_4_schema.sql` / `v1_4_rpc.sql` with sha256 provenance; only the rejected salary literal in 5 comments is replaced by a token.
- **Scope done:** users (manager_id → reports_to; new 1.6 columns; pseudonyms generated; **v1.6.8: team_joined_at NULL, TPS source audited; v1.6.9: hire_date ← trusted start_date (≠ creation date, UTC), start_date → generated alias**), spoons history (rows kept; `energy_state` / `available_capacity_pct` → generated `day_status`; **v1.6.8: `row_source = legacy_v1_4`**), golden spoons → numeric(10,1), projects (none exist in v1.4; the schema's `is_core = false` migration runs), company settings (CLDR backfill + needs_review + reminder hold, reusing the pack's functions). Out-of-scope tables frozen **read-only** as `legacy_v1_4_*`; **v1.6.9: DROP / ALTER blocked by the superuser event-trigger guard** (runner step). Idempotent, dry-run, rollback via backup — see README.
- **Results on the fixture (v1.6.9):** 10 users (8 hire_date mapped, 1 untrusted + 1 without → TPS exempt; source audit hire 8 / exempt 2 / team_join 0; 1 `start_date_untrusted`), 12 spoon days kept and marked legacy, 7 legacy tables read-only, 2 companies held; catalog identical to a fresh v1.6.9 install except 4 company NOT NULLs that lock once the held companies get a country; second run changes nothing; rollback restores v1.4 exactly.

| # | Item from the migration | Status |
|---|------------------------------|--------|
| O-45 | 7 out-of-scope v1.4 tables kept as `legacy_v1_4_*` | **Resolved 21.10:** frozen, read-only (grants + triggers), never dropped. **v1.6.9:** DROP / ALTER (incl. RENAME, SET SCHEMA, DROP SCHEMA … CASCADE) blocked for every role by the event triggers; only a superuser can lift them (documented procedure). Remaining: a superuser can still bypass (disable the triggers / `session_replication_role = replica`) — superuser is the trust boundary |
| O-46 | `org_role_code`: every migrated user gets `employee`; non-employee app_roles counted | **OK as built (21.10)** — map per real user at go-live |
| O-47 | v1.4 companies have no country → held + needs_review until the CHRO sets it | **OK as built (21.10)** |
| O-48 | v1.4 spoon days have no submission time → `reported_at` NULL | **OK as built (21.10)**, marked `row_source = 'legacy_v1_4'` |
| O-49 | ~~Users without `start_date` → migration day as team-join date~~ | **Replaced (Karin 21.10):** no fallback; exempt when no hire date |

## Resolved in v1.6.11 (Karin 24.10 + Chief of Drive 24.10)

| # | Resolution | Where encoded |
|---|-----------|---------------|
| O-8 | **TPS-12 / IHS fractional scores:** confirmed as built — round half-up to the nearest integer first, then apply last-digit rounding (to 0 or 5), then divide by 10 — **superseded in v1.6.16** (v3 §3.6: no Golden Spoons from a score) | `fn_round_score_last_digit` (kept) |
| O-6 | **IHS score source:** comes solely from anonymous employee questionnaire answers on a 1–5 scale, converted linearly to 0–100 (`(mean - 1) / 4 * 100`); IHS submission and scoring enabled (`403 scoring_not_locked` removed); quarterly team average `ihs_team_avg` in `team_aggregate` at N≥5 actual respondents | `fn_ihs_score`, `questionnaire_definition` (`scoring_method = 'ihs'`), `questionnaire_submission.ihs_score`, `rpc_submit_questionnaire`, `rpc_team_aggregate_refresh` |
| O-1 | **Turnover replacement cost point estimate:** tier midpoint (`junior` = 40 % / 0.40, `mid` = 125 % / 1.25, `senior` = 300 % / 3.00); min/max range columns kept | `turnover_tier_config.midpoint_pct`, `fn_turnover_tier_midpoint_pct`, `fn_turnover_tier_midpoint_factor`, `employee_turnover_cost_range_v.turnover_cost_midpoint`, `team_aggregate.turnover_cost_midpoint_sum` |
| O-2 | **Turnover tier assignment:** defaults automatically from `org_role.tier` (1 → `junior`, 2–3 → `mid`, 4 → `senior`, 5 / outside → `NULL` excluded unless overridden); CHRO (`vp_hr`) may override per employee | `fn_default_turnover_tier_for_org_tier`, `fn_user_default_turnover_tier`, `fn_effective_turnover_tier`, `trg_eva_default_turnover_tier`, `trg_users_sync_turnover_tier`, `rpc_upsert_employee_value_asset` |
| O-3 | **Deprived employee definition:** deprived in a week when weekly average available spoons < 5 OR weekly burnout score `B_t >= 0.65` | `fn_weekly_deprivation_metrics`, `fn_is_employee_deprived`, `fn_sync_employee_deprived` |
| O-4 & O-18 | **Company-wide turnover tier `avg_annual_salary` & full Shadow Balance / CHR Real EBITDA:** uses company-wide average annual salary of employees in that turnover tier group (`fn_company_tier_avg_salary`), never individual or small-team salary averages; encodes `happiness_debt_sum` / `happiness_debt_balance`, 12 % `deprivation_tax_amount`, `shadow_balance_sum`, and `chr_real_ebitda = gaap_reported_ebitda - happiness_debt_balance - deprivation_tax_amount` at N≥10 actual contributors | `fn_company_tier_avg_salary`, `fn_chr_real_ebitda`, `fn_shadow_balance_contributors`, `shadow_balance_aggregate`, `rpc_shadow_balance_refresh`, `rpc_team_aggregate_refresh` |
| O-5 | **Morning & midday check-in RPCs:** `rpc_morning_checkin` (simple average of 0–10 scales, half-point scores floored in employee's favor so fewer spoons are deducted, sets `spoon_budget.reported_at`) & `rpc_midday_checkin` (open 12:00–15:00 employee-local time, integer delta −4..+4, capped at 12 and floored at 0 without recalculating morning score) | `fn_morning_checkin_score`, `fn_morning_spoon_deduction`, `fn_is_midday_window`, `rpc_morning_checkin`, `rpc_midday_checkin` |
| Q5 | **Visibility:** "never show the deduction" applies ONLY to check-in survey answer options; task spoon costs (`0, 1, 2`) and golden spoon rewards remain visible to the employee | `task`, `questionnaire_submission`, `avatar_state`, `rpc_morning_checkin` |
| O-16 / Q11 | **Currencies in v1:** only Golden Spoons active in v1 (0.5 daily, 2 per shift at `rpc_morning_checkin` once per local day, 10 at initial signup via `rpc_signup_profile`); CHR Coins deferred to v2 (CHR shelf rows kept inactive) | `spoon_budget.shift_golden_awarded`, `rpc_morning_checkin`, `rpc_signup_profile`, `shop_item_catalog` (`chk_chr_shelf_todo`) |
| C-1 & C-2 | **Confirmed by Karin:** keep soft WIP limit (alert only at >2 core projects, no blocking) and locked Weinberg table `L(P) = 0/20/40/60/75 %` capped at `P >= 5` | `fn_wip_raise_alerts`, `context_switch_loss_config`, `fn_context_switch_loss` |
| O-30 & O-31 | **Technical confirmations (Chief of Drive):** `EPWI_cognitive <= 1.10` is `target`, `> 1.10` and `<= 1.50` is `above_target`, `> 1.50` is `overload` (danger); population SD σ (`stddev_pop`) for AIDB | `fn_epwi_cognitive_band`, `fn_aidb_of` |
| O-53 schema | **Confirmed by Chief of Drive:** the `legacy_v1_4` schema move in the non-superuser fallback (`migrations/legacy_lockdown_fallback.sql`) is confirmed and kept | `migrations/legacy_lockdown_fallback.sql` |

### Implementation notes / edge cases in v1.6.11 (for Chief of Drive)
- **Morning check-in half-point rounding (O-5):** on the 0–10 pain/mental/mood distress scales (0 = best, 10 = worst; deduction bands `0–4 → 0`, `5 → −2`, `6–7 → −3`, `8–10 → −4`), `fn_morning_spoon_deduction` applies `floor(avg_score)` so half-point / fractional averages (`4.5 → 4 → 0 deducted`, `5.5 → 5 → 2 deducted`, `7.5 → 7 → 3 deducted`) round to the lower band (**fewer spoons deducted**).
- **IHS item count (O-6):** the formula `(mean - 1) / 4 * 100` depends only on the mean of the 1–5 answers; since the exact Hebrew item wording/count for IHS is not locked in the DB (Hitokoto & Uchida 2015 has 9 items, the prototype has 3 placeholders), `questionnaire_definition` seeds `item_count = 9` while `fn_questionnaire_answers_valid` accepts any non-empty `int[]` of 1–5 answers for `scoring_method = 'ihs'`.
- **Deprivation fallback for legacy/system flag (O-3):** `fn_is_employee_deprived` evaluates `(weekly_spoon_avg < 5) OR (weekly_b_t >= 0.65)` whenever the employee has any spoon or workload report in that week; if she has neither report in that week yet, it falls back to `COALESCE(employee_value_asset.is_deprived, false)` so system-flagged rows (`rpc_set_deprivation_flag`) still count.

## Resolved in v1.6.12 (Karin 24.10 + Chief of Drive 24.10)

| # | Resolution | Where encoded |
|---|-----------|---------------|
| O-7 | **PCQ-12 answer scale:** locked as 1–6 (Luthans original scale, 12 items, all required), converted linearly to 0–100 (`(mean - 1) / 5.0 * 100`); `answer_min = 1, answer_max = 6` enforced on PCQ-12 submissions | `questionnaire_definition` (`scoring_method = 'pcq12'`, `answer_min = 1`, `answer_max = 6`), `fn_pcq12_score`, `fn_questionnaire_score`, `questionnaire_submission.pcq12_score` |
| O-25 | **Board / Tier 5 metrics:** tier 5 governance roles (`board_chair`, `board_member`, `owner_shareholder`) see all company-wide organizational averages at the whole-company level only (TPS-12, spoons, workload/EPWI/PEWI, IHS at `N >= 5` actual respondents; Happiness Debt, 12 % deprivation tax, Shadow Balance, and CHR Real EBITDA at `N >= 10` actual contributors), and never any team or individual breakdown (`403`) | `rpc_get_board_macro_metrics`, `rpc_company_averages` |
| O-14 | **Offboarding crypto-shredding retention period:** self-request (`rpc_request_crypto_shred` / `rpc_crypto_shred_pseudonym_key`) executes immediate crypto-shredding (0-day wait); automatic offboarding (`rpc_offboard_employee`) revokes access (`employment_ended_at` set, `consent_vault = false`) and wipes manager vault immediately on termination date, schedules crypto-shredding for `terminated_at + 30 days` (`pseudonym_key.scheduled_shred_at`), cancellable via `rpc_revert_offboarding` if termination is reverted within those 30 days, and `rpc_run_scheduled_crypto_shred` shreds keys whose 30-day wait has elapsed | `pseudonym_key.scheduled_shred_at`, `fn_schedule_crypto_shred`, `fn_users_offboarding_shred`, `rpc_request_crypto_shred`, `rpc_offboard_employee`, `rpc_revert_offboarding`, `rpc_run_scheduled_crypto_shred` |
| O-13 | **Per-company ledger chain:** one ledger chain per company (`org_id`), genesis record (`event_type = 'GENESIS'`, `manager_id = NULL`, `previous_hash = NULL`) seeded automatically on company creation (and backfilled for existing companies), and `fn_ledger_verify_chain` writes an audit alert (`ledger_chain_broken`) + `fn_ledger_chain` blocks writes (`403 ledger_chain_broken`) on a broken chain | `manager_ledger`, `fn_ledger_chain_is_valid`, `fn_ledger_verify_chain`, `fn_ledger_chain`, `fn_seed_company_ledger_genesis`, `trg_companies_ledger_genesis`, `rpc_ledger_append` |
| O-19 | **Manager vault rules:** direct manager only (`is_management = true AND NOT averages_only` with active solid-line reports), requires office-network AND company-device flags (`is_office_network = true AND is_company_device = true`; else `403 manager_vault_environment_denied`) + inactivity timeout check (`<= 15 minutes` default; else wipes session and raises `403 manager_vault_session_expired`), and immediate wipe on manager transfer/dismissal or employee transfer/offboarding | `manager_vault_session`, `manager_vault_entry`, `fn_manager_vault_wipe`, `fn_users_manager_vault_guard`, `trg_users_manager_vault_guard`, `fn_assert_manager_vault_active`, `rpc_manager_vault_open`, `rpc_manager_vault_put`, `rpc_manager_vault_entries`, `rpc_manager_vault_close` |
| O-20 | **Governance-only user provisioning:** CHRO (`vp_hr`) provisions tier-5 governance users (`board_chair`, `board_member`, `owner_shareholder`) via `rpc_provision_governance_user`, defaulting `has_employee_profile = false` unless explicitly marked as also an employee (`p_also_employee = true`) | `rpc_provision_governance_user`, `fn_users_governance_profile_default`, `trg_users_governance_profile_default` |

### Implementation notes / edge cases in v1.6.12 (for Chief of Drive)
- **Per-company genesis record (`O-13`):** `manager_ledger.manager_id` is now nullable solely for `event_type = 'GENESIS'` (enforced by `CHECK (event_type = 'GENESIS' OR manager_id IS NOT NULL)`), and `trg_companies_ledger_genesis` seeds the genesis record automatically on `INSERT INTO companies` (plus an idempotent backfill for existing companies). Because `fn_ledger_chain` runs `BEFORE INSERT ON manager_ledger` inside the caller's transaction, raising `403 ledger_chain_broken` rolls back the attempted `INSERT`; `fn_ledger_verify_chain(p_org_id)` is `VOLATILE` so calling it directly persists the `ledger_chain_broken` audit alert row and returns `false`.
- **Offboarding retention & revert (`O-14`):** `rpc_offboard_employee(p_user_id, p_terminated_at DEFAULT NULL)` is callable by `service_role` (or CHRO `vp_hr` for her own company). If `p_terminated_at` is already $>= 30$ days in the past, the trigger shreds immediately; otherwise `scheduled_shred_at = terminated_at + interval '30 days'`, and `rpc_revert_offboarding(p_user_id)` can cancel it at any time before `scheduled_shred_at` / `rpc_run_scheduled_crypto_shred()`.

## Resolved in v1.6.13 (Karin 25.10 + Chief of Drive 25.10 — EverStore expansion & privacy)

| # | Resolution | Where encoded |
|---|-----------|---------------|
| EverStore catalog expansion | **EverStore is NOT cosmetic-only:** the 8 items (`theme_*`, `badge_*`) are the **opening seed catalog (`קטלוג פתיחה`)**, not a closed 8-item list. Added `category` (`cosmetic`, `time_benefit`, `health_wellbeing`, `learning`, `donation`, `experience`, `gift_card`, `merchandise`), `provider text NULL`, `cosmetic_only boolean NOT NULL DEFAULT true` (allows `true` or `false` for tangible benefits), strictly locked `real_money_purchase_allowed = false` and `affects_daily_energy_spoons = false`, expanded `shop_tier_enum` (`basic`, `advanced`, `premium`, `custom`), and allowed **any positive price in Golden Spoons** (`price_golden_spoons > 0`) | `shop_item_catalog`, `shop_tier_enum`, `rpc_everstore_purchase`, `rpc_everstore_upsert_item` |
| Golden Spoons expiration & conversion | **Golden Spoons never expire** while the employee is active in the organization (`avatar_state.golden_spoons_expires_at` always `NULL`, enforced by `CHECK (golden_spoons_expires_at IS NULL)`). `rpc_convert_golden_to_chr` remains **active on the server in v1** (while the conversion button is hidden in the employee UI until v2, as CHR Coins are deferred to v2 per O-16) — **superseded in v1.6.16: blocked, 422 `chr_coins_deferred_to_v2`** | `avatar_state.golden_spoons_expires_at`, `rpc_convert_golden_to_chr` |
| Time-benefit voucher privacy (`נעילת הפרגוד`) | Purchasing/redeeming a `time_benefit` item in EverStore automatically converts through HR into a standard approved absence / refresh time entry (`approved_absence_entry`: `'זמן התרעננות / היעדרות מאושרת'`), so the direct manager coordinates the schedule (`approved_absence_manager_v`, `rpc_coordinate_approved_absence`) without ever seeing that the voucher came from an EverStore purchase, while `shop_purchase` remains strictly hidden from managers (own-rows RLS only) | `shop_purchase`, `approved_absence_entry`, `fn_approved_absence_manager_feed`, `approved_absence_manager_v`, `rpc_everstore_purchase`, `rpc_coordinate_approved_absence` |
| Stale `TODO` cleanup | Cleaned up all resolved `TODO` comments in `openapi.yaml`, `schema.sql`, and `rpc.sql` (including #6 shop purchase eligibility, O-5 morning/midday check-in scoring, O-1..O-4 turnover/deprivation/salary rules, O-10 farming at ≤3, O-13 ledger chain scope) | `openapi.yaml`, `schema.sql`, `rpc.sql` |

## Resolved in v1.6.19 (Karin 31.10 via Chief of Drive — Tsaban's papers; plan approved 16:26)

### Karin's decisions (31.10) — recorded as decisions, not judgment calls

| # | Decision | Where encoded |
|---|----------|---------------|
| J-43 → **הוכרע** | The board-report memo line "יצא עם העוזבים" updates **only after 10 NEW leavers** (distinct employees) have accumulated since the last published value. Until then the previous value is shown with a waiting note (Karin's text, `text_status` 'טיוטה': "מוצג הערך מהעדכון הקודם; העדכון הבא ממתין להצטברות של מספיק עוזבים חדשים (10 לפחות)."). Before the first batch no amount is shown. Tested: 1..9 new leavers → no change; the 10th → update; the difference between two board reports is never one leaver's debt (it is 0 or a sum of ≥ 10 leavers); the leaver list minus the memo line is also 0 | `leaver_memo_snapshot` (WORM), `fn_leaver_memo_try_snapshot`, `fn_leaver_memo_on_event` (triggers), `fn_board_memo_line`, `rpc_build_board_report`; `tests/test_board_v1_6_19.sql` §1 |
| Threshold per cell | **10 accumulated leavers per cell** (batch and team-in-batch), the same value as the Shadow Balance threshold (J-40) | `fn_leaver_batch_size`, `fn_leaver_batch_teams` |
| No 2-transfer rule | No "≥ 2 transfers" rule anywhere — the only threshold is 10 | — (nothing encoded; tested with company J) |
| Complementary rule | A team row is not shown if the rest of the batch could be computed from it: shown teams have ≥ 10 leavers each AND the rest of the batch is 0 or ≥ 10; otherwise the smallest shown team is folded back until that holds. The same rule is used for the adoption layer cells (≥ 5 buyers / reporters there) | `fn_complement_safe_keys`, `fn_leaver_batch_teams`, `fn_board_layer_adoption` |
| Batching of adjustments | Remediations and reversals move the memo line / list only inside a batch, and only when the pending adjustments touch **≥ 10 distinct transfers**; until then they wait (same note) | `fn_leaver_memo_try_snapshot` (`adjustment_batch` rows) |
| A-3 (closed) | ILS estimate = **average cost of a redeemed spoon, 3-month moving average** (Σ internal ILS cost ÷ Σ Golden Spoons of the company's EverStore purchases in the current company-local month + the 2 previous); shown only with **≥ 10 purchases**, else exactly 'אין עדיין מספיק מימושים לאומדן'; an item without an internal cost → 'חסר: everstore_item_cost.internal_cost_ils'. **cfo / vp_hr only** (service / anon / others → 403). `liability_method` = `avg_redeemed` (locked). `spoon_cost_ils` is **deprecated and unused** (kept, `not_defined`, locked — not deleted) | `fn_redeemed_spoon_cost_3m`, `rpc_get_redeemed_spoon_cost_estimate`, `rpc_get_open_golden_spoons_liability` (strict), `fn_board_layer_investment` |
| A-10 (closed) | All DOIs checked by Karin; the earlier unverified-DOI note is removed. r = 0.37 may appear **only inside the binding text and always next to 0.14–0.16** — that text was not provided, so the pack holds no r = 0.37 anywhere (gap G-1 below). The B_t burnout weight 0.37 (0.41·S + 0.37·O + 0.22·D) is a different number and is unchanged | `fn_board_sources` |
| Sources (5) | Exactly 5 entries, each with `doi` + `status_he`: IJEB — Tsaban & Shavit (2026), *Corporate happiness responsibility (CHR) – changing the role of corporations*, IJEB 33(1), 123–160, doi 10.1080/13571516.2025.2599785, 'פורסם' (year 2026 in one constant `fn_chr_paper_year()`; the DOI is unchanged) · Oswald, Proto & Sgroi (2015), doi 10.1086/681096, 'פורסם' · Bellet, De Neve & Ward (2024), doi 10.1287/mnsc.2023.4766, 'פורסם' · Tsaban & Shavit (2026), *Unveiling the Value of Happiness: Why Reporting on Corporate Investments in Employee Happiness Matters*, World 7(5), 77, doi 10.3390/world7050077, 'פורסם' (עבר ביקורת עמיתים) · Tsaban (2026), *Does Employee Well-Being Pay?*, doi 10.13140/rg.2.2.35568.62722, 'טיוטה'. Karin's own texts keep `text_status` 'טיוטה' | `fn_chr_paper_year`, `fn_board_sources`, `rpc_build_board_report.sources` |
| J-54 fix | Cancelled time-benefit absences (A-13) are excluded from every absence count | `fn_team_month_absences`, `fn_company_month_absences` |

### Built per the approved plan (sections 2, 2b, 3)

| Area | What | Where encoded |
|------|------|---------------|
| Aggregate leaver list (mandatory) | `rpc_list_leaver_transfers(company)` returns **no per-employee or per-transfer row and no id**. Columns: `row_kind` (`batch` · `batch_team` · `adjustment_batch` · `company_total`), `batch_no`, `team`, `period_from`, `period_to`, `leavers_count`, `transferred`, `remediated`, `reversed`, `open_balance`, `label_he` ('יצא עם העוזבים'), `note_he`, `text_status`. cfo / vp_hr only (strict — service / anon → 403), every call audited. `company_total.open_balance` = the published memo line | `rpc_list_leaver_transfers`, OpenAPI `LeaverListRow` |
| Remediation (2b) | `p_transfer_event_id` can no longer be passed (400 `transfer_selection_not_allowed`); the team's oldest open transfer is used internally (A-12 still holds: a remediation never reduces another leaver's share); "no open transfer" and "above its open balance" give the same 422 `remediation_not_attributable` | `rpc_record_remediation`, `fn_remediation_target` |
| Reversal output | `{status: 'reversed', label_he: 'יצא עם העוזבים'}` only — no amount, team, id or memo value | `fn_reverse_leaver_transfer` |
| Verification levels 0–4 (A1) | Computed from evidence only; the manual tier put → 422 `verification_level_is_computed`; an industry comparison is stored but never raises the level; a logged company-side timing / wording change caps the metric month at level 1 (B2) | `metric_verification_evidence`, `rpc_put_metric_verification_evidence`, `fn_board_verification_levels` |
| 'תיק אימות' (A2) | Per questionnaire metric / month: wording + change vs previous period, population vs payroll + exceptions, timing vs organisational events, Golden Spoons value in effect; built live; a WORM copy is kept with every published report (`last_kept_at`) | `fn_build_verification_dossier`, `rpc_get_verification_dossier`, `fn_keep_board_dossiers` |
| Pay linkage (A3) | cfo / vp_hr flag a metric as used for pay / manager bonuses (WORM history); a report whose pay-linked metric is below level 2 is not published (422 `pay_linked_metric_below_level_2`) | `rpc_put_metric_pay_linkage`, `fn_assert_pay_linked_levels` |
| Burnout recommendation (A4) | Only 'לבדוק את תנאי העבודה בצוות' ('טיוטה'), only when the risk rises; a guard refuses texts suggesting more feedback / documentation / an improvement plan / PIP | `fn_burnout_recommendation`, `fn_recommendation_allowed`, `rpc_get_burnout_trend` |
| Social events (A5) | 'ללא הערכה מקצועית'; no attendance table, no Golden Spoons | `social_event`, `rpc_create_social_event` (vp_hr), `rpc_list_social_events` |
| Report layers (B1, B3) + measuring body (B2) | (a) investment & activity, (b) adoption & usage under 'אימוץ' (redemption rate 'לא הוגדר'), (c) outcomes, plus governance; each with its verification level; missing input → 'חסר: <field>'; measuring body CHR-ETRS; causal note ('טיוטה'); ILS only as a total | `fn_board_layers`, `fn_board_layer_*`, `fn_board_causal_note`, input RPCs `rpc_put_wellbeing_spend` / `_safety_incidents` / `_key_role_turnover` / `_company_governance` / `_payroll_population`, `rpc_add_org_event`, `rpc_put_questionnaire_items` |
| Board report keys | added `verification_levels`, `layers`, `measuring_body`, `causal_note`, `verification_dossiers`, `sources`; removed `assurance_tier`, `sources_note_he` | `rpc_build_board_report`, OpenAPI |

### Judgment calls of the approved plan (J-40 – J-54; J-43 is now a decision)

| # | Call | Status |
|---|------|--------|
| J-40 | The small-cell threshold for leaver data reuses the existing Shadow Balance threshold `shadow_balance` = 10 | **Confirmed by Karin 31.10** (10 per cell) |
| J-41 | ~~Small cells rolled up team → company month → multi-month company row~~ | **Superseded by Karin 31.10**: cells are batches of 10 new leavers; a team row is shown only inside a batch under the complementary rule; leavers not yet in a batch show no amount (company_total with the waiting note) |
| J-42 | Remediations and reversals are summed only inside the same cells, never as rows of their own | **Built** as `adjustment_batch` rows inside a batch (≥ 10 distinct transfers, Karin 31.10) |
| J-43 | Memo line changes only per batch of ≥ 10 new leavers | **הוכרע — Karin 31.10** (see the decisions table) |
| J-44 | `p_transfer_event_id` removed (400 if passed); the oldest open transfer is used; one 422 for "none" / "above balance". Probing risk reduced, not removed (see G-3) | Built |
| J-45 | The leaver list and the ILS estimate / liability are strictly cfo / vp_hr; service calls get 403 too | Built |
| J-46 | Verification level computed only from evidence; manual put → 422; industry comparison stored, never counted | Built |
| J-47 | A pay-linked metric below level 2 blocks publishing the report (422) rather than refusing the flag (a level can drop later) | Built |
| J-48 | A company-side timing / wording change caps the affected metrics at level 1 for the month of the change | Built (month granularity) |
| J-49 | Social events keep no attendance at all | Built |
| J-50 | 'טיוטה' is returned as `text_status` next to every new fixed Hebrew text | Built |
| J-51 | The B4 EBITDA text 'מדד ניהולי חלופי שמציג קשר, לא השפעה סיבתית מבודדת' is added next to the existing locked definition ('מדד ניהולי חלופי, לא רווח חשבונאי'), not replacing it | Built (`chr_real_ebitda.note_he` + `text_status` 'טיוטה', `fn_real_ebitda_note_he`) |
| J-52 | Forbidden burnout phrases matched in Hebrew and English (משוב נוסף, תיעוד, תוכנית שיפור, PIP); the Hebrew forms need Karin's confirmation | Built — **for Karin** |
| J-53 | Redemption-rate denominator, the "key role" definition and the board "absences" definition stay 'לא הוגדר' until Karin defines them | Built — **for Karin** |
| J-54 | Cancelled absences excluded from all absence counts (bug fix) | **Approved 31.10**, built |

### New judgment calls made during the v1.6.19 build (J-55+) — for Karin / Chief of Drive review

| # | Call |
|---|------|
| J-55 | `questionnaire_identified` is NULL (not false) for metrics that are not measured by a questionnaire; their level ignores that criterion |
| J-56 | Voluntary key-role turnover is an aggregate monthly input (exits + key-role headcount), shown only with ≥ 5 key roles — no per-person "voluntary" flag or role catalogue exists |
| J-57 | On the board, ILS appears only as a total (the EverStore spend estimate); the per-spoon value is never shown next to it |
| J-58 | The 3-month spoon-cost estimate counts only purchases with a positive Golden Spoons price, dated by the company-local purchase day |
| J-59 | Legacy (pre-1.6.18) unattributed remediations have no transfer; they ride along with the next batch of any kind |
| J-60 | "3-month moving average" window = the current company-local month + the 2 previous months, up to the report / request day |
| J-61 | The questionnaire catalogue is global, so a wording / timing change logged by any company counts for the questionnaire in that month (only the instrument owner CHR-ETRS changes locked ones) |
| J-62 | A layer's verification level = the lowest level of its metrics in the month |
| J-63 | Adjustments only join a batch; there is no adjustment-only snapshot unless the pending adjustments touch ≥ 10 distinct transfers |
| J-64 | In-place upgrade from v1.6.18: a company with ≥ 10 un-batched leavers gets its first batch at upgrade, but held-back adjustments (< 10 transfers) are not in it — so the published memo can be **higher** than the v1.6.18 internal memo (test upgrade: 50,780 published vs 30,780 internal). See G-4 |
| J-65 | The causal-note wording ('הדוח מציג השקעה, אימוץ ותוצאות זה לצד זה; הוא אינו קובע שההשקעה גרמה לתוצאות.') is mine, marked 'טיוטה' — for Karin to replace |
| J-66 | A dossier whose questionnaire has its first wording version in the period reports "changed vs previous period" |
| J-67 | A company-side wording change is logged when name / item_count / scale range of an existing unlocked questionnaire changes; a frequency change is logged as a timing change; service (CHR-ETRS) edits are not logged |
| J-68 | `rpc_get_verification_dossier` always builds live from current inputs and adds `last_kept_at` (the WORM copy kept with the report stays the record) |
| J-70 | The dossier's non-reporting text ('מי שלא דיווח לא נספר: אין השלמה או הערכה של נתונים חסרים.') is my wording of the existing rule, marked 'טיוטה' — for Karin |
| J-69 | Test file names: the new suite is `tests/test_board_v1_6_19.sql`; `tests/test_agents_v1_6_16.sql` keeps its name (content v1.6.19); the migration is renamed `migrations/migrate_v1_4_to_v1_6_19.sql` |

### Gaps and conflicts found in the v1.6.19 build (not fixed silently)

| # | Gap |
|---|-----|
| G-1 | The binding text that must carry r = 0.37 next to 0.14–0.16 was never provided — not in the pack (להשלמה) |
| G-2 | Failed attempts (403 / 422) cannot be audited: the audit row is rolled back with the failed call (PostgREST runs each call in one transaction) |
| G-3 | Remediation 422s still leak a little (a caller can learn that a team has / lacks open balance above an amount by trying); reduced by one shared code, not removed |
| G-4 | Upgrade memo jump (J-64): the first published memo after upgrade can exceed the pre-upgrade value until ≥ 10 transfers of adjustments accumulate |
| G-5 | `fn_avg_redeemed_spoon_cost_ils` (v1.6.16) is now unused — kept, not deleted |

## Resolved in v1.6.18 (Karin 31.10 via Chief of Drive — fix round)

| # | Resolution | Where encoded |
|---|-----------|---------------|
| A-12 Reversal amount | A reversed offboarding returns to the team the **moved debt minus the documented remediations already made against that transfer**, never the full amount. Remediations are now **attributed per transfer**: each `rpc_record_remediation` is linked to exactly ONE `leaver_transfer` of its own team (named by the new optional `p_transfer_event_id`, else the team's oldest transfer with an open balance and a month ≤ the remediation month) and may not exceed that transfer's open balance (422 `remediation_exceeds_transfer`; none open → 422 `no_open_leaver_transfer`; wrong team / later month / unknown → 400 `invalid_remediation`) — so a remediation can never reduce another leaver's share. Open balance = moved − attributed remediations − reversal. Tested: debt 100 → remediation 30 → reversal → the team gets back **70**, that transfer's "יצא עם העוזבים" balance is **0** (30 + 70 = 100, no double count), the total memo line drops by **70**, not 100; the other leavers' balances do not move | `happiness_debt_remediation_allocation` (WORM, no person column, closed), `fn_transfer_remediated`, `fn_transfer_open_balance`, `fn_remediation_target`, `rpc_record_remediation(…, p_transfer_event_id)`, `fn_reverse_leaver_transfer`, `rpc_list_leaver_transfers`, CHECK `happiness_debt_events_amount_check`, v1.6.18 back-fill block; agents §9 / §9c |
| A-13 Time benefit scheduled after exit | A time benefit bought before leaving but scheduled **after the end of employment** is **cancelled**: its `approved_absence_entry` → `schedule_status 'cancelled'`, `cancel_reason 'employment_ended'`, and the Golden Spoons it cost are **refunded** to the employee, who is then in the 30-day window where only products can be bought (J-15). Runs when the end of employment is recorded or moved (trigger on `users.employment_ended_at`); idempotent (cancelled rows skipped, one WORM refund per absence). A benefit on or before the end day is unaffected. **Nothing is moved earlier automatically**; moving it earlier is only the employee's own regular request (`rpc_request_absence_reschedule`), allowed before the end and refused after it (403). The manager sees the plain HR status only (no purchase, item, price or Golden Spoons field — נעילת הפרגוד) and cannot coordinate a cancelled entry or an ex-employee's entry | `approved_absence_entry` (+ `cancelled_at`, `cancel_reason`, v1.6.18 upgrade block), `time_benefit_absence_link` (closed), `time_benefit_refund` (WORM, closed), `rpc_everstore_purchase` (writes the link), `fn_employment_end_local_date`, `fn_cancel_time_benefits_after_exit`, `trg_users_time_benefit_cancel`, `rpc_request_absence_reschedule`, `rpc_coordinate_approved_absence`; agents §4c |
| A-14 Questionnaire amounts per company | All three questionnaire amounts are adjustable per company — monthly `golden_spoons_per_questionnaire` (default 10, PCQ-12 + Cantril), short `golden_spoons_per_short_questionnaire` (default 2), quarterly `golden_spoons_per_quarterly_questionnaire` (default 10, TPS-12 + IHS). (1) One value for every employee of the company — the amount is a function of (definition, company) only, never of answers, team or role (tested across two teams and two org roles, lowest vs. highest answers). (2) **1–20** per questionnaire, else **422 `questionnaire_reward_out_of_range`**. (3) **vp_hr only** — cfo's permission removed, including on the quarterly value (cfo → 403 `insufficient_privilege`, also for a reset); every change goes to the WORM `access_audit_log` (value before / after, effective_from) and to the WORM `questionnaire_reward_history` (effective_from = now); it applies from now on only — each submission snapshots `reward_golden_spoons`, `reward_setting_key` and `reward_effective_from`, so earlier submissions provably keep what they earned. (4) Employees see the current value before filling out: computed field `golden_spoons_reward` on `/questionnaire_definition` (OpenAPI) | `agent_settings` seed (unlocked), `fn_is_questionnaire_reward_key`, `fn_assert_questionnaire_reward_change`, `rpc_put_agent_setting`, `questionnaire_reward_history`, `fn_questionnaire_reward_effective_from`, `rpc_submit_questionnaire`, `golden_spoons_reward(questionnaire_definition)`; agents §1 / §3b |

### Judgment calls and edge cases in v1.6.18 (none fixed silently — for Karin / Chief of Drive review)

| # | Call |
|---|------|
| J-28 | A-12 attribution design: remediations were **company / team-level only** in v1.6.17, so per-transfer attribution is new — a WORM allocation table (remediation event → leaver_transfer, amount). A new remediation goes to **one** transfer, never split; a remediation larger than the target's open balance is refused (422) — the caller records two remediations instead. Without `p_transfer_event_id` the team's **oldest** open transfer is used (FIFO) |
| J-29 | `rpc_list_leaver_transfers` exposes transfer event ids, team, month and amounts to vp_hr / cfo so they can name a transfer. No person field, but in a small team a transfer can be matched to a known leaver by team + month — management data, not an agent output to employees or the board |
| J-30 | v1.6.17 → v1.6.18 upgrade: existing team-level remediations are back-filled oldest-transfer-first within their team (may split across transfers; never above a transfer's open balance; never to a later month). A remainder that fits no transfer stays unattributed and keeps reducing the company memo line as before (totals unchanged by the upgrade). v1.6.17 reversals that already returned a full amount are WORM and are not rewritten |
| J-31 | A fully remediated transfer that is reversed writes a documented **0** `leaver_reversal` (CHECK relaxed for reversals only), so "once per transfer" and the audit trail still hold |
| J-32 | "The team gets back 70" = the `leaver_reversal` event (team of the transfer, J-20). `employee_value_asset.happiness_debt_liability` of the returning employee is not changed (it is rule-derived and recomputed by `fn_sync_employee_deprived`) |
| J-33 | A-13 "scheduled after the end of employment" = `requested_date` **>** the employee-local date of `employment_ended_at`; a benefit on the end day itself is kept (still a day of employment) |
| J-34 | "Employment ended" keeps the J-19 meaning (`employment_ended_at` recorded). A future-dated end date therefore cancels at the moment it is recorded, and from then on the employee can no longer move a benefit — a move earlier must be requested before HR records the end. Moving the end date later does not restore cancelled benefits; a reversed offboarding does not restore them either (the Golden Spoons were refunded; the employee can buy again) |
| J-35 | The refund is the purchase price kept in the closed link (`time_benefit_absence_link`). Absences created by v1.6.17 have no link: on upgrade they are matched to the same employee's time_benefit purchase made in the same call (created ≤ 5 seconds after it); an unmatched entry is still cancelled but refunds nothing (`cancelled_without_refund` in the output) |
| J-36 | `rpc_request_absence_reschedule` accepts any day from today on (earlier or later), not only earlier; the entry goes back to `pending_coordination` for the manager. The direct manager can no longer coordinate / move a cancelled entry or an ex-employee's entry (new 403) |
| J-37 | A-14 "only vp_hr" is enforced for every API caller, service calls included (no vp_hr behind the call → 403); only direct DB writes by the pack owner bypass it. Values may have one decimal (e.g. 2.5 — the wallet unit); more decimals → 400 `invalid_setting_value`. Changes apply immediately (no future-dated effective_from) |
| J-38 | "Field in the questionnaire API" implemented as a PostgREST computed field (`golden_spoons_reward`) on the existing `/questionnaire_definition` read, not a new endpoint; `questionnaire_reward_history` stores no person column (who changed it is in `access_audit_log`) |
| J-39 | Test file names kept: `tests/test_agents_v1_6_16.sql` (content v1.6.18); `tests/test_v1_5.sql` is unchanged in v1.6.18 (header still 1.6.17) and is not re-uploaded |

## Resolved in v1.6.17 (Karin 31.10 via Chief of Drive — fix round)

| # | Resolution | Where encoded |
|---|-----------|---------------|
| A-5 TPS-12 / IHS | Fixed **10 כפיות** per participation (same as a monthly questionnaire): `agent_settings.golden_spoons_per_quarterly_questionnaire` = 10, `set`, **adjustable** (not locked — cfo / vp_hr may override it per company); never a code constant (a company override is what TPS-12 pays — tested) | `schema.sql` agent_settings seed, `fn_questionnaire_reward`, tests (test_v1_5 §questionnaires, agents §1 / §3) |
| J-3 (reversed) Cantril | Cantril stays a **MONTHLY** questionnaire → `golden_spoons_per_questionnaire` **10 כפיות** — replaces the v1.6.16 J-3 guess (short → 2) and the earlier 2.5 lock | `questionnaire_definition` seed + `chk_locked_catalogue` + v1.6.17 upgrade block |
| J-15 (confirmed) | After employment ends **no time benefits** (early leave, approved absence / day off). In the 30-day window only EverStore products can be redeemed. Enforced in `rpc_everstore_purchase` (time_benefit → 403) and by the DB guard on `early_leave_log` / `approved_absence_entry` for every path (`rpc_log_go_home`, low-spoons report, task assignment, direct insert) | `fn_employment_ended`, `fn_block_time_benefit_after_exit`, `trg_early_leave_after_exit`, `trg_approved_absence_after_exit`; agents §4b |
| A-8 Reversed offboarding | When an offboarding is reversed (marked by mistake or the employee returned) the leaver's Happiness Debt on the memo line "יצא עם העוזבים" **returns to the team**: a documented `leaver_reversal` event (same team and amount, period = company month of the reversal) with `reverses_event_id` = the original `leaver_transfer`; at most one reversal per transfer (unique index; a second call → `nothing_to_reverse`, a second `rpc_revert_offboarding` → 403); memo = Σ transfers − Σ remediations − Σ reversals. No person column in `happiness_debt_events`; the event ↔ employee link is kept only in the closed internal `happiness_debt_leaver_link` and deleted on crypto-shredding | `happiness_debt_events`, `happiness_debt_leaver_link`, `fn_users_leaver_debt_transfer`, `fn_reverse_leaver_transfer`, `trg_users_leaver_debt_reversal`, `fn_leaver_memo`, `fn_crypto_shred_pseudonym_key`; agents §9b |
| A-11 | Confirmation of J-3 (reversed: Cantril monthly 10) and J-15 (confirmed) — done | see the rows above |

### Judgment calls and edge cases in v1.6.17 (none fixed silently — for Karin / Chief of Drive review)

| # | Call |
|---|------|
| J-17 | "Adjustable parameter" read as an **unlocked** agent_setting (company override allowed). ~~The monthly 10 and short 2 stay locked~~ — **v1.6.18 (A-14): all three amounts are adjustable per company, 1–20, vp_hr only (cfo no longer may change the quarterly value)** |
| J-18 | Cantril shares the monthly key `golden_spoons_per_questionnaire` with PCQ-12 (no separate Cantril key) — a change of the monthly amount changes both. **v1.6.18:** unchanged and now visible to companies (A-14 lists PCQ-12 and Cantril under the monthly value) |
| J-19 | J-15 guard keys on `users.employment_ended_at IS NOT NULL` (the offboarding flow sets it at termination). The go-home / low-spoons / task-assignment paths now answer 403 for an ex-employee instead of writing an early-leave row |
| J-20 | A reversal returns ~~the full original transfer~~ (**v1.6.18 A-12: the transfer's open balance = moved − its attributed remediations**) to the **team of the transfer** (department at exit), even if the employee comes back to another department; its period is the company month of the reversal, so past months and already published board reports do not change |
| J-21 | ~~Edge case: a team-level remediation followed by a full reversal reduced other leavers' share~~ — **resolved v1.6.18 (A-12)**: remediations are attributed per transfer and the reversal returns only the open balance (see J-28 – J-31) |
| J-22 | The exit month's `exported_on_exit` ledger row stays as history (amounts are ≥ 0 by CHECK); the memo line is computed from `happiness_debt_events` only |
| J-23 | The event ↔ employee link is a new internal table holding `user_id` (like `golden_spoons_ledger`): closed (RLS forced, no grants), never returned, deleted on crypto-shredding. A return after the 30-day window is a re-hire (the key is shredded) → no reversal |
| J-24 | `rpc_revert_offboarding` keeps its existing HR contract (input user_id, returns the `users` row to the CHRO / service). It is not an agent output; the new reversal output (`fn_reverse_leaver_transfer`) is id-free |
| J-25 | ~~A time benefit bought while employed but scheduled after the end date stays pending~~ — **resolved v1.6.18 (A-13)**: cancelled and refunded at exit (see J-33 – J-36) |
| J-26 | Test-only fix (no code change): `tests/test_v1_5.sql` O40 "today + 1 accepted" failed on a Saturday run (the CHRO week-start change scheduled from the run date makes today + 1 a 1-day bridge); the test now expects 422 `bridge_period` on such a day. v1.6.16 fails the same way when run on a Saturday |
| J-27 | `tests/test_agents_v1_6_16.sql` keeps its filename (content v1.6.17; **v1.6.18** content since this round) so its Drive history stays in one file |

## Resolved in v1.6.16 (Karin 30.10 + Chief of Drive 30.10 — agents-bot-instructions-v3; replaces planned v1.6.14 / v1.6.15)

| # | Resolution | Where encoded |
|---|-----------|---------------|
| A1 Conversion | `rpc_convert_golden_to_chr` blocked in v1: every call → **422 `chr_coins_deferred_to_v2`** (HINT "CHR Coins shelf is deferred to v2; Golden Spoons conversion is disabled in v1"); no balance change, no row; still defined + granted for v2 | `rpc.sql` `rpc_convert_golden_to_chr`, `openapi.yaml`, tests (test_v1_5 §8 + agents §2) |
| A2 EverStore summary | Anonymous aggregate summary, vp_hr / cfo only (else 403 `insufficient_privilege`): grouped by category / item_id / name_he / tier / cosmetic_only / provider, `purchase_count bigint`, `total_golden_spoons numeric(12,1)`, plus company and time_benefit totals; < 5 buyers → "אחר" → merged into the smallest passing category, else company total only; never user_id / pseudonym / person_id / team / timestamps | `fn_everstore_budget_summary`, `everstore_budget_summary_v`, `rpc_everstore_budget_summary` |
| Golden Spoons per participation (Karin 30.10) | **Monthly questionnaire incl. PCQ-12 = 10 כפיות; weekly or short = 2 כפיות**, participation only, stored as **locked agent_settings** (`golden_spoons_per_questionnaire`, `golden_spoons_per_short_questionnaire`), never code constants | `agent_settings`, `questionnaire_definition.reward_setting_key`, `fn_questionnaire_reward` |
| 5th burnout signal (Karin 30.10) | Team level: rate = voluntary exits + transfer requests of the last 3 months ÷ team employees; "סיכון עולה" only when rate ≥ **1.5 ×** organization average AND ≥ **2** events, both in **2 consecutive periods**; sensitive — shown only for teams of ≥ **10** employees. 1.5 / 2 / 10 / 3 months are agent_settings (`movement_rate_multiplier`, `movement_min_events`, `movement_min_team_size`, `movement_window_months`); **replaces the 15 % placeholder** (`movement_rise_pct` removed) | `team_movements`, `fn_movement_period`, `rpc_get_burnout_trend` |
| v3 agents | agent_settings API, Agent 1 (liability, daily summary, 30-day exit redemption), Agent 2 (burnout trend, coverage, score range gate), Agent 3 (board report, reconciliation, 4-line Shadow Balance, memo line, assurance tiers, BCR), deprived = 2 consecutive weeks, role `cfo` | `schema.sql` / `rpc.sql` agents sections, `tests/test_agents_v1_6_16.sql` |

### v3 conflicts with earlier decisions — v3 wins (none fixed silently)

| # | Earlier decision | v3 / v1.6.16 |
|---|------------------|--------------|
| C-1 | v1.6.13: `rpc_convert_golden_to_chr` **active** on the server in v1 | Blocked: 422 `chr_coins_deferred_to_v2` (Karin 30.10) |
| C-2 | O-8 / O-6 (24.10): TPS-12 / IHS reward = score ÷ 10 with last-digit rounding; Cantril 2.5; HR questionnaires 0.5–2.5 | v3 §3.6: participation only, fixed amount from agent_settings (Karin: monthly 10, short 2); score/10 removed; HR sets no amount |
| C-3 | O-16: 0.5 Golden Spoons per daily questionnaire | Daily / weekly = short questionnaire = 2 (Karin 30.10) |
| C-4 | O-3 (24.10): deprived in **a** week | v3 §6.2: two consecutive weeks |
| C-5 | O-14 (v1.6.12): access revoked immediately on termination | v3 decision 4: 30 days to redeem Golden Spoons in EverStore after the end of employment (purchase path only; other access still revoked) |
| C-6 | v3 §6.1 `movement_rise_pct` "לא הוגדר (הוצע 15%)" and v2 "key-role movements" | Karin 30.10 rule (1.5 × / 2 events / 10 employees), team level |
| C-7 | Two margin keys (`margin_budget_points_pcq` 10 / `_ihs` 12.5) | One coefficient `score_range_coefficient` 12.5 |
| C-8 | Board report could be built without a reconciliation | Not published without a balanced reconciliation and prior-period figures (422) |
| C-9 | Leaver Happiness Debt left the recompute silently | Moves to the memo line "יצא עם העוזבים" (`leaver_transfer` + `exported_on_exit`), never deleted |

### Judgment calls in v1.6.16 (for Karin / Chief of Drive review)

| # | Call |
|---|------|
| J-1 | `cfo` added to `users.app_role` (v3 §2.3 names the role; it did not exist) |
| J-2 | 422 MESSAGE = code (Error Contract), HINT = the sentence |
| J-3 | ~~Cantril (monthly, 1 item) treated as a **short** questionnaire → 2, not 10~~ — **reversed by Karin 31.10 (v1.6.17): monthly → 10** |
| J-4 | Karin's values, the movement parameters and the 30-day / 5-buyer / 3-month / 2-period / 12 % / 10 % values are **locked** settings (company PUT → 403); open values stay unlocked "לא הוגדר" |
| J-5 | v3 names (`get_burnout_trend`, `build_board_report`, …) are served as `rpc_*`; the v3 `/agents/...` paths are documented as aliases in openapi |
| J-6 | Team = company + department (current department); org average includes the team itself |
| J-7 | EverStore budget measured in Golden Spoons per company-local month; linear month-end forecast; each threshold reported once per month |
| J-8 | Item-level small cells also collapse ("פריטים נוספים"); the time_benefit total is hidden with 1–4 buyers |
| J-9 | Remediation reduces the memo line only; ~~reversing an offboarding does not reverse `leaver_transfer`~~ — **superseded in v1.6.17 (A-8): a reversal returns it to the team** |
| J-10 | The 4-line split is entered by cfo / vp_hr and must equal the system balance; prior period required unless `is_first_period` |
| J-11 | BCR 6–9 yes → "לא הוגדר" (v3 labels only ≥ 10 and ≤ 5) |
| J-12 | "שוליים מטעים": payroll falls + at least one leaver in the month + company PCQ-12 falls (proxy for "because of leavers") |
| J-13 | 5th signal shown only with full coverage AND ≥ 10 employees; burnout access = cfo / vp_hr or a manager whose subtree holds a team member |
| J-14 | Memo line shown only from 10 מדווחים בפועל in the company month; EPWI inputs stored only; PCQ-12 month = employee-local date |
| J-15 | Time benefits refused after the end of employment (an approved absence cannot be scheduled) — **confirmed by Karin 31.10; enforced on every path in v1.6.17** |
| J-16 | `golden_chr_conversion.rate` (the v2 Golden → CHR 1:50 rate) stays employee-readable on an always-empty table; no ILS rate is readable by any employee |

### ADR entries to add (v3 §6.5) — numbering continues after "אינדקס ADR CHR-ETRS v48" (numbers: להשלמה)

The 8 decisions of 30.10 · Golden Spoons per participation (fixed, from settings) · separation of measurement and management · score range gate (one coefficient 12.5 in agent_settings) · CHR Real EBITDA as an alternative measure and the 4-line Shadow Balance · Happiness Debt on exit (`happiness_debt_events`, memo line) · replacement cost above baseline + "שוליים מטעים" flag · sensitivity switch for מס קיפוח · assurance tiers · the 15-question check · deprived employee: two consecutive weeks · optional EPWI inputs · 5th signal at team level (Karin 30.10) · report not published without a reconciliation table · CHR Coins conversion blocked in v1.

## Still open after v1.6.19 (להשלמה — not invented)

| # | Item |
|---|------|
| A-1 | `daily_summary_time` — לא הוגדר (no daily summary until set) — להשלמה |
| A-2 | `company_timezone` — לא הוגדר (falls back to `companies.timezone`) — להשלמה if a company needs another zone |
| A-4 | `turnover_baseline_junior / _mid / _senior` — לא הוגדר (unit assumed: leavers per company month; cost above baseline hidden) — להשלמה |
| A-6 | `golden_spoons_per_checkin` (midday check-in participation) — לא הוגדר, pays 0 — להשלמה |
| A-7 | BCR middle band (6–9 yes) label — לא הוגדר in v3 — להשלמה |
| A-9 | ADR numbers for the v3 §6.5 list above — להשלמה |
| A-15 | The binding text with r = 0.37 next to 0.14–0.16 (A-10 rule) — wording not provided — להשלמה (G-1) |
| A-16 | J-52 Hebrew forbidden phrases, J-53 definitions (redemption-rate denominator, key role, board absences) and the causal-note text (J-65) — for Karin — להשלמה |

_(A-5, A-8 and A-11 were closed in v1.6.17 — see *Resolved in v1.6.17*; A-12, A-13 and A-14 were closed in v1.6.18 — see *Resolved in v1.6.18*; A-3 and A-10 were closed in v1.6.19 — see *Resolved in v1.6.19*.)_

### Still open after v1.6.13 (carried over)

| # | Item |
|---|------|
| O-38 | Reminder sender job (push / in-app, idempotency, cadence) — stub (`rpc_workload_reminder_job`) — TODO להשלמה |
| O-52 | Drop the deprecated `users.start_date` alias in v1.7 (planned; clients must read `hire_date`) |
| O-53 (rest) | Fallback weaker than the event trigger (ADMIN re-grant, DB owner, trigger function owner — see *Gaps v1.6.10*; `legacy_v1_4` schema move itself **confirmed 24.10**); managed-host role attributes not verified — TODO להשלמה at go-live |
| O-55 | Rows audited `tz_edge_review` need a human look at go-live (flag only; no rule decided) — TODO להשלמה |
| — | Remaining non-backend / v2 / external-adapter items in the general *Still OPEN* table above (`O-6` UI item text, `O-22` v2 sensors/HRV/weights/Dutch/Contrast Nullification, `O-23` wireframe approval, `O-26` push/SMS provider adapters & cadence, `O-27` prototype border `--line #E8EBF1`) stay TODO להשלמה |
| ~~O-7, O-13, O-14, O-19, O-20, O-25~~ | **Resolved v1.6.12 (24.10)** — see *Resolved in v1.6.12* above |
| ~~O-1..O-6, O-8, O-16, O-18, O-30, O-31, Q5, C-1, C-2~~ | **Resolved v1.6.11 (24.10)** — see *Resolved in v1.6.11* above |
| ~~O-53~~ | ~~Who runs the guard on a managed host~~ — **resolved v1.6.10** (fallback; schema move confirmed 24.10) |
| ~~O-54~~ | ~~UA needs_review / UZ Samarkand~~ — **resolved v1.6.10** (pin final; Tashkent) |

## v1.6.3 — gaps / conflicts between the research doc and the locks (NOT resolved silently)

| # | Doc says | Lock / infographic says | What the code does |
|---|----------|-------------------------|--------------------|
| C-1 | ~~§6.2: "hard limits on WIP … at most two core projects in parallel"~~ | Lock 3: soft limit, alert only, no blocking | **Confirmed by Karin (24.10):** soft WIP limit kept (alert only at >2 core projects, no blocking) |
| C-2 | ~~§3.1 / §5.1 / §6.1: Weinberg's 20 %-per-project loss vs doc~~ | L(P) = 0/20/40/60/75 % locked | **Confirmed by Karin (24.10):** locked Weinberg table L(P) = 0/20/40/60/75 % (capped at P≥5) kept |
| C-3 | ~~§6.2 names PEWI but gives no formula~~ | Lock 1 lists PEWI as a PM aggregate | **Resolved v1.6.7 (Karin):** PEWI = mean EPWI of the reporting members (see below) |
| C-4 | §5.2 defines AIDB and < 65 %; no "> 80 % target" in the doc | Infographic: target > 80 % | Infographic value used |
| C-5 | ~~§5.3 betas vs B_t 0.50 / −0.30 / 0.20~~ | **Superseded (v1.6.4)** — the sigmoid and its weights are removed; see *B_t provenance* | — |
| C-6 | §5.2 names M_SPOF without a formula | M_SPOF = 1 + K_critical_single/K_total | Locked formula used |
| C-7 | §5.1: the 40 % switching-overhead tipping point | L(3) = 40 % | Consistent; no separate 40 % alert added (none locked) |

## The 9 assumptions put to Karin on 2026-10-20 — status

| # | Assumption | Status |
|---|------------|--------|
| 2 | TPS fractional score → whole number, then last-digit rule | **Locked by Karin (24.10, O-8)** — confirmed as built |
| 4 | Red team alert | **Locked by Karin** — kept, ≥5 reporters, team-level only |
| 5 | TPS-12 30-day rule start date | **Locked by Karin** — `team_joined_at` (current team) |
| 6 | Shop access | **Locked by Karin** — every user with an employee profile |
| 7 | Crypto-shredding | **Locked by Karin** — self-request or automatic offboarding only |
| 8 | Pseudonym assignment | **Locked by Karin** — system-assigned, unique, immutable |
| 9 | Prototype scrim opacity `rgba(5,10,48,0.5)` | **Locked by Karin** — no code change |
| 1 | Farming at ≤3 spoons | **Locked by Karin** — ALL tasks blocked (O-10 resolved) |
| 3 | Team N: members vs respondents | **Locked by Karin** — actual contributors (O-11 resolved) |

## The 15 questions from the 2026-10-20 review — status

| # | Question | Status |
|---|----------|--------|
| 1 | N≥10 for almost all team data (12.10) vs N≥5 | **Answered 20.10**: regular N≥5; Cuckoo / Shadow Balance / emergency N≥10 |
| 2 | 7-colour palette drops gold `#FAAF00` | **Answered 20.10**: gold stays (`#CFD4DE` border left untouched for now) |
| 3 | How the morning check-in scales combine into one 0–10 score; halves like 4.5 | **Answered 24.10 (O-5)**: simple average of morning scales (0–10), half-points rounded in employee's favor (less spoon deduction), sets `reported_at` |
| 4 | Noon ±3: raw score change or deduction-band change; what hours are "noon" | **Answered 24.10 (O-5)**: midday check-in open 12:00–15:00 employee-local time, direct integer delta −4..+4, capped 0..12 without recalculating morning score |
| 5 | Does "never show the deduction" also cover task prices (0/1/2) and "+8.5" rewards | **Answered 24.10 (Q5)**: applies ONLY to check-in survey answer options; task spoon costs (0/1/2) and golden spoon rewards stay visible |
| 6 | TPS-12 reward = score ÷ 10? IHS score source | **Answered 24.10 (O-6, O-8)**: TPS ÷ 10 confirmed (**superseded in v1.6.16**: participation reward only); IHS from 1–5 questionnaire answers `((mean - 1) / 4 * 100)` |
| 7 | When is the reward "shown" | **Answered 20.10**: answers lock once score/reward is shown; any review happens before |
| 8 | At ≤3 spoons, should Farming tasks lock too | **Answered 20.10**: yes, all tasks (O-10) |
| 9 | Emergency "flowing down the chain of command"; who sees the declare screen | **Answered (B5)**: only the safety & emergency manager declares; type names locked 13.10 (O-17) |
| 10 | CEO and VPs as separate roles; owner role; VP access depth | **Answered (B1/B2)**: role tree; role-to-tier mapping still a question (Q-K2) |
| 11 | "100 CHR Coins per workday" in v1? Keep 0.5 daily / 2 per shift / 10 at signup golden rules? | **Answered 24.10 (O-16 / Q11)**: only Golden Spoons active in v1 (0.5 daily, 2 per shift, 10 at signup); CHR Coins deferred to v2 |
| 12 | Store "in development" or hidden | **Answered 20.10**: live, no badge |
| 13 | Rejected salary literal in comments? Remove HRV table? | **Answered 20.10**: literal removed everywhere; HRV kept, marked v2 |
| 14 | What decides the turnover tier; point in range; what marks "deprived" | **Answered 24.10 (O-1, O-2, O-3, O-4, O-18)**: midpoint (40/125/300 %), tier from `org_role.tier` + CHRO override, deprived = weekly spoons < 5 OR `B_t >= 0.65`, company-wide tier avg salary |
| 15 | Team N: all members or respondents only | **Answered 20.10**: actual respondents / contributors (O-11) |

---

## Questions for Karin — NOT decided (encoded as working assumptions, flagged TODO להשלמה)

| # | Question | Working assumption in code |
|---|----------|---------------------------|
| Q-K1 | ~~Cuckoo contributor window~~ | **Resolved (Karin 20.10)** — rolling 30-day window of reporters (`fn_cuckoo_window`, tests at day 30 / 31 and 9 / 10 reporters) |
| Q-K2 | ~~Role-to-tier mapping~~ | **Resolved (Karin, Q8)** — table below, for Karin's review |
| Q-K3 | Prototype border `--line #E8EBF1` matches the page background (O-27) | No change made |

*End of ADR_GAPS.md — Specs to Code MVP pack v1.6.19-mvp*
