-- CHR-ETRS v1.7.0 · modules/all.sql — loads the J-178 … J-219 modules in order, after schema.sql + rpc.sql.
-- Every module is idempotent (re-apply safe).
\ir 10_j_common.sql
\ir 15_j_platform_operator.sql
\ir 20_j_capabilities.sql
\ir 30_j_research.sql
\ir 40_j_auditor.sql
\ir 50_j_kiosk_badge.sql
\ir 55_j_kiosk_session.sql
\ir 60_j_everstore_suppliers.sql
\ir 70_j_leaver_nonprofit.sql
\ir 90_j_whats_changed.sql
\ir 95_j_directory_sync.sql
