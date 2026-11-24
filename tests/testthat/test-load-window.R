# load_window() (spec section 4; P2-02): loads the n most recent published
# months missing from load_log, oldest first. The portal and the download are
# mocked; the months are the fixtures.

# Mocks the portal: the months in `published` are listed, and a download
# copies the month's fixture file, or fails for the months in `broken`
local_portal <- function(dir, broken = integer(), published = fixture_months(),
                         env = parent.frame()) {
  testthat::local_mocked_bindings(
    epd_resources = function() {
      data.frame(year_month = rev(published), name = "x", sha256 = NA_character_)
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
  months <- c(202607L, 202608L, 202609L)
  messages <- testthat::capture_messages(res <- load_window(dbname = dbname))
  expect_true("Loading 3 months, oldest first: 202607, 202608, 202609\n" %in% messages)
  expect_true(any(startsWith(messages, "Loaded 3 months in ")))
  expect_false(any(startsWith(messages, "Dropped")))
  expect_identical(res$year_month, months)
  expect_identical(res$source_rows, rep(3984, 3))
  expect_identical(res$loaded_rows, as.numeric(oracle_month_totals(months)$fact_rows))
  expect_true(all(res$seconds > 0))
  con <- local_test_db("owner", dbname = dbname)
  log <- load_log(con)
  expect_equal(res$loaded_rows, as.numeric(log$loaded_rows))
  expect_identical(log$year_month, months)
  expect_identical(log$status, rep("loaded", 3))
  expect_loaded_as_oracle(con, months)

  expect_message(
    res <- load_window(dbname = dbname),
    "Nothing to load: the 3 most recent published months, 202607 to 202609, are loaded.",
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
  expect_message(
    load_window(1, dbname = dbname),
    "Nothing to load: the most recent published month, 202609, is loaded.", fixed = TRUE
  )
})

test_that("a month dropped from the window is loaded again once the window is larger", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "2")
  dbname <- local_loaded_db(c(202607L, 202608L, 202609L))
  con <- local_test_db("owner", dbname = dbname)
  expect_identical(load_log(con)$status, c("dropped", "loaded", "loaded"))
  local_portal(withr::local_tempdir())
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  res <- suppressMessages(load_window(dbname = dbname))
  expect_identical(res$year_month, 202607L)
  expect_identical(load_log(con)$status, c("dropped", "loaded", "loaded", "loaded"))
  expect_loaded_as_oracle(con, c(202607L, 202608L, 202609L))
})

test_that("a month older than every month the window keeps is left out, with a message", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  dbname <- local_loaded_db(c(202607L, 202608L, 202609L))
  con <- local_test_db("owner", dbname = dbname)
  log <- load_log(con)
  # The portal no longer lists 202609, so the 3 most recent it lists start at 202606
  local_portal(withr::local_tempdir(), published = setdiff(fixture_months(), 202609L))
  expect_message(
    res <- load_window(dbname = dbname),
    paste(
      "Leaving out 202606: the window keeps the most recent 3 months (PREXP_WINDOW_MONTHS),",
      "from 202607 on."
    ),
    fixed = TRUE
  )
  expect_identical(nrow(res), 0L)
  expect_identical(load_log(con), log)
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

test_that("a portal that lists no month stops the run before the database is opened", {
  withr::local_envvar(PREXP_DB_NAME = NA)
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw('{"success": true, "result": {"resources": []}}'))
  })
  expect_error(load_window(), "The portal lists no monthly file", fixed = TRUE)
})

test_that("n is a whole number of months, at most the window", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "12", PREXP_DB_NAME = NA)
  # Refused before the portal is asked or a database is opened
  testthat::local_mocked_bindings(
    epd_resources = function() stop("load_window() asked the portal", call. = FALSE)
  )
  for (bad in list(0, 13, 1.5, -1, Inf, NA, NA_real_, TRUE, "12", c(1, 2))) {
    expect_error(
      load_window(bad), "`n` must be a whole number of months from 1 to the window, 12",
      info = paste(format(bad), collapse = ", ")
    )
  }
})
