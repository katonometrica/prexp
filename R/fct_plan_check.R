# The plan check (spec sections 5.2 and 6.3): every app query, with its large
# and small sample, run once to warm the cache and then explained with
# EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, FORMAT JSON). It fails on a
# sequential scan of a partition of the fact table, on more partitions than
# the months asked for, on heap fetches in an index-only scan of one, and on
# planning and execution slower than max_ms.
#
# TIMING OFF: the run time of the whole statement is still measured, without
# reading the clock for every row in every node, which adds half again to a
# plan that moves tens of thousands of rows, as a practice's top drugs does.

# The fact table's partitions: core.prescribing_YYYYMM, and the _new table a
# load builds beside them
fact_partition <- "^prescribing_[0-9]{6}(_new)?$"

#' Every node of a plan
#'
#' Walks a plan from `EXPLAIN (FORMAT JSON)`, parsed with
#' `jsonlite::fromJSON(simplifyVector = FALSE)`, without recursion, so any
#' depth works: its main tree, init plans and sub plans alike.
#'
#' @param plan The top node: the `Plan` element of the parsed output.
#' @return A data frame with one row per node, in depth-first order: `depth`,
#'   `node_type`, `relationship` (to its parent: `Outer`, `InitPlan`, ...),
#'   `relation`, `heap_fetches`, `subplans_removed`.
#' @noRd
plan_nodes <- function(plan) {
  field <- function(node, name, empty) {
    value <- node[[name]]
    if (is.null(value)) empty else value
  }
  stack <- list(list(node = plan, depth = 0L))
  rows <- list()
  while (length(stack) > 0L) {
    top <- stack[[length(stack)]]
    stack[[length(stack)]] <- NULL
    node <- top$node
    rows[[length(rows) + 1L]] <- data.frame(
      depth = top$depth,
      node_type = field(node, "Node Type", NA_character_),
      relationship = field(node, "Parent Relationship", NA_character_),
      relation = field(node, "Relation Name", NA_character_),
      heap_fetches = as.numeric(field(node, "Heap Fetches", NA_real_)),
      subplans_removed = as.numeric(field(node, "Subplans Removed", NA_real_))
    )
    children <- field(node, "Plans", list())
    for (child in rev(children)) {
      stack[[length(stack) + 1L]] <- list(node = child, depth = top$depth + 1L)
    }
  }
  do.call(rbind, rows)
}

#' What one plan shows
#'
#' @param explained The parsed output of `EXPLAIN (ANALYZE, FORMAT JSON)`: a
#'   list holding one list with `Plan`, `Planning Time` and `Execution Time`.
#' @param max_ms The slowest planning and execution allowed, in milliseconds.
#' @param months The number of months the query asked for, the most partitions
#'   of the fact table its plan may read; NA for a query without months.
#' @return A one-row data frame: `ms` (planning plus execution), `seq_scans`
#'   (sequential scans of the fact table's partitions), `partitions` (how many
#'   partitions are read), `heap_fetches` (in index-only scans of them: the
#'   loader sets their visibility map, while small tables such as
#'   `core.load_log` change with every load), `pruned`
#'   (partitions removed when the plan starts, with a generic plan) and
#'   `problems`, a description of each failure, or `""`.
#' @noRd
plan_summary <- function(explained, max_ms, months = NA_integer_) {
  top <- explained[[1]]
  nodes <- plan_nodes(top$Plan)
  on_fact <- !is.na(nodes$relation) & grepl(fact_partition, nodes$relation)
  seq_scan <- on_fact & nodes$node_type %in% c("Seq Scan", "Parallel Seq Scan")
  index_only <- on_fact & nodes$node_type == "Index Only Scan" & !is.na(nodes$heap_fetches)
  ms <- top[["Planning Time"]] + top[["Execution Time"]]
  out <- data.frame(
    ms = round(ms, 2),
    seq_scans = sum(seq_scan),
    partitions = length(unique(nodes$relation[on_fact])),
    heap_fetches = sum(nodes$heap_fetches[index_only]),
    pruned = sum(nodes$subplans_removed, na.rm = TRUE)
  )
  problems <- c(
    if (out$seq_scans > 0L) {
      paste0("sequential scan of ", toString(unique(nodes$relation[seq_scan])))
    },
    if (!is.na(months) && out$partitions > months) {
      sprintf("reads %d partitions for %d months", out$partitions, months)
    },
    if (out$heap_fetches > 0) paste(out$heap_fetches, "heap fetches in index-only scans"),
    if (ms > max_ms) sprintf("%.1f ms, over %g ms", ms, max_ms)
  )
  out$problems <- paste(problems, collapse = "; ")
  out
}

#' Check the plans of every app query
#'
#' Runs each query of the registry with its large sample, over the whole
#' window, and its small sample, over the last three months: once to warm the
#' cache, then with `EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, FORMAT JSON)`,
#' which measures the whole statement without timing each node. A check fails
#' on a sequential scan of a partition of the fact table, on a plan that reads
#' more partitions than the months asked for (they were not pruned), on heap
#' fetches in an index-only scan of one (its visibility map is not set), on
#' planning and execution taking more than `max_ms`, or on a sample whose code
#' is not in the database. Prints a table of the results and writes one JSON
#' line per check to standard output.
#'
#' The app sends each query as an unnamed prepared statement, which the server
#' plans with the parameters' values; the checks do the same by default.
#' `generic = TRUE` checks instead the generic plans that a client preparing
#' its statements once would get, made without the values: they must still
#' prune the partitions, when the plan starts.
#'
#' On the full database every check must pass: the function stops with an
#' error when one fails, so `Rscript -e "prexp::check_plans()"` exits with a
#' non-zero status and a scheduled task can alert. On a small database, such as
#' the test fixtures, sequential scans are the planner's right choice: use
#' `report_only = TRUE` there.
#'
#' @param con A connection that can read the app views, such as the loader's;
#'   by default a new loader connection to `PREXP_DB_NAME`.
#' @param max_ms The slowest planning and execution allowed, in milliseconds.
#' @param report_only Report failures without stopping.
#' @param generic Check generic plans instead of plans made with the values.
#' @return A data frame with one row per query and sample, invisibly.
#' @export
check_plans <- function(con = NULL, max_ms = 50, report_only = FALSE, generic = FALSE) {
  if (is.null(con)) {
    con <- db_connect("loader")
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }
  window <- DBI::dbGetQuery(con, query_sql("window"))
  if (is.na(window$first_month)) {
    stop("No month is loaded: the plan check needs data.", call. = FALSE)
  }
  window <- list(first_month = window$first_month, last_month = window$last_month)
  if (generic) {
    mode <- DBI::dbGetQuery(con, "SELECT current_setting('plan_cache_mode') AS mode")$mode
    DBI::dbGetQuery(con, "SELECT set_config('plan_cache_mode', 'force_generic_plan', false)")
    on.exit(
      DBI::dbGetQuery(con, "SELECT set_config('plan_cache_mode', $1, false)", params = list(mode)),
      add = TRUE, after = FALSE
    )
  }
  registry <- query_registry()
  results <- list()
  for (query in names(registry)) {
    entry <- registry[[query]]
    sql <- query_sql(query)
    for (sample in names(entry$samples)) {
      res <- check_one(con, sql, entry, entry$samples[[sample]], window, max_ms, generic)
      res <- cbind(data.frame(query = query, sample = sample), res)
      log_check(res, generic)
      results[[length(results) + 1L]] <- res
    }
  }
  results <- do.call(rbind, results)
  results$ok <- results$problems == ""
  columns <- c(
    "query", "sample", "codes", "months", "ms", "seq_scans", "partitions", "pruned", "ok"
  )
  # One line per check, in a log too
  width <- options(width = max(getOption("width"), 150L))
  on.exit(options(width), add = TRUE)
  print(results[, columns], row.names = FALSE)
  failed <- results[!results$ok, ]
  if (nrow(failed) > 0L) {
    detail <- paste0(failed$query, " (", failed$sample, "): ", failed$problems, collapse = "\n")
    if (report_only) {
      message(nrow(failed), " of ", nrow(results), " checks would fail:\n", detail)
    } else {
      stop(nrow(failed), " of ", nrow(results), " plan checks failed:\n", detail, call. = FALSE)
    }
  }
  invisible(results)
}

# One query with one sample
check_one <- function(con, sql, entry, sample, window, max_ms, generic) {
  resolved <- resolve_sample(con, entry, sample, window)
  checked <- data.frame(codes = paste(resolved$codes, collapse = ", "), months = resolved$months)
  if (!is.na(resolved$missing)) {
    return(cbind(checked, data.frame(
      ms = NA_real_, seq_scans = NA_integer_, partitions = NA_integer_, heap_fetches = NA_real_,
      pruned = NA_real_, problems = paste(resolved$missing, "is not in the database")
    )))
  }
  explained <- if (generic) {
    explain_generic(con, sql, resolved$params)
  } else {
    explain_bound(con, sql, resolved$params)
  }
  cbind(checked, plan_summary(explained, max_ms, resolved$months))
}

# Run once to warm the cache, then explain, with the parameters bound: the
# server plans with their values, as it does for the app's queries
explain_bound <- function(con, sql, params) {
  run <- function(text) {
    if (length(params) == 0L) {
      DBI::dbGetQuery(con, text)
    } else {
      DBI::dbGetQuery(con, text, params = params)
    }
  }
  run(sql)
  parse_plan(run(paste(explain_prefix, sql)))
}

# The same with a prepared statement and plan_cache_mode set to
# force_generic_plan: the plan is made once, without the values. EXECUTE
# cannot take bound parameters, so the values are written as literals.
explain_generic <- function(con, sql, params) {
  DBI::dbExecute(con, paste("PREPARE prexp_plan_check AS", sql))
  on.exit(DBI::dbExecute(con, "DEALLOCATE prexp_plan_check"), add = TRUE)
  execute <- "EXECUTE prexp_plan_check"
  if (length(params) > 0L) {
    literals <- vapply(params, sql_literal, character(1), con = con)
    execute <- paste0(execute, "(", paste(literals, collapse = ", "), ")")
  }
  DBI::dbGetQuery(con, execute)
  parse_plan(DBI::dbGetQuery(con, paste(explain_prefix, execute)))
}

# A sample's value as an SQL literal: a number, a quoted string or NULL
sql_literal <- function(value, con) {
  if (is.na(value)) {
    "NULL"
  } else if (is.character(value)) {
    as.character(DBI::dbQuoteString(con, value))
  } else {
    format(value, scientific = FALSE, digits = 15)
  }
}

explain_prefix <- "EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, FORMAT JSON)"

parse_plan <- function(res) {
  jsonlite::fromJSON(paste(res[[1]], collapse = "\n"), simplifyVector = FALSE)
}

# One JSON line per check, for the scheduled task's log
log_check <- function(res, generic) {
  line <- list(
    time = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z"), event = "plan_check",
    plan = if (generic) "generic" else "custom",
    query = res$query, sample = res$sample, codes = res$codes, months = res$months, ms = res$ms,
    seq_scans = res$seq_scans, partitions = res$partitions, heap_fetches = res$heap_fetches,
    pruned = res$pruned, ok = res$problems == "", problems = res$problems
  )
  cat(jsonlite::toJSON(line, auto_unbox = TRUE, na = "null", digits = NA), "\n", sep = "")
}
