#!/usr/bin/env bash
# CHR-ETRS MVP v1.6.18 · tests/test_migration.sh — v1.4 → v1.6.18 migration tests (PostgreSQL 17).
# v1.6.18 (2026-10-31): runs migrate_v1_4_to_v1_6_18.sql; catalog compared with a fresh v1.6.18 pack.
# Version: 1.6.18-mvp (2026-10-31; base 1.6.13-mvp 2026-10-21) — supersedes the 1.6.9 test. Two modes (MIG_MODE):
#   super   (default): the app connection is a superuser → the runner installs the event-trigger guard;
#                      + the timezone preflight block (non-UTC source DB with / without --source-tz).
#   nosuper          : the app connection is chr_app_owner (LOGIN CREATEDB CREATEROLE, NOT superuser, like a
#                      managed Supabase owner) → the guard is refused and the O-53 FALLBACK applies.
# The admin connection (PGUSER, superuser) only sets up roles / databases and inspects.
# v1.4 fixture (real v1.4 structure, tests/fixtures/) → dry run → apply (runner, with backup) → counts →
# catalog = fresh v1.6.18 → second run changes nothing → release held companies → rollback = v1.4 again.
# Prints one "PASS MIG …" / "FAIL MIG …" line per check; exits 1 on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
unset PGTZ
MODE=${MIG_MODE:-super}
ADMIN=${PGUSER:-postgres}
case "$MODE" in
  super)   APP=$ADMIN;         SFX="" ;;
  nosuper) APP=chr_app_owner;  SFX="_ns" ;;
  *) echo "MIG_MODE must be super or nosuper" >&2; exit 2 ;;
esac
DB=${MIG_TEST_DB:-chr_mig_test$SFX}; FRESH=${MIG_FRESH_DB:-chr_mig_fresh$SFX}; TZDB="${DB}_tz"
export BACKUP_DIR; BACKUP_DIR="$(mktemp -d)"
FAILS=0; PASSES=0; W="$(mktemp -d)"
echo "migration tests: mode $MODE (app connection $APP)"

# ok / bad: record one check
ok()  { echo "PASS MIG $1"; PASSES=$((PASSES + 1)); }
bad() { echo "FAIL MIG $1"; FAILS=$((FAILS + 1)); }
# check <name> <expected> <actual>: equality check
check() { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
# q <sql>: one value from the test database (admin connection)
# SP: legacy tables live in schema legacy_v1_4 after the nosuper fallback → found unqualified in the checks
SP="-c search_path=public,legacy_v1_4"
q() { PGOPTIONS="$PGOPTIONS $SP" psql -X -U "$ADMIN" -d "$DB" -qAt -v ON_ERROR_STOP=1 -c "$1"; }
# qdb <db> <sql>: one value from another database (admin connection)
qdb() { psql -X -U "$ADMIN" -d "$1" -qAt -v ON_ERROR_STOP=1 -c "$2"; }
# snap <file>: catalog + data snapshot of the test database
snap() { psql -X -U "$ADMIN" -d "$DB" -qAt -f tests/catalog_snapshot.sql > "$1.cat"; psql -X -U "$ADMIN" -d "$DB" -qAt -f tests/data_hash.sql > "$1.dat"; }
# recreate <db>: empty database owned by the app connection, compared in UTC (the cluster default here is
# Asia/Jerusalem — a UTC source is what the preflight passes without --source-tz)
recreate() { psql -X -U "$ADMIN" -qc "DROP DATABASE IF EXISTS \"$1\" WITH (FORCE)" postgres
             psql -X -U "$ADMIN" -qc "CREATE DATABASE \"$1\" OWNER \"$APP\"" postgres
             psql -X -U "$ADMIN" -qc "ALTER DATABASE \"$1\" SET timezone TO 'UTC'" postgres; }
# runner <args…>: the migration runner as the app connection
runner() { PGUSER="$APP" migrations/run_migration.sh "$@"; }
# app_sql <db> <sql>: run SQL as the app connection (output + errors on stdout)
app_sql() { PGOPTIONS="$PGOPTIONS $SP" psql -X -U "$APP" -d "$1" -qAt -v ON_ERROR_STOP=1 -c "$2" 2>&1; }

# roles: nosuper mode starts from scratch (its databases first, then the fallback owner role)
for d in "$DB" "$FRESH" "$TZDB"; do psql -X -U "$ADMIN" -qc "DROP DATABASE IF EXISTS \"$d\" WITH (FORCE)" postgres; done
if [ "$MODE" = nosuper ]; then
  psql -X -U "$ADMIN" -qc "DROP ROLE IF EXISTS legacy_v1_4_owner" postgres
  if [ "$(qdb postgres "SELECT count(*) FROM pg_roles WHERE rolname = '$APP'")" = 0 ]; then
    psql -X -U "$ADMIN" -qc "CREATE ROLE $APP LOGIN CREATEDB CREATEROLE BYPASSRLS NOSUPERUSER" postgres
  else psql -X -U "$ADMIN" -qc "ALTER ROLE $APP LOGIN CREATEDB CREATEROLE BYPASSRLS NOSUPERUSER" postgres; fi
fi

recreate "$FRESH"
psql -X -U "$APP" -d "$FRESH" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql > /dev/null
psql -X -U "$ADMIN" -d "$FRESH" -qAt -f tests/catalog_snapshot.sql > "$W/fresh.cat"
recreate "$DB"
psql -X -U "$APP" -d "$DB" -v ON_ERROR_STOP=1 -q -f tests/fixtures/v1_4_schema.sql -f tests/fixtures/v1_4_rpc.sql -f tests/fixtures/v1_4_data.sql > /dev/null
snap "$W/v14"
check "fixture is v1.4 (users.manager_id, spoon_budget.energy_state)" "2" \
  "$(q "SELECT count(*) FROM information_schema.columns WHERE (table_name, column_name) IN (('users','manager_id'),('spoon_budget','energy_state'))")"

# fails <name> <pattern> <sql>: the statement must fail with an error matching <pattern>
# (as the admin connection; fails_app / runs as the app connection)
fails() { local out; out="$(PGOPTIONS="$PGOPTIONS $SP" psql -X -U "$ADMIN" -d "$DB" -qAt -v ON_ERROR_STOP=1 -c "$3" 2>&1)" && { bad "$1 (succeeded)"; return; }
          case "$out" in *$2*) ok "$1" ;; *) bad "$1 ($out)" ;; esac; }
# runs <name> <sql>: the statement must succeed
runs() { local out; out="$(psql -X -U "$ADMIN" -d "$DB" -qAt -v ON_ERROR_STOP=1 -c "$2" 2>&1)" && ok "$1" || bad "$1 ($out)"; }
# fails_app <name> <pattern> <sql>: as the app connection, must fail matching <pattern>
fails_app() { local out; out="$(app_sql "$DB" "$3")" && { bad "$1 (succeeded)"; return; }
              case "$out" in *$2*) ok "$1" ;; *) bad "$1 ($out)" ;; esac; }
check "admin connection is a superuser (setup / inspection)" "t" "$(q "SELECT rolsuper FROM pg_roles WHERE rolname = current_user")"
check "mode $MODE: app connection $APP superuser = $([ "$MODE" = super ] && echo t || echo f)" "$([ "$MODE" = super ] && echo t || echo f)" \
  "$(app_sql postgres "SELECT rolsuper FROM pg_roles WHERE rolname = current_user")"

check "O-50: v1.4 users has a created_at column (timestamptz, NOT NULL) — basis of the trust rule" "timestamp with time zone|NO" \
  "$(q "SELECT data_type || '|' || is_nullable FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'created_at'")"

# --- dry run -----------------------------------------------------------------
runner dry-run "$DB" > "$W/dry.log" 2>&1 && ok "dry run exits 0" || { bad "dry run exits 0"; cat "$W/dry.log"; }
grep -q "DRY RUN — rolling back" "$W/dry.log" && ok "dry run rolls back" || bad "dry run rolls back"
grep -qE "users\.migrated +\| +12$" "$W/dry.log" && ok "dry run reports counts (users.migrated 12)" || bad "dry run reports counts"
if [ "$MODE" = super ]; then
  grep -q "legacy protection: event-trigger guard (superuser)" "$W/dry.log" && ok "dry run reports the protection mode (guard, superuser)" || bad "dry run reports the protection mode (guard)"
else
  grep -q "legacy protection: NO superuser — apply would use the FALLBACK" "$W/dry.log" && ok "dry run reports the protection mode (fallback, no superuser)" || bad "dry run reports the protection mode (fallback)"
fi
grep -q "compared in: UTC" "$W/dry.log" && ok "tz preflight: UTC source passes, dates compared in UTC" || bad "tz preflight: UTC source passes"
snap "$W/after_dry"
cmp -s "$W/v14.cat" "$W/after_dry.cat" && ok "dry run: catalog unchanged" || bad "dry run: catalog unchanged"
cmp -s "$W/v14.dat" "$W/after_dry.dat" && ok "dry run: data unchanged" || bad "dry run: data unchanged"

# --- v1.6.13 rule 4: timezone preflight on a non-UTC source (copy of the v1.4 DB, Asia/Jerusalem) --------
if [ "$MODE" = super ]; then
  psql -X -U "$ADMIN" -qc "CREATE DATABASE \"$TZDB\" TEMPLATE \"$DB\" OWNER \"$APP\"" postgres
  psql -X -U "$ADMIN" -qc "ALTER DATABASE \"$TZDB\" SET timezone TO 'Asia/Jerusalem'" postgres
  runner apply "$TZDB" > "$W/tz1.log" 2>&1 && bad "tz preflight: non-UTC source without --source-tz stops (succeeded)" \
    || { grep -q 'source database timezone is "Asia/Jerusalem" (not UTC)' "$W/tz1.log" && grep -q -- "--source-tz" "$W/tz1.log" \
         && ok "tz preflight: non-UTC source without --source-tz stops with a clear message" || bad "tz preflight: wrong stop ($(cat "$W/tz1.log"))"; }
  check "…before the backup and without a change (no backup, start_date still plain)" "0|" \
    "$(ls "$BACKUP_DIR" | grep -c "^${TZDB}_pre" || true)|$(qdb "$TZDB" "SELECT attgenerated FROM pg_attribute WHERE attrelid = 'users'::regclass AND attname = 'start_date'")"
  psql -X -U "$APP" -d "$TZDB" -v ON_ERROR_STOP=1 -f migrations/migrate_v1_4_to_v1_6_18.sql > "$W/tz1b.log" 2>&1 \
    && bad "tz preflight: plain psql without -v source_tz also stops (succeeded)" \
    || { grep -q "not UTC" "$W/tz1b.log" && ok "tz preflight: plain psql without -v source_tz also stops" || bad "tz preflight: plain psql stop ($(tail -3 "$W/tz1b.log"))"; }
  runner --source-tz Mars/Olympus dry-run "$TZDB" > "$W/tz2.log" 2>&1 && bad "tz preflight: unknown --source-tz refused (succeeded)" \
    || { grep -q 'unknown --source-tz "Mars/Olympus"' "$W/tz2.log" && ok "tz preflight: unknown --source-tz refused" || bad "tz preflight: unknown zone ($(cat "$W/tz2.log"))"; }
  runner --source-tz Asia/Jerusalem apply "$TZDB" > "$W/tz3.log" 2>&1 && ok "tz preflight: --source-tz Asia/Jerusalem → apply runs" || { bad "tz preflight: --source-tz apply"; cat "$W/tz3.log"; }
  grep -q "compared in: Asia/Jerusalem" "$W/tz3.log" && ok "…dates compared in Asia/Jerusalem" || bad "…dates compared in Asia/Jerusalem"
  # Asia/Jerusalem: u1 (09-14 13:00 local) AND u3 (09-15 01:30 local) untrusted; u5 (00:30 local) is the edge
  for kv in "users.start_date_untrusted 2" "users.hire_date_from_v1_4_start_date 9" "users.hire_date_missing 3" \
            "users.tz_edge_review 1" "users.tps_wait_hire 9" "users.tps_wait_exempt 3"; do
    set -- $kv
    grep -qE "^ ${1//./\\.} +\| +$2$" "$W/tz3.log" && ok "tz apply count $1 = $2" || bad "tz apply count $1 = $2"
  done
  check "tz: untrusted audits compared in Asia/Jerusalem (u1, u3)" "Asia/Jerusalem|10000000-0000-0000-0000-000000000008,10000000-0000-0000-0000-000000000010" \
    "$(qdb "$TZDB" "SELECT string_agg(DISTINCT scope->>'compared_in', ','), string_agg(scope->>'user_id', ',' ORDER BY scope->>'user_id') FROM access_audit_log WHERE action = 'start_date_untrusted'")"
  check "tz: edge audit tz_edge_review = u5 only (00:30 local, zone Asia/Jerusalem, trusted, hire 2025-09-01 kept)" \
    "1|10000000-0000-0000-0000-000000000012|Asia/Jerusalem|false|2025-09-01" \
    "$(qdb "$TZDB" "SELECT count(*), max(scope->>'user_id'), max(scope->>'zone'), max(scope->>'untrusted'), (SELECT hire_date FROM users WHERE email = 'u5@alpha') FROM access_audit_log WHERE action = 'tz_edge_review'")"
  runner apply "$TZDB" > "$W/tz4.log" 2>&1 && ok "tz preflight: already migrated non-UTC DB re-runs without --source-tz (nothing left to compare)" \
    || { bad "tz preflight: re-run on migrated non-UTC DB"; cat "$W/tz4.log"; }
  check "…and adds no audit (1 edge, 2 untrusted)" "1|2" \
    "$(qdb "$TZDB" "SELECT (SELECT count(*) FROM access_audit_log WHERE action = 'tz_edge_review'), (SELECT count(*) FROM access_audit_log WHERE action = 'start_date_untrusted')")"
  psql -X -U "$ADMIN" -qc "DROP DATABASE \"$TZDB\" WITH (FORCE)" postgres
  rm -f "$BACKUP_DIR/${TZDB}_pre"*
fi

# --- apply -------------------------------------------------------------------
runner apply "$DB" > "$W/apply.log" 2>&1 && ok "apply exits 0" || { bad "apply exits 0"; cat "$W/apply.log"; }
check "apply took a backup first" "1" "$(ls "$BACKUP_DIR" | wc -l)"
# expected run counts (fixture: 12 users — 10 trusted start dates, 1 untrusted (= creation date), 1 without —,
# 1 created within 1 h of UTC midnight (u4),
# 3 non-employee app roles, 3 manager links, 12 spoon days, 2 avatars,
# 2 companies without country, 1/1/8 rows in team_aggregate/employee_value_asset/shop_item_catalog, 4 role_cost_config)
for kv in "users.migrated 12" "users.org_role_needs_review 3" "users.manager_id_to_reports_to 3" \
          "users.pseudonym_assigned 12" "users.hire_date_from_v1_4_start_date 10" "users.start_date_untrusted 1" \
          "users.hire_date_missing 2" "users.tps_wait_team_join 0" "users.tps_wait_hire 10" "users.tps_wait_exempt 2" \
          "users.tz_edge_review 1" \
          "spoon_budget.marked_legacy_v1_4 12" "legacy.tables_read_only 7" \
          "spoon_budget.rows_kept 12" "avatar_state.golden_spoons_to_numeric 2" \
          "companies.reminders_on_hold_no_country 2" "companies.timezone_needs_review 2" \
          "legacy.team_aggregate 1" "legacy.employee_value_asset 1" "legacy.shop_item_catalog 8" \
          "legacy.role_cost_config 4" "project.legacy_set_non_core 0"; do
  set -- $kv
  grep -qE "^ ${1//./\\.} +\| +$2$" "$W/apply.log" && ok "apply count $1 = $2" || bad "apply count $1 = $2"
done
check "users kept (12)" "12" "$(q "SELECT count(*) FROM users")"
check "reports_to = v1.4 manager_id" "10000000-0000-0000-0000-000000000002" \
  "$(q "SELECT reports_to FROM users WHERE email = 'e1@alpha'")"
check "pseudonyms set, unique per company" "12|12" "$(q "SELECT count(display_pseudonym), count(DISTINCT (company_id, display_pseudonym)) FROM users")"
check "org_role_code defaults to employee (review TODO)" "12" "$(q "SELECT count(*) FROM users WHERE org_role_code = 'employee'")"
check "O-49: no team_joined_at invented (v1.4 has no team-join field)" "0" "$(q "SELECT count(team_joined_at) FROM users")"
check "O-50: trusted v1.4 start_date → hire_date (e1 2025-03-01; u2 2025-09-01; u3 2025-09-15, created 22:30 UTC the day before → trusted under the UTC rule)" \
  "10|2025-03-01|2025-09-01|2025-09-15" \
  "$(q "SELECT (SELECT count(hire_date) FROM users), (SELECT hire_date FROM users WHERE email = 'e1@alpha'), (SELECT hire_date FROM users WHERE email = 'u2@beta'), (SELECT hire_date FROM users WHERE email = 'u3@alpha')")"
check "O-50: start_date = creation date (u1, 2025-09-14) → untrusted: hire_date NULL, TPS exempt" "|exempt" \
  "$(q "SELECT (SELECT hire_date FROM users WHERE email = 'u1@beta'), (SELECT w.source FROM users u, fn_tps_wait_start(u.user_id) w WHERE u.email = 'u1@beta')")"
check "O-50: untrusted case audited once (start_date_untrusted: user, start_date, creation date, compared in UTC)" \
  "1|10000000-0000-0000-0000-000000000008|2025-09-14|2025-09-14|UTC" \
  "$(q "SELECT count(*), max(scope->>'user_id'), max(scope->>'start_date'), max(scope->>'created_at_date'), max(scope->>'compared_in') FROM access_audit_log WHERE action = 'start_date_untrusted'")"
check "O-50: start_date is now the generated alias, equal to hire_date for all 12 users" "s|0" \
  "$(q "SELECT (SELECT attgenerated FROM pg_attribute WHERE attrelid = 'users'::regclass AND attname = 'start_date'), (SELECT count(*) FROM users WHERE start_date IS DISTINCT FROM hire_date)")"
fails "O-50: writing start_date after the migration is refused (generated column)" "generated" "UPDATE users SET start_date = DATE '2020-01-01' WHERE email = 'e1@alpha'"
check "O-49: TPS wait source audited once per user (hire 10, exempt 2)" "exempt=2,hire=10" \
  "$(q "SELECT string_agg(src || '=' || n, ',' ORDER BY src) FROM (SELECT scope->>'source' src, count(*) n FROM access_audit_log WHERE action = 'tps_wait_source' GROUP BY 1) x")"
check "tz: edge audit tz_edge_review (UTC) = u4 only (23:40 UTC, trusted, hire kept; flag only)" \
  "1|10000000-0000-0000-0000-000000000011|UTC|false|2025-09-01|2025-09-01" \
  "$(q "SELECT count(*), max(scope->>'user_id'), max(scope->>'zone'), max(scope->>'untrusted'), (SELECT hire_date FROM users WHERE email = 'u4@beta'), (SELECT hire_date FROM users WHERE email = 'u5@alpha') FROM access_audit_log WHERE action = 'tz_edge_review'")"
check "O-49: user without a start date is exempt" "exempt" "$(q "SELECT w.source FROM users u, fn_tps_wait_start(u.user_id) w WHERE u.email = 'b1@beta'")"
check "spoons history kept with counts" "12|$(q "SELECT 0") " "$(q "SELECT count(*) FROM spoon_budget")|$(q "SELECT count(*) FROM spoon_budget WHERE reported_at IS NOT NULL") "
check "O-48: empty reported_at marked legacy (row_source = legacy_v1_4); new rows default to app" "12|app" \
  "$(q "SELECT (SELECT count(*) FROM spoon_budget WHERE row_source = 'legacy_v1_4' AND reported_at IS NULL), (SELECT column_default FROM information_schema.columns WHERE table_name = 'spoon_budget' AND column_name = 'row_source')" | sed "s/'::text//; s/'//")"
check "day_status derived from the v1.4 counts" "0" \
  "$(q "SELECT count(*) FROM spoon_budget WHERE day_status IS DISTINCT FROM CASE WHEN current_spoon_count <= 3 THEN 'GO_HOME' WHEN current_spoon_count <= 5 THEN 'FIGHTING_BLOCKED' ELSE 'OPEN' END::day_status_enum")"
check "golden spoons kept (7.0)" "7.0" "$(q "SELECT golden_spoons FROM avatar_state WHERE user_id = '10000000-0000-0000-0000-000000000003'")"
check "v1.4 companies: no country → held + needs_review" "2|2|2" \
  "$(q "SELECT count(*) FILTER (WHERE country IS NULL), count(*) FILTER (WHERE reminders_on_hold), count(*) FILTER (WHERE timezone_status = 'needs_review') FROM companies")"
check "audit 'reminders_on_hold' per held company" "2" "$(q "SELECT count(*) FROM access_audit_log WHERE action = 'reminders_on_hold'")"
check "legacy rows kept (team_aggregate, shop)" "1|8" "$(q "SELECT (SELECT count(*) FROM legacy_v1_4_team_aggregate), (SELECT count(*) FROM legacy_v1_4_shop_item_catalog)")"
check "legacy tables closed to clients" "f" "$(q "SELECT has_table_privilege('authenticated', 'legacy_v1_4_employee_value_asset', 'SELECT')")"
check "O-45: 7 legacy tables, each guarded read-only (row + truncate triggers), no write grant for any client role" "7|7|7|0" \
  "$(q "SELECT (SELECT count(*) FROM pg_class WHERE relname LIKE 'legacy\_v1\_4\_%' AND relkind = 'r'),
               (SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_legacy_read_only_row'),
               (SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_legacy_read_only_truncate'),
               (SELECT count(*) FROM pg_class c, unnest(ARRAY['anon','authenticated','service_role']) r, unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE']) p
                 WHERE c.relname LIKE 'legacy\_v1\_4\_%' AND c.relkind = 'r' AND has_table_privilege(r, c.oid, p))")"
for stmt in "INSERT INTO legacy_v1_4_team_aggregate (org_id, department, member_count) SELECT org_id, 'X', 5 FROM legacy_v1_4_team_aggregate" \
            "UPDATE legacy_v1_4_shop_item_catalog SET currency = currency" \
            "DELETE FROM legacy_v1_4_role_cost_config" \
            "TRUNCATE legacy_v1_4_employee_value_asset"; do
  out="$(PGOPTIONS="$PGOPTIONS $SP" psql -X -U "$ADMIN" -d "$DB" -qAt -c "$stmt" 2>&1 || true)"
  case "$out" in *legacy_read_only*) ok "O-45: write refused even for $ADMIN: ${stmt%% *} → legacy_read_only" ;; *) bad "O-45: write refused: $stmt ($out)" ;; esac
done
check "O-45: legacy rows still there and readable (1|8|4|1)" "1|8|4|1" \
  "$(q "SELECT (SELECT count(*) FROM legacy_v1_4_team_aggregate), (SELECT count(*) FROM legacy_v1_4_shop_item_catalog), (SELECT count(*) FROM legacy_v1_4_role_cost_config), (SELECT count(*) FROM legacy_v1_4_employee_value_asset)")"
if [ "$MODE" = super ]; then
# --- legacy DDL guard (event triggers, installed by the runner as superuser) --------
check "DDL guard: 2 event triggers (sql_drop, ddl_command_end ALTER TABLE), enabled, superuser-owned" \
  "trg_legacy_v1_4_alter_guard:ddl_command_end:O:t,trg_legacy_v1_4_drop_guard:sql_drop:O:t" \
  "$(q "SELECT string_agg(e.evtname || ':' || e.evtevent || ':' || e.evtenabled::text || ':' || CASE WHEN r.rolsuper THEN 't' ELSE 'f' END, ',' ORDER BY e.evtname) FROM pg_event_trigger e JOIN pg_roles r ON r.oid = e.evtowner")"
check "DDL guard: the 7 legacy tables are registered" "7" "$(q "SELECT cardinality(chr_guard.fn_legacy_names())")"
fails "DDL guard: DROP TABLE on a legacy table blocked (superuser)" "legacy_ddl_blocked" "DROP TABLE legacy_v1_4_role_cost_config"
fails "DDL guard: DROP TABLE … CASCADE blocked" "legacy_ddl_blocked" "DROP TABLE legacy_v1_4_team_aggregate CASCADE"
fails "DDL guard: DROP SCHEMA public CASCADE blocked (would drop legacy tables)" "legacy_ddl_blocked" "DROP SCHEMA public CASCADE"
fails "DDL guard: ALTER TABLE … ADD COLUMN blocked" "legacy_ddl_blocked" "ALTER TABLE legacy_v1_4_team_aggregate ADD COLUMN x int"
fails "DDL guard: ALTER TABLE … DROP COLUMN blocked" "legacy_ddl_blocked" "ALTER TABLE legacy_v1_4_shop_item_catalog DROP COLUMN currency"
fails "DDL guard: ALTER TABLE … RENAME blocked" "legacy_ddl_blocked" "ALTER TABLE legacy_v1_4_shop_item_catalog RENAME TO shop_old"
fails "DDL guard: ALTER TABLE … SET SCHEMA blocked" "legacy_ddl_blocked" "ALTER TABLE legacy_v1_4_cuckoo_alert SET SCHEMA auth"
check "DDL guard: legacy tables all still there, rows intact (7 tables; 1|8|4|1)" "7|1|8|4|1" \
  "$(q "SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname LIKE 'legacy\_v1\_4\_%' AND c.relkind = 'r'), (SELECT count(*) FROM legacy_v1_4_team_aggregate), (SELECT count(*) FROM legacy_v1_4_shop_item_catalog), (SELECT count(*) FROM legacy_v1_4_role_cost_config), (SELECT count(*) FROM legacy_v1_4_employee_value_asset)")"
runs "DDL guard: other tables unaffected (superuser: ALTER / CREATE / RENAME / DROP, rolled back)" \
  "BEGIN; ALTER TABLE project ADD COLUMN t_guard int; ALTER TABLE project DROP COLUMN t_guard; CREATE TABLE t_guard_tmp (i int); ALTER TABLE t_guard_tmp RENAME TO t_guard_tmp2; DROP TABLE t_guard_tmp2; ROLLBACK;"
runs "DDL guard: other tables unaffected (non-superuser role, rolled back)" \
  "BEGIN; CREATE ROLE chr_guard_probe; GRANT CREATE ON SCHEMA public TO chr_guard_probe; SET ROLE chr_guard_probe; CREATE TABLE t_probe (i int); ALTER TABLE t_probe ADD COLUMN j int; DROP TABLE t_probe; RESET ROLE; ROLLBACK;"
fails "DDL guard: a non-superuser cannot lift it" "must be" \
  "BEGIN; CREATE ROLE chr_guard_probe2; SET ROLE chr_guard_probe2; ALTER EVENT TRIGGER trg_legacy_v1_4_alter_guard DISABLE; ROLLBACK;"
runs "DDL guard: documented lift (superuser, one transaction) allows the change" \
  "BEGIN; ALTER EVENT TRIGGER trg_legacy_v1_4_drop_guard DISABLE; ALTER EVENT TRIGGER trg_legacy_v1_4_alter_guard DISABLE; ALTER TABLE legacy_v1_4_team_aggregate ADD COLUMN lift_probe int; ROLLBACK;"
check "DDL guard: …and is back after that transaction (both enabled, no column added)" "OO|0" \
  "$(q "SELECT (SELECT string_agg(evtenabled::text, '' ORDER BY evtname) FROM pg_event_trigger), (SELECT count(*) FROM pg_attribute WHERE attrelid = 'legacy_v1_4_team_aggregate'::regclass AND attname = 'lift_probe')")"
runner guard "$DB" > /dev/null 2>&1 && check "DDL guard: reinstall is idempotent (2 triggers, 7 tables)" "2|7" \
  "$(q "SELECT (SELECT count(*) FROM pg_event_trigger), cardinality(chr_guard.fn_legacy_names())")" || bad "DDL guard: reinstall exits 0"
else
# --- v1.6.13 O-53: no superuser → FALLBACK lockdown (REVOKE ALL + NOLOGIN owner), the run does not fail ----
grep -q "WARNING: legacy DDL guard REFUSED (no superuser)" "$W/apply.log" && grep -q "LEGACY DDL GUARD NOT INSTALLED" "$W/apply.log" \
  && ok "fallback: loud WARNING printed (runner + database)" || bad "fallback: WARNING printed"
grep -q "legacy protection: FALLBACK applied" "$W/apply.log" && ok "fallback: apply reports the fallback (not a failure)" || bad "fallback: apply reports the fallback"
check "fallback: no event trigger (refused without superuser)" "0" "$(q "SELECT count(*) FROM pg_event_trigger")"
check "fallback: owner of all 7 legacy tables = legacy_v1_4_owner, NOLOGIN, not superuser" "7|7|f|f" \
  "$(q "SELECT (SELECT count(*) FROM pg_class WHERE relname LIKE 'legacy\_v1\_4\_%' AND relkind = 'r'), (SELECT count(*) FROM pg_class WHERE relname LIKE 'legacy\_v1\_4\_%' AND relkind = 'r' AND relowner = 'legacy_v1_4_owner'::regrole), (SELECT rolcanlogin FROM pg_roles WHERE rolname = 'legacy_v1_4_owner'), (SELECT rolsuper FROM pg_roles WHERE rolname = 'legacy_v1_4_owner')")"
check "fallback: app owner $APP has no USAGE / SET on legacy_v1_4_owner; only the PG16 creator ADMIN entry remains (documented gap)" "f|f|1|0" \
  "$(q "SELECT pg_has_role('$APP', 'legacy_v1_4_owner', 'USAGE'), pg_has_role('$APP', 'legacy_v1_4_owner', 'SET'),
               (SELECT count(*) FROM pg_auth_members WHERE roleid = 'legacy_v1_4_owner'::regrole AND admin_option AND NOT inherit_option AND NOT set_option),
               (SELECT count(*) FROM pg_auth_members WHERE roleid = 'legacy_v1_4_owner'::regrole AND (inherit_option OR set_option))")"
check "fallback: 7 legacy tables + the legacy enum type in schema legacy_v1_4 (owner legacy_v1_4_owner, no USAGE for $APP / PUBLIC)" "7|1|legacy_v1_4_owner|f|f" \
  "$(q "SELECT (SELECT count(*) FROM pg_class WHERE relnamespace = 'legacy_v1_4'::regnamespace AND relkind = 'r'),
               (SELECT count(*) FROM pg_type WHERE typnamespace = 'legacy_v1_4'::regnamespace AND typtype = 'e' AND typowner = 'legacy_v1_4_owner'::regrole),
               (SELECT nspowner::regrole::text FROM pg_namespace WHERE nspname = 'legacy_v1_4'),
               has_schema_privilege('$APP', 'legacy_v1_4', 'USAGE'), has_schema_privilege('public', 'legacy_v1_4', 'USAGE')")"
check "fallback: no privilege at all for PUBLIC, anon, authenticated, service_role, $APP (7 tables × 7 privileges)" "0" \
  "$(q "SELECT count(*) FROM pg_class c, unnest(ARRAY['public','anon','authenticated','service_role','$APP']) r,
               unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
         WHERE c.relname LIKE 'legacy\_v1\_4\_%' AND c.relkind = 'r' AND has_table_privilege(r, c.oid, p)")"
check "fallback: ACLs hold no grant for any role other than the owner" "0" \
  "$(q "SELECT count(*) FROM pg_class c, aclexplode(c.relacl) a WHERE c.relname LIKE 'legacy\_v1\_4\_%' AND c.relkind = 'r' AND a.grantee <> c.relowner")"
fails_app "fallback: app owner INSERT denied" "permission denied" "INSERT INTO legacy_v1_4.legacy_v1_4_team_aggregate (org_id, department, member_count) VALUES (gen_random_uuid(), 'X', 5)"
fails_app "fallback: app owner UPDATE denied" "permission denied" "UPDATE legacy_v1_4.legacy_v1_4_shop_item_catalog SET currency = currency"
fails_app "fallback: app owner DELETE denied" "permission denied" "DELETE FROM legacy_v1_4.legacy_v1_4_role_cost_config"
fails_app "fallback: app owner TRUNCATE denied" "permission denied" "TRUNCATE legacy_v1_4.legacy_v1_4_employee_value_asset"
fails_app "fallback: app owner SELECT denied" "permission denied" "SELECT count(*) FROM legacy_v1_4.legacy_v1_4_manager_ledger"
fails_app "fallback: app owner ALTER TABLE … ADD COLUMN denied" "permission denied" "ALTER TABLE legacy_v1_4.legacy_v1_4_team_aggregate ADD COLUMN x int"
fails_app "fallback: app owner ALTER TABLE … RENAME denied" "permission denied" "ALTER TABLE legacy_v1_4.legacy_v1_4_shop_item_catalog RENAME TO shop_old"
fails_app "fallback: app owner ALTER TABLE … OWNER denied" "permission denied" "ALTER TABLE legacy_v1_4.legacy_v1_4_cuckoo_alert OWNER TO $APP"
fails_app "fallback: app owner DROP TABLE denied" "permission denied" "DROP TABLE legacy_v1_4.legacy_v1_4_role_cost_config"
fails_app "fallback: app owner DROP SCHEMA legacy_v1_4 CASCADE denied" "must be owner" "DROP SCHEMA legacy_v1_4 CASCADE"
fails_app "fallback: app owner DROP TYPE (legacy enum) … CASCADE denied" "permission denied" "DROP TYPE legacy_v1_4.legacy_v1_4_shop_tier_enum CASCADE"
runs "fallback: app owner DROP SCHEMA public CASCADE leaves the legacy tables (probe rolled back)" \
  "BEGIN; SET LOCAL ROLE $APP; DROP SCHEMA public CASCADE; RESET ROLE; DO \$\$ BEGIN IF (SELECT count(*) FROM pg_class WHERE relnamespace = 'legacy_v1_4'::regnamespace AND relkind = 'r') <> 7 THEN RAISE EXCEPTION 'legacy tables lost'; END IF; END \$\$; ROLLBACK;"
fails_app "fallback: app owner cannot log in as / SET ROLE to the owner" "permission denied" "SET ROLE legacy_v1_4_owner"
app_sql "$DB" "GRANT SELECT ON legacy_v1_4_team_aggregate TO anon" > /dev/null || true
check "fallback: app owner cannot GRANT on legacy tables (attempt grants nothing)" "f" "$(q "SELECT has_table_privilege('anon', 'legacy_v1_4_team_aggregate', 'SELECT')")"
check "fallback: audit row legacy_guard_fallback (owner, 7 tables, 7 moved, installed by $APP)" "1|legacy_v1_4_owner|7|7|$APP" \
  "$(q "SELECT count(*), max(scope->>'owner'), max(scope->>'tables'), max(scope->>'moved'), max(scope->>'installed_by') FROM access_audit_log WHERE action = 'legacy_guard_fallback'")"
runner guard "$DB" > "$W/guard2.log" 2>&1 && ok "fallback: guard step re-run exits 0" || { bad "fallback: guard step re-run exits 0"; cat "$W/guard2.log"; }
check "fallback: re-run is idempotent (still 1 audit row, 7 tables owned, no SET/INHERIT member)" "1|7|0" \
  "$(q "SELECT (SELECT count(*) FROM access_audit_log WHERE action = 'legacy_guard_fallback'), (SELECT count(*) FROM pg_class WHERE relname LIKE 'legacy\_v1\_4\_%' AND relkind = 'r' AND relowner = 'legacy_v1_4_owner'::regrole), (SELECT count(*) FROM pg_auth_members WHERE roleid = 'legacy_v1_4_owner'::regrole AND (inherit_option OR set_option))")"
check "fallback: legacy rows intact (1|8|4|1)" "1|8|4|1" \
  "$(q "SELECT (SELECT count(*) FROM legacy_v1_4_team_aggregate), (SELECT count(*) FROM legacy_v1_4_shop_item_catalog), (SELECT count(*) FROM legacy_v1_4_role_cost_config), (SELECT count(*) FROM legacy_v1_4_employee_value_asset)")"
fi
check "new 1.6.7 tables empty (projects: none in v1.4); ledger has 1 genesis row per company (2 companies, O-13)" "0|0|2" "$(q "SELECT (SELECT count(*) FROM project), (SELECT count(*) FROM team_aggregate), (SELECT count(*) FROM manager_ledger WHERE event_type = 'GENESIS')")"
psql -X -U "$ADMIN" -d "$DB" -qAt -f tests/catalog_snapshot.sql > "$W/mig.cat"
check "catalog = fresh v1.6.18 except the 4 company NOT NULLs held back by NULL countries" \
  "$(printf '%s\n' companies.country companies.last_workday_dow companies.timezone companies.week_start_dow)" \
  "$(diff "$W/fresh.cat" "$W/mig.cat" | sed -n 's/^> col public\.\([a-z_.]*\) .* nn=false .*/\1/p' | sort)"
check "no other catalog difference" "8" "$(diff "$W/fresh.cat" "$W/mig.cat" | grep -c '^[<>]')"

# --- second run: idempotent --------------------------------------------------
snap "$W/m1"
psql -X -U "$APP" -d "$DB" -v ON_ERROR_STOP=1 -f migrations/migrate_v1_4_to_v1_6_18.sql > "$W/second.log" 2>&1 && ok "second run exits 0" || bad "second run exits 0"
snap "$W/m2"
cmp -s "$W/m1.cat" "$W/m2.cat" && ok "second run: catalog unchanged" || bad "second run: catalog unchanged"
cmp -s "$W/m1.dat" "$W/m2.dat" && ok "second run: data unchanged" || { bad "second run: data unchanged"; diff "$W/m1.dat" "$W/m2.dat" || true; }
check "second run: every count 0" "0" "$(sed -n 's/^ [a-z_.0-9]* *| *\([0-9-]*\)$/\1/p' "$W/second.log" | grep -vc '^0$' || true)"

# --- release the held companies, then the NOT NULLs lock on the next run ---------
out="$(psql -X -U "$ADMIN" -d "$DB" -qAt -c "UPDATE companies SET country = 'zz' WHERE company_name = 'Alpha Ltd'" 2>&1 || true)"
case "$out" in *unknown_country*) ok "unknown country (ZZ) → unknown_country" ;; *) bad "unknown country (ZZ) → unknown_country ($out)" ;; esac
check "…and the hold stays" "2" "$(q "SELECT count(*) FROM companies WHERE reminders_on_hold AND country IS NULL")"
q "UPDATE companies SET country = 'il' WHERE company_name = 'Alpha Ltd'" > /dev/null
q "UPDATE companies SET country = 'de' WHERE company_name = 'Beta GmbH'" > /dev/null
check "country set → reminders released + audited" "0|2" \
  "$(q "SELECT (SELECT count(*) FROM companies WHERE reminders_on_hold), (SELECT count(*) FROM access_audit_log WHERE action = 'reminders_released')")"
check "IL confirmed, DE confirmed (Busingen excluded, ruling 21.10)" "confirmed|confirmed" \
  "$(q "SELECT string_agg(timezone_status, '|' ORDER BY country DESC) FROM companies")"
psql -X -U "$APP" -d "$DB" -v ON_ERROR_STOP=1 -f migrations/migrate_v1_4_to_v1_6_18.sql > /dev/null 2>&1 && ok "third run exits 0" || bad "third run exits 0"
psql -X -U "$ADMIN" -d "$DB" -qAt -f tests/catalog_snapshot.sql > "$W/m3.cat"
cmp -s "$W/fresh.cat" "$W/m3.cat" && ok "after release: catalog = fresh v1.6.18 exactly" || bad "after release: catalog = fresh v1.6.18 exactly"

# --- rollback ------------------------------------------------------------------
runner rollback "$DB" > "$W/rb.log" 2>&1 && ok "rollback exits 0" || { bad "rollback exits 0"; cat "$W/rb.log"; }
snap "$W/rb"
cmp -s "$W/v14.cat" "$W/rb.cat" && ok "rollback: v1.4 catalog restored" || bad "rollback: v1.4 catalog restored"
cmp -s "$W/v14.dat" "$W/rb.dat" && ok "rollback: v1.4 data restored" || bad "rollback: v1.4 data restored"
check "rollback: database setting kept (timezone UTC), legacy tables gone, no event trigger" "UTC|0|0" \
  "$(q "SELECT current_setting('TimeZone'), (SELECT count(*) FROM pg_class WHERE relname LIKE 'legacy\_v1\_4\_%'), (SELECT count(*) FROM pg_event_trigger)")"

rm -rf "$W" "$BACKUP_DIR"
echo "MIGRATION TESTS ($MODE): $PASSES passed, $FAILS failed"
[ "$FAILS" -eq 0 ]
