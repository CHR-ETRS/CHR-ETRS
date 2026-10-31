-- =============================================================================
-- CHR-ETRS MVP v1.6.10 · migrations/preflight_tz.sql — source timezone preflight (Chief of Drive 21.10, rule 4)
-- Version: 1.6.10-mvp (2026-10-21) — new. Included by migrate_v1_4_to_v1_6_10.sql (inside its transaction)
-- and run alone by run_migration.sh before the backup (psql -1).
-- v1.x filled users.start_date with DEFAULT CURRENT_DATE in the database session's zone. The trust rule
-- (start_date = creation date → unknown) compares dates in that zone, so it must be known:
--   * source zone (SHOW timezone) is UTC → compare in UTC;
--   * not UTC → STOP, unless the operator passes the zone explicitly (runner --source-tz <zone>,
--     psql -v source_tz=<zone>) → compare in that zone.
-- Only enforced while a v1.x start_date is still waiting to be merged (users.start_date a plain column);
-- on an already migrated database there is nothing to compare and the run continues (zone noted only).
-- Result: transaction-local setting chr.mig_source_tz (read by schema fn_mig_source_tz).
-- The runner unsets PGTZ so that SHOW timezone is the server / database setting.
-- =============================================================================
\if :{?source_tz}
\else
\set source_tz ''
\endif
SELECT set_config('chr.mig_source_tz_arg', :'source_tz', true) AS source_tz_arg \gset
DO $$
DECLARE
  v_db      text := current_setting('TimeZone');
  v_arg     text := current_setting('chr.mig_source_tz_arg', true);
  v_pending boolean := to_regclass('public.users') IS NOT NULL AND EXISTS (
                         SELECT 1 FROM pg_attribute WHERE attrelid = 'public.users'::regclass
                            AND attname = 'start_date' AND NOT attisdropped AND attgenerated = '');
  v_utc     boolean := upper(current_setting('TimeZone')) IN ('UTC', 'ETC/UTC', 'UCT', 'ETC/UCT', 'GMT', 'ETC/GMT',
                         'GMT0', 'ETC/GMT0', 'GMT+0', 'ETC/GMT+0', 'GMT-0', 'ETC/GMT-0', 'ZULU', 'ETC/ZULU',
                         'UNIVERSAL', 'ETC/UNIVERSAL', 'GREENWICH', 'ETC/GREENWICH');
  v_use     text;
BEGIN
  IF COALESCE(v_arg, '') <> '' THEN
    IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = v_arg) THEN
      RAISE EXCEPTION 'preflight: unknown --source-tz "%" (not an IANA zone known to this server)', v_arg;
    END IF;
    v_use := v_arg;
  ELSIF v_utc THEN
    v_use := 'UTC';
  ELSIF v_pending THEN
    RAISE EXCEPTION 'preflight: the source database timezone is "%" (not UTC). v1.4 start dates were defaulted in that session zone, so the trust rule needs it explicitly: re-run with --source-tz <zone> (runner) or -v source_tz=<zone> (psql), e.g. --source-tz %', v_db, v_db;
  ELSE
    v_use := 'UTC';   -- nothing left to compare (start_date already merged)
  END IF;
  PERFORM set_config('chr.mig_source_tz', v_use, true);
  RAISE NOTICE 'preflight: source timezone "%" → comparing v1.x dates in "%"', v_db, v_use;
END $$;
