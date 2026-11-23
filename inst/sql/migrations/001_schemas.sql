-- 001_schemas.sql: schemas, the trigram extension and default privileges.
--
-- Applied by prexp::migrate() as prexp_owner, in one transaction. migrate()
-- has already created the meta schema for meta.schema_migrations, and it stays
-- owner-only. Roles belong to the cluster, not to a database, so migrations
-- never create them: docker/db/init/01-roles.sh does (locally and in CI), and
-- they are created by hand on the server.
--
-- Roles (spec section 3.1):
--   prexp_owner   owns every object and runs the migrations
--   prexp_loader  writes raw and core; reads raw, core and app, because the
--                 plan check runs the app's queries as the loader
--   prexp_app     reads app, nothing else (read-only, 5 s timeout and JIT off
--                 are role settings from docker/db/init/02-database.sql)
--
-- Applied files are never edited. Change privileges in a new migration.

CREATE SCHEMA raw;
CREATE SCHEMA core;
CREATE SCHEMA app;

-- In public, which every role can use, so the app's search queries can call
-- similarity() and the trigram indexes can use gin_trgm_ops.
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA public;

GRANT USAGE ON SCHEMA raw, core, app TO prexp_loader;
GRANT USAGE ON SCHEMA app TO prexp_app;

-- Tables and sequences that prexp_owner creates later in raw and core.
-- The loader gets data access only: creating, attaching, dropping or
-- vacuuming tables still needs the owner.
ALTER DEFAULT PRIVILEGES FOR ROLE prexp_owner IN SCHEMA raw, core
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO prexp_loader;
ALTER DEFAULT PRIVILEGES FOR ROLE prexp_owner IN SCHEMA raw, core
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO prexp_loader;

-- Views (and any table) that prexp_owner creates later in app.
ALTER DEFAULT PRIVILEGES FOR ROLE prexp_owner IN SCHEMA app
  GRANT SELECT ON TABLES TO prexp_loader, prexp_app;
