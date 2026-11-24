# load_window() (spec section 4; P2-02): loads the n most recent published
# months missing from load_log, oldest first, so nothing is dropped on the way.
# The portal and the download are mocked; the months are the fixtures.

# Mocks the portal: the fixture months are published, and a download copies
# the month's fixture file, or fails for the months in `broken`
local_portal <- function(dir, broken = integer(), env = parent.frame()) {
  testthat::local_mocked_bindings(
    epd_resources = function() {
      data.frame(year_month = rev(fixture_months()), name = "x", sha256 = NA_character_)
    },
    month_resource = function(year_month) {
      list(name = paste0("EPD_SNOMED_", year_month), url = "https://example.invalid/csv",
           sha256 = fixture_sha256(year_month))
    },
    download_month = function(year_month, ...) {
      if (year_month %in% broken) {
        stop("The portal did not answer.", call. = FALSE)
      }
      file <- file.path(dir, sprintf("EPD_SNOMED_%d.zip", year_month))
      file.copy(fixture_file(year_month), file)
      file
    },
    .env = env
  )
}

test_that("the most recent months missing are loaded oldest first, then nothing", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  dbname <- local_migrated_db()
  local_portal(withr::local_tempdir())
  messages <- testthat::capture_messages(res <- load_window(dbname = dbname))
  expect_true("Loading 3 months, oldest first: 202607, 202608, 202609\n" %in% messages)
  expect_true(any(startsWith(messages, "Loaded 3 months in ")))
  expect_false(any(startsWith(messages, "Dropped")))
  expect_identical(res$year_month, c(202607L, 202608L, 202609L))
  expect_identical(res$source_rows, rep(3984, 3))
  con <- local_test_db("owner", dbname = dbname)
  log <- load_log(con)
  expect_identical(log$year_month, c(202607L, 202608L, 202609L))
  expect_identical(log$status, rep("loaded", 3))
  expect_loaded_as_oracle(con, c(202607L, 202608L, 202609L))

  expect_message(
    res <- load_window(dbname = dbname),
    "Nothing to load: the most recent published months, 202607 to 202609, are all loaded.",
    fixed = TRUE
  )
  expect_identical(nrow(res), 0L)
  expect_identical(nrow(load_log(con)), 3L)
})

test_that("only the months missing are loaded, and n can be smaller than the window", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  dbname <- local_loaded_db(202608L)
  local_portal(withr::local_tempdir())
  res <- suppressMessages(load_window(2, dbname = dbname))
  expect_identical(res$year_month, 202609L)
  con <- local_test_db("owner", dbname = dbname)
  expect_identical(load_log(con)$year_month, c(202608L, 202609L))
})

test_that("a month that fails stops the run, and running again carries on", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  dbname <- local_migrated_db()
  dir <- withr::local_tempdir()
  local_portal(dir, broken = 202608L)
  expect_error(
    suppressMessages(load_window(dbname = dbname)),
    paste(
      "Loading 202608 failed, after 1 of 3 months: The portal did not answer.",
      "Run load_window() again to carry on."
    ),
    fixed = TRUE
  )
  con <- local_test_db("owner", dbname = dbname)
  expect_identical(load_log(con)$status, c("loaded", "failed"))

  local_portal(dir)
  res <- suppressMessages(load_window(dbname = dbname))
  expect_identical(res$year_month, c(202608L, 202609L))
  expect_identical(load_log(con)$status, c("loaded", "failed", "loaded", "loaded"))
})

test_that("n is a whole number of months, at most the window", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "12")
  for (bad in list(0, 13, 1.5, NA, "12", c(1, 2))) {
    expect_error(load_window(bad), "`n` must be a whole number of months from 1 to the window, 12")
  }
})
