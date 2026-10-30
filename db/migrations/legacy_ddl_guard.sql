-- =============================================================================
-- CHR-ETRS MVP v1.6.10 · migrations/legacy_ddl_guard.sql
-- Version: 1.6.10-mvp (2026-10-21) — unchanged logic since 1.6.9 (new there; Chief of Drive 21.10, rule 4 / O-45).
-- v1.6.10 (O-53): when refused (no superuser) the runner applies legacy_lockdown_fallback.sql instead.
-- Blocks DROP and ALTER of the frozen v1.4 tables (legacy_v1_4_*) with two EVENT TRIGGERS, which
-- PostgreSQL only lets a SUPERUSER create. Row writes / TRUNCATE are already refused by the schema
-- (trg_legacy_read_only_*); this closes the DDL side, the table owner included.
--   * trg_legacy_v1_4_drop_guard  (sql_drop)          : any command that would drop a legacy table
--     (DROP TABLE, DROP SCHEMA … CASCADE, DROP OWNED …) is aborted.
--   * trg_legacy_v1_4_alter_guard (ddl_command_end)   : ALTER TABLE on a legacy table (columns,
--     constraints, RENAME, SET SCHEMA, owner …) is aborted; a post-check also catches a renamed /
--     moved table (every table registered at install time must still exist as public.<name>).
-- Error: 'legacy_ddl_blocked' (SQLSTATE 42501, http_hint=403). Objects live in schema chr_guard
-- (outside the app schema; no client access). The two event-trigger functions are SECURITY DEFINER
-- (superuser-owned) so the check also runs for DDL issued by non-superusers.
--
-- Installed by migrations/run_migration.sh apply (after the migration commits) or `… guard <db>`,
-- with a superuser connection (GUARD_PGUSER, default PGUSER). Idempotent: re-running refreshes the
-- registered table list and recreates both triggers.
--
-- LIFTING IT DELIBERATELY (authorised operator, superuser, one transaction — the guard is back on
-- commit or rollback):
--   BEGIN;
--   ALTER EVENT TRIGGER trg_legacy_v1_4_drop_guard DISABLE;
--   ALTER EVENT TRIGGER trg_legacy_v1_4_alter_guard DISABLE;
--   -- … the approved change, e.g. ALTER TABLE legacy_v1_4_role_cost_config … …
--   ALTER EVENT TRIGGER trg_legacy_v1_4_drop_guard ENABLE;
--   ALTER EVENT TRIGGER trg_legacy_v1_4_alter_guard ENABLE;
--   COMMIT;
-- Removing it for good (only with a Chief of Drive ruling that ends O-45):
--   DROP EVENT TRIGGER trg_legacy_v1_4_drop_guard; DROP EVENT TRIGGER trg_legacy_v1_4_alter_guard;
--   DROP SCHEMA chr_guard CASCADE;
-- Note: a superuser can also bypass event triggers with SET session_replication_role = replica — by
-- design of PostgreSQL; superuser rights are the trust boundary.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- Refuse to run without superuser rights (event triggers need them).
DO $$
BEGIN
  IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
    RAISE EXCEPTION 'legacy_ddl_guard.sql must run as a superuser (event triggers) — current user %', current_user;
  END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS chr_guard;
REVOKE ALL ON SCHEMA chr_guard FROM PUBLIC;

-- Register the legacy tables present now (names baked into an immutable function; refreshed on re-run).
DO $$
DECLARE v text[];
BEGIN
  SELECT COALESCE(array_agg(c.relname::text ORDER BY c.relname), '{}') INTO v
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname LIKE 'legacy\_v1\_4\_%';
  EXECUTE format('CREATE OR REPLACE FUNCTION chr_guard.fn_legacy_names() RETURNS text[] LANGUAGE sql IMMUTABLE AS %L',
                 'SELECT ' || quote_literal(v::text) || '::text[]');
END $$;

-- Is this table name protected? (pattern, or registered at install time)
CREATE OR REPLACE FUNCTION chr_guard.fn_is_legacy(p_name text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_name LIKE 'legacy\_v1\_4\_%' OR p_name = ANY (chr_guard.fn_legacy_names())
$$;

-- Abort the current command.
CREATE OR REPLACE FUNCTION chr_guard.fn_block(p_tag text, p_what text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'legacy_ddl_blocked: % on % (frozen v1.4 table, O-45)', p_tag, p_what
    USING ERRCODE = '42501', DETAIL = 'http_hint=403;code=legacy_ddl_blocked', HINT = 'legacy_ddl_blocked';
END;
$$;

-- sql_drop: a legacy table is among the dropped objects → abort.
CREATE OR REPLACE FUNCTION chr_guard.fn_legacy_drop_guard()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER   -- runs as the installing superuser, so any role's DDL can be checked
SET search_path = pg_catalog, chr_guard
AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pg_event_trigger_dropped_objects()
            WHERE object_type = 'table' AND chr_guard.fn_is_legacy(object_name) LOOP
    PERFORM chr_guard.fn_block(tg_tag, r.object_identity);
  END LOOP;
END;
$$;

-- ddl_command_end (ALTER TABLE): the altered table is a legacy one, or a registered one is gone → abort.
CREATE OR REPLACE FUNCTION chr_guard.fn_legacy_alter_guard()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER   -- runs as the installing superuser, so any role's DDL can be checked
SET search_path = pg_catalog, chr_guard
AS $$
DECLARE r record; v_missing text;
BEGIN
  FOR r IN SELECT c.relname, d.object_identity FROM pg_event_trigger_ddl_commands() d
             JOIN pg_class c ON d.classid = 'pg_class'::regclass AND c.oid = d.objid
            WHERE chr_guard.fn_is_legacy(c.relname) LOOP
    PERFORM chr_guard.fn_block(tg_tag, r.object_identity);
  END LOOP;
  SELECT n INTO v_missing FROM unnest(chr_guard.fn_legacy_names()) n
   WHERE to_regclass(format('public.%I', n)) IS NULL LIMIT 1;
  IF v_missing IS NOT NULL THEN
    PERFORM chr_guard.fn_block(tg_tag, 'public.' || v_missing || ' (renamed or moved)');
  END IF;
END;
$$;

DROP EVENT TRIGGER IF EXISTS trg_legacy_v1_4_drop_guard;
CREATE EVENT TRIGGER trg_legacy_v1_4_drop_guard ON sql_drop
  EXECUTE FUNCTION chr_guard.fn_legacy_drop_guard();
DROP EVENT TRIGGER IF EXISTS trg_legacy_v1_4_alter_guard;
CREATE EVENT TRIGGER trg_legacy_v1_4_alter_guard ON ddl_command_end WHEN TAG IN ('ALTER TABLE')
  EXECUTE FUNCTION chr_guard.fn_legacy_alter_guard();

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA chr_guard FROM PUBLIC;
SELECT 'legacy DDL guard installed' AS status, cardinality(chr_guard.fn_legacy_names()) AS tables_registered;
COMMIT;
