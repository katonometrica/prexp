#!/usr/bin/env bash
# Creates the login roles prexp_loader and prexp_app and the test database
# (docs/spec.md §2.2, §3.1). Idempotent: a rerun creates nothing twice and sets both
# passwords again, so it also rotates them.
#
# Three ways to run it:
#   1. The postgres image runs it once, when the data volume is empty: executed if
#      the file is executable, sourced otherwise. The subshell below makes both safe.
#      Without PGHOST, psql uses the local socket as $POSTGRES_USER on $POSTGRES_DB,
#      like the image's own scripts.
#   2. CI, against the postgres service container (P0-06):
#        PGHOST=postgres PGUSER=prexp_owner PGPASSWORD=... PGDATABASE=prexp \
#        PREXP_LOADER_PASSWORD=... PREXP_APP_PASSWORD=... bash docker/db/init/01-roles.sh
#   3. By hand, for example from the rstudio container (PGHOST=db is already set):
#        PGUSER=prexp_owner PGPASSWORD="$PREXP_OWNER_PASSWORD" bash ~/prexp/docker/db/init/01-roles.sh
#      or, after changing passwords in .env, inside the db container, where it also resets
#      prexp_owner's password from POSTGRES_PASSWORD (the local socket needs no password):
#        docker compose exec db bash /docker-entrypoint-initdb.d/01-roles.sh
#
# Needs PREXP_LOADER_PASSWORD and PREXP_APP_PASSWORD. Optional: PREXP_TEST_DB_NAME
# (default prexp_test). The role prexp_owner must exist: the postgres image creates it as
# POSTGRES_USER; on the server it is created first (P1-08).
# psql reads the passwords from the environment (\getenv) and quotes them itself
# (:'name'). They never appear on a command line or in SQL assembled by the shell.
# Committed with the executable bit: git add --chmod=+x docker/db/init/01-roles.sh

prexp_init_roles() (
  set -Eeuo pipefail

  : "${PREXP_LOADER_PASSWORD:?PREXP_LOADER_PASSWORD is not set}"
  : "${PREXP_APP_PASSWORD:?PREXP_APP_PASSWORD is not set}"
  export PREXP_TEST_DB_NAME="${PREXP_TEST_DB_NAME:-prexp_test}"

  # Inside the postgres container: local socket as the bootstrap superuser.
  # Anywhere else the PG* variables decide.
  local reset_owner=off
  if [ -z "${PGHOST:-}" ] && [ -n "${POSTGRES_USER:-}" ]; then
    export PGUSER="${PGUSER:-$POSTGRES_USER}"
    export PGDATABASE="${PGDATABASE:-${POSTGRES_DB:-$POSTGRES_USER}}"
    # Only in this project's db container is POSTGRES_PASSWORD prexp_owner's password;
    # in other postgres containers (Coolify, P1-08) it belongs to another superuser.
    if [ "${POSTGRES_USER}" = "prexp_owner" ] && [ -n "${POSTGRES_PASSWORD:-}" ]; then
      reset_owner=on
    fi
  fi

  psql --no-psqlrc --no-password --quiet --set ON_ERROR_STOP=1 --set reset_owner="$reset_owner" <<'SQL'
\getenv loader_password PREXP_LOADER_PASSWORD
\getenv app_password PREXP_APP_PASSWORD
\getenv test_db PREXP_TEST_DB_NAME

-- Keep statements that carry a password out of the server log: statement logging,
-- duration and sample logging, and logging of failed statements, for this session.
-- Changing these needs a superuser (or SET privilege on them). Without it the first
-- set_config fails, and ON_ERROR_STOP ends the script before any password is sent.
SELECT set_config('log_statement', 'none', false),
       set_config('log_min_duration_statement', '-1', false),
       set_config('log_min_duration_sample', '-1', false),
       set_config('log_transaction_sample_rate', '0', false),
       set_config('log_min_error_statement', 'panic', false)
\g /dev/null

-- Login roles: create when missing, then (re)set the password
SELECT 'CREATE ROLE prexp_loader LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'prexp_loader')
\gexec
SELECT 'CREATE ROLE prexp_app LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'prexp_app')
\gexec
ALTER ROLE prexp_loader WITH LOGIN PASSWORD :'loader_password';
ALTER ROLE prexp_app WITH LOGIN PASSWORD :'app_password';
\if :reset_owner
\getenv owner_password POSTGRES_PASSWORD
ALTER ROLE prexp_owner WITH PASSWORD :'owner_password';
\endif

-- Test database, owned by the owner role
SELECT format('CREATE DATABASE %I OWNER prexp_owner', :'test_db')
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_database WHERE datname = :'test_db')
\gexec
ALTER DATABASE :"test_db" OWNER TO prexp_owner;
SQL

  echo "01-roles.sh: roles prexp_loader and prexp_app and database ${PREXP_TEST_DB_NAME} are ready"
)

prexp_init_roles
