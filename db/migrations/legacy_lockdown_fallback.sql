-- =============================================================================
-- CHR-ETRS MVP v1.6.10 · migrations/legacy_lockdown_fallback.sql
-- Version: 1.6.10-mvp (2026-10-21) — new (Chief of Drive 21.10, O-53).
-- Used by run_migration.sh when the event-trigger guard (legacy_ddl_guard.sql) is refused because the
-- connection is not a superuser (e.g. managed Supabase). Runs as the application owner (PGUSER):
--   1. role legacy_v1_4_owner (NOLOGIN, no rights) is created if missing;
--   2. on every legacy_v1_4_* table: REVOKE ALL from every grantee (PUBLIC, anon, authenticated,
--      service_role, the app owner, any other role found in the ACL);
--   3. tables (and the legacy enum type) move to schema legacy_v1_4 owned by legacy_v1_4_owner — needed
--      because the app owner owns schema public (pg_database_owner) and a schema owner may DROP any table
--      in it (found by the v1.6.10 tests) — and their ownership moves to legacy_v1_4_owner → the app roles
--      can no longer read / write / ALTER / DROP them (no USAGE on the schema, not owner; row writes are
--      also refused by trg_legacy_read_only_*);
--   4. the temporary membership needed for steps 2–3 (PG16+: SET on the new owner) is revoked again;
--   5. WARNING printed + audit row 'legacy_guard_fallback' (only when a table moved in this run).
-- Idempotent: a second run finds every table already in legacy_v1_4, owned by legacy_v1_4_owner → no change,
-- no audit. Reading the rows: SELECT … FROM legacy_v1_4.legacy_v1_4_<name> (with the membership below).
-- Weaker than the event trigger (see ADR_GAPS O-53): the role that created legacy_v1_4_owner keeps
-- ADMIN OPTION on it (PostgreSQL 16+ CREATEROLE rule) and could deliberately re-grant itself; a
-- superuser can do anything. Reading the frozen rows needs a temporary membership:
--   GRANT legacy_v1_4_owner TO <admin> WITH INHERIT TRUE;  … SELECT …;  REVOKE legacy_v1_4_owner FROM <admin>;
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- 1. dedicated NOLOGIN owner role (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'legacy_v1_4_owner') THEN
    CREATE ROLE legacy_v1_4_owner NOLOGIN NOINHERIT NOCREATEDB NOCREATEROLE;
  END IF;
  COMMENT ON ROLE legacy_v1_4_owner IS 'CHR-ETRS: owner of the frozen v1.4 tables (O-53 fallback); never log in, never grant';
END $$;

-- 2–4. revoke every grant, move tables + legacy types into schema legacy_v1_4 (owned by the NOLOGIN role:
--      the app owner owns schema public through pg_database_owner and could otherwise DROP them), then
--      move ownership (temporary SET/INHERIT membership, revoked at the end)
CREATE FUNCTION pg_temp.legacy_lockdown() RETURNS TABLE (tables int, moved int) LANGUAGE plpgsql AS $$
DECLARE r record; g record; v_tables int := 0; v_moved int := 0;
BEGIN
  GRANT legacy_v1_4_owner TO CURRENT_USER WITH INHERIT TRUE, SET TRUE;   -- temporary (revoked below)
  IF to_regnamespace('legacy_v1_4') IS NULL THEN
    CREATE SCHEMA legacy_v1_4 AUTHORIZATION legacy_v1_4_owner;
  END IF;
  EXECUTE 'REVOKE ALL ON SCHEMA legacy_v1_4 FROM PUBLIC';
  COMMENT ON SCHEMA legacy_v1_4 IS 'CHR-ETRS: frozen v1.4 tables (O-45/O-53 fallback), owner legacy_v1_4_owner; no client access';
  -- legacy enum types first (a table column depends on them; DROP TYPE … CASCADE by their owner would drop it)
  FOR r IN SELECT t.typname, t.typowner FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
            WHERE n.nspname = 'public' AND t.typtype = 'e' AND t.typname LIKE 'legacy\_v1\_4\_%' LOOP
    EXECUTE format('ALTER TYPE public.%I SET SCHEMA legacy_v1_4', r.typname);
  END LOOP;
  FOR r IN SELECT t.typname FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
            WHERE n.nspname = 'legacy_v1_4' AND t.typtype = 'e' AND t.typowner <> 'legacy_v1_4_owner'::regrole LOOP
    EXECUTE format('ALTER TYPE legacy_v1_4.%I OWNER TO legacy_v1_4_owner', r.typname);
  END LOOP;
  FOR r IN SELECT c.oid, n.nspname, c.relname, c.relowner FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('public', 'legacy_v1_4') AND c.relkind = 'r' AND c.relname LIKE 'legacy\_v1\_4\_%'
            ORDER BY c.relname LOOP
    v_tables := v_tables + 1;
    EXECUTE format('REVOKE ALL ON TABLE %I.%I FROM PUBLIC', r.nspname, r.relname);
    FOR g IN SELECT DISTINCT a.grantee FROM pg_class c, aclexplode(c.relacl) a
              WHERE c.oid = r.oid AND a.grantee <> 0 LOOP
      EXECUTE format('REVOKE ALL ON TABLE %I.%I FROM %I', r.nspname, r.relname, g.grantee::regrole::text);
    END LOOP;
    IF r.nspname = 'public' THEN
      EXECUTE format('ALTER TABLE public.%I SET SCHEMA legacy_v1_4', r.relname);
    END IF;
    IF r.relowner <> 'legacy_v1_4_owner'::regrole THEN
      EXECUTE format('ALTER TABLE legacy_v1_4.%I OWNER TO legacy_v1_4_owner', r.relname);
      v_moved := v_moved + 1;
    END IF;
  END LOOP;
  REVOKE legacy_v1_4_owner FROM CURRENT_USER;
  RETURN QUERY SELECT v_tables, v_moved;
END $$;

-- 5. report: WARNING always, audit row only when this run moved something
DO $$
DECLARE v record;
BEGIN
  SELECT * INTO v FROM pg_temp.legacy_lockdown();
  RAISE WARNING E'\n*** LEGACY DDL GUARD NOT INSTALLED (no superuser) — FALLBACK APPLIED ***\n*** % legacy_v1_4_* tables: all grants revoked, moved to schema legacy_v1_4, owner legacy_v1_4_owner (NOLOGIN); moved now: % ***\n*** weaker than the event trigger: see ADR_GAPS O-53 ***', v.tables, v.moved;
  IF v.moved > 0 THEN
    INSERT INTO access_audit_log (viewer_id, company_id, action, scope)
    VALUES (NULL, NULL, 'legacy_guard_fallback',
            jsonb_build_object('owner', 'legacy_v1_4_owner', 'schema', 'legacy_v1_4', 'tables', v.tables, 'moved', v.moved,
                               'installed_by', current_user, 'reason', 'event trigger refused: not a superuser (O-53)'));
  END IF;
END $$;

COMMIT;
