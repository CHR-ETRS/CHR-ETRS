<!-- CHR-ETRS MVP v1 · TESTING.md · Version: 1.6.21-mvp r4 (2026-11-01; r4 = J-137 A stale note + team_not_calculated reminder, J-138 approved: counts; r3 = J-129 approved text, J-132 small teams in the board report total ('אחר'): counts; r2 = J-135 closed: the suite is date-independent, real clock, no libfaketime; r1 = J-123 B, J-128 A, J-121 A, J-126 A; 2026-10-31: J-115 A, J-112 A, J-108 A, no-department reminder, upgrade from c3a57b6) — supersedes the v1.6.21 TESTING.md. How the v1.6.21-r4 results were produced. -->
# How to run the CHR-ETRS code-pack tests (v1.6.21-mvp)

These are the exact steps used for the v1.6.21-r4 run on 2026-11-01 (real clock, no libfaketime).

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
grep -c "WARNING:  PASS" /tmp/run_tests.log            # SQL checks passed (v1.6.21-r4: 1357; v1.6.21-r3: 1346; v1.6.21-r2: 1336; v1.6.21-r1: 1335; v1.6.21: 1318; v1.6.20-r2: 1285)
grep -c "WARNING:  FAIL" /tmp/run_tests.log            # must be 0 (a FAIL also stops the run with exit ≠ 0)
grep "MIGRATION TESTS" /tmp/run_tests.log              # super: 114 passed, 0 failed · nosuper: 108 passed, 0 failed
/tmp/venv-oas/bin/openapi-spec-validator openapi.yaml   # → openapi.yaml: OK
```

What `run_tests.sh` does, in order (each on a fresh database):

1. `ref_country_calendar.sql` → `schema.sql` → `rpc.sql`, then the same three again (idempotency) →
   `tests/test_v1_5.sql` (812 checks in v1.6.21-r4: +11 J-137 stale teams / note (X = 1, X = 0, row null) / vp_hr team_not_calculated reminder (created, not for calculated or smaller teams, idempotent, name only, vp_hr only); J-138 closed (approved, no new check); 801 in v1.6.21-r3: +10 J-132 small teams in the board report total / 'אחר' / remainder rule / report = board-member figures, J-129 exact text and J-115 remainder 4 updated in place; 791 in v1.6.21-r2: +1 J-135 cb11's day after the midday checks; 790 in v1.6.21-r1: +8 J-123 company-level alert, +3 J-121 'אחר' / placeholder, −1 replaced J-112 manager check; 780 in v1.6.21; +13 J-115 company totals / placeholder / EBITDA and J-112 company-level Cuckoo; 767 in v1.6.20-r2).
2. Fresh DB → pack → `tests/test_agents_v1_6_16.sql` (agents; 299 checks).
3. Fresh DB → pack → `tests/test_board_v1_6_19.sql` (board report; filename kept; 246 checks in v1.6.21-r4 too (J-102 catalog allowlist + fn_team_latest_earlier_row, which reads stored team rows only); 246 in v1.6.21-r1: +4 J-126 automatic close, +3 J-128 count never with a group metric; 239 in v1.6.21; +20 J-108 immediate notice and the two decisions, the no-department reminder; 219 in v1.6.20-r2).
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

To keep a full log (as for v1.6.21-r4): `mkdir -p /workspace/test-logs && ./tests/run_tests.sh 2>&1 | tee /workspace/test-logs/v1.6.21-r4_run_tests_$(git rev-parse --short HEAD).log`.

The "no person_id / user_id / pseudonym in agent and board outputs" rule, the A-10 binding text, G-3
identical responses, the B_t 0.37 weight and the J-88 exact absence definition are checked **inside** the SQL
suites (`t_ids_free`, the A-10 / G-3 / J-88 checks) — they are part of the PASS counts above.

## 8. Clean up

```bash
pg_ctl -D /tmp/pg17 stop && rm -rf /tmp/pg17 /tmp/venv-oas /tmp/old_4d5 /tmp/old_d149 /tmp/upgrade_*
```
