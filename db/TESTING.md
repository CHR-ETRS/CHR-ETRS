<!-- CHR-ETRS MVP v1 · TESTING.md · Version: 1.6.21-mvp r5 (2026-11-04; r5 = J-140 reminder wording approved; r4 2026-11-01; r4 = J-137 A stale note + team_not_calculated reminder, J-138 approved: counts; r3 = J-129 approved text, J-132 small teams in the board report total ('אחר'): counts; r2 = J-135 closed: the suite is date-independent, real clock, no libfaketime; r1 = J-123 B, J-128 A, J-121 A, J-126 A; 2026-10-31: J-115 A, J-112 A, J-108 A, no-department reminder, upgrade from c3a57b6) — supersedes the v1.6.21 TESTING.md. How the v1.6.21-r5 results were produced. -->
# How to run the CHR-ETRS code-pack tests (v1.6.21-mvp)

These are the exact steps used for the v1.6.21-r5 run on 2026-11-04 (real clock, no libfaketime), re-run on 2026-11-04 for
branch `db/authz-sensitive-rpcs` (J-146 A, then the sensitive-RPC authorization) on top of main 1ea87b7, and on 2026-11-23 for PR #12
(J-156 A / J-169 / J-170, on top of 4f04c0e; second round J-255 A – J-263 B on top of 191553c).

> **v1.6.21-r2 (J-135 closed):** the suite no longer depends on the date or the hour. It runs on the **real clock**; no
> faked-clock cluster or libfaketime is needed (the r1 note that required one is withdrawn). The four clock-sensitive
> fixtures that were found are fixed in the tests only (no product change) — see ADR_GAPS *Resolved in v1.6.21-r2*. The r2
> pack was also run once on a throw-away cluster with a faked clock at 13 dates/hours (2026-10-31 12:00, month / quarter /
> year boundaries just before and after midnight, Friday night, the 30-day offboarding edge, both DST changes): all
> suites and both migration modes passed at every point. That check is optional and not part of a normal run.

Everything runs locally against a **throw-away
PostgreSQL 17 cluster**. Nothing touches Supabase, staging or production.

## 1. What you need

| Item | Version used | Notes |
|------|--------------|-------|
| OS | Debian GNU/Linux 13 (trixie) | Any Linux or macOS with PostgreSQL 17 works |
| PostgreSQL server + client | **17.11**, binaries in `/usr/lib/postgresql/17/bin` | Debian / Ubuntu: `sudo apt-get install -y postgresql-17 postgresql-contrib-17` (PGDG repo). The pack needs the `pgcrypto` and `uuid-ossp` extensions (part of `postgresql-contrib`) |
| Python | 3.13.5 (3.9+ is fine) | `run_tests.sh` uses `python3` for the A-10 text check |
| openapi-spec-validator | 0.9.0 | In a venv, see step 4 |
| bash, grep, diff, md5sum | system | |

The tests do **not** use a server that is already running for other work: they DROP and CREATE databases
(`chr_v16_test*`, `chr_mig_*`) and the roles `chr_app_owner`, `legacy_v1_4_owner`, `anon`, `authenticated`,
`service_role`. Use a dedicated temporary cluster as below.

## 2. Start a temporary cluster (superuser `postgres`, Unix socket in /tmp, port 54317)

Run as a normal (non-root) user:

```bash
export PATH=/usr/lib/postgresql/17/bin:$PATH      # macOS / Homebrew: export PATH="$(brew --prefix postgresql@17)/bin:$PATH"
rm -rf /tmp/pg17
initdb -D /tmp/pg17 -U postgres --auth=trust --encoding=UTF8 --locale=C.UTF-8
pg_ctl -D /tmp/pg17 -o "-k /tmp -p 54317" -l /tmp/pg17.log start
psql -h /tmp -p 54317 -U postgres -c "SELECT version()"
```

- `-U postgres` makes `postgres` the **superuser** of the cluster (used by "super" mode and as the admin connection).
- `--auth=trust` is acceptable only because this cluster is local and disposable.
- Stop it afterwards with `pg_ctl -D /tmp/pg17 stop` (and `rm -rf /tmp/pg17` to throw it away).

## 3. Environment variables (every shell you test in)

```bash
export PATH=/usr/lib/postgresql/17/bin:$PATH
export PGHOST=/tmp PGPORT=54317 PGUSER=postgres
unset PGDATABASE PGPASSWORD PGTZ
```

## 4. Python + OpenAPI validator

```bash
python3 -m venv /tmp/venv-oas
/tmp/venv-oas/bin/pip install "openapi-spec-validator==0.9.0"
```

## 5. Run everything (from the `db/` folder of the repo, or the pack folder)

```bash
cd db                                   # the folder holding schema.sql, rpc.sql, openapi.yaml, tests/
./tests/run_tests.sh 2>&1 | tee /tmp/run_tests.log; echo "exit ${PIPESTATUS[0]}"
grep -c "WARNING:  PASS" /tmp/run_tests.log            # SQL checks passed (db/authz-sensitive-rpcs, PR #12 thirteenth round (Karin 27.11 — J-311 self-read pending_hr_review): 1623 = 1621 + 2 in test_assign_authz (the employee's own pending flag with exactly 7 fields and no reason / note / reviewer; another employee, a manager's self-read and the manager list see nothing new); the nosuper-applied run prints 199 `PASS NOSUPER`; `PASS HRUP` 73 → 81 (+1 J-311 catalog check after each of the 8 upgrade paths); PR #12 twelfth round (Karin 27.11 — J-313 end date active through the whole last company-local day): 1621 = 1617 + 4 in test_assign_authz (boundary checks for Jerusalem, Los Angeles, UTC, DST days and the no-zone strict fallback; a real-clock employee ended now is still active); the nosuper-applied run of the same file prints 197 `PASS NOSUPER`; `PASS HRUP` 61 → 73 (the J-313 object check after every upgrade, an upgrade from d1bdc6f with an end timestamp of now); PR #12 eleventh round (Karin 27.11 — J-354 without dblink; docs-only J-306 / J-325 – J-328 closed, J-358 – J-361): 1617 unchanged (the J-354 refusal checks were rewritten for the returned 400 / 422 body, not added) on the superuser-applied DB; the same 193 test_assign_authz checks now ALSO run on a pack applied by a non-superuser owner and print `PASS NOSUPER` (193, not part of the 1617: `grep -c 'PASS NOSUPER'`), and `PASS HRUP` rises 41 → 61 (upgrade from the real d1bdc6f pack, applied by a superuser and by a non-superuser: the schema chr_internal, the dblink extension and fn_audit_view_committed are gone, no audit row deleted; plus the no-extension check after every upgrade); PR #12 tenth round (Karin 27.11 — J-346 – J-354): 1617 = 1614 + 3 in test_assign_authz (J-346 warning, J-352 read audit, J-354 refused-stage audit); ninth round was docs only (1614 unchanged); PR #12 eighth round (Karin 25.11 — J-310, J-329 – J-338): 1614 = 1603 + 11 in test_assign_authz (section 17), plus 41 `PASS HRUP` lines (+9: the new import objects after every upgrade, upgrade from 130bdca with a staged batch); PR #12 seventh round (HR absence bulk import J-300 B – J-308 A): 1603 = 1585 + 18 in test_assign_authz (section 16), plus 32 `PASS HRUP` lines (+6: import objects after every upgrade, upgrade from 46a366f); PR #12 sixth round (J-295 – J-300): 1585 = 1576 + 9 in test_assign_authz (section 15 + J-284 A adjusted), plus 26 `PASS HRUP` lines; PR #12 fifth round (J-289 – J-294): 1576 = 1560 + 16 in test_assign_authz, plus 26 `PASS HRUP` lines of tests/test_hr_kind_upgrade.sh; PR #12 fourth round (J-276 – J-288): 1560 = 1548 + 12 in test_assign_authz, plus 22 `PASS HRUP` lines of tests/test_hr_kind_upgrade.sh (not SQL WARNING lines); PR #12 third round (J-267 C – J-275): 1548 = 1530 + 18 in test_assign_authz; PR #12 second round (J-255 A – J-263 B): 1530 = 1501 + 28 in test_assign_authz + 1 in test_v1_5; PR #12 J-156 A / J-169 / J-170 uniform manager list: 1501 = 1477 + 24 in test_assign_authz; J-163 no ledger system path: 1477 — 3 system-ledger checks replaced, total unchanged; sensitive-RPC authorization: 1477; J-146 A on db/authz-sensitive-rpcs: 1415; main 1ea87b7 incl. test_assign_authz.sql: 1389 — the r5 figure 1361 below was the count before test_assign_authz.sql (28) was added; v1.6.21-r5: 1361; v1.6.21-r4: 1357; v1.6.21-r3: 1346; v1.6.21-r2: 1336; v1.6.21-r1: 1335; v1.6.21: 1318; v1.6.20-r2: 1285)
grep -c "WARNING:  FAIL" /tmp/run_tests.log            # must be 0 (a FAIL also stops the run with exit ≠ 0)
grep "MIGRATION TESTS" /tmp/run_tests.log              # super: 114 passed, 0 failed · nosuper: 108 passed, 0 failed
/tmp/venv-oas/bin/openapi-spec-validator openapi.yaml   # → openapi.yaml: OK
```

What `run_tests.sh` does, in order (each on a fresh database):

1. `ref_country_calendar.sql` → `schema.sql` → `rpc.sql`, then the same three again (idempotency) →
   `tests/test_v1_5.sql` (817 checks: +1 with the PR #12 second round — J-260 A: the direct manager's Farming at 5 and at 4 is now the neutral refusal, the go-home fixture is self-assigned; 816 with PR #12 — the manager-feed / time-benefit / coordinate checks now read the uniform list — and by J-146 A — 4 manager-assign Circuit Breaker checks of section 5 now expect `assignment_unavailable` — and by J-147 / J-150 — the ledger checks run as the company's cfo, the turnover-tier check expects `access_denied`; 816 in v1.6.21-r5: +1 J-141 job / report rerun adds no reminder, per (team, month, vp_hr) = 1, total = active vp_hr; +2 J-139 live 'אחר' = report (D), no row / no note in both (F); +1 J-140 exact approved reminder text, no digit / id / pseudonym; 812 in v1.6.21-r4: +11 J-137 stale teams / note (X = 1, X = 0, row null) / vp_hr team_not_calculated reminder (created, not for calculated or smaller teams, idempotent, name only, vp_hr only); J-138 closed (approved, no new check); 801 in v1.6.21-r3: +10 J-132 small teams in the board report total / 'אחר' / remainder rule / report = board-member figures, J-129 exact text and J-115 remainder 4 updated in place; 791 in v1.6.21-r2: +1 J-135 cb11's day after the midday checks; 790 in v1.6.21-r1: +8 J-123 company-level alert, +3 J-121 'אחר' / placeholder, −1 replaced J-112 manager check; 780 in v1.6.21; +13 J-115 company totals / placeholder / EBITDA and J-112 company-level Cuckoo; 767 in v1.6.20-r2).
2. Fresh DB → pack → `tests/test_agents_v1_6_16.sql` (agents; 299 checks; PR #12: the A-13 manager-view check now expects an empty uniform list, J-259).
3. Fresh DB → pack → `tests/test_board_v1_6_19.sql` (board report; filename kept; 246 checks in v1.6.21-r4 too (J-102 catalog allowlist + fn_team_latest_earlier_row, which reads stored team rows only); 246 in v1.6.21-r1: +4 J-126 automatic close, +3 J-128 count never with a group metric; 239 in v1.6.21; +20 J-108 immediate notice and the two decisions, the no-department reminder; 219 in v1.6.20-r2).
3a. Fresh DB → pack → `tests/test_assign_authz.sql` (rpc_assign_task authorization; 199 checks with the PR #12 thirteenth round: +2 — J-311. 197 checks with the PR #12 twelfth round: +4 — J-313 boundary at 23:59:59 on the last day (active) and 00:00:00 the next day (inactive) in Asia/Jerusalem, America/Los_Angeles and UTC companies, on DST days, a UTC-vs-company-zone instant, no zone → strict rule, and an employee whose end is now is still active (the J-297 B strict boundary check and the immediate-offboarding `reviewable` expectation were replaced). 193 checks with the PR #12 eleventh round (unchanged count): the refused-upload checks (J-307 C 400s, J-335 A 422, J-338 A, J-354) now read the RETURNED Error Contract body and the HTTP status the RPC sets (`response.status`, via the test helper `t_stage_call`): exactly one audit row per refusal (company + reason only, no file content), no batch / staged row left, a 403 not logged, and a valid upload unchanged (no status override); the whole file is run twice — on the superuser-applied DB and (`${DB}_authz_ns`) on a pack applied by a non-superuser owner `chr_app_owner`, printed as `PASS NOSUPER`. 193 checks with the PR #12 tenth round: +3 — J-346 a nobody e-mail is a warning not an exception and the row is still processed by number; J-352 every successful rpc_hr_employee_numbers read is audited (who, when, company — never the numbers); J-354 a 422 and a 400 stage refusal are audited (reason, no file content). 190 checks with the PR #12 eighth round: +11 — section 17 (Karin 25.11): J-335 A row limit (empty = no limit; a configured limit → 422 import_too_many_rows, nothing staged); J-331 B stage audit row (company, batch, row count only); J-334 A case-insensitive cells and employee number; J-329 C identity_mismatch and J-337 B put_cancel_same_day → outcome exception, requires_attention, exceptions list, nothing written; J-333 A a second vp_hr commits; J-332 B a stored row on a file day or a named employee's new end date → 409 import_batch_changed (again on retry), nothing written, then a new dry run commits; J-336 B the employee-number reader (vp_hr of the company only, active employees, no user id, not logged, no number in the company list); J-338 A header keeps file name + SHA-256. 179 checks with the PR #12 seventh round: +18 — section 16, the HR absence bulk import: employee number setter (vp_hr only, unique per company, 409 taken); only vp_hr of the same company stages / validates / commits (manager, employee, CFO, legal, board, owner, department head, another company's vp_hr → 403; anon cannot execute; another company's batch = unknown id); input checks (400, no reason column); match by number and by e-mail (case-insensitive), unmatched / leaver / missing_key, cross-company rows unmatched both ways, future end date active; invalid action / date / kind, no_entry; conflicts (last row wins, both rows reported) and exact duplicates; the dry run writes nothing (HR rows + audit fingerprint); commit with J-279 re-put semantics and cancel as status; audit rows per write with the kind + one header; double commit and commit-before-dry-run → 409; committed rows immutable; J-284 extended to the import objects; section 11's catalogue check now also lists the import RPCs. 161 checks with the PR #12 sixth round: +9 — section 15 (J-297 B boundary at the end instant = left, future end date: put / cancel / set kind allowed, past end date refused; J-296 B reviewable true / false = the guard; J-295 C offboarding returns the pending list — future end reviewable, immediate end not, none → count 0 — only service_role may call it, nothing in the audit row); J-284 A adjusted for the internal offboarding helper (reads the table, never the kind). 152 checks with the PR #12 fifth round: +16 — section 14 (J-291 B self-read audit rows without the kind, empty read logged, anon / not signed in refused; J-292 no vp_hr read row while put / cancel still log the kind; J-293 user_id + full name per company row, every other role refused; J-294 C (chosen wording: active only) leaver refused byte-identical to an unknown id, active still fine, one internal guard; J-289 A needs_review not sick in totals or the J-276 max; manager list still uniform) and the direct-SELECT-blocked checks in section 10; 136 checks with the PR #12 fourth round: +12 section 13 (J-278 B review flow — constraints, the needs_review row in the uniform manager list, review list, refusals, set kind, audit with the kind; J-280 B audit rows with the kind (section 11 updated); J-288 B company reader access matrix and shape; J-289 counting; J-284 A no export / CHRO function); 124 checks with the PR #12 third round: +10 section 11 (J-267 C / J-269 A / J-279 / J-280: who reads the kind — vp_hr, the employee's own rows; manager, other employee, skip level, cfo, legal_ethics, board_chair, board_member, owner_shareholder, another company's vp_hr refused; catalog; no kind in the audit; invalid / missing kind; a kind correction leaves the manager list byte-identical) and +8 section 12 (J-272 B / J-276 / J-277: deduplicated HR sick days, GREATEST with the manual number, board sum, 'חסר', thresholds); 106 checks with the PR #12 second round: +8 section 6b (J-260 A: 0–5 כפיות, Farming and Fighting → 12 identical neutral refusals; above 5 unchanged) and section 10 rebuilt (+20: HR sick / other sources, merged day, coordination by a part id, vp_hr-only HR writes, audit, cancel / re-open); 78 checks with PR #12: +24 in section 10 — J-156 A / J-169 / J-170 uniform manager unavailability list: byte-identical rows across sources, today / future only, no time / כפיות / type / count, coordination for every source, refusals, vp_hr J-80 input; 54 checks with J-146 A: +26 — direct manager: 6 refusal reasons give 1 identical neutral answer, data / visible rows unchanged, exact text; self keeps the exact reason; J-153 = A: 26 stranger answers identical `access_denied` at 12 / 5 / 3 כפיות; helpers internal; 28 with J-143).
3b. Fresh DB → pack → `tests/test_sensitive_authz.sql` (sensitive-RPC authorization, J-147 – J-150; 62 checks: J-148 system recognition 4; reset spoons 16; value asset 16; ledger 21 (J-163: service_role refused / server session access_denied / data unchanged, no service_role grant); identical answers / no digit / 37 refusals 3; structure 2).
3c. `tests/test_hr_kind_upgrade.sh` (J-278 B, PR #12 fourth round; seventh round: + the import objects after every upgrade and an upgrade from 46a366f — 32 PASS HRUP lines; eighth round: + the case-insensitive number index, `exception` outcome, fingerprint column and empty row limit after every upgrade, and an upgrade from 130bdca with a staged batch — 41 PASS HRUP lines; eleventh round: + the no-extension check after every upgrade and an upgrade from d1bdc6f, applied by a superuser and by a non-superuser owner, with an old refusal audit row that must stay — 61 PASS HRUP lines; twelfth round: + the J-313 end-day object / boundary check after every upgrade and, in the d1bdc6f upgrade, an employee ended now — left before, active after — 73 PASS HRUP lines): the hr_absence_entry kind review upgrade from simulated c56d380 / 8eade64 shapes and — when the git history is available — the real c56d380 / 8eade64 packs; 26 `PASS HRUP` lines (J-291 B: + the direct read is gone after every upgrade), ends with `HR KIND UPGRADE TESTS: 0 failed`.
4. `MIG_MODE=super ./tests/test_migration.sh` — v1.4 → v1.6.21 migration as superuser (event-trigger DDL guard +
   timezone preflight): dry run, apply, counts, catalog = fresh, idempotence, rollback.
5. `MIG_MODE=nosuper ./tests/test_migration.sh` — the same as a **non-superuser** owner: the script itself creates
   `chr_app_owner` (`LOGIN CREATEDB CREATEROLE BYPASSRLS NOSUPERUSER`) through the admin (`PGUSER=postgres`)
   connection and uses the O-53 fallback. No manual role setup is needed.
6. A-10 check: every `r = 0.37` in openapi.yaml / README.md / ADR_GAPS.md sits inside the full binding text.
7. The salary-literal grep (the forbidden literal must have 0 hits).

To run one suite alone (example: board):

```bash
psql -qc "DROP DATABASE IF EXISTS t_board" postgres && psql -qc "CREATE DATABASE t_board" postgres
psql -d t_board -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql
psql -d t_board -v ON_ERROR_STOP=1 -qAt -f tests/test_board_v1_6_19.sql > /tmp/board.log 2>&1; echo "exit $?"
grep -c "WARNING:  PASS" /tmp/board.log
```

One migration mode alone: `MIG_MODE=nosuper ./tests/test_migration.sh`.
Known flake: in rare runs the nosuper mode stops with `permission denied to terminate process` (a background
connection the non-superuser cannot end). Re-run the same command; it is not a pack failure.

## 6. In-place upgrade check (old pack already loaded, with data → apply the new pack twice)

`OLD` = folder of the old pack (e.g. `git archive 4d5faf9 db | tar -x -C /tmp/old_4d5` from the repo root → `/tmp/old_4d5/db`,
or a v1.6.18 pack folder). `NEW` = this folder.

```bash
cat > /tmp/upgrade_check.sh <<'SH'
#!/usr/bin/env bash
# usage: upgrade_check.sh <label> <old pack dir> <new pack dir>
set -uo pipefail
L=$1; OLD=$2; NEW=$3; D=up_$L; F=up_fresh; W=/tmp/upgrade_$L; mkdir -p $W
counts="SELECT (SELECT count(*) FROM happiness_debt_events)||'|'||(SELECT count(*) FROM happiness_debt_remediation_allocation)||'|'||(SELECT count(*) FROM remediation_records)||'|'||(SELECT count(*) FROM users)||'|'||(SELECT count(*) FROM approved_absence_entry)||'|'||(SELECT count(*) FROM early_leave_log)"
cat_q="SELECT p.proname||'('||pg_get_function_identity_arguments(p.oid)||')->'||pg_get_function_result(p.oid)||' '||md5(p.prosrc)||' '||p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' UNION ALL SELECT 'col '||table_name||'.'||column_name||' '||data_type||' '||is_nullable FROM information_schema.columns WHERE table_schema='public' UNION ALL SELECT 'trg '||tgrelid::regclass||'.'||tgname FROM pg_trigger WHERE NOT tgisinternal UNION ALL SELECT 'pol '||tablename||'.'||policyname FROM pg_policies WHERE schemaname='public' UNION ALL SELECT 'acl '||p.proname||' '||coalesce(p.proacl::text,'') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' ORDER BY 1"
psql -qc "DROP DATABASE IF EXISTS $D" postgres; psql -qc "CREATE DATABASE $D" postgres
# old pack + its agents test as realistic data
(cd $OLD && psql -d $D -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql >/dev/null 2>&1 \
  && psql -d $D -v ON_ERROR_STOP=1 -qAt -f tests/test_agents_v1_6_16.sql > $W/old_data.log 2>&1) || { echo "old load FAILED"; exit 1; }
# J-101 data: one company whose department reads 'General' (2 employees + its vp_hr), written with the OLD pack
psql -d $D -v ON_ERROR_STOP=1 -q <<'SQL' || { echo "J-101 data FAILED"; exit 1; }
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
VALUES (md5('up-gen-co')::uuid, 'Upgrade General Co', 'IL', 0, 4, 'Asia/Jerusalem');
INSERT INTO auth.users (id) SELECT md5('up-gen-' || k)::uuid FROM unnest(ARRAY['hr', 'e1', 'e2']) k;
INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date)
SELECT md5('up-gen-' || k)::uuid, md5('up-gen-co')::uuid, k || '@upgen', 'Up ' || k, 'General',
       CASE k WHEN 'hr' THEN 'vp_hr' ELSE 'employee' END, CASE k WHEN 'hr' THEN 'vp' ELSE 'employee' END,
       'Asia/Jerusalem', CURRENT_DATE - 100
  FROM unnest(ARRAY['hr', 'e1', 'e2']) k;
-- v1.6.21: one employee without a department (written with the OLD pack) → the pack gives the vp_hr one reminder
INSERT INTO auth.users (id) VALUES (md5('up-gen-nd')::uuid);
INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date)
VALUES (md5('up-gen-nd')::uuid, md5('up-gen-co')::uuid, 'nd@upgen', 'Up nd', NULL, 'employee', 'employee', 'Asia/Jerusalem', CURRENT_DATE - 100);
SQL
before=$(psql -d $D -Atc "$counts")
notices="SELECT count(*) FROM notification WHERE kind = 'default_department_review'"
for i in 1 2; do (cd $NEW && psql -d $D -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql > $W/apply$i.log 2>&1) \
  && echo "apply $i OK" || { echo "apply $i FAILED"; grep ERROR $W/apply$i.log | head; exit 1; }
  n=$(psql -d $D -Atc "$notices"); if [ $i = 1 ]; then notice1=$n; else notice2=$n; fi; done
# J-101: the notice goes once to every active vp_hr of a company with a 'General' (marker false) — the same after apply 2
exp=$(psql -d $D -Atc "SELECT count(*) FROM users v WHERE v.app_role = 'vp_hr' AND v.employment_ended_at IS NULL AND fn_general_department_ambiguous_count(v.company_id) > 0")
dup=$(psql -d $D -Atc "SELECT count(*) FROM (SELECT 1 FROM notification WHERE kind = 'default_department_review' GROUP BY recipient_id, ref_id HAVING count(*) > 1) x")
[ "$notice1" = "$exp" ] && [ "$notice2" = "$exp" ] && [ "$dup" = 0 ] && [ "$exp" -ge 1 ] \
  && echo "PASS J-101 notice once: after apply 1 = $notice1, after apply 2 = $notice2 (expected $exp), duplicates 0" \
  || echo "FAIL J-101 notice: apply1 $notice1 apply2 $notice2 expected $exp dup $dup"
# v1.6.21: the no-department reminder — one per active vp_hr of a company with employees without a department, unchanged after apply 2
rexp=$(psql -d $D -Atc "SELECT count(*) FROM users v WHERE v.app_role = 'vp_hr' AND v.employment_ended_at IS NULL AND fn_no_department_employee_count(v.company_id) > 0")
rgot=$(psql -d $D -Atc "SELECT count(*) FROM notification WHERE kind = 'no_department_reminder'")
rdup=$(psql -d $D -Atc "SELECT count(*) FROM (SELECT 1 FROM notification WHERE kind = 'no_department_reminder' GROUP BY recipient_id, ref_id HAVING count(*) > 1) x")
[ "$rgot" = "$rexp" ] && [ "$rdup" = 0 ] && [ "$rexp" -ge 1 ] && echo "PASS no-department reminder: $rgot (expected $rexp), duplicates 0" \
  || echo "FAIL no-department reminder: got $rgot expected $rexp dup $rdup"
after=$(psql -d $D -Atc "$counts")
[ "$before" = "$after" ] && echo "PASS data unchanged ($after)" || echo "FAIL data changed: $before → $after"
psql -qc "DROP DATABASE IF EXISTS $F" postgres; psql -qc "CREATE DATABASE $F" postgres
(cd $NEW && psql -d $F -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql >/dev/null 2>&1)
psql -d $D -Atc "$cat_q" > $W/up.cat; psql -d $F -Atc "$cat_q" > $W/fresh.cat
# the old test's own helper objects (t_*) are expected extras in the upgraded DB
n=$(diff $W/fresh.cat $W/up.cat | grep '^[<>]' | grep -vcE "^[<>] (t_[a-z_]+\(|col t_[a-z_]+\.|acl t_[a-z_]+ |trg t_|pol t_)")
# J-101 = A: the upgrade marks NO existing row as the default department; ambiguous 'General' rows are only counted
echo "J-101: marked default after upgrade = $(psql -d $D -Atc "SELECT count(*) FROM users WHERE department_is_default") (expected 1 = only the employee written without a department, marked by the OLD pack's J-96 default; no 'General' row marked), ambiguous 'General' = $(psql -d $D -Atc "SELECT fn_general_department_ambiguous_count(NULL)")"
[ "$n" = 0 ] && echo "PASS catalog = fresh ($(wc -l < $W/fresh.cat) entries, test helpers ignored)" || { echo "FAIL catalog: $n lines differ"; diff $W/fresh.cat $W/up.cat | head -20; }
SH
chmod +x /tmp/upgrade_check.sh
git -C "$(git rev-parse --show-toplevel)" archive c3a57b6 db | (mkdir -p /tmp/old_c3a && tar -x -C /tmp/old_c3a)
/tmp/upgrade_check.sh sc3a /tmp/old_c3a/db "$PWD"
```

(v1.6.21 used c3a57b6 = merged main with PR #9 (v1.6.20-r2). v1.6.20 used 4d5faf9 and a v1.6.18 pack folder; v1.6.20-r1 used 4d5faf9 and f848795; v1.6.20-r2 used 4d5faf9 and
d149bc9 — the r1 commit already on PR #9.)

## 7. Greps used as release gates (must print 0)

```bash
grep -rnE '10{1}50{3}' --include='*.sql' --include='*.yaml' --include='*.md' --include='*.sh' --include='*.py' . | wc -l   # salary literal
export LC_ALL=C.UTF-8                                                                                                      # needed for \p{Hebrew} in grep -P
INC="--include=*.sql --include=*.yaml --include=*.md --include=*.sh --include=*.py"
grep -rn 'משיבים' $INC --exclude=TESTING.md . | wc -l                                        # terminology: always "מדווחים בפועל"
grep -rn 'מס החסך' $INC --exclude=TESTING.md . | wc -l                                                                    # terminology: always "מס קיפוח"
grep -rnP '(?<![\p{Hebrew}])כפות(?![\p{Hebrew}])' $INC --exclude=TESTING.md . | wc -l                                    # the word "כפות" on its own
grep -rn 'צבן' $INC --exclude=TESTING.md . | wc -l                                                                        # the name is spelled צבאן
```

To keep a full log (as for v1.6.21-r4): `mkdir -p /workspace/test-logs && ./tests/run_tests.sh 2>&1 | tee /workspace/test-logs/v1.6.21-r5_run_tests_$(git rev-parse --short HEAD).log`.

The "no person_id / user_id / pseudonym in agent and board outputs" rule, the A-10 binding text, G-3
identical responses, the B_t 0.37 weight and the J-88 exact absence definition are checked **inside** the SQL
suites (`t_ids_free`, the A-10 / G-3 / J-88 checks) — they are part of the PASS counts above.

## 8. Clean up

```bash
pg_ctl -D /tmp/pg17 stop && rm -rf /tmp/pg17 /tmp/venv-oas /tmp/old_4d5 /tmp/old_d149 /tmp/upgrade_*
```
