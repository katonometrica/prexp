# The fetch functions (spec section 5.2; P3-02): each checks its arguments
# before it queries, runs its query file with the values bound, and returns a
# tibble with its documented columns and types. Their values are checked
# against the oracle in test-fetch-values.R (P3-03).

# Each column's class, by name
col_types <- function(df) vapply(df, function(x) class(x)[1], character(1))

int <- "integer"
dbl <- "numeric"
chr <- "character"
lgl <- "logical"

test_that("each fetch returns a tibble with its documented columns and types", {
  dbname <- local_loaded_db(c(202608L, 202609L))
  con <- local_test_db("app", dbname = dbname)
  chemical <- id_of(con, "chemical", "0212000B0")
  presentation <- id_of(con, "presentation", "0212000B0AAABAB")
  practice <- id_of(con, "practice", "N81655")
  months <- c(202608L, 202609L)
  expect_columns <- function(res, types) {
    expect_s3_class(res, "tbl_df")
    expect_identical(col_types(res), types)
    expect_gt(nrow(res), 0L)
  }
  measures <- c(items = dbl, adq_usage = dbl, nic = dbl, actual_cost = dbl)

  expect_columns(
    fetch_window(con),
    c(first_month = int, last_month = int, months = int, loaded_at = "POSIXct")
  )
  expect_columns(
    fetch_search_drugs(con, "atorva"),
    c(
      level = chr, id = int, code = chr, name = chr, chemical_id = int,
      chemical_name = chr, is_generic = lgl
    )
  )
  expect_columns(
    fetch_search_practices(con, "n81"),
    c(
      practice_id = int, practice_code = chr, practice_name = chr, postcode = chr,
      icb_name = chr, region_name = chr
    )
  )
  series <- c(year_month = int, measure = chr, value = dbl, practices = int)
  expect_columns(fetch_drug_series(con, "chemical", chemical, months, "nic"), series)
  expect_columns(
    fetch_drug_series(con, "presentation", presentation, months, "total_quantity"), series
  )
  expect_columns(
    fetch_drug_presentations(con, chemical, months),
    c(
      presentation_id = int, bnf_code = chr, bnf_description = chr, is_generic = lgl,
      items = dbl, total_quantity = dbl, measures[-1]
    )
  )
  expect_columns(
    fetch_practice_profile(con, practice),
    c(
      practice_id = int, practice_code = chr, practice_name = chr, address = chr,
      postcode = chr, icb_code = chr, icb_name = chr, region_code = chr, region_name = chr,
      is_unidentified = lgl, first_seen = int, last_seen = int
    )
  )
  expect_columns(
    fetch_practice_series(con, practice, months),
    c(year_month = int, presentations = int, items = dbl, nic = dbl, actual_cost = dbl)
  )
  expect_columns(
    fetch_practice_top_drugs(con, practice, months, by = "actual_cost", limit = 5),
    c(
      presentation_id = int, bnf_code = chr, bnf_description = chr, chemical_id = int,
      chemical_name = chr, is_generic = lgl, measures, total = dbl
    )
  )
  regions <- c(region_code = chr, region_name = chr, measure = chr, value = dbl)
  expect_columns(fetch_region_comparison(con, "chemical", chemical, months, "items"), regions)
  expect_columns(
    fetch_region_comparison(con, "presentation", presentation, months, "adq_usage"), regions
  )
})

test_that("a series or comparison returns the measure asked for, as value", {
  dbname <- local_loaded_db(202609L)
  con <- local_test_db("app", dbname = dbname)
  presentation <- id_of(con, "presentation", "0212000B0AAABAB")
  months <- c(202609L, 202609L)
  raw <- DBI::dbGetQuery(
    con, query_sql("drug_series_presentation"), params = list(presentation, 202609L, 202609L)
  )
  for (measure in c("items", "total_quantity", "adq_usage", "nic", "actual_cost")) {
    res <- fetch_drug_series(con, "presentation", presentation, months, measure)
    expect_identical(res$measure, measure)
    expect_identical(res$value, as.numeric(raw[[measure]]), label = measure)
  }
})

test_that("an unknown id returns no rows, with the same columns", {
  dbname <- local_loaded_db(202609L)
  con <- local_test_db("app", dbname = dbname)
  months <- c(202609L, 202609L)
  unknown <- 2147483647L
  calls <- list(
    fetch_drug_series(con, "chemical", unknown, months, "items"),
    fetch_drug_presentations(con, unknown, months),
    fetch_practice_profile(con, unknown),
    fetch_practice_series(con, unknown, months),
    fetch_practice_top_drugs(con, unknown, months),
    fetch_region_comparison(con, "presentation", unknown, months, "nic")
  )
  for (res in calls) {
    expect_s3_class(res, "tbl_df")
    expect_identical(nrow(res), 0L)
    expect_gt(ncol(res), 0L)
  }
  expect_identical(
    col_types(fetch_drug_series(con, "chemical", unknown, months, "items")),
    c(year_month = int, measure = chr, value = dbl, practices = int)
  )
})

test_that("every fetch checks its arguments before it queries", {
  # No connection at all: a refused argument must stop the call first
  con <- NULL
  months <- c(202609L, 202609L)
  refused <- function(call) expect_error(call, class = "prexp_invalid_argument")
  refused(fetch_search_drugs(con, "a"))
  refused(fetch_search_drugs(con, "atorva", limit = 0))
  refused(fetch_search_practices(con, strrep("a", 101)))
  refused(fetch_search_practices(con, "abc", limit = 101))
  refused(fetch_drug_series(con, "substance", 1, months, "items"))
  refused(fetch_drug_series(con, "chemical", 0, months, "items"))
  refused(fetch_drug_series(con, "chemical", 1, c(202609, 202608), "items"))
  refused(fetch_drug_series(con, "chemical", 1, months, "total_quantity"))
  refused(fetch_drug_presentations(con, "abc", months))
  refused(fetch_drug_presentations(con, 1, 202609))
  refused(fetch_practice_profile(con, NA))
  refused(fetch_practice_series(con, 1, c(202609, 202613)))
  refused(fetch_practice_top_drugs(con, 1, months, by = "total_quantity"))
  refused(fetch_practice_top_drugs(con, 1, months, limit = 1001))
  refused(fetch_practice_top_drugs(con, 1, months, after = -5))
  refused(fetch_region_comparison(con, "chemical", 1, months, "total_quantity"))
  refused(fetch_region_comparison(con, "chemical", 1, months, "items", per = "per_1000"))
})

test_that("a search matches %, _ and \\ as themselves", {
  dbname <- local_loaded_db(202609L)
  con <- local_test_db("app", dbname = dbname)
  owner <- local_test_db("owner", dbname = dbname)
  names <- DBI::dbGetQuery(owner, "
    SELECT chemical_name AS name FROM core.dim_chemical
    UNION ALL SELECT bnf_description FROM core.dim_presentation")$name
  names <- names[!is.na(names)]
  # Percentages are in many names: "1%" must start a word, not stand for "1"
  # followed by anything
  res <- fetch_search_drugs(con, "1%", limit = 100)
  expected <- names[grepl("(^| )1%", names, ignore.case = TRUE)]
  expect_gt(length(expected), 0L)
  expect_setequal(res$name, expected)
  # No name holds two underscores or a backslash, which unescaped would match
  # every name
  for (q in c("__", "\\a", "%%")) {
    expect_identical(nrow(fetch_search_drugs(con, q, limit = 100)), 0L, label = q)
    expect_identical(nrow(fetch_search_practices(con, q, limit = 100)), 0L, label = q)
  }
  # A name that contains the text is ranked by similarity, with q as typed
  res <- fetch_search_drugs(con, "0.1% cream", limit = 100)
  expect_gt(nrow(res), 1L)
  expect_true(all(grepl("0.1% cream", res$name, fixed = TRUE)))
  similarity <- DBI::dbGetQuery(con, "
    SELECT similarity(n, $1) AS s
    FROM jsonb_array_elements_text($2::jsonb) WITH ORDINALITY AS t(n, i)
    ORDER BY i", params = list("0.1% cream", as.character(jsonlite::toJSON(res$name))))$s
  expect_identical(similarity, sort(similarity, decreasing = TRUE))
})

test_that("no SQL is built from strings in fct_queries.R", {
  path <- testthat::test_path("..", "..", "R", "fct_queries.R")
  skip_if_not(file.exists(path), "The package sources are not here")
  code <- readLines(path, warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  expect_false(any(grepl("\\b(paste0?|sprintf|glue|str_c|str_glue)\\s*\\(", code)))
})

test_that("the fetch functions take the app's pool as well as a connection", {
  dbname <- local_loaded_db(202609L)
  pool <- local_test_pool(dbname)
  con <- local_test_db("app", dbname = dbname)
  months <- c(202609L, 202609L)
  practice <- id_of(con, "practice", "N81655")
  expect_identical(fetch_window(pool), fetch_window(con))
  expect_identical(
    fetch_practice_series(pool, practice, months), fetch_practice_series(con, practice, months)
  )
  expect_identical(fetch_search_drugs(pool, "atorva"), fetch_search_drugs(con, "atorva"))
})
