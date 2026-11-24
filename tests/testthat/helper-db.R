# Database helpers for tests.
#
# local_test_db() connects as one role to PREXP_TEST_DB_NAME, or to another
# database, and disconnects when the calling test ends. local_temp_db()
# creates an empty database, owned by prexp_owner and dropped when the calling
# test ends; migration tests use it because migrations change the schema.
#
# When no database is reachable, both skip the test and say why, so pure tests
# still run anywhere. CI sets PREXP_TEST_DB_REQUIRED=true to fail instead.

local_test_db <- function(role = c("app", "loader", "owner"),
                          dbname = Sys.getenv("PREXP_TEST_DB_NAME"),
                          env = parent.frame()) {
  role <- match.arg(role)
  if (!nzchar(dbname)) {
    no_test_db("PREXP_TEST_DB_NAME is not set")
  }
  # Only a database that cannot be reached skips the test: an app login that
  # db_connect() refuses as writable is a failure. One handler: an error raised
  # again from a handler of the same tryCatch() would reach its other handlers.
  con <- tryCatch(
    db_connect(role, dbname = dbname, connect_timeout = "5"),
    error = function(e) {
      if (inherits(e, "prexp_writable_login")) {
        stop(e)
      }
      no_test_db(conditionMessage(e))
    }
  )
  withr::defer(DBI::dbDisconnect(con), envir = env)
  con
}

local_temp_db <- function(env = parent.frame()) {
  admin <- local_test_db("owner", env = env)
  name <- basename(tempfile("prexp_tmp_"))
  quoted <- DBI::dbQuoteIdentifier(admin, name)
  DBI::dbExecute(admin, paste("CREATE DATABASE", quoted, "TEMPLATE template0"), immediate = TRUE)
  drop <- paste("DROP DATABASE IF EXISTS", quoted, "WITH (FORCE)")
  withr::defer(DBI::dbExecute(admin, drop, immediate = TRUE), envir = env)
  name
}

# The app's pool on a test database, closed when the calling test ends. A
# connection as the app role comes first, so that only an unreachable database
# skips the test: db_pool() refusing the login is a failure.
local_test_pool <- function(dbname = Sys.getenv("PREXP_TEST_DB_NAME"), env = parent.frame()) {
  local_test_db("app", dbname = dbname, env = env)
  pool <- db_pool(dbname = dbname)
  withr::defer(pool::poolClose(pool), envir = env)
  pool
}

# A new database with every migration applied, dropped when the calling test ends.
local_migrated_db <- function(env = parent.frame()) {
  dbname <- local_temp_db(env = env)
  owner <- local_test_db("owner", dbname = dbname, env = env)
  suppressMessages(migrate(owner))
  dbname
}

no_test_db <- function(reason) {
  msg <- paste0("No test database (", reason, ")")
  if (identical(tolower(Sys.getenv("PREXP_TEST_DB_REQUIRED")), "true")) {
    stop(msg, call. = FALSE)
  }
  testthat::skip(msg)
}
