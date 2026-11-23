-- Settings for the read-only app role (docs/spec.md §2.2, §3.1).
-- Role-level, so they apply in every database, prexp_test included. Idempotent.
-- Run by the postgres image after 01-roles.sh on first start, and by CI:
--   psql --no-psqlrc --set ON_ERROR_STOP=1 --file docker/db/init/02-database.sql
\set ON_ERROR_STOP on

ALTER ROLE prexp_app SET default_transaction_read_only = on;
ALTER ROLE prexp_app SET statement_timeout = '5s';
ALTER ROLE prexp_app SET jit = off;
