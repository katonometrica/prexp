#!/usr/bin/env bash
# Creates the login role prexp_owner and the database prexp on the server (P6-02;
# docs/spec.md §2.3, §7; docs/server.md), before docker/db/init/01-roles.sh and
# 02-database.sql. In the Compose stack the postgres image makes prexp_owner its
# bootstrap superuser (POSTGRES_USER), so this file is not in docker/db/init. On the
# server Coolify's superuser is postgres, and prexp_owner is an ordinary login that
# owns the prexp database, which is all the migrations need: they create schemas, the
# trusted pg_trgm extension and grants on prexp_owner's own objects.
#
# Run as a Coolify initialization script, which the postgres image runs once, when the
# data directory is empty: executed if the file is executable, sourced otherwise. The
# subshell below makes both safe. Without PGHOST, psql uses the local socket as
# $POSTGRES_USER on $POSTGRES_DB, like the image's own scripts. Idempotent: a rerun
# creates nothing twice and sets the password again, so it also rotates it, for
# example from the database's terminal in Coolify after changing the variable:
#   bash /docker-entrypoint-initdb.d/00-owner.sh
#
# Needs PREXP_OWNER_PASSWORD. Optional: PREXP_DB_NAME (default prexp).
# psql reads the password from the environment (\getenv) and quotes it itself
# (:'name'). It never appears on a command line or in SQL assembled by the shell.

prexp_init_owner() (
  set -Eeuo pipefail

  : "${PREXP_OWNER_PASSWORD:?PREXP_OWNER_PASSWORD is not set}"
  export PREXP_DB_NAME="${PREXP_DB_NAME:-prexp}"

  # Inside the postgres container: local socket as the bootstrap superuser.
  # Anywhere else the PG* variables decide.
  if [ -z "${PGHOST:-}" ] && [ -n "${POSTGRES_USER:-}" ]; then
    export PGUSER="${PGUSER:-$POSTGRES_USER}"
    export PGDATABASE="${PGDATABASE:-${POSTGRES_DB:-$POSTGRES_USER}}"
  fi
  # Where prexp_owner is the bootstrap superuser (the Compose stack), making it an
  # ordinary login would take away what the image gave it
  if [ "${PGUSER:-}" = "prexp_owner" ] || [ "${POSTGRES_USER:-}" = "prexp_owner" ]; then
    echo "00-owner.sh: prexp_owner is this server's bootstrap user; nothing to do" >&2
    return 0
  fi

  psql --no-psqlrc --no-password --quiet --set ON_ERROR_STOP=1 <<'SQL'
\getenv owner_password PREXP_OWNER_PASSWORD
\getenv db PREXP_DB_NAME

-- Keep statements that carry a password out of the server log, for this session.
-- Changing these needs a superuser: without one the first set_config fails, and
-- ON_ERROR_STOP ends the script before the password is sent.
SELECT set_config('log_statement', 'none', false),
       set_config('log_min_duration_statement', '-1', false),
       set_config('log_min_duration_sample', '-1', false),
       set_config('log_transaction_sample_rate', '0', false),
       set_config('log_min_error_statement', 'panic', false)
\g /dev/null

-- The owner: a login, and nothing more
SELECT 'CREATE ROLE prexp_owner LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'prexp_owner')
\gexec
ALTER ROLE prexp_owner WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  PASSWORD :'owner_password';

-- The app's database, owned by the owner role
SELECT format('CREATE DATABASE %I OWNER prexp_owner', :'db')
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_database WHERE datname = :'db')
\gexec
ALTER DATABASE :"db" OWNER TO prexp_owner;
SQL

  echo "00-owner.sh: role prexp_owner and database ${PREXP_DB_NAME} are ready"
)

prexp_init_owner
