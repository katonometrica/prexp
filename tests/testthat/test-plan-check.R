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
})

test_that("months count across the turn of the year", {
  expect_identical(index_month(month_index(202601L) - 1L), 202512L)
  expect_identical(index_month(month_index(202609L) - 2L), 202607L)
  expect_identical(index_month(month_index(202512L) + 1L), 202601L)
  expect_identical(month_index(202609L) - month_index(202510L) + 1L, 12L)
})

test_that("a clean plan passes: index-only scans of the twelve months asked for", {
  res <- plan_summary(read_plan("clean"), max_ms = 50, months = 12L)
  expect_identical(res$seq_scans, 0L)
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
  # The large practice of the full data is not in the fixtures: its stand-in is used
  expect_identical(res$codes[res$query == "practice_series" & res$sample == "large"], "N81655")
  # Every sample found, every plan read
  expect_false(any(grepl("is not in the database", res$problems)))
  expect_false(any(is.na(res$ms)))
  # The large sample asks for the whole window, the small one for three months,
  # and the plan reads no more partitions than that
  top <- res[res$query == "practice_top_drugs", ]
  expect_identical(top$months, c(4L, 3L))
  expect_identical(top$partitions, c(4L, 3L))
  expect_false(any(grepl("partitions for", res$problems)))
  # One JSON line per check
  lines <- grep("^[{]", output, value = TRUE)
  expect_length(lines, nrow(res))
  first <- jsonlite::fromJSON(lines[1])
  expect_identical(first$event, "plan_check")
  expect_identical(first$plan, "custom")
  expect_identical(first$query, res$query[1])
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
  expect_error(
    utils::capture.output(check_plans(con, max_ms = 0)),
    "plan checks failed:\nwindow (window): ", fixed = TRUE
  )
  expect_message(
    utils::capture.output(check_plans(con, max_ms = 0, report_only = TRUE)),
    "checks would fail"
  )
})
