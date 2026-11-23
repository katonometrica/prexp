# The monthly loader (spec section 4): stage a month's file, work out its
# dimensions, build the month beside the live data, check it, and swap it in.
#
# Staging and the checks run as prexp_loader. Creating, attaching and detaching
# partitions needs ownership of the tables, which no grant gives, so the
# dimensions, the build and the swap run on one owner connection, which also
# holds the month's temporary tables between those steps (spec section 3.1).
# Nothing in core changes before the swap. The SQL is in inst/sql/load/.

# The named statements of inst/sql/load/<file>.sql. Each starts at a line
# "-- name: <name>" and runs to the next; the comments before the first one are
# the file's header.
load_statements <- function(file) {
  path <- system.file("sql", "load", paste0(file, ".sql"), package = "prexp", mustWork = TRUE)
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  starts <- grep("^-- name: [a-z_]+$", lines)
  ends <- c(starts[-1L] - 1L, length(lines))
  sql <- vapply(seq_along(starts), function(i) {
    trimws(paste(lines[(starts[i] + 1L):ends[i]], collapse = "\n"))
  }, character(1))
  stats::setNames(sql, sub("^-- name: ", "", lines[starts]))
}

# The statements for one month: {ym} becomes the month and {next} the month
# after it, both checked integers, so nothing else reaches the text.
month_statements <- function(file, year_month) {
  ym <- check_year_month(year_month)
  sql <- load_statements(file)
  sql[] <- gsub("{next}", ym + 1L, gsub("{ym}", ym, sql, fixed = TRUE), fixed = TRUE)
  sql
}

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

#' Work out the staged month's dimensions
#'
#' Fills temporary tables with the month's chemicals, presentations and
#' practices and their ids: existing ones, or new ones from the identity
#' sequences. Nothing in `core` changes; [apply_dimensions()] writes them
#' during the swap. Runs `inst/sql/load/dimensions.sql`.
#'
#' @param con The owner connection that will build and swap the month.
#' @param year_month The staged month, as `YYYYMM`.
#' @return A data frame with the month's codes and new codes per dimension,
#'   invisibly.
#' @noRd
prepare_dimensions <- function(con, year_month) {
  ym <- check_year_month(year_month)
  sql <- month_statements("dimensions", ym)
  quiet_notices(con)
  steps <- c(
    "drop_month_tables", "month_chemical", "new_chemical_ids", "month_presentation",
    "new_presentation_ids", "month_practice", "new_practice_ids", "analyze_month_tables"
  )
  for (name in steps) {
    DBI::dbExecute(con, sql[[name]], immediate = TRUE)
  }
  counts <- DBI::dbGetQuery(con, "
    SELECT 'chemical' AS dimension, count(*)::int4 AS codes,
           count(*) FILTER (WHERE is_new)::int4 AS new
    FROM pg_temp.month_chemical
    UNION ALL
    SELECT 'presentation', count(*)::int4, count(*) FILTER (WHERE is_new)::int4
    FROM pg_temp.month_presentation
    UNION ALL
    SELECT 'practice', count(*)::int4, count(*) FILTER (WHERE is_new)::int4
    FROM pg_temp.month_practice")
  invisible(counts)
}

#' Write the month's dimensions to core
#'
#' Called by the swap, inside its transaction, on the connection that ran
#' [prepare_dimensions()]: updates the codes already known (first and last
#' month seen; names, ICB and region only from a month at least as recent as
#' the last one seen) and inserts the new ones, chemicals first.
#'
#' @param con The owner connection, in a transaction.
#' @param year_month The month, as `YYYYMM`.
#' @noRd
apply_dimensions <- function(con, year_month) {
  sql <- month_statements("dimensions", year_month)
  steps <- c(
    "update_chemicals", "insert_chemicals", "update_presentations", "insert_presentations",
    "update_practices", "insert_practices"
  )
  for (name in steps) {
    DBI::dbExecute(con, sql[[name]], immediate = TRUE)
  }
  invisible(TRUE)
}

# NOTICEs, such as "table does not exist, skipping", are printed as messages by
# RPostgres; loader sessions only report warnings and errors.
quiet_notices <- function(con) {
  DBI::dbExecute(con, "SET client_min_messages = warning", immediate = TRUE)
}
