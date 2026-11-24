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

test_that("db_pool() lends read-only connections as the app, to the database given", {
  pool <- local_test_pool()
  session <- DBI::dbGetQuery(pool, "
    SELECT current_user AS login, current_database() AS dbname,
           current_setting('application_name') AS name,
           current_setting('transaction_read_only') AS read_only")
  expect_identical(
    session,
    data.frame(
      login = "prexp_app", dbname = Sys.getenv("PREXP_TEST_DB_NAME"), name = "prexp-app",
      read_only = "on"
    )
  )
  expect_error(
    DBI::dbExecute(pool, "CREATE TABLE app.not_allowed (x int)"), "read-only transaction"
  )
})

test_that("the app refuses a login that can write, even one the client made read-only", {
  local_test_db("owner")
  dbname <- Sys.getenv("PREXP_TEST_DB_NAME")
  read_only <- "-c default_transaction_read_only=on"
  for (role in c("loader", "owner")) {
    withr::with_envvar(
      c(
        PREXP_APP_USER = paste0("prexp_", role),
        PREXP_APP_PASSWORD = Sys.getenv(paste0("PREXP_", toupper(role), "_PASSWORD"))
      ),
      {
        refused <- paste0("The app must connect read-only, but prexp_", role, " ")
        expect_error(
          db_pool(dbname = dbname), refused, fixed = TRUE, class = "prexp_writable_login"
        )
        # With minSize = 0 the first connection opens after the pool: the error
        # is still the check's own
        error <- expect_error(db_pool(dbname = dbname, minSize = 0), class = "prexp_writable_login")
        expect_true(startsWith(conditionMessage(error), refused))
        expect_error(db_connect("app", dbname = dbname), refused, fixed = TRUE)
        # A read-only default the client asked for can be set off again
        client <- "only because the client asked"
        expect_error(db_pool(dbname = dbname, options = read_only), client, fixed = TRUE)
        withr::with_envvar(
          c(PGOPTIONS = read_only),
          expect_error(db_connect("app", dbname = dbname), client, fixed = TRUE)
        )
        # Acting as the app's role is not being its login: RESET ROLE undoes it.
        # Only a superuser may act as a role it is not a member of.
        if (role == "owner") {
          as_app <- "-c role=prexp_app"
          expect_error(
            db_pool(dbname = dbname, options = as_app), paste0(refused, "has "), fixed = TRUE
          )
          expect_error(
            db_connect("app", dbname = dbname, options = paste(as_app, read_only)),
            paste0(refused, "is read-only only because the client asked"), fixed = TRUE
          )
        }
      }
    )
  }
})

test_that("a refused connection is closed before the error", {
  local_test_db("owner")
  dbname <- Sys.getenv("PREXP_TEST_DB_NAME")
  con <- db_connect("loader", dbname = dbname)
  expect_error(check_read_only(con), "prexp_loader has default_transaction_read_only = off")
  expect_false(DBI::dbIsValid(con))
  # The pool's and db_connect()'s refused connections too. pool does not close
  # a connection its onCreate refuses, so the check must. Each connection the
  # check sees is kept here, so that garbage collection cannot close a leaked one.
  seen <- list()
  check <- check_read_only
  local_mocked_bindings(check_read_only = function(con) {
    seen[[length(seen) + 1L]] <<- con
    check(con)
  })
  withr::local_envvar(
    PREXP_APP_USER = "prexp_loader", PREXP_APP_PASSWORD = Sys.getenv("PREXP_LOADER_PASSWORD")
  )
  expect_error(db_pool(dbname = dbname), class = "prexp_writable_login")
  expect_error(db_pool(dbname = dbname, minSize = 0), class = "prexp_writable_login")
  expect_error(db_connect("app", dbname = dbname), class = "prexp_writable_login")
  expect_length(seen, 3L)
  expect_false(any(vapply(seen, DBI::dbIsValid, logical(1))))
})

test_that("a refused app login fails the tests that need it, rather than skip them", {
  local_test_db("owner")
  withr::local_envvar(
    PREXP_APP_USER = "prexp_loader",
    PREXP_APP_PASSWORD = Sys.getenv("PREXP_LOADER_PASSWORD"),
    PREXP_TEST_DB_REQUIRED = NA
  )
  expect_error(local_test_db("app"), class = "prexp_writable_login")
  expect_error(local_test_pool(), class = "prexp_writable_login")
})
