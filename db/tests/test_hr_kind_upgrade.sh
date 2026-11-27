#!/usr/bin/env bash
# CHR-ETRS MVP v1.6.21 · tests/test_hr_kind_upgrade.sh — J-278 B (Karin 23.11): upgrade of hr_absence_entry to the
# kind review state. Never a guessed kind: rows without a kind (c56d380 shape) and 'other' rows of the J-267 C
# shape (8eade64, where 'other' was back-filled) become kind NULL + 'needs_review'; 'sick' rows stay 'reviewed'.
# Runs on (1) SIMULATED old shapes — the current pack with the table turned back to the c56d380 / 8eade64 shape — and
# (2) when the git history is available, the REAL c56d380 / 8eade64 packs (git show). Also checks a re-apply changes
# nothing (a reviewed row is never reset), and (J-291 B) that the direct client read is gone. Prints PASS / FAIL lines; exits 1 on any FAIL.
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${TEST_DB:-chr_v16_test}_hrup
FAILS=0

# Print PASS / FAIL for one check (name, actual, expected).
check() {
  if [ "$2" = "$3" ]; then echo "PASS HRUP $1"; else echo "FAIL HRUP $1: got [$2] expected [$3]"; FAILS=$((FAILS + 1)); fi
}

# Create an empty database; $1 = optional owner role (a non-superuser owner for the nosuper checks).
fresh_db() {
  psql -qc "DROP DATABASE IF EXISTS $DB WITH (FORCE)" postgres
  psql -qc "CREATE DATABASE $DB${1:+ OWNER $1}" postgres
}

# Apply a pack (reference + schema + rpc) from a directory; APPLY_USER = optional role that applies it.
apply_pack() {
  (cd "$1" && psql ${APPLY_USER:+-U $APPLY_USER} -d "$DB" -v ON_ERROR_STOP=1 -q -f ref_country_calendar.sql -f schema.sql -f rpc.sql) >/dev/null 2>&1
}

# Insert one company, two employees and their HR rows; $1 = 'nokind' (c56d380) or 'kind' (8eade64).
add_rows() {
  psql -d "$DB" -v ON_ERROR_STOP=1 -qAt >/dev/null <<SQL
INSERT INTO companies (company_id, company_name, country, week_start_dow, last_workday_dow, timezone)
VALUES ('00000000-0000-0000-0000-00000000aa01', 'UpCo', 'IL', 0, 4, 'Asia/Jerusalem');
INSERT INTO auth.users (id) VALUES ('00000000-0000-0000-0000-00000000ab01'), ('00000000-0000-0000-0000-00000000ab02');
INSERT INTO users (user_id, company_id, email, full_name, department, app_role, org_role_code, timezone, hire_date)
VALUES ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000aa01', 'a@up.test', 'Up A', 'T', 'employee', 'employee', 'Asia/Jerusalem', DATE '2025-01-01'),
       ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000aa01', 'b@up.test', 'Up B', 'T', 'employee', 'employee', 'Asia/Jerusalem', DATE '2025-01-01');
SQL
  if [ "$1" = nokind ]; then
    psql -d "$DB" -v ON_ERROR_STOP=1 -qAt >/dev/null -c "INSERT INTO hr_absence_entry (user_id, company_id, absence_date)
      VALUES ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000aa01', CURRENT_DATE),
             ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000aa01', CURRENT_DATE + 1)"
  else
    psql -d "$DB" -v ON_ERROR_STOP=1 -qAt >/dev/null -c "INSERT INTO hr_absence_entry (user_id, company_id, absence_date, absence_kind)
      VALUES ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000aa01', CURRENT_DATE, 'sick'),
             ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000aa01', CURRENT_DATE + 1, 'other')"
  fi
}

# Read the rows as "date offset:kind:review" lines (no ids).
rows() {
  psql -d "$DB" -qAt -c "SELECT string_agg((absence_date - CURRENT_DATE) || ':' || COALESCE(absence_kind, '-') || ':' || kind_review_status, ' ' ORDER BY absence_date) FROM hr_absence_entry"
}

# J-300 B / J-301 B: the import objects exist after an upgrade — employee_number + its per-company unique index,
# the two staging tables with RLS forced, no policy and no client grant. $1 = label.
import_objects() {
  check "$1: J-300 B / J-301 B import objects (employee_number unique per company case-insensitively, staging closed to clients)" "$(psql -d "$DB" -qAt -c "SELECT (SELECT count(*) FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'employee_number')::text || '/' || (SELECT indisunique FROM pg_index WHERE indexrelid = 'uq_users_company_employee_number_ci'::regclass)::text || '/' || (SELECT count(*) FROM pg_class WHERE relname IN ('hr_absence_import_batch', 'hr_absence_import_row') AND relrowsecurity AND relforcerowsecurity)::text || '/' || (SELECT count(*) FROM pg_policy WHERE polrelid IN ('hr_absence_import_batch'::regclass, 'hr_absence_import_row'::regclass))::text || '/' || has_table_privilege('authenticated', 'hr_absence_import_row', 'SELECT')::text")" "1/true/2/0/false"
  check "$1: J-354 no extension (no dblink, no chr_internal schema, no fn_audit_view_committed, no fn_hr_import_refuse client grant)" "$(psql -d "$DB" -qAt -c "SELECT (to_regproc('fn_audit_view_committed') IS NULL)::text || '/' || (SELECT count(*) FROM pg_extension WHERE extname = 'dblink')::text || '/' || (SELECT count(*) FROM pg_namespace WHERE nspname = 'chr_internal')::text || '/' || has_function_privilege('authenticated', 'fn_hr_import_refuse(uuid, int, text)', 'EXECUTE')::text")" "true/0/0/false"
  check "$1: Karin 25.11 import objects (old case-sensitive index gone, 'exception' outcome, fingerprint column, empty row limit)" "$(psql -d "$DB" -qAt -c "SELECT (to_regclass('uq_users_company_employee_number') IS NULL)::text || '/' || (SELECT count(*) FROM pg_constraint WHERE conrelid = 'hr_absence_import_row'::regclass AND pg_get_constraintdef(oid) LIKE '%exception%')::text || '/' || (SELECT count(*) FROM information_schema.columns WHERE table_name = 'hr_absence_import_batch' AND column_name = 'validated_fingerprint')::text || '/' || (SELECT value_status FROM agent_settings WHERE company_id IS NULL AND setting_key = 'hr_import_max_rows')")" "true/1/1/not_defined"
}

# Upgrade checks after the current pack was applied over an old shape; $1 = label, $2 = expected rows.
after_upgrade() {
  check "$1: rows after upgrade (never a guessed kind)" "$(rows)" "$2"
  check "$1: 3 kind / review constraints" "$(psql -d "$DB" -qAt -c "SELECT count(*) FROM pg_constraint WHERE conrelid = 'hr_absence_entry'::regclass AND conname IN ('chk_hr_absence_kind', 'chk_hr_absence_review_status', 'chk_hr_absence_kind_reviewed')")" "3"
  check "$1: absence_kind nullable, review state NOT NULL" "$(psql -d "$DB" -qAt -c "SELECT string_agg(column_name || '=' || is_nullable, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_name = 'hr_absence_entry' AND column_name IN ('absence_kind', 'kind_review_status')")" "absence_kind=YES,kind_review_status=NO"
  check "$1: needs_review rows are not sick days in the totals" "$(psql -d "$DB" -qAt -c "SELECT fn_hr_sick_days('00000000-0000-0000-0000-00000000aa01', 'T', date_trunc('month', CURRENT_DATE)::date) + fn_hr_sick_days('00000000-0000-0000-0000-00000000aa01', 'T', date_trunc('month', CURRENT_DATE + 1)::date) - CASE WHEN date_trunc('month', CURRENT_DATE) = date_trunc('month', CURRENT_DATE + 1) THEN fn_hr_sick_days('00000000-0000-0000-0000-00000000aa01', 'T', date_trunc('month', CURRENT_DATE)::date) ELSE 0 END")" "$3"
  check "$1: J-291 B no direct client read (SELECT revoked, own-rows policy gone)" "$(psql -d "$DB" -qAt -c "SELECT has_table_privilege('authenticated', 'hr_absence_entry', 'SELECT')::text || '/' || (SELECT count(*) FROM pg_policy WHERE polrelid = 'hr_absence_entry'::regclass)")" "false/0"
  import_objects "$1"
  # vp_hr's review (stand-in: the state the review RPC writes), then a re-apply must not reset it
  psql -d "$DB" -qAt >/dev/null -c "UPDATE hr_absence_entry SET absence_kind = 'other', kind_review_status = 'reviewed' WHERE absence_date = CURRENT_DATE + 1"
  apply_pack .
  check "$1: re-apply keeps the reviewed kind" "$(rows)" "$4"
}

# (1) simulated c56d380 shape (no kind columns)
fresh_db; apply_pack .
psql -d "$DB" -qAt >/dev/null -c "ALTER TABLE hr_absence_entry DROP COLUMN kind_review_status, DROP COLUMN absence_kind"
add_rows nokind; apply_pack .
after_upgrade "simulated c56d380" "0:-:needs_review 1:-:needs_review" "0" "0:-:needs_review 1:other:reviewed"
# (1) simulated 8eade64 shape (absence_kind NOT NULL, 'other' back-filled, no review state)
fresh_db; apply_pack .
psql -d "$DB" -qAt >/dev/null -c "ALTER TABLE hr_absence_entry DROP COLUMN kind_review_status; ALTER TABLE hr_absence_entry ALTER COLUMN absence_kind SET NOT NULL"
add_rows kind; apply_pack .
after_upgrade "simulated 8eade64" "0:sick:reviewed 1:-:needs_review" "1" "0:sick:reviewed 1:other:reviewed"
# (2) the real earlier packs, when the git history is available
for REV in c56d380 8eade64; do
  if git cat-file -e "$REV:db/schema.sql" 2>/dev/null; then
    OLD=$(mktemp -d)
    for f in ref_country_calendar.sql schema.sql rpc.sql; do git show "$REV:db/$f" > "$OLD/$f"; done
    fresh_db; apply_pack "$OLD"
    if [ "$REV" = c56d380 ]; then add_rows nokind; EXP="0:-:needs_review 1:-:needs_review"; SICK=0; EXP2="0:-:needs_review 1:other:reviewed";
    else add_rows kind; EXP="0:sick:reviewed 1:-:needs_review"; SICK=1; EXP2="0:sick:reviewed 1:other:reviewed"; fi
    apply_pack .
    after_upgrade "real $REV pack" "$EXP" "$SICK" "$EXP2"
    check "real $REV pack: old 3-column reader replaced by the 6-column reader" "$(psql -d "$DB" -qAt -c "SELECT pg_get_function_result('rpc_hr_absence_list(uuid, uuid)'::regprocedure) LIKE '%kind_review_status%'")" "t"
    rm -rf "$OLD"
  else
    echo "SKIP HRUP real $REV pack (git history not available)"
  fi
done
# (3) J-308 A: upgrade from the sixth-round commit 46a366f (no import objects yet) — the HR rows are untouched.
if git cat-file -e "46a366f:db/schema.sql" 2>/dev/null; then
  OLD=$(mktemp -d)
  for f in ref_country_calendar.sql schema.sql rpc.sql; do git show "46a366f:db/$f" > "$OLD/$f"; done
  fresh_db; apply_pack "$OLD"; add_rows kind
  BEFORE="$(rows)"
  apply_pack .
  check "real 46a366f pack: HR rows unchanged by the import upgrade" "$(rows)" "$BEFORE"
  import_objects "real 46a366f pack"
  rm -rf "$OLD"
else
  echo "SKIP HRUP real 46a366f pack (git history not available)"
fi
# (4) Karin 25.11: upgrade from the seventh-round commit 130bdca WITH a staged import (old outcome check, old
# case-sensitive number index) — the staged rows and the HR rows survive; the new objects are in place.
if git cat-file -e "130bdca:db/schema.sql" 2>/dev/null; then
  OLD=$(mktemp -d)
  for f in ref_country_calendar.sql schema.sql rpc.sql; do git show "130bdca:db/$f" > "$OLD/$f"; done
  fresh_db; apply_pack "$OLD"; add_rows kind
  psql -d "$DB" -v ON_ERROR_STOP=1 -qAt >/dev/null <<SQL
UPDATE users SET employee_number = 'N-1' WHERE user_id = '00000000-0000-0000-0000-00000000ab01';
INSERT INTO hr_absence_import_batch (batch_id, company_id) VALUES ('00000000-0000-0000-0000-00000000ac01', '00000000-0000-0000-0000-00000000aa01');
INSERT INTO hr_absence_import_row (batch_id, row_no, employee_number, absence_date_text, absence_kind_text, action_text, outcome, code)
VALUES ('00000000-0000-0000-0000-00000000ac01', 1, 'N-1', '2026-01-05', 'sick', 'put', 'rejected', 'invalid_kind');
SQL
  BEFORE="$(rows)"
  apply_pack .
  check "real 130bdca pack: HR rows unchanged" "$(rows)" "$BEFORE"
  check "real 130bdca pack: staged row and number kept" "$(psql -d "$DB" -qAt -c "SELECT (SELECT count(*) FROM hr_absence_import_row)::text || '/' || (SELECT employee_number FROM users WHERE user_id = '00000000-0000-0000-0000-00000000ab01')")" "1/N-1"
  import_objects "real 130bdca pack"
  rm -rf "$OLD"
else
  echo "SKIP HRUP real 130bdca pack (git history not available)"
fi
# (5) Karin 27.11 (J-354, no extension): upgrade from d1bdc6f, which created schema chr_internal, the dblink extension
# (superuser apply only) and fn_audit_view_committed — all dropped cleanly, the audit data is never touched. Both ways:
# applied by a SUPERUSER (the extension is dropped) and by a NON-superuser owner (the extension never existed; the empty
# schema is dropped). A refusal audit row written by that build stays.
if git cat-file -e "d1bdc6f:db/schema.sql" 2>/dev/null; then
  OLD=$(mktemp -d)
  for f in ref_country_calendar.sql schema.sql rpc.sql; do git show "d1bdc6f:db/$f" > "$OLD/$f"; done
  if [ "$(psql -qAt -c "SELECT count(*) FROM pg_roles WHERE rolname = 'chr_app_owner'" postgres)" = 0 ]; then
    psql -qc "CREATE ROLE chr_app_owner LOGIN CREATEDB CREATEROLE BYPASSRLS NOSUPERUSER" postgres
  else
    psql -qc "ALTER ROLE chr_app_owner LOGIN CREATEDB CREATEROLE BYPASSRLS NOSUPERUSER" postgres
  fi
  for mode in super nosuper; do
    if [ "$mode" = super ]; then OWNER=""; APPLY_USER=""; else OWNER=chr_app_owner; APPLY_USER=chr_app_owner; fi
    fresh_db "$OWNER"; export APPLY_USER; apply_pack "$OLD"; add_rows kind
    check "real d1bdc6f pack ($mode): the old build had the schema and the helper (dblink only when applied by a superuser)" "$(psql -d "$DB" -qAt -c "SELECT (to_regproc('fn_audit_view_committed') IS NOT NULL)::text || '/' || (SELECT count(*) FROM pg_namespace WHERE nspname = 'chr_internal')::text || '/' || (SELECT count(*) FROM pg_extension WHERE extname = 'dblink')::text")" "$([ "$mode" = super ] && echo true/1/1 || echo true/1/0)"
    psql -d "$DB" -v ON_ERROR_STOP=1 -qAt >/dev/null -c "INSERT INTO access_audit_log (viewer_id, company_id, action, scope) VALUES ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000aa01', 'hr_absence_import_stage', '{\"company_id\": \"00000000-0000-0000-0000-00000000aa01\", \"reason\": \"import_too_many_rows\"}')"
    BEFORE="$(rows)"; AUDIT0="$(psql -d "$DB" -qAt -c "SELECT count(*) FROM access_audit_log")"
    apply_pack .
    check "real d1bdc6f pack ($mode): HR rows unchanged" "$(rows)" "$BEFORE"
    check "real d1bdc6f pack ($mode): no audit row deleted, the refusal row of the old build stays" "$(psql -d "$DB" -qAt -c "SELECT (count(*) >= $AUDIT0)::text || '/' || (SELECT count(*) FROM access_audit_log WHERE action = 'hr_absence_import_stage' AND scope->>'reason' = 'import_too_many_rows')::text FROM access_audit_log")" "true/1"
    import_objects "real d1bdc6f pack ($mode)"
    apply_pack .
    check "real d1bdc6f pack ($mode): a second apply changes nothing and still has no extension" "$(psql -d "$DB" -qAt -c "SELECT (SELECT count(*) FROM pg_extension WHERE extname = 'dblink')::text || '/' || (SELECT count(*) FROM pg_namespace WHERE nspname = 'chr_internal')::text")" "0/0"
  done
  unset APPLY_USER
  rm -rf "$OLD"
else
  echo "SKIP HRUP real d1bdc6f pack (git history not available)"
fi
psql -qc "DROP DATABASE IF EXISTS $DB WITH (FORCE)" postgres
echo "HR KIND UPGRADE TESTS: $FAILS failed"
[ "$FAILS" = 0 ]
