# The monthly loader (spec section 4): stage a month's file, work out its
# dimensions, build the month beside the live data, check it, and swap it in.
#
# Staging and the checks run as prexp_loader. Creating, attaching and detaching
# partitions needs ownership of the tables, which no grant gives, so the
# dimensions, the build and the swap run on one owner connection, which also
# holds the month's temporary tables between those steps (spec section 3.1).
# Nothing in core changes before the swap. The SQL is in inst/sql/load/.

#' Stream a monthly file into staging
#'
#' Truncates `raw.epd_staging`, then streams the file's CSV into it with
#' `psql`'s `\copy` as the loader role, computing the stream's SHA-256 on the
#' way, in one pipeline under `bash -o pipefail`, so a failing extract fails the
#' step. The file path reaches `bash` as an argument and the password as
#' `PGPASSWORD` in the child's environment, never in the command. A blank value
#' is staged as an empty string, never NULL (`FORCE_NOT_NULL`), so a blank
#' measure fails its cast in the build instead of being left out of a sum.
#'
#' @param file A monthly ZIP holding one CSV, or the CSV.
#' @param sha256 The portal's SHA-256 of the CSV, or `NULL` not to check it.
#' @param dbname Database name; defaults to `PREXP_DB_NAME`.
#' @return A list with `rows` (the `COPY` count, the source's rows),
#'   `sha256` (of the stream) and `seconds`.
#' @noRd
stage_month <- function(file, sha256 = NULL, dbname = NULL) {
  file <- path.expand(file)
  cfg <- db_config("loader", dbname)
  hash <- tempfile("sha256-")
  on.exit(unlink(hash), add = TRUE)
  script <- paste(
    sep = "\n",
    "set -o pipefail",
    'tmp="$(mktemp -d)"',
    "trap 'rm -rf \"$tmp\"' EXIT",
    'mkfifo "$tmp/stream"',
    'sha256sum < "$tmp/stream" > "$2" &',
    "hasher=$!",
    paste(
      source_stream_command(file), '| tee "$tmp/stream" |',
      "psql -X -v ON_ERROR_STOP=1 -c 'TRUNCATE raw.epd_staging'",
      "-c '\\copy raw.epd_staging FROM STDIN WITH (FORMAT csv, HEADER true, FORCE_NOT_NULL *)'"
    ),
    "status=$?",
    'wait "$hasher"',
    'exit "$status"'
  )
  started <- Sys.time()
  res <- run_bash(script, c(file, hash), error_on_status = FALSE, env = c(
    "current",
    PGHOST = cfg$host, PGPORT = cfg$port, PGDATABASE = cfg$dbname, PGUSER = cfg$user,
    PGPASSWORD = cfg$password, PGAPPNAME = "prexp-stage", PGCONNECT_TIMEOUT = "10"
  ))
  if (res$status != 0L) {
    stop("Staging ", basename(file), " failed: ", trimws(res$stderr), call. = FALSE)
  }
  copied <- regmatches(res$stdout, regexec("(?m)^COPY ([0-9]+)$", res$stdout, perl = TRUE))[[1]]
  if (length(copied) != 2L || copied[2] == "0") {
    stop("Staging ", basename(file), " loaded no rows.", call. = FALSE)
  }
  observed <- substr(readLines(hash, n = 1L, warn = FALSE), 1L, 64L)
  if (!is.null(sha256) && !identical(tolower(observed), tolower(sha256))) {
    stop(
      "The SHA-256 of the data staged from ", basename(file), ", ", observed,
      ", differs from the portal's, ", sha256, ".",
      call. = FALSE
    )
  }
  list(
    rows = as.numeric(copied[2]), sha256 = observed,
    seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))
  )
}
