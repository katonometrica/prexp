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
