#!/usr/bin/env bash
# CHR-ETRS MVP v1.7.0 · tests/run_tests.sh — fresh DB → CLDR/tz reference → schema → rpc → modules → tests (PostgreSQL 17)
# Version: 1.7.0-mvp (supersedes 1.6.21-mvp); runs tests/test_v1_5.sql, tests/test_agents_v1_6_16.sql (agents, v3;
# content v1.7.0), tests/test_board_v1_6_19.sql (filename kept; content v1.7.0) (board report, leaver batching, ILS estimate, levels),
# tests/test_assign_authz.sql (J-143 security fix: rpc_assign_task self / direct manager only; J-146 A neutral refusal),
# tests/test_sensitive_authz.sql (J-147 – J-150: rpc_daily_reset_spoons / rpc_upsert_employee_value_asset / rpc_ledger_append),
# v1.7.0 (Karin 16.11, J-178 – J-219): tests/test_j_spoons.sql, test_j_research.sql, test_j_roles.sql, test_j_kiosk.sql,
# test_j_everstore.sql, test_j_leaver.sql, test_j_whats_changed.sql (each on a fresh DB, shared tests/j_helpers.sql) and the
# whole-repo terminology gate tests/test_j_terms.sh, the v1.6.21 → v1.7.0 upgrade check tests/test_upgrade_v1_7_0.sh, and the v1.4 → v1.7.0 migration tests (tests/test_migration.sh)
# twice: as superuser (event-trigger guard + timezone preflight) and as a non-superuser owner (O-53 fallback). Real clock (no
# libfaketime). Usage: PGHOST=/tmp PGPORT=54317 PGUSER=postgres ./tests/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${TEST_DB:-chr_v16_test}
psql -qc "DROP DATABASE IF EXISTS $DB" postgres
psql -qc "CREATE DATABASE $DB" postgres
psql -d "$DB" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f modules/all.sql
# idempotency: reference + schema + rpc must re-apply cleanly
psql -d "$DB" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f modules/all.sql
psql -d "$DB" -v ON_ERROR_STOP=1 -qAt -f tests/test_v1_5.sql
# v1.6.16 agents (v3): fresh DB so the agents fixtures do not mix with test_v1_5 rows
psql -qc "DROP DATABASE IF EXISTS ${DB}_agents" postgres
psql -qc "CREATE DATABASE ${DB}_agents" postgres
psql -d "${DB}_agents" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f modules/all.sql
psql -d "${DB}_agents" -v ON_ERROR_STOP=1 -qAt -f tests/test_agents_v1_6_16.sql
# v1.6.19 board report / leaver batching / ILS estimate / verification levels: fresh DB (batches use the real clock)
psql -qc "DROP DATABASE IF EXISTS ${DB}_board" postgres
psql -qc "CREATE DATABASE ${DB}_board" postgres
psql -d "${DB}_board" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f modules/all.sql
psql -d "${DB}_board" -v ON_ERROR_STOP=1 -qAt -f tests/test_board_v1_6_19.sql
# J-143 security fix: rpc_assign_task authorization (self or direct manager only) on a fresh DB
psql -qc "DROP DATABASE IF EXISTS ${DB}_authz" postgres
psql -qc "CREATE DATABASE ${DB}_authz" postgres
psql -d "${DB}_authz" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f modules/all.sql
psql -d "${DB}_authz" -v ON_ERROR_STOP=1 -qAt -f tests/test_assign_authz.sql
# Sensitive-RPC authorization (Karin 04.11, J-147 – J-150): reset spoons / value asset / ledger on a fresh DB
psql -qc "DROP DATABASE IF EXISTS ${DB}_sens" postgres
psql -qc "CREATE DATABASE ${DB}_sens" postgres
psql -d "${DB}_sens" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f modules/all.sql
psql -d "${DB}_sens" -v ON_ERROR_STOP=1 -qAt -f tests/test_sensitive_authz.sql
# v1.7.0 (Karin 16.11, J-178 – J-219): one fresh DB per suite
for SUITE in spoons research roles kiosk everstore leaver whats_changed; do
  psql -qc "DROP DATABASE IF EXISTS ${DB}_j_${SUITE}" postgres
  psql -qc "CREATE DATABASE ${DB}_j_${SUITE}" postgres
  psql -d "${DB}_j_${SUITE}" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f modules/all.sql
  psql -d "${DB}_j_${SUITE}" -v ON_ERROR_STOP=1 -qAt -f "tests/test_j_${SUITE}.sql"
done
# v1.7.0: db/config starts EMPTY and the loader is a no-op on it (every function returns 0 rows)
python3 - <<'PY2'
import json, pathlib, sys
bad = [p.name for p in sorted(pathlib.Path('config').glob('*.json'))
       if any(v for v in json.loads(p.read_text(encoding='utf-8')).values())]
print('PASS config files start empty' if not bad else 'FAIL config not empty: ' + ', '.join(bad))
sys.exit(1 if bad else 0)
PY2
SYNC_OUT=$(python3 tools/sync_config.py --db "${DB}_j_spoons")
if [ "$(echo "$SYNC_OUT" | cut -d'|' -f2 | sort -u)" = "0" ]; then echo "PASS tools/sync_config.py loads the empty config (4 × 0 rows)"; else echo "FAIL sync_config: $SYNC_OUT"; exit 1; fi
# v1.7.0 terminology gate over the whole repository
./tests/test_j_terms.sh
# v1.4 → v1.7.0 migration: dry run, apply, counts, catalog = fresh, idempotence, rollback — in both modes
MIG_MODE=super ./tests/test_migration.sh
MIG_MODE=nosuper ./tests/test_migration.sh
# v1.7.0: upgrade of an existing v1.6.21 database (4f04c0e) with migrations/migrate_v1_6_21_to_v1_7_0.sql
./tests/test_upgrade_v1_7_0.sh
# A-10 (Karin 31.10): every "r = 0.37" in openapi.yaml / README.md / ADR_GAPS.md must sit inside the full binding text
# (taken from the pack itself: fn_board_binding_text_he), so the correlation is never shown alone.
BIND_FILE=$(mktemp)
psql -d "${DB}_board" -qAt -c "SELECT fn_board_binding_text_he()" > "$BIND_FILE"
python3 - "$BIND_FILE" openapi.yaml README.md ADR_GAPS.md <<'PY'
import re, sys
full = open(sys.argv[1], encoding='utf-8').read().rstrip('\n')
bad = 0
for f in sys.argv[2:]:
    text = open(f, encoding='utf-8').read()
    n_r = len(re.findall(r'r\s*=\s*0\.37', text))
    n_full = text.count(full)
    ok = n_r == n_full
    print(('PASS' if ok else 'FAIL') + f' A-10 {f}: "r = 0.37" x{n_r}, full binding text x{n_full}')
    bad += 0 if ok else 1
sys.exit(1 if bad else 0)
PY
rm -f "$BIND_FILE"
# The rejected fixed salary literal must not appear anywhere in the pack (pattern avoids writing it here)
if grep -rnE '10{1}50{3}' --include='*.sql' --include='*.yaml' --include='*.md' --include='*.sh' --include='*.py' . ; then
  echo "FAIL rejected salary literal found"; exit 1
fi
echo "PASS no rejected salary literal in pack"
