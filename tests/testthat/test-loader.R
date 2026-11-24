# load_month() and its build, check and swap (spec section 4; P1-07). Each test
# loads fixture months into a new migrated database and compares every table
# with the oracle (helper-oracle.R).

leftovers <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'core' AND c.relname LIKE 'prescribing\\_%\\_new') AS new_tables,
           (SELECT count(*)::int FROM raw.epd_staging) AS staged")
}

test_that("a fixture month loads, and the fact table and rollups equal the oracle", {
  dbname <- local_migrated_db()
  messages <- testthat::capture_messages(res <- load_fixture(202609L, dbname))
  for (step in c("header", "stage", "dimensions", "build", "check", "swap", "clean")) {
    expect_true(any(startsWith(messages, paste0(step, ": "))), label = step)
  }
  expect_match(messages[length(messages)], "^Loaded 202609: 3984 source rows")
  con <- local_test_db("owner", dbname = dbname)
  expect_loaded_as_oracle(con, 202609L)
  expect_identical(res$loaded_rows, as.numeric(nrow(oracle_fact(202609L))))

  log <- load_log(con)
  expect_identical(log$status, "loaded")
  expect_identical(log$source_rows, 3984)
  expect_identical(log$loaded_rows, res$loaded_rows)
  expect_identical(
    DBI::dbGetQuery(con, "SELECT source_sha256 FROM core.load_log")$source_sha256,
    fixture_sha256(202609L)
  )

  # Attached, with the parent's indexes adopted rather than built again
  expect_identical(partitions(con), "prescribing_202609")
  own <- DBI::dbGetQuery(con, "
    SELECT indexname FROM pg_indexes WHERE tablename = 'prescribing_202609' ORDER BY 1")$indexname
  expect_identical(own, c("prescribing_202609_practice_idx", "prescribing_202609_presentation_idx"))
  adopted <- DBI::dbGetQuery(con, "
    SELECT count(*)::int AS n FROM pg_inherits
    WHERE inhparent IN (
      SELECT indexrelid FROM pg_index WHERE indrelid = 'core.prescribing'::regclass
    )")$n
  expect_identical(adopted, 2L)
  expect_identical(leftovers(con), data.frame(new_tables = 0L, staged = 0L))

  # The app sees the month through its views
  app <- local_test_db("app", dbname = dbname)
  window <- DBI::dbGetQuery(app, "SELECT first_month, last_month, months FROM app.v_window")
  expect_identical(window, data.frame(first_month = 202609L, last_month = 202609L, months = 1L))
})

test_that("loading a month again gives identical results and replaces the previous load", {
  dbname <- local_loaded_db(202609L)
  suppressMessages(load_fixture(202609L, dbname))
  con <- local_test_db("owner", dbname = dbname)
  expect_loaded_as_oracle(con, 202609L)
  expect_identical(load_log(con)$status, c("replaced", "loaded"))
  expect_identical(partitions(con), "prescribing_202609")
  expect_identical(leftovers(con), data.frame(new_tables = 0L, staged = 0L))
})

test_that("months load side by side", {
  dbname <- local_loaded_db(c(202608L, 202609L))
  con <- local_test_db("owner", dbname = dbname)
  expect_loaded_as_oracle(con, c(202608L, 202609L))
  expect_identical(partitions(con), c("prescribing_202608", "prescribing_202609"))
})

test_that("a count mismatch leaves the live data unchanged and the attempt failed", {
  dbname <- local_loaded_db(202609L)
  real_stage <- stage_month
  testthat::local_mocked_bindings(stage_month = function(...) {
    res <- real_stage(...)
    res$rows <- res$rows + 1
    res
  })
  expect_error(
    suppressMessages(load_fixture(202609L, dbname)),
    paste(
      "The check of 202609 failed: staging holds 3984 rows, the file 3985.",
      "The live data is unchanged."
    ),
    fixed = TRUE
  )
  con <- local_test_db("owner", dbname = dbname)
  expect_loaded_as_oracle(con, 202609L)
  log <- load_log(con)
  expect_identical(log$status, c("loaded", "failed"))
  expect_match(log$error[2], "staging holds 3984 rows", fixed = TRUE)
  expect_identical(leftovers(con), data.frame(new_tables = 0L, staged = 0L))
})

test_that("an error inside the swap rolls the whole swap back", {
  dbname <- local_loaded_db(202609L)
  testthat::local_mocked_bindings(rename_new_indexes = function(con, ym) stop("injected failure"))
  expect_error(suppressMessages(load_fixture(202609L, dbname)), "injected failure")
  con <- local_test_db("owner", dbname = dbname)
  # The detach, the drop, the renames and the rollup rows were all undone
  expect_loaded_as_oracle(con, 202609L)
  expect_identical(partitions(con), "prescribing_202609")
  expect_identical(load_log(con)$status, c("loaded", "failed"))
  expect_identical(leftovers(con), data.frame(new_tables = 0L, staged = 0L))
})

test_that("the swap waits for a reader's lock, retries, and gives up without changing anything", {
  dbname <- local_loaded_db(202609L)
  owner <- local_test_db("owner", dbname = dbname)
  loader <- local_test_db("loader", dbname = dbname)
  staged <- stage_month(fixture_file(202609L), dbname = dbname)
  check_staged_month(loader, 202609L)
  prepare_dimensions(owner, 202609L)
  suppressMessages(build_month(owner, 202609L))
  checked <- check_month(loader, 202609L, staged$rows)
  load_id <- start_load(loader, 202609L, NA_character_, NULL)

  # An app query in an open transaction holds a lock on the partition
  app <- local_test_db("app", dbname = dbname)
  DBI::dbBegin(app)
  DBI::dbGetQuery(app, "SELECT count(*) FROM app.v_practice_presentation")
  swap <- function() {
    swap_month(owner, 202609L, load_id, staged$rows, checked$loaded_rows, 1,
               lock_timeout = "200ms", attempts = 2L, pause = 0)
  }
  expect_message(
    expect_error(swap(), "lock timeout"),
    "waited too long for a lock (attempt 1 of 2)", fixed = TRUE
  )
  expect_loaded_as_oracle(owner, 202609L)
  expect_identical(load_log(owner)$status, c("loaded", "running"))

  # Once the reader has finished, the same swap goes through
  DBI::dbRollback(app)
  swap()
  expect_identical(load_log(owner)$status, c("replaced", "loaded"))
  expect_loaded_as_oracle(owner, 202609L)
})

test_that("two loads never run at once", {
  dbname <- local_migrated_db()
  other <- local_test_db("loader", dbname = dbname)
  DBI::dbGetQuery(other, "SELECT pg_advisory_lock($1, $2)", params = as.list(load_lock))
  expect_error(load_fixture(202609L, dbname), "Another load is running")
})

test_that("a file for another month is refused, and changes nothing in core", {
  dbname <- local_loaded_db(202608L)
  con <- local_test_db("owner", dbname = dbname)
  before <- core_state(con)
  for (ym in c(202610L, 202601L)) {
    expect_error(
      suppressMessages(load_month(ym, file = fixture_file(202609L), dbname = dbname)),
      sprintf("The staged file holds 2026-09, not %d-%02d.", ym %/% 100L, ym %% 100L)
    )
  }
  # The dimensions too: no month that was never loaded in first_seen or last_seen
  expect_identical(core_state(con), before)
  expect_identical(load_log(con)$status, c("loaded", "failed", "failed"))
})

test_that("a new month that fails its check changes nothing in core, dimensions included", {
  dbname <- local_loaded_db(202608L)
  con <- local_test_db("owner", dbname = dbname)
  before <- core_state(con)
  real_check <- check_month
  testthat::local_mocked_bindings(check_month = function(con, year_month, source_rows) {
    real_check(con, year_month, source_rows + 1)
  })
  expect_error(suppressMessages(load_fixture(202609L, dbname)), "The check of 202609 failed")
  expect_identical(core_state(con), before)
  expect_identical(max(before$practices$last_seen), 202608L)
})

test_that("blank ITEMS, a measure that is not a number, and no items are refused", {
  dbname <- local_migrated_db()
  row <- source_line
  load_rows <- function(...) {
    csv <- local_source_file(c(source_header(), row(), ...), zip = FALSE)
    suppressMessages(load_month(209901L, file = csv, dbname = dbname))
  }
  expect_no_error(load_rows())
  # A blank ITEMS in a pair of two rows would otherwise be left out of the sum
  expect_error(load_rows(row(ITEMS = "")), 'invalid input syntax for type integer: ""')
  expect_error(load_rows(row(NIC = '"NaN"')), "a measure that is negative or not finite")
  expect_error(load_rows(row(ACTUAL_COST = '"-1."')), "a measure that is negative or not finite")
  expect_error(load_rows(row(ITEMS = "0")), "1 staged rows have ITEMS below 1")
  con <- local_test_db("owner", dbname = dbname)
  expect_identical(load_log(con)$status, c("loaded", rep("failed", 4)))
  expect_identical(nrow(loaded_fact(con)), 1L)
})

test_that("nothing after the commit can mark a live month failed", {
  dbname <- local_migrated_db()
  testthat::local_mocked_bindings(
    refresh_after_swap = function(con) stop("statistics went wrong")
  )
  expect_warning(
    suppressMessages(load_fixture(202609L, dbname)),
    paste(
      "202609 is loaded, but the statistics of core.prescribing and the rollups were not",
      "refreshed: statistics went wrong"
    ),
    fixed = TRUE
  )
  con <- local_test_db("owner", dbname = dbname)
  expect_identical(load_log(con)$status, "loaded")
  expect_loaded_as_oracle(con, 202609L)
  # And a failure recorded late never overwrites a committed load
  load_id <- DBI::dbGetQuery(con, "SELECT load_id FROM core.load_log")$load_id
  suppressMessages(fail_load(con, con, 202609L, load_id, "too late"))
  expect_identical(load_log(con)$status, "loaded")
})

# The condition R signals for Ctrl-C
interrupt_condition <- function() {
  signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
}

test_that("an interrupt during the swap rolls it back, and is reported as such", {
  dbname <- local_loaded_db(202609L)
  testthat::local_mocked_bindings(rename_new_indexes = function(con, ym) interrupt_condition())
  expect_error(
    suppressMessages(load_fixture(202609L, dbname)),
    "The swap of 202609 was interrupted and rolled back."
  )
  con <- local_test_db("owner", dbname = dbname)
  expect_loaded_as_oracle(con, 202609L)
  expect_identical(load_log(con)$status, c("loaded", "failed"))
  expect_identical(leftovers(con), data.frame(new_tables = 0L, staged = 0L))
})

test_that("an interrupt outside the swap still records the failure and cleans up", {
  dbname <- local_migrated_db()
  real_build <- build_month
  testthat::local_mocked_bindings(build_month = function(con, year_month) {
    real_build(con, year_month)
    interrupt_condition()
  })
  expect_error(
    suppressMessages(load_fixture(202609L, dbname)), "The load of 202609 was interrupted."
  )
  con <- local_test_db("owner", dbname = dbname)
  log <- load_log(con)
  expect_identical(log$status, "failed")
  expect_identical(log$error, "Interrupted.")
  expect_identical(leftovers(con), data.frame(new_tables = 0L, staged = 0L))
  expect_length(partitions(con), 0L)
})

test_that("a load cut short is marked failed by the next one", {
  dbname <- local_migrated_db()
  loader <- local_test_db("loader", dbname = dbname)
  DBI::dbExecute(loader, "INSERT INTO core.load_log (year_month) VALUES (202608)")
  suppressMessages(load_fixture(202609L, dbname))
  log <- load_log(loader)
  expect_identical(log$status, c("failed", "loaded"))
  expect_match(log$error[1], "Interrupted")
})

test_that("a downloaded month is found, loaded and deleted; a bad download is deleted too", {
  dbname <- local_migrated_db()
  dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    month_resource = function(year_month) {
      list(name = paste0("EPD_SNOMED_", year_month), url = "https://example.invalid/csv",
           sha256 = fixture_sha256(year_month))
    },
    download_month = function(year_month, ...) {
      file <- file.path(dir, sprintf("EPD_SNOMED_%d.zip", year_month))
      file.copy(fixture_file(year_month), file)
      file
    }
  )
  messages <- testthat::capture_messages(load_month(202609L, dbname = dbname))
  expect_true(any(startsWith(messages, "find: ")) && any(startsWith(messages, "download: ")))
  expect_false(file.exists(file.path(dir, "EPD_SNOMED_202609.zip")))
  con <- local_test_db("owner", dbname = dbname)
  expect_loaded_as_oracle(con, 202609L)
  expect_identical(
    DBI::dbGetQuery(con, "SELECT source_url FROM core.load_log")$source_url,
    "https://example.invalid/csv"
  )

  # A download whose content does not match the portal's hash is removed
  testthat::local_mocked_bindings(month_resource = function(year_month) {
    list(name = "x", url = "https://example.invalid/csv", sha256 = strrep("0", 64))
  })
  expect_error(suppressMessages(load_month(202608L, dbname = dbname)), "differs from the portal's")
  expect_false(file.exists(file.path(dir, "EPD_SNOMED_202608.zip")))
})

test_that("a damaged download is deleted; a verified one is kept when the database fails", {
  dbname <- local_migrated_db()
  dir <- withr::local_tempdir()
  damaged <- function(year_month) {
    file <- file.path(dir, sprintf("EPD_SNOMED_%d.zip", year_month))
    bytes <- readBin(fixture_file(year_month), "raw", file.size(fixture_file(year_month)))
    writeBin(bytes[seq_len(length(bytes) %/% 2L)], file)
    file
  }
  testthat::local_mocked_bindings(
    month_resource = function(year_month) {
      list(name = "x", url = "https://example.invalid/csv", sha256 = fixture_sha256(year_month))
    },
    download_month = function(year_month, ...) damaged(year_month)
  )
  expect_error(suppressMessages(load_month(202609L, dbname = dbname)), "Could not read the archive")
  expect_false(file.exists(file.path(dir, "EPD_SNOMED_202609.zip")))

  testthat::local_mocked_bindings(
    download_month = function(year_month, ...) {
      file <- file.path(dir, sprintf("EPD_SNOMED_%d.zip", year_month))
      file.copy(fixture_file(year_month), file)
      file
    },
    build_month = function(con, year_month) stop("the database is full")
  )
  expect_error(suppressMessages(load_month(202609L, dbname = dbname)), "the database is full")
  expect_true(file.exists(file.path(dir, "EPD_SNOMED_202609.zip")))
})
