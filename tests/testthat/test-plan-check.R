# The query registry and the plan check (spec sections 5.2 and 6.3; P2-04).
# The plan walker runs on plans saved from the full database
# (fixtures/plans/), check_plans() end to end on fixture months, where tiny
# tables make sequential scans the right plan, so only in report-only mode.

read_plan <- function(name) {
  jsonlite::fromJSON(
    testthat::test_path("fixtures", "plans", paste0(name, ".json")), simplifyVector = FALSE
  )
}

test_that("every query in the registry has its file, and every file its entry", {
  files <- sub("[.]sql$", "", list.files(system.file("sql", "queries", package = "prexp")))
  expect_setequal(names(query_registry()), files)
  for (query in names(query_registry())) {
    entry <- query_registry()[[query]]
    sql <- query_sql(query)
    # The parameters the file uses are the registry's, $1 to $n
    used <- regmatches(sql, gregexpr("(?<=[$])[0-9]+", sql, perl = TRUE))[[1]]
    expect_identical(sort(unique(as.integer(used))), seq_along(entry$params), label = query)
    expect_true(length(entry$samples) >= 1L, label = query)
  }
  expect_error(query_sql("drop_everything"), "Unknown query: drop_everything.")
  expect_error(query_sql(""), "Unknown query")
  expect_error(query_sql(NA_character_), "Unknown query")
  expect_error(query_sql(c("window", "window")), "Unknown query")
  # Each file is read once and kept, as its text
  path <- system.file("sql", "queries", "window.sql", package = "prexp")
  text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_identical(query_sql("window"), text)
  expect_identical(query_text[["window"]], text)
  expect_identical(query_sql("window"), text)
})

test_that("months count across the turn of the year", {
  expect_identical(index_month(month_index(202601L) - 1L), 202512L)
  expect_identical(index_month(month_index(202609L) - 2L), 202607L)
  expect_identical(index_month(month_index(202512L) + 1L), 202601L)
  expect_identical(month_index(202609L) - month_index(202510L) + 1L, 12L)
})

test_that("a clean plan passes: index-only scans of the twelve months asked for", {
  res <- plan_summary(read_plan("clean"), max_ms = 50, months = 12L)
  expect_identical(res$rows, 25)
  expect_identical(res$seq_scans, 0L)
  expect_identical(res$heap_scans, 0L)
  expect_identical(res$partitions, 12L)
  expect_identical(res$heap_fetches, 0)
  expect_identical(res$pruned, 0)
  expect_identical(res$problems, "")
})

test_that("a generic plan prunes when it starts, and reads only the months asked for", {
  res <- plan_summary(read_plan("generic"), max_ms = 50, months = 3L)
  expect_identical(res$partitions, 3L)
  expect_identical(res$pruned, 9)
  expect_identical(res$problems, "")
})

test_that("a sequential scan, unpruned partitions, heap fetches and slowness fail", {
  res <- plan_summary(read_plan("seq_scan"), max_ms = 1e6, months = 3L)
  expect_gt(res$seq_scans, 0L)
  expect_match(res$problems, "^sequential scan of prescribing_2026")
  unpruned <- plan_summary(read_plan("clean"), max_ms = 50, months = 3L)
  expect_identical(unpruned$problems, "reads 12 partitions for 3 months")
  slow <- plan_summary(read_plan("clean"), max_ms = 0.001)
  expect_match(slow$problems, "^[0-9.]+ ms, over 0.001 ms$")
  # The limit is on planning plus execution: 0.642 + 20.361 ms in this plan
  plan <- read_plan("clean")
  expect_equal(plan[[1]][["Planning Time"]] + plan[[1]][["Execution Time"]], 21.003)
  expect_identical(plan_summary(plan, max_ms = 20.5)$problems, "21.0 ms, over 20.5 ms")
  # Any other read of a partition than an index-only scan goes to the heap
  heap <- plan
  heap[[1]]$Plan$Plans <- c(heap[[1]]$Plan$Plans, list(list(
    "Node Type" = "Bitmap Heap Scan", "Relation Name" = "prescribing_202609"
  )))
  expect_match(
    plan_summary(heap, 50, months = 12L)$problems,
    "not index-only: Bitmap Heap Scan of prescribing_202609", fixed = TRUE
  )
  # A query that returns nothing tests nothing
  empty <- plan
  empty[[1]]$Plan[["Actual Rows"]] <- 0
  expect_identical(
    plan_summary(empty, 50, months = 12L)$problems,
    "returns no rows: the sample no longer tests anything"
  )
  fetches <- read_plan("clean")
  fetches[[1]]$Plan <- list(
    "Node Type" = "Index Only Scan", "Relation Name" = "prescribing_202609", "Heap Fetches" = 7
  )
  expect_identical(plan_summary(fetches, 50)$problems, "7 heap fetches in index-only scans")
  # Only the fact table's: small tables such as load_log change with every load
  fetches[[1]]$Plan[["Relation Name"]] <- "load_log"
  expect_identical(plan_summary(fetches, 50)$problems, "")
})

test_that("the walker finds every node, init plans included, at any depth", {
  nodes <- plan_nodes(read_plan("nested")[[1]]$Plan)
  expect_true("InitPlan" %in% nodes$relationship)
  expect_identical(nodes$depth[1], 0L)
  expect_true(all(diff(nodes$depth) <= 1L))
  deep <- list("Node Type" = "Seq Scan", "Relation Name" = "prescribing_202609")
  for (i in seq_len(2000)) {
    deep <- list("Node Type" = "Nested Loop", Plans = list(deep, list("Node Type" = "Result")))
  }
  nodes <- plan_nodes(deep)
  expect_identical(nrow(nodes), 4001L)
  expect_identical(max(nodes$depth), 2000L)
  expect_identical(
    nodes$relation[nodes$depth == 2000L & nodes$node_type == "Seq Scan"], "prescribing_202609"
  )
})

test_that("check_plans() reports every query and sample on the fixture months", {
  dbname <- local_loaded_db(202606:202609)
  con <- local_test_db("loader", dbname = dbname)
  output <- utils::capture.output(
    res <- suppressMessages(check_plans(con, report_only = TRUE))
  )
  registry <- query_registry()
  expect_identical(nrow(res), sum(lengths(lapply(registry, `[[`, "samples"))))
  expect_setequal(unique(res$query), names(registry))
  # The large samples are the worst cases in the data: the practice with the
  # most prescribing rows, the chemical with the most presentation rollup rows,
  # the two characters that start the most names' words
  large_practice <- res$codes[res$query == "practice_series" & res$sample == "large"]
  prescribing <- DBI::dbGetQuery(con, "
    SELECT p.practice_code, sum(m.presentations)::int AS n FROM app.v_practice_month m
    JOIN app.v_practice p USING (practice_id) WHERE NOT p.is_unidentified GROUP BY 1")
  expect_identical(
    prescribing$n[prescribing$practice_code == large_practice], max(prescribing$n)
  )
  large_chemical <- res$codes[res$query == "drug_presentations" & res$sample == "large"]
  rollup <- DBI::dbGetQuery(con, "
    SELECT c.chemical_code, count(*)::int AS n FROM app.v_presentation_month m
    JOIN app.v_chemical c USING (chemical_id) GROUP BY 1")
  expect_identical(rollup$n[rollup$chemical_code == large_chemical], max(rollup$n))
  # The search texts: two characters picked from the data, then fixed ones
  searches <- res$codes[res$query %in% c("search_drugs", "search_practices")]
  expect_identical(nchar(searches[c(1, 3)]), c(2L, 2L))
  expect_identical(searches[c(2, 4)], c("pitolisant", "N81655"))
  drugs <- DBI::dbGetQuery(con, "
    SELECT chemical_name AS name FROM app.v_chemical
    UNION ALL SELECT bnf_description FROM app.v_presentation")$name
  matches <- function(q) sum(grepl(paste0("(^| )", q), drugs, ignore.case = TRUE))
  expect_true(matches(searches[1]) >= max(vapply(c("ta", "co", "ca", "so"), matches, 0L)))
  # Every sample found, every plan read, every query returning rows
  expect_false(any(grepl("has no data", res$problems)))
  expect_false(any(is.na(res$ms)))
  expect_true(all(res$rows > 0))
  # The large sample asks for the whole window, the small one for three months,
  # and the plan reads no more partitions than that
  top <- res[res$query == "practice_top_drugs", ]
  expect_identical(top$months, c(4L, 3L))
  expect_identical(top$partitions, c(4L, 3L))
  expect_false(any(grepl("partitions for", res$problems)))
  # The table, one line per check under its header, and one JSON line per check
  json <- grepl("^[{]", output)
  expect_identical(sum(json), nrow(res))
  expect_identical(sum(!json), nrow(res) + 1L)
  expect_match(output[!json][1], "^ *query +sample +codes +months +rows +ms")
  first <- jsonlite::fromJSON(output[json][1])
  expect_identical(first$event, "plan_check")
  expect_identical(first$plan, "custom")
  expect_identical(first$query, res$query[1])
  expect_identical(
    vapply(output[json], function(line) jsonlite::fromJSON(line)$ok, logical(1), USE.NAMES = FALSE),
    res$ok
  )
})

test_that("generic plans are checked too, and the session is left as it was", {
  dbname <- local_loaded_db(202606:202609)
  con <- local_test_db("loader", dbname = dbname)
  DBI::dbExecute(con, "SET plan_cache_mode = force_custom_plan")
  output <- utils::capture.output(
    res <- suppressMessages(check_plans(con, report_only = TRUE, generic = TRUE))
  )
  expect_false(any(is.na(res$ms)))
  # The small sample's month that was not asked for is pruned when the plan starts
  top <- res[res$query == "practice_top_drugs", ]
  expect_identical(top$partitions, c(4L, 3L))
  expect_identical(top$pruned, c(0, 1))
  lines <- grep("^[{]", output, value = TRUE)
  expect_length(lines, nrow(res))
  expect_true(all(vapply(lines, function(line) jsonlite::fromJSON(line)$plan, "") == "generic"))
  expect_identical(DBI::dbGetQuery(con, "SHOW plan_cache_mode")[[1]], "force_custom_plan")
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT name FROM pg_prepared_statements")), 0L)
})

test_that("on a database with no month loaded, the check stops", {
  dbname <- local_migrated_db()
  con <- local_test_db("loader", dbname = dbname)
  expect_error(check_plans(con), "No month is loaded")
})

test_that("a failing check stops unless it is report-only, and names the failures", {
  dbname <- local_loaded_db(202609L)
  con <- local_test_db("loader", dbname = dbname)
  # The failures go out as a message, which is never cut short, then the error
  expect_error(
    expect_message(
      utils::capture.output(check_plans(con, max_ms = 0)),
      "22 of 22 plan checks failed:\nwindow (window): ", fixed = TRUE
    ),
    "22 of 22 plan checks failed (listed above).", fixed = TRUE
  )
  expect_message(
    utils::capture.output(check_plans(con, max_ms = 0, report_only = TRUE)),
    "checks would fail"
  )
})

test_that("a sample code with no data, or a query that errors, fails its check only", {
  dbname <- local_loaded_db(202609L)
  con <- local_test_db("loader", dbname = dbname)
  registry <- query_registry()
  registry$practice_profile$samples$small$practice <- "ZZZ999"
  real_sql <- query_sql
  testthat::local_mocked_bindings(
    query_registry = function() registry,
    query_sql = function(query) {
      if (query == "practice_series") "SELECT no_such_column FROM app.v_window" else real_sql(query)
    }
  )
  utils::capture.output(res <- suppressMessages(check_plans(con, report_only = TRUE)))
  expect_identical(nrow(res), 22L)
  expect_identical(
    res$problems[res$query == "practice_profile" & res$sample == "small"],
    "practice ZZZ999 has no data in the months asked for"
  )
  expect_match(res$problems[res$query == "practice_series"], "^error: ")
  # The checks after it ran
  expect_false(any(is.na(res$ms[res$query == "region_comparison_presentation"])))
  expect_error(
    suppressMessages(utils::capture.output(check_plans(con))), "plan checks failed", fixed = TRUE
  )
})

test_that("a code is found only with data in the months asked for, in the order given", {
  dbname <- local_loaded_db(c(202608L, 202609L))
  con <- local_test_db("loader", dbname = dbname)
  expect_identical(lookup_id(con, "practice", c("Y03965", "N81655"), 202608L)$code, "Y03965")
  expect_identical(lookup_id(con, "practice", c("N81655", "Y03965"), 202608L)$code, "N81655")
  # Dimension rows outlive the window: a code last seen before the months is missing
  expect_true(is.na(lookup_id(con, "practice", "N81655", 202610L)$id))
  expect_identical(lookup_id(con, "practice", c("ZZZ999", "Y03965"), 202608L)$code, "Y03965")
})

test_that("with no connection given, the check opens and closes its own", {
  dbname <- local_loaded_db(202609L)
  withr::local_envvar(PREXP_DB_NAME = dbname)
  utils::capture.output(res <- suppressMessages(check_plans(report_only = TRUE, generic = TRUE)))
  expect_identical(nrow(res), 22L)
  expect_false(any(is.na(res$ms)))
})
