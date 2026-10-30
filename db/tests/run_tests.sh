#!/usr/bin/env bash
# CHR-ETRS MVP v1.6.16 · tests/run_tests.sh — fresh DB → CLDR/tz reference → schema → rpc → tests (PostgreSQL 17)
# Version: 1.6.16-mvp (supersedes 1.6.13-mvp); runs tests/test_v1_5.sql, tests/test_agents_v1_6_16.sql (agents, v3)
# and the v1.4 → v1.6.16 migration tests (tests/test_migration.sh)
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
# v1.4 → v1.6.16 migration: dry run, apply, counts, catalog = fresh, idempotence, rollback — in both modes
MIG_MODE=super ./tests/test_migration.sh
MIG_MODE=nosuper ./tests/test_migration.sh
# The rejected fixed salary literal must not appear anywhere in the pack (pattern avoids writing it here)
if grep -rnE '10{1}50{3}' --include='*.sql' --include='*.yaml' --include='*.md' --include='*.sh' --include='*.py' . ; then
  echo "FAIL rejected salary literal found"; exit 1
fi
echo "PASS no rejected salary literal in pack"
