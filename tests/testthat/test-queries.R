# The app's queries (spec section 5.2; P2-03): one SQL file per query in
# inst/sql/queries/, read by the plan check and the fetch functions. Each file
# must prepare as the app role, which can use the app schema and nothing else,
# with the parameter types the fetch functions bind; run on loaded fixture
# months, each must return its columns and the fact table's totals.

query_files <- function() {
  list.files(system.file("sql", "queries", package = "prexp"), pattern = "[.]sql$",
             full.names = TRUE)
}

# Runs a query file with these values bound, as RPostgres sends them
run_query <- function(con, query, ...) {
  params <- list(...)
  if (length(params) == 0L) {
    return(DBI::dbGetQuery(con, query_sql(query)))
  }
  DBI::dbGetQuery(con, query_sql(query), params = params)
}

# The id of a chemical, presentation or practice code
id_of <- function(con, kind, code) {
  sql <- switch(kind,
    chemical = "SELECT chemical_id FROM app.v_chemical WHERE chemical_code = $1",
    presentation = "SELECT presentation_id FROM app.v_presentation WHERE bnf_code = $1",
    practice = "SELECT practice_id FROM app.v_practice WHERE practice_code = $1"
  )
  DBI::dbGetQuery(con, sql, params = list(code))[[1]]
}

test_that("every query prepares as the app role, with the parameter types expected", {
  dbname <- local_migrated_db()
  con <- local_test_db("app", dbname = dbname)
  months <- c("integer", "integer", "integer")
  expected <- list(
    window = character(),
    search_drugs = c("text", "bigint"),
    search_practices = c("text", "bigint"),
    drug_series_chemical = months,
    drug_series_presentation = months,
    drug_presentations = months,
    practice_profile = "integer",
    practice_series = months,
    practice_top_drugs = c(months, "text", "bigint", "integer"),
    region_comparison_chemical = months,
    region_comparison_presentation = months
  )
  files <- query_files()
  expect_setequal(sub("[.]sql$", "", basename(files)), names(expected))
  for (file in files) {
    query <- sub("[.]sql$", "", basename(file))
    sql <- paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    prepared <- tryCatch(
      {
        DBI::dbExecute(con, paste("PREPARE prexp_query AS", sql))
        TRUE
      },
      error = function(e) conditionMessage(e)
    )
    expect_true(isTRUE(prepared), label = paste(query, "prepares:", prepared))
    if (isTRUE(prepared)) {
      types <- DBI::dbGetQuery(con, "
        SELECT unnest(parameter_types)::text AS type FROM pg_prepared_statements
        WHERE name = 'prexp_query'")$type
      expect_identical(types, expected[[query]], label = query)
      DBI::dbExecute(con, "DEALLOCATE prexp_query")
    }
  }
})

test_that("every query runs as the app role on loaded months, with its columns", {
  dbname <- local_loaded_db(c(202608L, 202609L))
  con <- local_test_db("app", dbname = dbname)
  chemical <- id_of(con, "chemical", "0212000B0")
  presentation <- id_of(con, "presentation", "0212000B0AAABAB")
  practice <- id_of(con, "practice", "N81655")
  months <- list(202608L, 202609L)
  calls <- list(
    window = list(),
    search_drugs = list("atorva", 20L),
    search_practices = list("n81", 20L),
    drug_series_chemical = c(chemical, months),
    drug_series_presentation = c(presentation, months),
    drug_presentations = c(chemical, months),
    practice_profile = list(practice),
    practice_series = c(practice, months),
    practice_top_drugs = c(practice, months, list("nic", 25L, NA)),
    region_comparison_chemical = c(chemical, months),
    region_comparison_presentation = c(presentation, months)
  )
  measures <- c("items", "adq_usage", "nic", "actual_cost")
  columns <- list(
    window = c("first_month", "last_month", "months", "loaded_at"),
    search_drugs = c("level", "id", "code", "name", "chemical_id", "chemical_name", "is_generic"),
    search_practices = c(
      "practice_id", "practice_code", "practice_name", "postcode", "icb_name", "region_name"
    ),
    drug_series_chemical = c("year_month", "practices", measures),
    drug_series_presentation = c(
      "year_month", "practices", "items", "total_quantity", measures[-1]
    ),
    drug_presentations = c(
      "presentation_id", "bnf_code", "bnf_description", "is_generic", "items",
      "total_quantity", measures[-1]
    ),
    practice_profile = c(
      "practice_id", "practice_code", "practice_name", "address", "postcode", "icb_code",
      "icb_name", "region_code", "region_name", "is_unidentified", "first_seen", "last_seen"
    ),
    practice_series = c("year_month", "presentations", "items", "nic", "actual_cost"),
    practice_top_drugs = c(
      "presentation_id", "bnf_code", "bnf_description", "chemical_id", "chemical_name",
      "is_generic", measures, "total"
    ),
    region_comparison_chemical = c("region_code", "region_name", measures),
    region_comparison_presentation = c(
      "region_code", "region_name", "items", "total_quantity", measures[-1]
    )
  )
  expect_setequal(names(calls), sub("[.]sql$", "", basename(query_files())))
  for (query in names(calls)) {
    res <- do.call(run_query, c(list(con, query), calls[[query]]))
    expect_identical(names(res), columns[[query]], label = query)
    expect_gt(nrow(res), 0L, label = query)
  }
})

test_that("the monthly queries add up to the fact table, for the months asked for", {
  dbname <- local_loaded_db(c(202607L, 202608L, 202609L))
  app <- local_test_db("app", dbname = dbname)
  owner <- local_test_db("owner", dbname = dbname)
  direct <- function(sql, ...) DBI::dbGetQuery(owner, sql, params = list(...))
  chemical <- id_of(app, "chemical", "0212000B0")
  presentation <- id_of(app, "presentation", "0212000B0AAABAB")
  practice <- id_of(app, "practice", "N81655")
  # Two of the three months loaded
  first <- 202608L
  last <- 202609L

  expect_identical(
    run_query(app, "drug_series_chemical", chemical, first, last),
    direct("
      SELECT f.year_month, count(DISTINCT f.practice_id)::int4 AS practices,
             sum(f.items)::int8 AS items, sum(f.adq_usage) AS adq_usage, sum(f.nic) AS nic,
             sum(f.actual_cost) AS actual_cost
      FROM core.prescribing f JOIN core.dim_presentation p USING (presentation_id)
      WHERE p.chemical_id = $1 AND f.year_month BETWEEN $2 AND $3
      GROUP BY 1 ORDER BY 1", chemical, first, last)
  )
  series <- direct("
    SELECT year_month, count(*)::int4 AS practices, sum(items)::int8 AS items,
           sum(total_quantity) AS total_quantity, sum(adq_usage) AS adq_usage, sum(nic) AS nic,
           sum(actual_cost) AS actual_cost
    FROM core.prescribing WHERE presentation_id = $1 AND year_month BETWEEN $2 AND $3
    GROUP BY 1 ORDER BY 1", presentation, first, last)
  expect_identical(
    run_query(app, "drug_series_presentation", presentation, first, last), series
  )
  expect_identical(
    run_query(app, "drug_presentations", chemical, first, last)[
      , c("presentation_id", "items", "total_quantity", "nic", "actual_cost")
    ],
    direct("
      SELECT f.presentation_id, sum(f.items)::int8 AS items,
             sum(f.total_quantity) AS total_quantity, sum(f.nic) AS nic,
             sum(f.actual_cost) AS actual_cost
      FROM core.prescribing f JOIN core.dim_presentation p USING (presentation_id)
      WHERE p.chemical_id = $1 AND f.year_month BETWEEN $2 AND $3
      GROUP BY 1 ORDER BY 2 DESC, 1", chemical, first, last)
  )
  # The regions add up to the nation
  regions <- run_query(app, "region_comparison_presentation", presentation, first, last)
  expect_identical(
    regions[, c("region_code", "items", "nic")],
    direct("
      SELECT coalesce(pr.region_code, '-') AS region_code, sum(f.items)::int8 AS items,
             sum(f.nic) AS nic
      FROM core.prescribing f JOIN core.dim_practice pr USING (practice_id)
      WHERE f.presentation_id = $1 AND f.year_month BETWEEN $2 AND $3
      GROUP BY 1 ORDER BY 1", presentation, first, last)
  )
  expect_identical(sum(regions$items), sum(series$items))
  expect_identical(
    run_query(app, "practice_series", practice, first, last),
    direct("
      SELECT year_month, count(*)::int4 AS presentations, sum(items)::int8 AS items,
             sum(nic) AS nic, sum(actual_cost) AS actual_cost
      FROM core.prescribing WHERE practice_id = $1 AND year_month BETWEEN $2 AND $3
      GROUP BY 1 ORDER BY 1", practice, first, last)
  )
  # A month with no data, and months the wrong way round, give no rows
  expect_identical(nrow(run_query(app, "practice_series", practice, 202001L, 202003L)), 0L)
  expect_identical(nrow(run_query(app, "practice_series", practice, last, first)), 0L)
})

test_that("top drugs page through every presentation once, in order, by each measure", {
  dbname <- local_loaded_db(c(202608L, 202609L))
  con <- local_test_db("app", dbname = dbname)
  owner <- local_test_db("owner", dbname = dbname)
  practice <- id_of(con, "practice", "N81655")
  for (by in c("items", "nic", "actual_cost")) {
    # The order, from the fact table: by the measure, then by presentation_id
    expected <- DBI::dbGetQuery(owner, paste0("
      SELECT presentation_id FROM core.prescribing
      WHERE practice_id = $1 AND year_month BETWEEN 202608 AND 202609
      GROUP BY presentation_id ORDER BY sum(", by, ") DESC, presentation_id DESC"),
      params = list(practice)
    )$presentation_id
    # Page by page, passing back the last presentation_id as the app would
    walked <- integer()
    after <- NA_integer_
    repeat {
      page <- run_query(con, "practice_top_drugs", practice, 202608L, 202609L, by, 25L, after)
      if (nrow(page) == 0L) {
        break
      }
      walked <- c(walked, page$presentation_id)
      after <- page$presentation_id[nrow(page)]
    }
    expect_identical(walked, expected, label = by)
  }
})

test_that("search: an exact code first, both levels, no unidentified prescriber, nameless last", {
  dbname <- local_loaded_db(202609L)
  app <- local_test_db("app", dbname = dbname)
  owner <- local_test_db("owner", dbname = dbname)
  # A code typed in full, in lower case, comes first, then its presentations
  res <- run_query(app, "search_drugs", "0212000b0", 100L)
  expect_identical(res$code[1], "0212000B0")
  expect_identical(res$level[1], "chemical")
  expect_true(all(startsWith(res$code, "0212000B0")))
  expect_true("presentation" %in% res$level)
  # A presentation without a name matches by its code, after the others
  DBI::dbExecute(owner, "
    UPDATE core.dim_presentation SET bnf_description = NULL WHERE bnf_code = '0212000B0AAABAB'")
  res <- run_query(app, "search_drugs", "0212000B0", 100L)
  expect_identical(res$code[1], "0212000B0")
  expect_identical(res$code[nrow(res)], "0212000B0AAABAB")
  # Practices: a code in full first; unidentified prescribers never
  expect_identical(run_query(app, "search_practices", "n81655", 20L)$practice_code[1], "N81655")
  unidentified <- DBI::dbGetQuery(owner, "
    SELECT practice_code, practice_name FROM core.dim_practice WHERE is_unidentified")
  expect_gt(nrow(unidentified), 0L)
  for (q in c(unidentified$practice_code, "unidentified")) {
    found <- run_query(app, "search_practices", q, 100L)$practice_code
    expect_false(any(found %in% unidentified$practice_code), label = q)
  }
})

# The plan of a query with these values bound: as text, and as nodes
plan_text <- function(con, sql, params) {
  paste(DBI::dbGetQuery(con, paste("EXPLAIN", sql), params = params)[[1]], collapse = "\n")
}
plan_of <- function(con, sql, params) {
  res <- DBI::dbGetQuery(con, paste("EXPLAIN (FORMAT JSON)", sql), params = params)
  plan_nodes(parse_plan(res)[[1]]$Plan)
}

test_that("a search for three characters or more can use an index on each side of its match", {
  dbname <- local_loaded_db(202609L)
  con <- local_test_db("app", dbname = dbname)
  # The fixture's dimensions are small enough for any scan: forbid all but
  # bitmap scans, so that the plan shows which indexes serve each side of the OR
  for (scan in c("seqscan", "indexscan", "indexonlyscan")) {
    DBI::dbExecute(con, paste0("SET enable_", scan, " = off"))
  }
  drugs <- plan_text(con, query_sql("search_drugs"), list("atorva", 20L))
  for (index in c(
    "dim_chemical_name_trgm", "dim_chemical_code_prefix",
    "dim_presentation_description_trgm", "dim_presentation_code_prefix"
  )) {
    expect_match(drugs, index, fixed = TRUE)
  }
  practices <- plan_text(con, query_sql("search_practices"), list("b83", 20L))
  expect_match(practices, "dim_practice_name_trgm", fixed = TRUE)
  expect_match(practices, "dim_practice_code_prefix", fixed = TRUE)
})

test_that("a practice's top drugs join the presentations to the page only", {
  dbname <- local_loaded_db(202609L)
  con <- local_test_db("app", dbname = dbname)
  # The view's join is left out when no presentation column is used...
  totals <- plan_of(
    con, "SELECT presentation_id, sum(items) FROM app.v_practice_presentation
          WHERE practice_id = $1 GROUP BY 1", list(1L)
  )
  expect_false("dim_presentation" %in% totals$relation)
  # ...so the query reads the presentations once, for the page's names
  top <- plan_of(con, query_sql("practice_top_drugs"), list(1L, 202609L, 202609L, "items", 25L, NA))
  expect_identical(sum(top$relation %in% "dim_presentation"), 1L)
})

test_that("two characters match the start of the name or of a word; three or more, anywhere", {
  dbname <- local_loaded_db(202609L)
  app <- local_test_db("app", dbname = dbname)
  owner <- local_test_db("owner", dbname = dbname)
  drugs <- DBI::dbGetQuery(owner, "
    SELECT 'chemical' AS level, chemical_id AS id, chemical_name AS name FROM core.dim_chemical
    UNION ALL
    SELECT 'presentation', presentation_id, bnf_description FROM core.dim_presentation")
  key <- function(rows) paste(rows$level, rows$id)
  # 'ta' starts words ("Tablets") and sits inside others ("Atorvastatin"); "ine"
  # ends many names ("Amlodipine"), chemicals and presentations alike
  for (q in c("ta", "ine")) {
    pattern <- if (nchar(q) < 3) paste0("(^| )", q) else q
    expected <- drugs[grepl(pattern, drugs$name, ignore.case = TRUE), ]
    expect_setequal(key(run_query(app, "search_drugs", q, 100000L)), key(expected))
    expect_true(any(expected$level == "chemical"), label = q)
  }
  # Practices: 'er' sits inside names ("CENTER", "SURGERY") more often than it
  # starts a word
  practices <- DBI::dbGetQuery(owner, "
    SELECT practice_code AS code, practice_name AS name FROM core.dim_practice
    WHERE NOT is_unidentified")
  inside <- grepl("er", practices$name, ignore.case = TRUE)
  word_start <- grepl("(^| )er", practices$name, ignore.case = TRUE)
  expect_gt(sum(inside), sum(word_start))
  found <- run_query(app, "search_practices", "er", 100L)
  expect_setequal(found$practice_code, practices$code[word_start])
})

test_that("a chemical's presentations read the rollup's covering key, index-only", {
  dbname <- local_loaded_db(202609L)
  app <- local_test_db("app", dbname = dbname)
  owner <- local_test_db("owner", dbname = dbname)
  # The loader vacuums the rollups after the swap, so their visibility maps are set
  maps <- DBI::dbGetQuery(owner, "
    SELECT relname, relpages, relallvisible FROM pg_class
    WHERE relname IN ('agg_presentation_month', 'agg_chemical_month', 'agg_practice_month')")
  expect_true(all(maps$relpages > 0))
  expect_identical(maps$relallvisible, maps$relpages)
  # The fixture's rollup is small enough for any scan: forbid the heap ones
  for (scan in c("seqscan", "bitmapscan")) {
    DBI::dbExecute(app, paste0("SET enable_", scan, " = off"))
  }
  chemical <- id_of(app, "chemical", "0212000B0")
  res <- DBI::dbGetQuery(
    app, paste("EXPLAIN (ANALYZE, FORMAT JSON)", query_sql("drug_presentations")),
    params = list(chemical, 202609L, 202609L)
  )
  nodes <- plan_nodes(parse_plan(res)[[1]]$Plan)
  rollup <- nodes[nodes$relation %in% "agg_presentation_month", ]
  expect_identical(unique(rollup$node_type), "Index Only Scan")
  expect_identical(sum(rollup$heap_fetches), 0)
})
