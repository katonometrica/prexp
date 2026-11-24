# The monthly loader (spec section 4): stage a month's file, work out its
# dimensions, build the month beside the live data, check it, and swap it in.
#
# Staging and the checks run as prexp_loader. Creating, attaching and detaching
# partitions needs ownership of the tables, which no grant gives, so the
# dimensions, the build and the swap run on one owner connection, which also
# holds the month's temporary tables between those steps (spec section 3.1).
# Nothing in core changes before the swap. The SQL is in inst/sql/load/.

# Advisory lock key for loads (namespace "prex", as the migration lock in db.R)
load_lock <- c(1886545272L, 2L)

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

# Runs expr, then reports how long it took.
timed <- function(step, expr) {
  started <- Sys.time()
  value <- force(expr)
  message(sprintf("%s: %.1f s", step, as.numeric(difftime(Sys.time(), started, units = "secs"))))
  value
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

#' Check that staging holds the month asked for
#'
#' Run right after staging, before anything uses the staged rows: a file for
#' another month must never reach the dimensions or the build.
#'
#' @param con A connection as the loader.
#' @param year_month The month, as `YYYYMM`.
#' @noRd
check_staged_month <- function(con, year_month) {
  ym <- check_year_month(year_month)
  staged <- DBI::dbGetQuery(con, month_statements("check_month", ym)[["staged_months"]])
  expected <- sprintf("%d-%02d", ym %/% 100L, ym %% 100L)
  if (!identical(staged$year_month, expected)) {
    stop(
      "The staged file holds ", toString(staged$year_month), ", not ", expected, ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
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

#' Build a month beside the live data
#'
#' Creates `core.prescribing_<ym>_new` from staging and the month's prepared
#' dimensions, one row per practice and presentation, with a `CHECK`
#' constraint for the month and the parent's indexes, and runs `VACUUM
#' (ANALYZE)` on it. Then computes the month's rollup rows into temporary
#' tables, which [swap_month()] copies on the same connection.
#'
#' @param con The owner connection that ran [prepare_dimensions()].
#' @param year_month The month, as `YYYYMM`.
#' @return The rows of the new table, invisibly.
#' @noRd
build_month <- function(con, year_month) {
  ym <- check_year_month(year_month)
  sql <- month_statements("build_month", ym)
  quiet_notices(con)
  run <- function(name) DBI::dbExecute(con, sql[[name]], immediate = TRUE)
  rows <- timed("build: aggregate", {
    run("analyze_staging")
    run("drop_new")
    run("create_new")
    run("insert_new")
  })
  timed("build: indexes", {
    parent <- DBI::dbGetQuery(con, sql[["parent_indexes"]])
    for (i in seq_len(nrow(parent))) {
      DBI::dbExecute(con, new_index_sql(parent$name[i], parent$definition[i], ym), immediate = TRUE)
    }
  })
  timed("build: vacuum", run("vacuum_new"))
  timed("build: rollups", {
    for (name in c("drop_rollups", "rollup_presentation", "rollup_chemical", "rollup_practice")) {
      run(name)
    }
  })
  invisible(as.numeric(rows))
}

# One of the parent's index definitions, for the new table: same columns, same
# INCLUDE list, so the attach adopts it. Named prescribing_<ym>_new_<suffix>,
# renamed by the swap.
new_index_sql <- function(name, definition, ym) {
  suffix <- sub("^prescribing_", "", name)
  pattern <- "^(CREATE (UNIQUE )?INDEX) \\S+ ON ONLY core\\.prescribing "
  if (!grepl(pattern, definition)) {
    stop("Unexpected index definition on core.prescribing: ", definition, call. = FALSE)
  }
  sub(pattern, sprintf("\\1 prescribing_%d_new_%s ON core.prescribing_%d_new ", ym, suffix, ym),
      definition)
}

#' Check a built month against staging
#'
#' Every staged value must be valid: `ITEMS` a whole number of at least 1, the
#' other measures finite and not negative. Staging must hold the rows the file
#' had; the new table one row per practice and presentation in staging; and
#' the sums of every measure must be equal, exactly. Any difference stops the
#' load, before the live data changes.
#'
#' @param con A connection as the loader.
#' @param year_month The month, as `YYYYMM`.
#' @param source_rows The `COPY` count from [stage_month()].
#' @return A list with `source_rows`, `loaded_rows` and the new table's
#'   `totals`, invisibly.
#' @noRd
check_month <- function(con, year_month, source_rows) {
  ym <- check_year_month(year_month)
  sql <- month_statements("check_month", ym)
  staging <- DBI::dbGetQuery(con, sql[["staging_totals"]])
  pairs <- DBI::dbGetQuery(con, sql[["staging_pairs"]])$pairs
  built <- DBI::dbGetQuery(con, sql[["new_totals"]])
  problems <- character()
  if (staging$bad_items > 0L) {
    problems <- c(problems, sprintf(
      "%d staged rows have ITEMS below 1", staging$bad_items
    ))
  }
  if (staging$bad_measures > 0L) {
    problems <- c(problems, sprintf(
      "%d staged rows have a measure that is negative or not finite", staging$bad_measures
    ))
  }
  if (staging$rows != source_rows) {
    problems <- c(problems, sprintf(
      "staging holds %.0f rows, the file %.0f", staging$rows, source_rows
    ))
  }
  if (built$rows != pairs) {
    problems <- c(problems, sprintf(
      "the new table has %.0f rows for %.0f practice and presentation pairs", built$rows, pairs
    ))
  }
  for (measure in c("items", "total_quantity", "adq_usage", "nic", "actual_cost")) {
    if (!identical(staging[[measure]], built[[measure]])) {
      problems <- c(problems, sprintf(
        "%s sums to %s in staging and %s in the new table",
        measure, staging[[measure]], built[[measure]]
      ))
    }
  }
  if (length(problems) > 0L) {
    stop(
      "The check of ", ym, " failed: ", paste(problems, collapse = "; "),
      ". The live data is unchanged.",
      call. = FALSE
    )
  }
  invisible(list(source_rows = staging$rows, loaded_rows = built$rows, totals = built))
}

#' Make a built month live
#'
#' In one transaction: writes the month's dimensions, replaces its rollup rows
#' with those [build_month()] computed, detaches and drops the month's current
#' partition if there is one, renames the new table and attaches it, and marks
#' the load `loaded` and the month's previous load `replaced`. A new month that
#' takes the window beyond `window` months drops the oldest months, in the same
#' transaction: their partitions and rollup rows go, and their loads are marked
#' `dropped`. Any error rolls the whole swap back.
#'
#' Each lock is waited for at most `lock_timeout`, well under the app's 5 s
#' statement timeout, because the app's queries queue behind a waiting detach.
#' A lock timeout is retried after a pause that lets them run. After the
#' commit, the parent table's statistics are refreshed; a failure there is only
#' a warning, since the month is live.
#'
#' @param con The owner connection that prepared and built the month.
#' @param year_month The month, as `YYYYMM`.
#' @param load_id This load's row in `core.load_log`.
#' @param source_rows,loaded_rows,file_bytes Recorded in `core.load_log`.
#' @param window How many months the database keeps.
#' @param lock_timeout How long each lock may be waited for.
#' @param attempts Attempts when a lock times out.
#' @param pause Seconds between attempts.
#' @return The months dropped, oldest first, invisibly.
#' @noRd
swap_month <- function(con, year_month, load_id, source_rows, loaded_rows, file_bytes,
                       window = window_months(), lock_timeout = "1s", attempts = 10L,
                       pause = 2) {
  ym <- check_year_month(year_month)
  sql <- month_statements("swap_month", ym)
  log_params <- list(load_id, source_rows, loaded_rows, file_bytes)
  for (attempt in seq_len(attempts)) {
    swapped <- tryCatch(
      DBI::dbWithTransaction(con, {
        DBI::dbGetQuery(
          con, "SELECT set_config('lock_timeout', $1, true)", params = list(lock_timeout)
        )
        list(dropped = swap_statements(con, sql, ym, log_params, window))
      }),
      error = function(e) {
        if (attempt < attempts && is_lock_timeout(e)) {
          message("The swap of ", ym, " waited too long for a lock (attempt ", attempt, " of ",
                  attempts, "); trying again")
          return(FALSE)
        }
        stop(e)
      }
    )
    # dbWithTransaction() rolls back on an interrupt and returns NULL instead
    # of signalling it. An interrupt while the COMMIT's reply is on its way
    # leaves the swap committed (load_month() reports it): this load's row
    # says whether it was rolled back.
    if (is.null(swapped)) {
      rolled_back <- identical(load_status(con, load_id), "running")
      stop("The swap of ", ym, " was interrupted", if (rolled_back) " and rolled back", ".",
           call. = FALSE)
    }
    if (is.list(swapped)) {
      break
    }
    Sys.sleep(pause)
  }
  for (month in swapped$dropped) {
    message("Dropped ", month, " to keep the window at ", n_months(window))
  }
  not_refreshed <- function(e) {
    warning(
      ym, " is loaded, but the statistics of core.prescribing were not refreshed: ",
      conditionMessage(e),
      call. = FALSE
    )
  }
  tryCatch(analyze_parent(con), error = not_refreshed, interrupt = not_refreshed)
  invisible(swapped$dropped)
}

# This load's status in load_log, or NA when it cannot be read
load_status <- function(con, load_id) {
  tryCatch(
    DBI::dbGetQuery(
      con, "SELECT status FROM core.load_log WHERE load_id = $1", params = list(load_id)
    )$status,
    error = function(e) NA_character_
  )
}

swap_statements <- function(con, sql, ym, log_params, window) {
  run <- function(name) DBI::dbExecute(con, sql[[name]], immediate = TRUE)
  dropped <- window_drops(loaded_months(con), ym, window)
  if (ym %in% dropped) {
    # check_window() refused this load before it started; never drop the month
    # being loaded
    stop(ym, " is older than the first month of the full window.", call. = FALSE)
  }
  apply_dimensions(con, ym)
  for (rollup in c("presentation", "chemical", "practice")) {
    run(paste0("delete_", rollup))
    run(paste0("insert_", rollup))
  }
  # The rollup deletes take no lock that the app's reads wait for, unlike the
  # detaches below
  for (month in dropped) {
    delete_rollups(con, month)
  }
  live <- DBI::dbGetQuery(con, sql[["live_partition"]])
  if (live$attached) {
    run("detach")
  }
  if (live$exists) {
    run("drop_old")
  }
  run("rename_new")
  rename_new_indexes(con, ym)
  run("attach")
  for (month in dropped) {
    drop_partition(con, month)
  }
  run("replace_log")
  DBI::dbExecute(con, sql[["loaded_log"]], params = log_params)
  dropped
}

# A month leaving the window, in the swap's transaction: its rollup rows...
delete_rollups <- function(con, month) {
  sql <- month_statements("swap_month", month)
  for (rollup in c("presentation", "chemical", "practice")) {
    DBI::dbExecute(con, sql[[paste0("delete_", rollup)]], immediate = TRUE)
  }
}

# ...then its partition, which locks the parent table until the commit, and
# its load, marked dropped. Its dimension rows stay.
drop_partition <- function(con, month) {
  sql <- month_statements("swap_month", month)
  live <- DBI::dbGetQuery(con, sql[["live_partition"]])
  if (live$attached) {
    DBI::dbExecute(con, sql[["detach"]], immediate = TRUE)
  }
  if (live$exists) {
    DBI::dbExecute(con, sql[["drop_old"]], immediate = TRUE)
  }
  DBI::dbExecute(con, sql[["dropped_log"]], immediate = TRUE)
}

# Planner statistics for the parent table, which autovacuum never analyses.
# ONLY: each partition was analysed when it was built, and a plain ANALYZE
# would analyse them all again, waiting behind any VACUUM of one of them. It
# runs after the swap's transaction, whose lock timeout has ended, so it gets
# its own: the month is live, and the statistics can wait for the next load.
analyze_parent <- function(con) {
  DBI::dbExecute(con, "SET lock_timeout = '30s'", immediate = TRUE)
  on.exit(try(DBI::dbExecute(con, "RESET lock_timeout", immediate = TRUE), silent = TRUE))
  DBI::dbExecute(con, "ANALYZE ONLY core.prescribing", immediate = TRUE)
}

# The new table's indexes lose "_new" in their names once the table has.
rename_new_indexes <- function(con, ym) {
  names <- DBI::dbGetQuery(con, sprintf(
    "SELECT indexname FROM pg_indexes WHERE schemaname = 'core' AND tablename = 'prescribing_%d'",
    ym
  ))$indexname
  for (name in grep(sprintf("^prescribing_%d_new_", ym), names, value = TRUE)) {
    DBI::dbExecute(con, sprintf(
      "ALTER INDEX core.%s RENAME TO %s",
      name, sub(sprintf("^prescribing_%d_new_", ym), sprintf("prescribing_%d_", ym), name)
    ), immediate = TRUE)
  }
}

is_lock_timeout <- function(error) {
  grepl("lock timeout", conditionMessage(error), fixed = TRUE)
}

# NOTICEs, such as "table does not exist, skipping", are printed as messages by
# RPostgres; loader sessions only report warnings and errors.
quiet_notices <- function(con) {
  DBI::dbExecute(con, "SET client_min_messages = warning", immediate = TRUE)
}

#' How many months the database keeps
#'
#' From `PREXP_WINDOW_MONTHS`, a whole number of at least 1; 12 when it is not
#' set or empty.
#'
#' @return An integer.
#' @noRd
window_months <- function() {
  value <- trimws(Sys.getenv("PREXP_WINDOW_MONTHS"))
  if (!nzchar(value)) {
    return(12L)
  }
  if (!grepl("^[0-9]{1,4}$", value) || as.integer(value) < 1L) {
    stop(
      "PREXP_WINDOW_MONTHS must be a whole number of months, at least 1, not \"", value, "\".",
      call. = FALSE
    )
  }
  as.integer(value)
}

# The months with live data: the window
loaded_months <- function(con) {
  DBI::dbGetQuery(
    con, "SELECT year_month FROM core.load_log WHERE status = 'loaded' ORDER BY year_month"
  )$year_month
}

# The months a load of ym leaves out of a window of `window` months, oldest
# first. None for a month already loaded: a reload never drops anything.
# Otherwise the loaded months beyond the `window` most recent once ym is in,
# several if the window has been made smaller, and ym itself when it is older
# than the first month of a full window.
window_drops <- function(loaded, ym, window) {
  if (ym %in% loaded) {
    return(integer())
  }
  months <- sort(as.integer(c(loaded, ym)), decreasing = TRUE)
  sort(utils::tail(months, -window))
}

# Refuses a month that would be dropped as soon as it was loaded, before
# anything is downloaded or recorded. The months kept are the `window` most
# recent: more can be loaded, after the window was made smaller, until the next
# new month drops them.
check_window <- function(con, ym, window) {
  loaded <- loaded_months(con)
  if (ym %in% window_drops(loaded, ym, window)) {
    kept <- sort(loaded, decreasing = TRUE)[seq_len(window)]
    stop(
      ym, " would be dropped as soon as it was loaded: the window keeps the most recent ",
      n_months(window), " (PREXP_WINDOW_MONTHS), from ", min(kept), " on.",
      call. = FALSE
    )
  }
  invisible(loaded)
}

# "1 month", "12 months"
n_months <- function(n) paste(n, if (n == 1L) "month" else "months")

#' Load or reload one month
#'
#' Runs the steps of the monthly load (spec section 4) with a timed message for
#' each: find the month on the portal, download it, check its header, stage it
#' and check that it is the month asked for, work out its dimensions, build the
#' month beside the live data, check it against staging, and swap it in.
#' Nothing in `core` changes before the swap, which runs in one transaction, so
#' a month is either loaded completely, dimensions included, or left as it was.
#' Loading a month again rebuilds and swaps it.
#'
#' The database keeps a window of `PREXP_WINDOW_MONTHS` months (default 12), the
#' most recent loaded. A new month that takes it beyond that drops the oldest
#' in the same swap: its partition and rollup rows go, its dimension rows stay.
#' A reload never drops anything. A month older than the first month of a full
#' window is refused before anything is downloaded, since it would be dropped
#' at once.
#'
#' An advisory lock lets only one load run at a time on a database. The load is
#' recorded in `core.load_log`: `running` while it runs, then `loaded`, or
#' `failed` with the error. At the end staging is truncated and a downloaded
#' file is deleted. A downloaded file is also deleted when a step that reads it
#' fails before its SHA-256 has been checked, so a damaged download is never
#' used again.
#'
#' @param year_month The month, as `YYYYMM`.
#' @param file A local monthly file (ZIP or CSV) to load instead of
#'   downloading the month; it is kept.
#' @param sha256 With `file`, the expected SHA-256 of its CSV, or `NULL` not
#'   to check it. Without `file` the portal's is used.
#' @param dbname Database name; defaults to `PREXP_DB_NAME`.
#' @return A list with `year_month`, `source_rows`, `loaded_rows`, `dropped`
#'   (the months dropped from the window) and `seconds`, invisibly.
#' @export
load_month <- function(year_month, file = NULL, sha256 = NULL, dbname = NULL) {
  ym <- check_year_month(year_month)
  window <- window_months()
  started <- Sys.time()
  downloaded <- is.null(file)
  if (!downloaded) {
    file <- normalizePath(file, mustWork = TRUE)
  }
  # check_interrupts: Ctrl-C cancels the running statement instead of waiting
  # for it to finish
  loader <- db_connect("loader", dbname = dbname, check_interrupts = TRUE)
  on.exit(DBI::dbDisconnect(loader), add = TRUE)
  lock_loads(loader)
  before <- check_window(loader, ym, window)
  owner <- db_connect("owner", dbname = dbname, check_interrupts = TRUE)
  on.exit(DBI::dbDisconnect(owner), add = TRUE)
  quiet_notices(loader)
  quiet_notices(owner)

  source_url <- NA_character_
  if (downloaded) {
    res <- timed("find", month_resource(ym))
    sha256 <- res$sha256
    source_url <- res$url
  }
  load_id <- start_load(loader, ym, source_url, sha256)
  verified <- FALSE
  failed <- function(error) {
    fail_load(loader, owner, ym, load_id, error)
    # A download that could not be read, or whose content differs from the
    # portal's, is damaged or stale: the next run downloads it again
    if (downloaded && !verified && !is.null(file)) {
      unlink(file)
    }
  }
  result <- tryCatch(
    {
      if (downloaded) {
        file <- timed("download", download_month(ym))
      }
      timed("header", validate_header(file))
      staged <- timed("stage", stage_month(file, sha256, dbname))
      verified <- TRUE
      timed("staged month", check_staged_month(loader, ym))
      timed("dimensions", prepare_dimensions(owner, ym))
      timed("build", build_month(owner, ym))
      checked <- timed("check", check_month(loader, ym, staged$rows))
      dropped <- timed("swap", swap_month(
        owner, ym, load_id, staged$rows, checked$loaded_rows, file.size(file), window
      ))
      list(
        source_rows = staged$rows, loaded_rows = as.numeric(checked$loaded_rows),
        dropped = dropped
      )
    },
    error = function(e) {
      failed(conditionMessage(e))
      committed <- committed_load(owner, ym, load_id, before)
      if (!is.null(committed)) {
        stop(committed, call. = FALSE)
      }
      stop(e)
    },
    interrupt = function(e) {
      failed("Interrupted.")
      committed <- committed_load(owner, ym, load_id, before)
      if (!is.null(committed)) {
        stop(committed, call. = FALSE)
      }
      stop("The load of ", ym, " was interrupted.", call. = FALSE)
    }
  )
  timed("clean", {
    DBI::dbExecute(loader, "TRUNCATE raw.epd_staging", immediate = TRUE)
    if (downloaded) {
      unlink(file)
    }
  })
  seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  message(sprintf(
    "Loaded %d: %.0f source rows, %.0f rows, in %.0f s",
    ym, result$source_rows, result$loaded_rows, seconds
  ))
  invisible(c(list(year_month = ym), result, list(seconds = seconds)))
}

# A load stopped by an error or an interrupt can still have committed its
# swap: RPostgres turns Ctrl-C during the wait for the COMMIT's reply into an
# error, and the interrupt may also come just after the swap. This load's row
# says so once fail_load() has run, since a row still running then is marked
# failed. NULL when the swap did not commit; otherwise a message saying that
# the month is loaded, and which months left the window.
committed_load <- function(con, ym, load_id, before) {
  if (!identical(load_status(con, load_id), "loaded")) {
    return(NULL)
  }
  dropped <- tryCatch(setdiff(before, loaded_months(con)), error = function(e) integer())
  paste0(
    "The load of ", ym, " was stopped after its swap committed: ", ym, " is loaded",
    if (length(dropped) > 0L) paste0(", and ", toString(dropped), " left the window"), "."
  )
}

# Takes the load lock for this session, or stops: two loads must never run at
# once. Closing the connection releases it.
lock_loads <- function(con) {
  locked <- DBI::dbGetQuery(
    con, "SELECT pg_try_advisory_lock($1, $2) AS locked", params = as.list(load_lock)
  )$locked
  if (!isTRUE(locked)) {
    stop("Another load is running on this database. Try again when it has finished.",
         call. = FALSE)
  }
}

# Records a new attempt as running. Any other running attempt was cut short:
# the lock is held, so it cannot still be running.
start_load <- function(con, ym, source_url, sha256) {
  DBI::dbExecute(con, "
    UPDATE core.load_log
    SET status = 'failed', error = 'Interrupted: the load did not finish.', finished_at = now()
    WHERE status = 'running'", immediate = TRUE)
  DBI::dbGetQuery(con, "
    INSERT INTO core.load_log (year_month, source_url, source_sha256)
    VALUES ($1, $2, $3) RETURNING load_id",
    params = list(ym, source_url, if (is.null(sha256)) NA_character_ else sha256)
  )$load_id
}

# Records the failure and removes what the attempt left: the new table and the
# staged rows. The month's temporary tables go with the owner's session. Only a
# row still running is marked failed: once the swap has committed, the month is
# live and its row says so. Errors here are reported but never hide the load's
# own error.
fail_load <- function(loader, owner, ym, load_id, error) {
  tryCatch({
    DBI::dbExecute(
      owner, sprintf("DROP TABLE IF EXISTS core.prescribing_%d_new", ym), immediate = TRUE
    )
    DBI::dbExecute(loader, "TRUNCATE raw.epd_staging", immediate = TRUE)
    DBI::dbExecute(loader, "
      UPDATE core.load_log SET status = 'failed', error = $2, finished_at = now()
      WHERE load_id = $1 AND status = 'running'", params = list(load_id, error))
  }, error = function(e) {
    warning("Could not record the failed load of ", ym, ": ", conditionMessage(e), call. = FALSE)
  })
  invisible()
}

#' Load the most recent published months that are missing
#'
#' Asks the portal which months are published, takes the `n` most recent, and
#' loads each of them that has no `loaded` row in `core.load_log` with
#' [load_month()], oldest first, as they were published. Used for the first
#' load and to rebuild a database. A month that the window would drop, because
#' it keeps newer months, is left out with a message. Stops at the first month
#' that fails, naming it: the months before it stay loaded, and running
#' `load_window()` again carries on.
#'
#' @param n How many of the most recent published months to load; at most the
#'   window, `PREXP_WINDOW_MONTHS` (default 12), which is also the default.
#' @param dbname Database name; defaults to `PREXP_DB_NAME`.
#' @return A data frame with one row per month loaded: `year_month`,
#'   `source_rows`, `loaded_rows` and `seconds`, invisibly.
#' @export
load_window <- function(n = window_months(), dbname = NULL) {
  window <- window_months()
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || n != round(n) || n < 1 || n > window) {
    stop(
      "`n` must be a whole number of months from 1 to the window, ", window,
      " (PREXP_WINDOW_MONTHS), not ", paste(format(n), collapse = ", "), ".",
      call. = FALSE
    )
  }
  wanted <- utils::tail(sort(epd_resources()$year_month), n)
  con <- db_connect("loader", dbname = dbname)
  loaded <- tryCatch(loaded_months(con), finally = DBI::dbDisconnect(con))
  missing <- setdiff(wanted, loaded)
  # The window keeps the most recent of the months loaded and wanted. A month
  # outside them would be dropped by a newer one, as soon as it was loaded
  # (check_window() refuses it) or later in this run.
  kept <- utils::head(sort(union(loaded, wanted), decreasing = TRUE), window)
  outside <- setdiff(missing, kept)
  if (length(outside) > 0L) {
    message(
      "Leaving out ", toString(outside), ": the window keeps the most recent ",
      n_months(window), " (PREXP_WINDOW_MONTHS), from ", min(kept), " on."
    )
    missing <- intersect(missing, kept)
  }
  done <- data.frame(
    year_month = integer(), source_rows = numeric(), loaded_rows = numeric(), seconds = numeric()
  )
  if (length(missing) == 0L) {
    if (length(outside) == 0L) {
      message("Nothing to load: ", if (length(wanted) == 1L) {
        paste0("the most recent published month, ", wanted, ", is loaded.")
      } else {
        paste0(
          "the ", length(wanted), " most recent published months, ", min(wanted), " to ",
          max(wanted), ", are loaded."
        )
      })
    }
    return(invisible(done))
  }
  message("Loading ", n_months(length(missing)), ", oldest first: ", toString(missing))
  for (ym in missing) {
    res <- tryCatch(
      load_month(ym, dbname = dbname),
      error = function(e) {
        stop(
          "Loading ", ym, " failed, after ", nrow(done), " of ", n_months(length(missing)),
          ": ", conditionMessage(e), " Run load_window() again to carry on.",
          call. = FALSE
        )
      }
    )
    done[nrow(done) + 1L, ] <- list(ym, res$source_rows, res$loaded_rows, res$seconds)
  }
  message("Loaded ", n_months(nrow(done)), " in ", round(sum(done$seconds) / 60, 1), " min.")
  invisible(done)
}
