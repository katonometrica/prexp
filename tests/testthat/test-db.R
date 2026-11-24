test_that("db_config() names the missing variables, never their values", {
  withr::local_envvar(
    PREXP_DB_HOST = "db.internal",
    PREXP_DB_NAME = NA,
    PREXP_LOADER_PASSWORD = NA
  )
  error <- expect_error(
    db_config("loader"), "PREXP_DB_NAME, PREXP_LOADER_PASSWORD", fixed = TRUE
  )
  expect_no_match(conditionMessage(error), "db.internal", fixed = TRUE)
})

test_that("db_config() reads a role's settings, with defaults for the port and user", {
  withr::local_envvar(
    PREXP_DB_HOST = "db.internal",
    PREXP_DB_PORT = NA,
    PREXP_DB_NAME = "prexp",
    PREXP_APP_USER = NA,
    PREXP_APP_PASSWORD = "test-not-secret"
  )
  expect_identical(
    db_config("app"),
    list(
      host = "db.internal", port = "5432", dbname = "prexp",
      user = "prexp_app", password = "test-not-secret"
    )
  )
  expect_identical(db_config("app", dbname = "other")$dbname, "other")
})

test_that("db_connect() logs in as each role, and the app role is read-only", {
  for (role in c("owner", "loader", "app")) {
    con <- local_test_db(role)
    login <- DBI::dbGetQuery(con, "SELECT current_user AS login")$login
    expect_identical(login, paste0("prexp_", role))
  }
  app <- local_test_db("app")
  settings <- DBI::dbGetQuery(app, "
    SELECT current_setting('default_transaction_read_only') AS read_only,
           current_setting('statement_timeout') AS timeout")
  expect_identical(settings$read_only, "on")
  expect_identical(settings$timeout, "5s")
})

test_that("db_pool() lends read-only connections as the app", {
  pool <- local_test_pool()
  session <- DBI::dbGetQuery(pool, "
    SELECT current_user AS login, current_setting('application_name') AS name,
           current_setting('transaction_read_only') AS read_only")
  expect_identical(session, data.frame(login = "prexp_app", name = "prexp-app", read_only = "on"))
  expect_error(
    DBI::dbExecute(pool, "CREATE TABLE app.not_allowed (x int)"), "read-only transaction"
  )
})

test_that("the app refuses a login that can write, and leaves no connection behind", {
  owner <- local_test_db("owner")
  dbname <- Sys.getenv("PREXP_TEST_DB_NAME")
  for (role in c("loader", "owner")) {
    withr::with_envvar(
      c(
        PREXP_APP_USER = paste0("prexp_", role),
        PREXP_APP_PASSWORD = Sys.getenv(paste0("PREXP_", toupper(role), "_PASSWORD"))
      ),
      {
        refused <- paste0("must connect read-only, but prexp_", role)
        expect_error(db_pool(dbname = dbname), refused, fixed = TRUE)
        expect_error(db_pool(dbname = dbname, minSize = 0), refused, fixed = TRUE)
        expect_error(db_connect("app", dbname = dbname), refused, fixed = TRUE)
      }
    )
  }
  # A refused connection is closed before the error: none of the writable
  # logins is still connected as the app. A backend can take a moment to go.
  left <- function() {
    DBI::dbGetQuery(owner, "
      SELECT count(*)::int4 AS n FROM pg_stat_activity
      WHERE application_name = 'prexp-app' AND usename <> 'prexp_app'")$n
  }
  for (i in 1:50) {
    if (left() == 0L) break
    Sys.sleep(0.1)
  }
  expect_identical(left(), 0L)
})
