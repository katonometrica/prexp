# load_latest() (spec sections 4 and 7; P6-03): the monthly scheduled task.
# It loads the newest published month and any month a run missed, as
# load_window() does, then reloads each live month whose published hash has
# changed. The portal and the download are mocked; the months are the fixtures.

# The portal's hashes of the fixture months, named by month
fixture_hashes <- function(months) {
  stats::setNames(vapply(months, fixture_sha256, ""), months)
}

# Sets the hash a live month was loaded with, as if an earlier publication of
# it had been loaded
set_loaded_hash <- function(dbname, ym, hash) {
  owner <- local_test_db("owner", dbname = dbname)
  DBI::dbExecute(owner, "
    UPDATE core.load_log SET source_sha256 = $2
    WHERE year_month = $1 AND status = 'loaded'", params = list(ym, hash))
}

test_that("the newest month is loaded, dropping the oldest; then there is nothing new", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "2")
  dbname <- local_loaded_db(c(202607L, 202608L))
  months <- c(202607L, 202608L, 202609L)
  local_portal(withr::local_tempdir(), published = months, hashes = fixture_hashes(months))
  messages <- testthat::capture_messages(res <- load_latest(dbname = dbname))
  expect_true("Loading 1 month, oldest first: 202609\n" %in% messages)
  expect_true("No loaded month has been published again.\n" %in% messages)
  expect_identical(res$year_month, 202609L)
  expect_identical(res$reloaded, FALSE)
  con <- local_test_db("owner", dbname = dbname)
  log <- load_log(con)
  expect_identical(log$status[log$year_month == 202607L], "dropped")
  expect_identical(sort(log$year_month[log$status == "loaded"]), c(202608L, 202609L))
  expect_loaded_as_oracle(con, c(202608L, 202609L))

  # Nothing new: a message each, nothing loaded, the log as it was
  messages <- testthat::capture_messages(res <- load_latest(dbname = dbname))
  expect_identical(messages, c(
    "Nothing to load: the 2 most recent published months, 202608 to 202609, are loaded.\n",
    "No loaded month has been published again.\n"
  ))
  expect_identical(nrow(res), 0L)
  expect_identical(load_log(con), log)
})

test_that("a month published again is reloaded, once", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  months <- c(202607L, 202608L, 202609L)
  dbname <- local_loaded_db(months)
  local_portal(withr::local_tempdir(), published = months, hashes = fixture_hashes(months))
  set_loaded_hash(dbname, 202608L, strrep("0", 64))
  messages <- testthat::capture_messages(res <- load_latest(dbname = dbname))
  expect_true("Reloading 202608: the portal has published it again.\n" %in% messages)
  expect_identical(res$year_month, 202608L)
  expect_identical(res$reloaded, TRUE)
  expect_identical(res$source_rows, 3984)
  con <- local_test_db("owner", dbname = dbname)
  log <- load_log(con)
  august <- log[log$year_month == 202608L, ]
  expect_identical(august$status, c("replaced", "loaded"))
  hash <- DBI::dbGetQuery(con, "
    SELECT source_sha256 FROM core.load_log WHERE year_month = 202608 AND status = 'loaded'")
  expect_identical(hash$source_sha256, unname(fixture_hashes(202608L)))
  expect_loaded_as_oracle(con, months)
  # Now loaded with the published hash: nothing to reload
  res <- suppressMessages(load_latest(dbname = dbname))
  expect_identical(nrow(res), 0L)
})

test_that("a month with no hash, on the portal or in the log, is never reloaded", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  months <- c(202607L, 202608L, 202609L)
  dbname <- local_loaded_db(months)
  # 202607 was loaded without a hash; the portal lists none for 202608
  set_loaded_hash(dbname, 202607L, NA_character_)
  set_loaded_hash(dbname, 202608L, strrep("0", 64))
  hashes <- fixture_hashes(months)
  hashes[["202608"]] <- NA_character_
  local_portal(withr::local_tempdir(), published = months, hashes = hashes)
  messages <- testthat::capture_messages(res <- load_latest(dbname = dbname))
  expect_true("No loaded month has been published again.\n" %in% messages)
  expect_identical(nrow(res), 0L)
  # A hash in other letters is the same hash, in the log or on the portal
  set_loaded_hash(dbname, 202609L, toupper(fixture_hashes(202609L)))
  res <- suppressMessages(load_latest(dbname = dbname))
  expect_identical(nrow(res), 0L)
  set_loaded_hash(dbname, 202609L, fixture_hashes(202609L))
  local_portal(withr::local_tempdir(), published = months, hashes = toupper(hashes))
  res <- suppressMessages(load_latest(dbname = dbname))
  expect_identical(nrow(res), 0L)
})

test_that("a failed reload stops, naming the month, and leaves its data live", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  months <- c(202607L, 202608L, 202609L)
  dbname <- local_loaded_db(months)
  dir <- withr::local_tempdir()
  local_portal(dir, published = months, hashes = fixture_hashes(months), broken = 202608L)
  set_loaded_hash(dbname, 202608L, strrep("0", 64))
  expect_error(
    suppressMessages(load_latest(dbname = dbname)),
    paste(
      "Reloading 202608, published again, failed: .*The portal did not answer.",
      "The month's previous data stays live; the next run tries again."
    )
  )
  con <- local_test_db("owner", dbname = dbname)
  log <- load_log(con)
  expect_identical(sort(log$year_month[log$status == "loaded"]), months)
  expect_identical(log$status[log$year_month == 202608L], c("loaded", "failed"))
  expect_loaded_as_oracle(con, months)

  # The failed attempt recorded the new hash; the next run still tries again
  local_portal(dir, published = months, hashes = fixture_hashes(months))
  res <- suppressMessages(load_latest(dbname = dbname))
  expect_identical(res$year_month, 202608L)
  expect_identical(res$reloaded, TRUE)
  log <- load_log(con)
  expect_identical(log$status[log$year_month == 202608L], c("replaced", "failed", "loaded"))
  expect_loaded_as_oracle(con, months)
})

test_that("a reload whose swap committed before an error does not say the old data is live", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  months <- c(202607L, 202608L, 202609L)
  dbname <- local_loaded_db(months)
  local_portal(withr::local_tempdir(), published = months, hashes = fixture_hashes(months))
  set_loaded_hash(dbname, 202608L, strrep("0", 64))
  real_swap <- swap_month
  testthat::local_mocked_bindings(swap_month = function(...) {
    real_swap(...)
    stop("server closed the connection unexpectedly", call. = FALSE)
  })
  err <- tryCatch(suppressMessages(load_latest(dbname = dbname)), error = function(e) e)
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "Reloading 202608, published again, failed: ", fixed = TRUE)
  expect_match(conditionMessage(err), "202608 is loaded", fixed = TRUE)
  expect_no_match(conditionMessage(err), "previous data stays live", fixed = TRUE)
})

test_that("a portal that fails after the loads stops the run, naming what was loaded", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "2")
  dbname <- local_loaded_db(c(202607L, 202608L))
  months <- c(202607L, 202608L, 202609L)
  local_portal(withr::local_tempdir(), published = months, hashes = fixture_hashes(months))
  # The first listing answers, as load_window() asks for it; the second fails
  listing <- epd_resources()
  calls <- new.env(parent = emptyenv())
  calls$n <- 0L
  testthat::local_mocked_bindings(epd_resources = function() {
    calls$n <- calls$n + 1L
    if (calls$n > 1L) {
      stop("The portal did not answer.", call. = FALSE)
    }
    listing
  })
  expect_error(
    suppressMessages(load_latest(dbname = dbname)),
    paste(
      "Checking the loaded months against the portal failed, after loading 202609:",
      "The portal did not answer. The next run checks them again."
    ),
    fixed = TRUE
  )
})

test_that("a failed load of the newest month stops before any reload", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  dbname <- local_loaded_db(c(202607L, 202608L))
  months <- c(202607L, 202608L, 202609L)
  local_portal(
    withr::local_tempdir(), published = months, hashes = fixture_hashes(months),
    broken = 202609L
  )
  set_loaded_hash(dbname, 202608L, strrep("0", 64))
  expect_error(
    suppressMessages(load_latest(dbname = dbname)),
    "Loading 202609 failed, after 0 of 1 month"
  )
  con <- local_test_db("owner", dbname = dbname)
  log <- load_log(con)
  expect_identical(nrow(log[log$year_month == 202608L, ]), 1L)
})

test_that("a new month is loaded, then each month published again that stays in the window", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "3")
  dbname <- local_loaded_db(c(202606L, 202607L, 202608L))
  months <- c(202606L, 202607L, 202608L, 202609L)
  local_portal(withr::local_tempdir(), published = months, hashes = fixture_hashes(months))
  # All three were published again; loading 202609 drops 202606, which is
  # then no longer live, so it is not reloaded
  for (ym in c(202606L, 202607L, 202608L)) {
    set_loaded_hash(dbname, ym, strrep("0", 64))
  }
  messages <- testthat::capture_messages(res <- load_latest(dbname = dbname))
  expect_true("Loading 1 month, oldest first: 202609\n" %in% messages)
  expect_identical(
    grep("^Reloading", messages, value = TRUE),
    paste0("Reloading ", c(202607L, 202608L), ": the portal has published it again.\n")
  )
  live <- c(202607L, 202608L, 202609L)
  expect_identical(res$year_month, c(202609L, 202607L, 202608L))
  expect_identical(res$reloaded, c(FALSE, TRUE, TRUE))
  expect_identical(res$source_rows, rep(3984, 3))
  totals <- oracle_month_totals(live)
  expect_identical(
    res$loaded_rows, as.numeric(totals$fact_rows[match(res$year_month, totals$year_month)])
  )
  expect_true(all(res$seconds > 0))
  con <- local_test_db("owner", dbname = dbname)
  log <- load_log(con)
  expect_identical(log$status[log$year_month == 202606L], "dropped")
  expect_identical(log$status[log$year_month == 202607L], c("replaced", "loaded"))
  expect_identical(log$status[log$year_month == 202608L], c("replaced", "loaded"))
  expect_loaded_as_oracle(con, live)
})
