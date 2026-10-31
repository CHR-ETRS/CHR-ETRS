-- CHR-ETRS v1.6.7 · tests/catalog_snapshot.sql — normalized catalog of schemas public + auth, one line per
-- object (column order ignored; legacy_v1_4_* archive objects excluded; a NULL ACL is shown as the
-- owner default it means, because pg_restore may write it out explicitly). Used to compare a migrated v1.4
-- database with a fresh v1.6.7 install.
WITH rel AS (
  SELECT c.oid, n.nspname || '.' || c.relname AS name, c.relkind, c.relrowsecurity, c.relforcerowsecurity,
         COALESCE(c.relacl, acldefault(CASE WHEN c.relkind = 'S' THEN 's' ELSE 'r' END::"char", c.relowner)) AS relacl
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname IN ('public', 'auth') AND c.relname NOT LIKE 'legacy\_v1\_4\_%' AND c.relkind IN ('r', 'v', 'm', 'i', 'S'))
SELECT line FROM (
  SELECT 'rel ' || name || ' kind=' || relkind::text || ' rls=' || relrowsecurity || '/' || relforcerowsecurity
         || ' acl=' || COALESCE((SELECT string_agg(a::text, ',' ORDER BY a::text) FROM unnest(relacl) a), '-') AS line FROM rel
  UNION ALL
  SELECT 'col ' || r.name || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || ' nn=' || a.attnotnull
         || ' def=' || COALESCE(pg_get_expr(d.adbin, d.adrelid), '') || ' gen=' || a.attgenerated::text
    FROM rel r JOIN pg_attribute a ON a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum WHERE r.relkind IN ('r', 'v')
  UNION ALL
  SELECT 'con ' || r.name || ' ' || co.conname || ' ' || pg_get_constraintdef(co.oid)
    FROM rel r JOIN pg_constraint co ON co.conrelid = r.oid
  UNION ALL
  SELECT 'idx ' || pg_get_indexdef(i.indexrelid) FROM rel r JOIN pg_index i ON i.indrelid = r.oid
  UNION ALL
  SELECT 'trg ' || pg_get_triggerdef(t.oid) FROM rel r JOIN pg_trigger t ON t.tgrelid = r.oid AND NOT t.tgisinternal
  UNION ALL
  SELECT 'trgstate ' || r.name || '.' || t.tgname || '=' || t.tgenabled::text FROM rel r JOIN pg_trigger t ON t.tgrelid = r.oid AND NOT t.tgisinternal
  UNION ALL
  SELECT 'pol ' || r.name || ' ' || p.polname || ' ' || p.polcmd::text || ' perm=' || p.polpermissive
         || ' roles=' || array_to_string(ARRAY(SELECT rolname FROM pg_roles WHERE oid = ANY (p.polroles) ORDER BY 1), ',')
         || ' using=' || COALESCE(pg_get_expr(p.polqual, p.polrelid), '') || ' check=' || COALESCE(pg_get_expr(p.polwithcheck, p.polrelid), '')
    FROM rel r JOIN pg_policy p ON p.polrelid = r.oid
  UNION ALL
  SELECT 'view ' || r.name || ' ' || md5(pg_get_viewdef(r.oid)) FROM rel r WHERE r.relkind = 'v'
  UNION ALL
  SELECT 'fn ' || n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ') -> '
         || pg_get_function_result(p.oid) || ' secdef=' || p.prosecdef || ' vol=' || p.provolatile::text
         || ' cfg=' || COALESCE(array_to_string(p.proconfig, ';'), '') || ' src=' || md5(p.prosrc)
         || ' acl=' || COALESCE((SELECT string_agg(a::text, ',' ORDER BY a::text) FROM unnest(COALESCE(p.proacl, acldefault('f', p.proowner))) a), '-')
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('public', 'auth')
  UNION ALL
  SELECT 'type ' || t.typname || ' ' || COALESCE((SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder) FROM pg_enum e WHERE e.enumtypid = t.oid), t.typtype::text)
    FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
   WHERE n.nspname IN ('public', 'auth') AND t.typtype IN ('e', 'd') AND t.typname NOT LIKE 'legacy\_v1\_4\_%'
  UNION ALL
  SELECT 'comment ' || r.name || ' ' || md5(COALESCE(obj_description(r.oid, 'pg_class'), '')) FROM rel r WHERE r.relkind = 'r'
) x ORDER BY line;
