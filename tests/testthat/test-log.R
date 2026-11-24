# The fetch timing log (spec section 5.4; P3-04): one JSON line on stdout per
# fetch, with the arguments hashed under a key; timing_summary() reads it back.

# The lines a call writes to the timing log, sent to a test connection: on
# their own they go to the process's standard output, which capture.output()
# cannot see
log_lines <- function(expr) {
  to <- textConnection(NULL, "w")
  withr::defer(close(to))
  withr::local_options(prexp.log_to = to)
  force(expr)
  textConnectionValue(to)
}

# The same with the log on, and the call's value
logged <- function(expr) {
  withr::local_envvar(PREXP_LOG = "on")
  value <- NULL
  lines <- log_lines(value <- expr)
  list(value = value, lines = lines)
}

test_that("each fetch writes one line: time, function, hashed arguments, rows, ms", {
  # Away from UTC, so that a local time stamped Z would be hours out
  withr::local_timezone("America/New_York")
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

test_that("ms is the query's time, in milliseconds", {
  con <- fixture_app()
  local_mocked_bindings(query_sql = function(query) "SELECT pg_sleep(0.2) IS NULL AS slept")
  started <- Sys.time()
  out <- logged(fetch_window(con))
  wall <- 1000 * as.numeric(difftime(Sys.time(), started, units = "secs"))
  ms <- jsonlite::fromJSON(out$lines)$ms
  expect_gte(ms, 190)
  expect_lte(ms, wall)
})

test_that("the hash names the request, under a key: the same arguments, the same hash", {
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
  # Not the plain hash of the arguments, which anyone could compute from a guess
  plain <- substr(tools::sha256sum(bytes = charToRaw('["Atorva",20]')), 1L, 16L)
  expect_false(identical(hash(fetch_search_drugs(con, "Atorva")), plain))
  # PREXP_LOG_KEY sets the key: one key, one hash; another key, another
  keyed <- function(key) {
    withr::local_envvar(PREXP_LOG_KEY = key)
    hash(fetch_search_drugs(con, "Atorva"))
  }
  expect_identical(keyed("first key"), keyed("first key"))
  expect_false(identical(keyed("first key"), keyed("second key")))
  expect_match(random_key(), "^[0-9a-f]{64}$")
  expect_false(identical(random_key(), random_key()))
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

test_that("a failed query logs its line with error, then fails; with the log off, no line", {
  local_test_db("app")
  con <- db_connect("app", dbname = local_fixture_db())
  DBI::dbDisconnect(con)
  out <- logged(expect_error(fetch_window(con)))
  expect_length(out$lines, 1L)
  line <- jsonlite::fromJSON(out$lines)
  expect_identical(names(line), c("time", "function", "args", "rows", "ms", "error"))
  expect_null(line$rows)
  expect_true(line$error)
  withr::local_envvar(PREXP_LOG = "off")
  expect_length(log_lines(expect_error(fetch_window(con))), 0L)
})

test_that("an interrupted query logs its line too, then is interrupted", {
  con <- fixture_app()
  interrupt <- structure(class = c("interrupt", "condition"), list(message = "", call = NULL))
  local_mocked_bindings(
    dbGetQuery = function(...) {
      signalCondition(interrupt)
      stop("not reached")
    },
    .package = "DBI"
  )
  out <- logged(tryCatch(fetch_window(con), interrupt = function(e) "interrupted"))
  expect_identical(out$value, "interrupted")
  expect_length(out$lines, 1L)
  expect_true(jsonlite::fromJSON(out$lines)$error)
})

test_that("PREXP_LOG = off writes nothing", {
  con <- fixture_app()
  for (value in c("off", "OFF", "false", "0", "no")) {
    withr::local_envvar(PREXP_LOG = value)
    expect_identical(length(log_lines(fetch_window(con))), 0L, label = value)
  }
  withr::local_envvar(PREXP_LOG = NA)
  expect_true(log_enabled())
})

test_that("the line goes to the process's standard output, whole, past any sink", {
  con <- fixture_app()
  withr::local_envvar(PREXP_LOG = "on")
  expect_identical(log_destination(), getConnection(1L))
  # capture.output() sinks the output, as shiny::renderPrint() does: the line
  # is not in it (it goes to the test run's own output instead)
  expect_length(utils::capture.output(res <- fetch_window(con)), 0L)
  # One write per line, the newline with it
  writes <- character()
  local_mocked_bindings(write_log_line = function(text) writes <<- c(writes, text))
  res <- fetch_window(con)
  expect_length(writes, 1L)
  expect_true(endsWith(writes, "}\n"))
  expect_identical(lengths(strsplit(writes, "\n", fixed = TRUE)), 1L)
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
    # The failed fetch is the fastest: leaving it out would move both percentiles
    vapply(1:20, function(ms) line("fetch_search_drugs", ms, error = ms == 1), ""),
    # Prefixes from docker compose logs and docker logs -t
    paste0("app-1  | ", line("fetch_drug_series", 5)),
    paste0("app-1  | ", line("fetch_drug_series", 6)),
    paste0("2026-11-24T13:45:12.345678901Z ", line("fetch_drug_series", 7)),
    # Lines to skip: broken, not a fetch, a fetch named only inside another
    # field, a time that is not one number
    "{\"time\":\"broken",
    "{\"note\":\"not a fetch\"}",
    '{"time":"t","note":{"function":"fetch_window"},"function":"other","ms":5}',
    '{"time":"t","function":"fetch_window","ms":[1,2]}',
    '{"time":"t","function":"fetch_window","ms":"slow"}'
  ), log)
  summary <- timing_summary(log)
  expect_s3_class(summary, "tbl_df")
  expect_identical(
    as.data.frame(summary),
    data.frame(
      "function" = c("fetch_drug_series", "fetch_search_drugs", "fetch_window"),
      count = c(3L, 20L, 100L), errors = c(0L, 1L, 0L), p50 = c(6, 10, 50), p95 = c(7, 19, 95),
      check.names = FALSE
    )
  )
  # The nearest rank, a time some fetch took: not rounding, not interpolation
  expect_identical(nearest_rank(c(4, 1, 3, 2), 0.95), 4)
  expect_identical(nearest_rank(c(4, 1, 3, 2), 0.5), 2)
  expect_identical(nearest_rank(as.numeric(1:5), 0.5), 3)
  expect_identical(nearest_rank(as.numeric(1:15), 0.95), 15)
  expect_identical(nearest_rank(7, 0.95), 7)
  # Several files at once; a log without timing lines gives no rows, and says so
  expect_identical(timing_summary(c(log, log))$count, c(6L, 40L, 200L))
  empty <- withr::local_tempfile(lines = "nothing here")
  expect_warning(none <- timing_summary(empty), "No fetch timing lines")
  expect_identical(nrow(none), 0L)
})

test_that("the log reads back: the lines fetches write are what timing_summary() reads", {
  con <- fixture_app()
  out <- unlist(lapply(1:5, function(i) logged(fetch_window(con))$lines))
  log <- withr::local_tempfile(lines = out)
  summary <- timing_summary(log)
  expect_identical(summary[["function"]], "fetch_window")
  expect_identical(summary$count, 5L)
})
