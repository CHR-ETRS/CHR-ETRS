#!/usr/bin/env bash
# CHR-ETRS MVP v1.6.21 · migrations/run_migration.sh — runner for migrate_v1_4_to_v1_6_21.sql (supersedes the 1.6.20, 1.6.19, 1.6.18, 1.6.17,
# 1.6.16 and 1.6.13 runners; v1.6.19 / v1.6.20 / v1.6.21: only the file name and the backup prefix change).
#   usage: run_migration.sh [--source-tz <zone>] {dry-run|apply|guard|rollback} <db>
#   dry-run  <db> : timezone preflight, run the migration, print the counts, ROLLBACK (nothing changes);
#                   reports which legacy protection apply would install (guard or fallback)
#   apply    <db> : timezone preflight → pg_dump -Fc backup into migrations/backups/ → migrate (one
#                   transaction) → legacy protection (do_guard)
#   guard    <db> : (re)install only the legacy protection
#   rollback <db> : restore the newest backup of <db> (drop + recreate + pg_restore)
# v1.6.13 (Chief of Drive 21.10):
#   * O-53: legacy protection = the event-trigger guard (legacy_ddl_guard.sql) when GUARD_PGUSER/PGUSER
#     is a superuser; otherwise NO failure: legacy_lockdown_fallback.sql (REVOKE ALL + owner
#     legacy_v1_4_owner NOLOGIN + WARNING + audit row). Replaces the 1.6.9 refusal without a superuser.
#   * rule 4: the source DB timezone must be UTC, else apply / dry-run stop (before the backup) unless
#     --source-tz <zone> is given; dates are then compared in that zone. PGTZ is ignored (unset) so the
#     check reads the server / database setting.
# Connection comes from the usual PG* environment variables. BACKUP_DIR overrides the backup folder.
set -euo pipefail
unset PGTZ
HERE="$(cd "$(dirname "$0")" && pwd)"
MIG="$HERE/migrate_v1_4_to_v1_6_21.sql"
PREFLIGHT="$HERE/preflight_tz.sql"
GUARD="$HERE/legacy_ddl_guard.sql"
FALLBACK="$HERE/legacy_lockdown_fallback.sql"
BACKUP_DIR="${BACKUP_DIR:-$HERE/backups}"
GUARD_USER="${GUARD_PGUSER:-${PGUSER:-}}"
SOURCE_TZ=""

# usage: print help and exit 2
usage() { echo "usage: $0 [--source-tz <zone>] {dry-run|apply|guard|rollback} <database>" >&2; exit 2; }

# options: --source-tz <zone> (anywhere before the command)
while [ $# -gt 0 ]; do
  case "$1" in
    --source-tz)   [ $# -ge 2 ] || usage; SOURCE_TZ="$2"; shift 2 ;;
    --source-tz=*) SOURCE_TZ="${1#*=}"; shift ;;
    *) break ;;
  esac
done
MODE="${1:-}"; DB="${2:-}"

# app_psql <args…>: psql as the migration (app) connection, with the source zone when given
app_psql() { psql -X -d "$DB" -v ON_ERROR_STOP=1 -v source_tz="$SOURCE_TZ" "$@"; }

# guard_psql <args…>: psql as the guard role (GUARD_PGUSER, default PGUSER)
guard_psql() { if [ -n "$GUARD_USER" ]; then psql -X -U "$GUARD_USER" -d "$DB" "$@"; else psql -X -d "$DB" "$@"; fi; }

# is_superuser: 0 when the guard role is a superuser
is_superuser() { [ "$(guard_psql -qAt -c 'SELECT rolsuper FROM pg_roles WHERE rolname = current_user' 2>/dev/null)" = "t" ]; }

# newest_backup: path of the newest backup of $DB (empty when none)
newest_backup() { ls -1t "$BACKUP_DIR/${DB}_pre_v1_6_21_"*.dump 2>/dev/null | head -n 1 || true; }

# do_preflight: source timezone check (stops on non-UTC without --source-tz); changes nothing
do_preflight() { app_psql -q -1 -f "$PREFLIGHT"; }

# do_dry_run: preflight, migrate with dry_run=1 (the script itself rolls back), report the protection mode
do_dry_run() {
  do_preflight
  app_psql -v dry_run=1 -f "$MIG"
  if is_superuser; then echo "legacy protection: event-trigger guard (superuser)"
  else echo "legacy protection: NO superuser — apply would use the FALLBACK (REVOKE ALL + owner legacy_v1_4_owner)"; fi
}

# do_guard: event-trigger guard as superuser; when refused, the non-superuser fallback (loud, never fails the run)
do_guard() {
  if is_superuser; then
    guard_psql -v ON_ERROR_STOP=1 -q -f "$GUARD"
    echo "legacy protection: event-trigger guard installed"
  else
    echo "WARNING: ************************************************************************" >&2
    echo "WARNING: legacy DDL guard REFUSED (no superuser) — applying the FALLBACK lockdown (O-53)" >&2
    echo "WARNING: ************************************************************************" >&2
    psql -X -d "$DB" -v ON_ERROR_STOP=1 -q -f "$FALLBACK"
    echo "legacy protection: FALLBACK applied (owner legacy_v1_4_owner, all grants revoked)"
  fi
}

# do_apply: preflight, back up, migrate, protect the legacy tables; the backup path is printed for the rollback
do_apply() {
  do_preflight
  mkdir -p "$BACKUP_DIR"
  local f="$BACKUP_DIR/${DB}_pre_v1_6_21_$(date +%Y%m%d%H%M%S%N).dump"
  pg_dump -Fc -d "$DB" -f "$f"
  echo "backup: $f"
  app_psql -v dry_run=0 -f "$MIG"
  do_guard
}

# do_rollback: recreate $DB (and its database settings) from its newest pre-migration backup (CREATEDB owner is enough)
do_rollback() {
  local f; f="$(newest_backup)"
  [ -n "$f" ] || { echo "no backup for $DB in $BACKUP_DIR" >&2; exit 1; }
  psql -X -d postgres -v ON_ERROR_STOP=1 -qc "DROP DATABASE IF EXISTS \"$DB\" WITH (FORCE)"
  # --create: the database is recreated from the dump with its own settings (e.g. ALTER DATABASE … SET timezone)
  pg_restore --create -d postgres --exit-on-error "$f"
  echo "restored $DB from $f"
}

[ -n "$DB" ] || usage
case "$MODE" in
  dry-run)  do_dry_run ;;
  apply)    do_apply ;;
  guard)    do_guard ;;
  rollback) do_rollback ;;
  *)        usage ;;
esac
