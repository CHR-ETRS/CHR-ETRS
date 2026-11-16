#!/usr/bin/env bash
# =============================================================================
# CHR-ETRS v1.7.0 · tests/test_j_terms.sh — terminology gate over the WHOLE repository (Karin 16.11)
#   * "מדווחים בפועל" (never "משיבים"), "מס קיפוח" (never "מס החסך"), "כפיות" (never the word "כפות" on its own),
#     "צבאן" (never "צבן");
#   * golden spoons rule: an amount "N כפיות" without "מוזהבות" / "זהב" on the same line as an EverStore price,
#     balance or donation (incl. server messages in SQL) is refused (J-226 / J-227 interpretation: same line = near;
#     "כפיות זהב" and "כפיות מוזהבות" are both accepted).
# Scope: every git-tracked file, except DECISION_2026-10-20_week_start.md (Karin: do not touch), the gate itself and
# TESTING.md (which quotes the patterns).
# =============================================================================
set -u
export LC_ALL=C.UTF-8
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT" || exit 2
FAIL=0
PASSN=0

# List the tracked text files in scope (NUL-separated).
files() {
  git ls-files -z -- . ':(exclude,glob)**/DECISION_2026-10-20_week_start.md' ':(exclude)db/tests/test_j_terms.sh' \
                       ':(exclude)db/TESTING.md'
}

# One gate: name, grep -P pattern, optional second filter (lines must also match it).
gate() {
  local name="$1" pat="$2" ctx="${3:-}" hits
  if [ -n "$ctx" ]; then
    hits=$(files | xargs -0 grep -InP -- "$pat" 2>/dev/null | grep -iP -- "$ctx")
  else
    hits=$(files | xargs -0 grep -InP -- "$pat" 2>/dev/null)
  fi
  if [ -z "$hits" ]; then
    echo "PASS terms: $name (0 hits)"; PASSN=$((PASSN + 1))
  else
    echo "FAIL terms: $name"; echo "$hits" | cut -c1-200 | head -20; FAIL=$((FAIL + 1))
  fi
}

gate 'never "משיבים" (always "מדווחים בפועל")' 'משיבים'
gate 'never "מס החסך" (always "מס קיפוח")' 'מס החסך'
gate 'never the word "כפות" on its own (always "כפיות")' '(?<![\p{Hebrew}])כפות(?![\p{Hebrew}])'
gate 'never "צבן" (always "צבאן")' 'צבן'
gate 'golden spoons: "N כפיות" next to an EverStore price / balance / donation always says מוזהבות / זהב' \
     '[0-9]+(\.[0-9]+)?\s*כפיות(?!\s*(מוזהבות|זהב))' \
     '(everstore|מחיר|יתר|תרומ|donat|price|balance|liabilit|ledger|עמות|nonprofit)'
gate 'golden spoons: server messages (SQL string literals) with "N כפיות" say מוזהבות / זהב' \
     "'[^']*[0-9]+(\.[0-9]+)?\s*כפיות(?!\s*(מוזהבות|זהב))[^']*'" \
     '(everstore|מחיר|יתר|תרומ|donat|price|balance|עמות)'

# The decision file is untouched by this branch (it is not in the repo today; the check guards any future copy).
if git diff --quiet 4f04c0e -- ':(glob)**/DECISION_2026-10-20_week_start.md' 2>/dev/null; then
  echo "PASS terms: DECISION_2026-10-20_week_start.md untouched"; PASSN=$((PASSN + 1))
else
  echo "FAIL terms: DECISION_2026-10-20_week_start.md was changed"; FAIL=$((FAIL + 1))
fi

echo "TERMS GATE: $PASSN passed, $FAIL failed"
[ "$FAIL" = 0 ]
