#!/usr/bin/env bash
# CHR-ETRS v1.7.0 · tests/test_upgrade_v1_7_0.sh — upgrade check v1.6.21 (commit 4f04c0e) → v1.7.0 (Karin 16.11)
# Old pack from git (4f04c0e) + a little data → migrate_v1_6_21_to_v1_7_0.sql: dry run changes nothing → apply →
# catalog = fresh v1.7.0 → second apply changes nothing → existing rows kept (Cantril re-keyed to 2, catalog rows
# 'platform'). Runs as the connection's PGUSER (superuser in run_tests.sh).
set -euo pipefail
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
cd "$(dirname "$0")/.."
OLD=$(mktemp -d); W=$(mktemp -d)
DB=${UP_TEST_DB:-chr_up170_test}; FRESH=${UP_FRESH_DB:-chr_up170_fresh}
PASSES=0; FAILS=0
ok()  { echo "PASS UP $1"; PASSES=$((PASSES + 1)); }
bad() { echo "FAIL UP $1"; FAILS=$((FAILS + 1)); }
check() { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
q() { psql -X -d "$DB" -qAt -v ON_ERROR_STOP=1 -c "$1"; }
snap() { psql -X -d "$DB" -qAt -f tests/catalog_snapshot.sql > "$1"; }

git -C "$(git rev-parse --show-toplevel)" archive 4f04c0e db | tar -x -C "$OLD"
for d in "$DB" "$FRESH"; do psql -X -qc "DROP DATABASE IF EXISTS \"$d\" WITH (FORCE)" postgres; psql -X -qc "CREATE DATABASE \"$d\"" postgres; done
psql -X -d "$FRESH" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f modules/all.sql > /dev/null
psql -X -d "$FRESH" -qAt -f tests/catalog_snapshot.sql > "$W/fresh.cat"
( cd "$OLD/db" && psql -X -d "$DB" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql > /dev/null )
q "INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
   VALUES ('00000000-0000-0000-0000-00000000a170', 'Upgrade Co', 'IL', 0, 4, 'Asia/Jerusalem')" > /dev/null
q "INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-00000000b170')" > /dev/null
q "INSERT INTO users (user_id, company_id, email, full_name, app_role, timezone)
   VALUES ('00000000-0000-0000-0000-00000000b170', '00000000-0000-0000-0000-00000000a170', 'up@j.test', 'Up', 'employee', 'Asia/Jerusalem')" > /dev/null
check "fixture is v1.6.21 (Cantril on golden_spoons_per_questionnaire, no golden_spoons_per_cantril)" "golden_spoons_per_questionnaire|0" \
  "$(q "SELECT (SELECT reward_setting_key FROM questionnaire_definition WHERE code = 'Cantril') || '|' ||
              (SELECT count(*) FROM agent_settings WHERE setting_key = 'golden_spoons_per_cantril')")"
CATALOG_ITEMS=$(q "SELECT count(*) FROM shop_item_catalog")
snap "$W/before.cat"
psql -X -d "$DB" -v ON_ERROR_STOP=1 -v dry_run=1 -q -f migrations/migrate_v1_6_21_to_v1_7_0.sql > /dev/null
snap "$W/dry.cat"
cmp -s "$W/before.cat" "$W/dry.cat" && ok "dry run changes nothing (catalog identical)" || bad "dry run changes nothing"
psql -X -d "$DB" -v ON_ERROR_STOP=1 -q -f migrations/migrate_v1_6_21_to_v1_7_0.sql > /dev/null
snap "$W/up.cat"
n=$(diff "$W/fresh.cat" "$W/up.cat" | grep -c '^[<>]' || true)
check "after the upgrade: catalog = fresh v1.7.0" "0" "$n"
[ "$n" = 0 ] || diff "$W/fresh.cat" "$W/up.cat" | head -20
psql -X -d "$DB" -v ON_ERROR_STOP=1 -q -f migrations/migrate_v1_6_21_to_v1_7_0.sql > /dev/null
snap "$W/up2.cat"
cmp -s "$W/up.cat" "$W/up2.cat" && ok "second apply changes nothing" || bad "second apply changes nothing"
check "Cantril re-keyed: golden_spoons_per_cantril = 2, monthly" "golden_spoons_per_cantril|2|monthly" \
  "$(q "SELECT d.reward_setting_key || '|' || fn_agent_setting_num(NULL, 'golden_spoons_per_cantril') || '|' || d.frequency
          FROM questionnaire_definition d WHERE d.code = 'Cantril'")"
check "existing rows kept (company, user, catalog count) and catalog rows default to 'platform' (J-232)" "1|1|$CATALOG_ITEMS|$CATALOG_ITEMS" \
  "$(q "SELECT (SELECT count(*) FROM companies) || '|' || (SELECT count(*) FROM users) || '|' || (SELECT count(*) FROM shop_item_catalog)
          || '|' || (SELECT count(*) FROM shop_item_catalog WHERE provider_kind = 'platform' AND company_id IS NULL)")"
check "app_role accepts researcher + external_auditor after the upgrade" "t" \
  "$(q "SELECT pg_get_constraintdef(oid) ~ 'external_auditor' AND pg_get_constraintdef(oid) ~ 'researcher' FROM pg_constraint WHERE conname = 'users_app_role_check'")"
for d in "$DB" "$FRESH"; do psql -X -qc "DROP DATABASE IF EXISTS \"$d\" WITH (FORCE)" postgres; done
rm -rf "$OLD" "$W"
echo "UPGRADE v1.6.21 → v1.7.0 TESTS: $PASSES passed, $FAILS failed"
[ "$FAILS" = 0 ]
