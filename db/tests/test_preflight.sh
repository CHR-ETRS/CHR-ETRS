#!/usr/bin/env bash
# =============================================================================
# CHR-ETRS v1.7.0 · tests/test_preflight.sh — the go-live readiness check (J-191 / J-243 / J-244, Karin 16.11)
#   * on the repository config (method_team.json EMPTY on purpose) tools/preflight.py must FAIL (non-zero);
#   * on a temporary copy with one TEST-ONLY placeholder address (never a real one) it must pass;
#   * a malformed method_team.json must fail.
# The repository config is never changed.
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

cp config/*.json "$TMP/"
echo '{"recipients": ["test-only-placeholder@example.invalid"]}' > "$TMP/method_team.json"
python3 tools/preflight.py --config-dir "$TMP" > /dev/null; check "preflight passes with one (test-only) recipient" 0 $?
echo '{"recipients": [""]}' > "$TMP/method_team.json"
python3 tools/preflight.py --config-dir "$TMP" > /dev/null; check "preflight fails on an empty address" nonzero $?
echo 'not json' > "$TMP/method_team.json"
python3 tools/preflight.py --config-dir "$TMP" > /dev/null; check "preflight fails on malformed JSON" nonzero $?

echo "PREFLIGHT TESTS: $PASSN passed, $FAILN failed"
[ "$FAILN" -eq 0 ]
