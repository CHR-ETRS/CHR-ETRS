#!/usr/bin/env bash
# CHR-ETRS MVP v1.6.21 · tests/run_tests.sh — fresh DB → CLDR/tz reference → schema → rpc → tests (PostgreSQL 17)
# Version: 1.6.21-mvp (supersedes 1.6.20-mvp, 1.6.19-mvp); runs tests/test_v1_5.sql, tests/test_agents_v1_6_16.sql (agents, v3;
# content v1.6.21), tests/test_board_v1_6_19.sql (filename kept; content v1.6.21) (v1.6.19 board report, leaver batching, ILS estimate, levels) and
# the v1.4 → v1.6.21 migration tests (tests/test_migration.sh)
# twice: as superuser (event-trigger guard + timezone preflight) and as a non-superuser owner (O-53 fallback). Usage: PGHOST=/tmp PGPORT=54317 PGUSER=postgres ./tests/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${TEST_DB:-chr_v16_test}
psql -qc "DROP DATABASE IF EXISTS $DB" postgres
psql -qc "CREATE DATABASE $DB" postgres
psql -d "$DB" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql
# idempotency: reference + schema + rpc must re-apply cleanly
psql -d "$DB" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql
psql -d "$DB" -v ON_ERROR_STOP=1 -qAt -f tests/test_v1_5.sql
# v1.6.16 agents (v3): fresh DB so the agents fixtures do not mix with test_v1_5 rows
psql -qc "DROP DATABASE IF EXISTS ${DB}_agents" postgres
psql -qc "CREATE DATABASE ${DB}_agents" postgres
psql -d "${DB}_agents" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql
psql -d "${DB}_agents" -v ON_ERROR_STOP=1 -qAt -f tests/test_agents_v1_6_16.sql
# v1.6.19 board report / leaver batching / ILS estimate / verification levels: fresh DB (batches use the real clock)
psql -qc "DROP DATABASE IF EXISTS ${DB}_board" postgres
psql -qc "CREATE DATABASE ${DB}_board" postgres
psql -d "${DB}_board" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql
psql -d "${DB}_board" -v ON_ERROR_STOP=1 -qAt -f tests/test_board_v1_6_19.sql
# v1.4 → v1.6.21 migration: dry run, apply, counts, catalog = fresh, idempotence, rollback — in both modes
MIG_MODE=super ./tests/test_migration.sh
MIG_MODE=nosuper ./tests/test_migration.sh
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
