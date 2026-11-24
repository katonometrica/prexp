# The fetch timing log (spec section 5.4): one JSON line on the process's
# standard output per fetch, for the p95 benchmark (P4-08) and for spotting
# slow queries in production.
#
#   {"time":"2026-11-24T13:45:12.345Z","function":"fetch_drug_series",
#    "args":"3f2a9c0d41b7e865","rows":12,"ms":4.21}
#
# time is when the fetch finished, in UTC; args is a keyed hash of the fetch's
# arguments after they are checked, so identical requests share it, while the
# values, search text included, never reach the log; rows and ms are the rows
# returned and the time from sending the query to the tibble. A query that
# fails or is interrupted gives "rows":null and "error":true. PREXP_LOG=off
# turns the log off, as the tests do; it is on otherwise, in the app and the
# jobs.
#
# The line goes to connection 1, the process's own standard output, which no
# sink() diverts: shiny::renderPrint() and capture.output() would otherwise
# take a fetch's line into their output. The option prexp.log_to, a
# connection, sends the lines there instead, for the tests.

log_enabled <- function() {
  !tolower(Sys.getenv("PREXP_LOG", "on")) %in% c("off", "false", "0", "no")
}

# The first 16 hex digits of the SHA-256 of a key and the arguments as JSON.
# The key keeps the hash from giving the arguments away: with a plain hash,
# anyone with the log could hash likely search texts until one matched.
args_hash <- function(args) {
  json <- jsonlite::toJSON(args, auto_unbox = TRUE, digits = NA, na = "null", null = "null")
  text <- paste0(log_key(), "\n", enc2utf8(as.character(json)))
  substr(tools::sha256sum(bytes = charToRaw(text)), 1L, 16L)
}

# PREXP_LOG_KEY if set, so that hashes compare across restarts; otherwise a
# key drawn when the process first logs, so that they compare within it
log_key <- function() {
  key <- Sys.getenv("PREXP_LOG_KEY")
  if (nzchar(key)) {
    return(key)
  }
  if (is.null(log_state$key)) {
    log_state$key <- random_key()
  }
  log_state$key
}

log_state <- new.env(parent = emptyenv())

# 32 bytes from the system's random source, as hex. Without one (Windows), a
# hash of the clock and the process id, which no one reading the log knows.
random_key <- function() {
  bytes <- tryCatch(
    readBin("/dev/urandom", "raw", 32L),
    error = function(e) raw(), warning = function(w) raw()
  )
  if (length(bytes) != 32L) {
    bytes <- charToRaw(paste(format(Sys.time(), "%Y%m%d%H%M%OS6"), Sys.getpid()))
  }
  tools::sha256sum(bytes = bytes)
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
  write_log_line(paste0(json, "\n"))
  invisible()
}

# One write, the line and its newline together: a write of up to 4,096 bytes
# to a pipe arrives whole, so the lines of processes sharing one do not mix
write_log_line <- function(text) {
  cat(text, file = log_destination())
}

log_destination <- function() {
  to <- getOption("prexp.log_to")
  if (inherits(to, "connection")) to else getConnection(1L)
}

#' Fetch times from a log, per function
#'
#' Reads the fetch timing lines from a log, such as the app's standard output,
#' and summarises them per fetch function, for the p95 benchmark. A timing
#' line may carry a prefix, as `docker compose logs` and `docker logs -t` add
#' one: a record starts at the first `{"time":` in a line. Other lines, and
#' records whose `function` is not a fetch's name or whose `ms` is not one
#' number, are skipped.
#'
#' A percentile is the nearest rank: the p95 is the smallest time that at least
#' 95% of the fetches took no longer than, a time some fetch actually took.
#'
#' @param path A log file, or several.
#' @return A tibble, one row per function in alphabetical order: `function`,
#'   `count` (integer, its fetches), `errors` (integer, how many failed), and
#'   `p50` and `p95` (double, milliseconds, over every fetch, failed ones
#'   included). No rows, with a warning, for a log that has lines but no
#'   timing lines.
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
  start <- regexpr("{\"time\":", lines, fixed = TRUE)
  records <- substring(lines[start > 0L], start[start > 0L])
  timing <- lapply(records, function(record) {
    tryCatch(jsonlite::fromJSON(record), error = function(e) NULL)
  })
  timing <- Filter(is_timing_record, timing)
  if (length(timing) == 0L && length(lines) > 0L) {
    warning("No fetch timing lines in ", toString(path), ".", call. = FALSE)
  }
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

# A parsed record is a fetch's timing line: a fetch's name and one time
is_timing_record <- function(x) {
  fetch <- if (is.list(x)) x[["function"]] else NULL
  ms <- if (is.list(x)) x$ms else NULL
  is.character(fetch) && length(fetch) == 1L && startsWith(fetch, "fetch_") &&
    is.numeric(ms) && length(ms) == 1L && is.finite(ms)
}

# The p-th percentile by nearest rank: the value at rank ceiling(p * n) of the
# sorted values
nearest_rank <- function(x, p) {
  sort(x)[ceiling(p * length(x))]
}
