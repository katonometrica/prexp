# The fetch timing log (spec section 5.4; P3-04): one JSON line on stdout per
# fetch, with the arguments hashed; timing_summary() reads it back.

# The lines a call writes to stdout, with the log on
logged <- function(expr) {
  withr::local_envvar(PREXP_LOG = "on")
  lines <- utils::capture.output(value <- force(expr))
  list(value = value, lines = lines)
}

test_that("each fetch writes one line: time, function, hashed arguments, rows, ms", {
  con <- fixture_app()
  out <- logged(fetch_search_drugs(con, "atorvastatin", limit = 7))
  expect_length(out$lines, 1L)
  line <- jsonlite::fromJSON(out$lines)
  expect_identical(names(line), c("time", "function", "args", "rows", "ms"))
  expect_match(line$time, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$")
  expect_lt(abs(as.numeric(difftime(
    as.POSIXct(line$time, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"), Sys.time(), units = "secs"
  ))), 60)
  expect_identical(line[["function"]], "fetch_search_drugs")
  expect_match(line$args, "^[0-9a-f]{16}$")
  expect_identical(line$rows, nrow(out$value))
  expect_true(is.numeric(line$ms) && line$ms >= 0 && line$ms < 5000)
  # The search text never reaches the log, in any case
  expect_no_match(out$lines, "atorva", ignore.case = TRUE)
})

test_that("the hash names the request: the same arguments, the same hash", {
  con <- fixture_app()
  months <- c(202608L, 202609L)
  hash <- function(expr) jsonlite::fromJSON(logged(expr)$lines)$args
  items <- hash(fetch_drug_series(con, "chemical", 1, months, "items"))
  expect_identical(hash(fetch_drug_series(con, "chemical", "1", months, "items")), items)
  expect_false(identical(hash(fetch_drug_series(con, "chemical", 1, months, "nic")), items))
  expect_false(identical(hash(fetch_drug_series(con, "presentation", 1, months, "items")), items))
  expect_false(identical(hash(fetch_drug_series(con, "chemical", 2, months, "items")), items))
  expect_identical(
    hash(fetch_search_drugs(con, " Atorva ")), hash(fetch_search_drugs(con, "Atorva"))
  )
})

test_that("every fetch logs once, and a refused argument logs nothing", {
  con <- fixture_app()
  months <- c(202608L, 202609L)
  calls <- list(
    fetch_window = quote(fetch_window(con)),
    fetch_search_practices = quote(fetch_search_practices(con, "n81")),
    fetch_drug_presentations = quote(fetch_drug_presentations(con, 1, months)),
    fetch_practice_profile = quote(fetch_practice_profile(con, 1)),
    fetch_practice_series = quote(fetch_practice_series(con, 1, months)),
    fetch_practice_top_drugs = quote(fetch_practice_top_drugs(con, 1, months)),
    fetch_region_comparison = quote(fetch_region_comparison(con, "chemical", 1, months, "nic"))
  )
  for (fetch in names(calls)) {
    lines <- logged(eval(calls[[fetch]]))$lines
    expect_length(lines, 1L)
    expect_identical(jsonlite::fromJSON(lines)[["function"]], fetch)
  }
  expect_length(
    logged(try(fetch_search_drugs(con, "a"), silent = TRUE))$lines, 0L
  )
})

test_that("a failed query logs its line with error, then fails", {
  local_test_db("app")
  con <- db_connect("app", dbname = local_fixture_db())
  DBI::dbDisconnect(con)
  withr::local_envvar(PREXP_LOG = "on")
  lines <- utils::capture.output(expect_error(fetch_window(con)))
  expect_length(lines, 1L)
  line <- jsonlite::fromJSON(lines)
  expect_identical(names(line), c("time", "function", "args", "rows", "ms", "error"))
  expect_null(line$rows)
  expect_true(line$error)
})

test_that("PREXP_LOG = off writes nothing", {
  con <- fixture_app()
  for (value in c("off", "OFF", "false", "0")) {
    withr::local_envvar(PREXP_LOG = value)
    lines <- utils::capture.output(res <- fetch_window(con))
    expect_identical(length(lines), 0L, label = value)
  }
  withr::local_envvar(PREXP_LOG = NA)
  expect_true(log_enabled())
})

test_that("timing_summary() gives count, errors, p50 and p95 per function", {
  log <- withr::local_tempfile()
  line <- function(fetch, ms, error = FALSE) {
    sprintf(
      '{"time":"2026-11-24T13:45:12.345Z","function":"%s","args":"a","rows":%s,"ms":%s%s}',
      fetch, if (error) "null" else "3", ms, if (error) ',"error":true' else ""
    )
  }
  writeLines(c(
    "Listening on http://0.0.0.0:3838",
    vapply(sample(1:100), function(ms) line("fetch_window", ms), ""),
    vapply(1:20, function(ms) line("fetch_search_drugs", ms, error = ms == 20), ""),
    "{\"time\":\"broken",
    "{\"note\":\"not a fetch\"}"
  ), log)
  summary <- timing_summary(log)
  expect_s3_class(summary, "tbl_df")
  expect_identical(
    as.data.frame(summary),
    data.frame(
      "function" = c("fetch_search_drugs", "fetch_window"), count = c(20L, 100L),
      errors = c(1L, 0L), p50 = c(10, 50), p95 = c(19, 95), check.names = FALSE
    )
  )
  # The nearest rank, a time some fetch took
  expect_identical(nearest_rank(c(4, 1, 3, 2), 0.95), 4)
  expect_identical(nearest_rank(c(4, 1, 3, 2), 0.5), 2)
  expect_identical(nearest_rank(7, 0.95), 7)
  # Several files at once; none with timing lines gives no rows
  expect_identical(timing_summary(c(log, log))$count, c(40L, 200L))
  empty <- withr::local_tempfile(lines = "nothing here")
  expect_identical(nrow(timing_summary(empty)), 0L)
})

test_that("the log reads back: the lines fetches write are what timing_summary() reads", {
  con <- fixture_app()
  out <- unlist(lapply(1:5, function(i) logged(fetch_window(con))$lines))
  log <- withr::local_tempfile(lines = out)
  summary <- timing_summary(log)
  expect_identical(summary[["function"]], "fetch_window")
  expect_identical(summary$count, 5L)
})
