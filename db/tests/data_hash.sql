-- CHR-ETRS v1.6.7 · tests/data_hash.sql — one md5 per table (schemas public + auth) of all its rows,
-- used by the migration tests to prove "nothing changed". Session-temp helper only.
-- md5 of every row of one table (row text, sorted), '-' for an empty table
CREATE FUNCTION pg_temp.tbl_md5(p_rel regclass) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  EXECUTE format('SELECT md5(string_agg(t::text, %L ORDER BY t::text)) FROM %s t', '|', p_rel) INTO v;
  RETURN COALESCE(v, '-');
END $$;
SELECT n.nspname || '.' || c.relname || ' ' || pg_temp.tbl_md5(c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('public', 'auth') AND c.relkind = 'r' ORDER BY 1;
