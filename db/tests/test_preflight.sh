#!/usr/bin/env bash
# =============================================================================
# CHR-ETRS v1.7.0 · tests/test_preflight.sh — the go-live readiness check (J-191 / J-243 / J-244 / J-251 / J-252,
# Karin 16.11)
#   * on the repository config (method_team.json and platform_operator.json EMPTY on purpose) tools/preflight.py must
#     FAIL (non-zero);
#   * on a temporary copy with TEST-ONLY placeholder addresses (never real ones) + a test DB it passes only while every
#     active company has an active vp_hr with an e-mail (J-252);
#   * a malformed / empty method_team.json or an empty platform_operator.json must fail.
# The repository config is never changed. The test DB is "${TEST_DB:-chr_v16_test}_preflight".
# =============================================================================
set -u
cd "$(dirname "$0")/.." || exit 2
PASSN=0
FAILN=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Record one check: name, expected exit (0 / nonzero), actual exit code.
check() {
  local name="$1" want="$2" got="$3"
  if { [ "$want" = 0 ] && [ "$got" -eq 0 ]; } || { [ "$want" = nonzero ] && [ "$got" -ne 0 ]; }; then
    echo "PASS $name"; PASSN=$((PASSN + 1))
  else
    echo "FAIL $name (exit $got)"; FAILN=$((FAILN + 1))
  fi
}

OUT=$(python3 tools/preflight.py); RC=$?
check "J-191: preflight FAILS on the repository config (method_team.json empty)" nonzero $RC
echo "$OUT" | grep -q "PREFLIGHT FAIL method_team.json: no recipients"; check "J-191: the failure names method_team.json" 0 $?
echo "$OUT" | grep -q "PREFLIGHT MANUAL"; check "J-244: the manual go-live items are listed" 0 $?
python3 -c 'import json,sys; sys.exit(0 if json.load(open("config/method_team.json")) == {"recipients": []} else 1)'
check "J-191: the repository method_team.json is still empty" 0 $?

echo "$OUT" | grep -q "PREFLIGHT FAIL platform_operator.json: no recipients"; check "J-251: preflight fails while the operator address config is empty" 0 $?
python3 -c 'import json,sys; sys.exit(0 if json.load(open("config/platform_operator.json")) == {"recipients": []} else 1)'
check "J-251: the repository platform_operator.json is still empty" 0 $?

# test DB: one company with an active vp_hr (with an e-mail)
PDB="${TEST_DB:-chr_v16_test}_preflight"
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
psql -qc "DROP DATABASE IF EXISTS $PDB" postgres && psql -qc "CREATE DATABASE $PDB" postgres
psql -d "$PDB" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql -f modules/all.sql > /dev/null
psql -d "$PDB" -v ON_ERROR_STOP=1 -qAt -f tests/j_helpers.sql > /dev/null
psql -d "$PDB" -v ON_ERROR_STOP=1 -qAt -c "SELECT t_company('P'), t_mk('hrP', 'P', 'vp_hr', 'vp', 'Mgmt')" > /dev/null

cp config/*.json "$TMP/"
echo '{"recipients": ["test-only-placeholder@example.invalid"]}' > "$TMP/method_team.json"
echo '{"recipients": ["test-only-operator@example.invalid"]}' > "$TMP/platform_operator.json"
python3 tools/preflight.py --config-dir "$TMP" --db "$PDB" > /dev/null
check "J-252: preflight PASSES — config filled (test-only) and every active company has an active vp_hr with an e-mail" 0 $?
python3 tools/preflight.py --config-dir "$TMP" > /dev/null
check "J-252: without --db the company check counts as not run → fails" nonzero $?
psql -d "$PDB" -v ON_ERROR_STOP=1 -qAt -c "SELECT t_company('Q'), t_mk('cfoQ', 'Q', 'cfo', 'vp', 'Mgmt'), t_mk('hrQ', 'Q', 'vp_hr', 'vp', 'Mgmt')" > /dev/null
psql -d "$PDB" -v ON_ERROR_STOP=1 -qAt -c "UPDATE users SET email = '' WHERE user_id = t_u('hrQ')" > /dev/null
OUTQ=$(python3 tools/preflight.py --config-dir "$TMP" --db "$PDB"); RC=$?
check "J-252: preflight FAILS when an active company has no active vp_hr with an e-mail (vp_hr without e-mail, only a cfo)" nonzero $RC
echo "$OUTQ" | grep -q "1 active company without an active vp_hr with an e-mail (J-252): Company Q"
check "J-252: the failure names the company only (Company Q)" 0 $?
psql -d "$PDB" -v ON_ERROR_STOP=1 -qAt -c "UPDATE companies SET service_ended_at = now() WHERE company_id = t_u('Q')" > /dev/null
python3 tools/preflight.py --config-dir "$TMP" --db "$PDB" > /dev/null
check "J-252: a company whose service ended is not checked → passes again" 0 $?
echo '{"recipients": []}' > "$TMP/platform_operator.json"
python3 tools/preflight.py --config-dir "$TMP" --db "$PDB" > /dev/null; check "J-251: an empty operator config fails" nonzero $?
echo '{"recipients": ["test-only-operator@example.invalid"]}' > "$TMP/platform_operator.json"
echo '{"recipients": [""]}' > "$TMP/method_team.json"
python3 tools/preflight.py --config-dir "$TMP" --db "$PDB" > /dev/null; check "preflight fails on an empty address" nonzero $?
echo 'not json' > "$TMP/method_team.json"
python3 tools/preflight.py --config-dir "$TMP" --db "$PDB" > /dev/null; check "preflight fails on malformed JSON" nonzero $?

echo "PREFLIGHT TESTS: $PASSN passed, $FAILN failed"
[ "$FAILN" -eq 0 ]
