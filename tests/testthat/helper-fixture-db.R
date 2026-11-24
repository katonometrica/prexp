# The fixture database (spec section 6.1): a database of its own, migrated,
# with the thirteen fixture months loaded by the real loader. It is made once
# per test run, by the first test that asks for it, and dropped when the run
# ends. Loading the thirteenth month moves the twelve-month window, so the
# oldest month is dropped, as it would be in production.
#
# Tests read it as the app, which can only read, and once loaded it is
# read-only by default for every login; a test that writes needs a database
# of its own (local_loaded_db()). Without a reachable test database, the tests
# that ask for it are skipped, or fail in CI.

fixture_db <- new.env(parent = emptyenv())

# A build that fails is not tried again: the same error then ends every later
# test that asks for the database, at once.
local_fixture_db <- function() {
  if (!is.null(fixture_db$error)) {
    stop(fixture_db$error)
  }
  if (is.null(fixture_db$dbname)) {
    if (!testthat::is_testing()) {
      stop(
        "The fixture database is made only during a test run. To step through a ",
        "test by hand, use local_loaded_db(fixture_months()) instead.",
        call. = FALSE
      )
    }
    fixture_db$dbname <- tryCatch(build_fixture_db(), error = function(e) {
      fixture_db$error <- e
      stop(e)
    })
  }
  fixture_db$dbname
}

# Made read-only by default once loaded, for every new session, the owner's
# too: the tests share it, so none may change it.
build_fixture_db <- function() {
  dbname <- local_migrated_db(env = testthat::teardown_env())
  for (ym in fixture_months()) {
    suppressMessages(load_fixture(ym, dbname))
  }
  owner <- local_test_db("owner", dbname = dbname)
  DBI::dbExecute(owner, paste(
    "ALTER DATABASE", DBI::dbQuoteIdentifier(owner, dbname),
    "SET default_transaction_read_only = on"
  ))
  dbname
}

# The months the fixture database keeps: the last twelve fixture months
fixture_window <- function() utils::tail(fixture_months(), 12L)

# The app's connection to the fixture database, closed when the calling test
# ends
fixture_app <- function(env = parent.frame()) {
  local_test_db("app", dbname = local_fixture_db(), env = env)
}
