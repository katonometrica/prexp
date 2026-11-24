# The fixture database (spec section 6.1): a database of its own, migrated,
# with the thirteen fixture months loaded by the real loader. It is made once
# per test run, by the first test that asks for it, and dropped when the run
# ends. Loading the thirteenth month moves the twelve-month window, so the
# oldest month is dropped, as it would be in production.
#
# Tests read it as the app, which can only read; a test that writes needs a
# database of its own (local_loaded_db()). Without a reachable test database,
# the tests that ask for it are skipped, or fail in CI.

fixture_db <- new.env(parent = emptyenv())

local_fixture_db <- function() {
  if (is.null(fixture_db$dbname)) {
    dbname <- local_migrated_db(env = testthat::teardown_env())
    for (ym in fixture_months()) {
      suppressMessages(load_fixture(ym, dbname))
    }
    fixture_db$dbname <- dbname
  }
  fixture_db$dbname
}

# The months the fixture database keeps: the last twelve fixture months
fixture_window <- function() utils::tail(fixture_months(), 12L)

# The app's connection to the fixture database, closed when the calling test
# ends
fixture_app <- function(env = parent.frame()) {
  local_test_db("app", dbname = local_fixture_db(), env = env)
}
