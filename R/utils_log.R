# The fetch timing log (spec section 5.4): one JSON line on stdout per fetch,
# for the p95 benchmark (P4-08) and for spotting slow queries in production.
#
#   {"time":"2026-11-24T13:45:12.345Z","function":"fetch_drug_series",
#    "args":"3f2a9c0d41b7e865","rows":12,"ms":4.21}
#
# time is when the fetch finished, in UTC; args is a hash of the fetch's
# arguments after they are checked, so identical requests share it, while the
# values, search text included, never reach the log; rows and ms are the rows
# returned and the time from sending the query to the tibble. A query that
# fails gives "rows":null and "error":true. PREXP_LOG=off turns the log off,
# as the tests do; it is on otherwise, in the app and the jobs.

log_enabled <- function() {
  !tolower(Sys.getenv("PREXP_LOG", "on")) %in% c("off", "false", "0", "no")
}

# The first 16 hex digits of the SHA-256 of the arguments as JSON
args_hash <- function(args) {
  json <- jsonlite::toJSON(args, auto_unbox = TRUE, digits = NA, na = "null", null = "null")
  substr(tools::sha256sum(bytes = charToRaw(enc2utf8(as.character(json)))), 1L, 16L)
}

# Writes one fetch's line, if the log is on. `started` is the Sys.time() when
# the query was sent.
log_fetch <- function(fetch, args, rows, started, error = FALSE) {
  if (!log_enabled()) {
    return(invisible())
  }
  finished <- Sys.time()
  line <- list(
    time = format(finished, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    "function" = fetch,
    args = args_hash(args),
    rows = if (error) NULL else rows,
    ms = round(1000 * as.numeric(difftime(finished, started, units = "secs")), 2)
  )
  if (error) {
    line$error <- TRUE
  }
  json <- jsonlite::toJSON(line, auto_unbox = TRUE, digits = NA, null = "null")
  cat(json, "\n", sep = "", file = stdout())
  invisible()
}

#' Fetch times from a log, per function
#'
#' Reads the fetch timing lines from a log, such as the app's standard output,
#' and summarises them per fetch function, for the p95 benchmark. Other lines
#' in the file are skipped.
#'
#' A percentile is the nearest rank: the p95 is the smallest time that at least
#' 95% of the fetches took no longer than, a time some fetch actually took.
#'
#' @param path A log file, or several.
#' @return A tibble, one row per function in alphabetical order: `function`,
#'   `count` (integer, its fetches), `errors` (integer, how many failed), and
#'   `p50` and `p95` (double, milliseconds, over every fetch, failed ones
#'   included). No rows for a log without timing lines.
#' @examples
#' log <- tempfile()
#' writeLines(c(
#'   "Listening on http://0.0.0.0:3838",
#'   sprintf(
#'     '{"time":"2026-11-24T13:45:1%d.000Z","function":"fetch_window","rows":1,"ms":%s}',
#'     1:4, c(0.4, 0.6, 0.5, 2.1)
#'   )
#' ), log)
#' timing_summary(log)
#' @export
timing_summary <- function(path) {
  lines <- unlist(lapply(path, readLines, warn = FALSE, encoding = "UTF-8"))
  lines <- lines[startsWith(lines, "{\"time\":") & grepl("\"function\":\"fetch_", lines)]
  timing <- lapply(lines, function(line) {
    tryCatch(jsonlite::fromJSON(line), error = function(e) NULL)
  })
  timing <- Filter(function(x) is.list(x) && is.numeric(x$ms) && is.character(x[["function"]]),
                   timing)
  fetch <- vapply(timing, function(x) x[["function"]], character(1))
  ms <- vapply(timing, function(x) as.numeric(x$ms), numeric(1))
  failed <- vapply(timing, function(x) isTRUE(x$error), logical(1))
  names <- sort(unique(fetch), method = "radix")
  tibble::as_tibble(list(
    "function" = names,
    count = vapply(names, function(f) sum(fetch == f), integer(1), USE.NAMES = FALSE),
    errors = vapply(names, function(f) sum(failed[fetch == f]), integer(1), USE.NAMES = FALSE),
    p50 = vapply(names, function(f) nearest_rank(ms[fetch == f], 0.5), numeric(1),
                 USE.NAMES = FALSE),
    p95 = vapply(names, function(f) nearest_rank(ms[fetch == f], 0.95), numeric(1),
                 USE.NAMES = FALSE)
  ))
}

# The p-th percentile by nearest rank: the value at rank ceiling(p * n) of the
# sorted values
nearest_rank <- function(x, p) {
  sort(x)[ceiling(p * length(x))]
}
