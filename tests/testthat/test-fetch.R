# The fetch functions (spec section 5.2; P3-02): each checks its arguments
# before it queries, runs its query file with the values bound, and returns a
# tibble with its documented columns and types. Their values are checked
# against the oracle in test-fetch-values.R (P3-03). Both read the fixture
# database, made once per test run (helper-fixture-db.R).

# Each column's class, by name
col_types <- function(df) vapply(df, function(x) class(x)[1], character(1))

int <- "integer"
dbl <- "numeric"
chr <- "character"
lgl <- "logical"

test_that("each fetch returns a tibble with its documented columns and types", {
  con <- fixture_app()
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

test_that("a series or comparison returns the measure asked for, from its level's query", {
  con <- fixture_app()
  months <- c(202608L, 202609L)
  # The level's own query, as the fetch must run it, with the measure picked
  ids <- list(
    chemical = id_of(con, "chemical", "0212000B0"),
    presentation = id_of(con, "presentation", "0212000B0AAABAB")
  )
  measures <- c("items", "total_quantity", "adq_usage", "nic", "actual_cost")
  for (level in names(ids)) {
    params <- list(ids[[level]], months[1], months[2])
    series <- DBI::dbGetQuery(con, query_sql(paste0("drug_series_", level)), params = params)
    regions <- DBI::dbGetQuery(
      con, query_sql(paste0("region_comparison_", level)), params = params
    )
    for (measure in intersect(measures, names(series))) {
      label <- paste(level, measure)
      res <- fetch_drug_series(con, level, ids[[level]], months, measure)
      expect_identical(res$measure, rep(measure, nrow(series)), label = label)
      expect_identical(res$value, as.numeric(series[[measure]]), label = label)
      res <- fetch_region_comparison(con, level, ids[[level]], months, measure)
      expect_identical(res$region_code, regions$region_code, label = label)
      expect_identical(res$value, as.numeric(regions[[measure]]), label = label)
    }
  }
})

test_that("a page of top drugs starts after the row it is given", {
  con <- fixture_app()
  practice <- id_of(con, "practice", "N81655")
  months <- c(202609L, 202609L)
  ten <- fetch_practice_top_drugs(con, practice, months, by = "nic", limit = 10)
  first <- fetch_practice_top_drugs(con, practice, months, by = "nic", limit = 5)
  second <- fetch_practice_top_drugs(
    con, practice, months, by = "nic", limit = 5, after = first$presentation_id[5]
  )
  expect_identical(nrow(ten), 10L)
  expect_identical(rbind(first, second), ten)
  expect_identical(
    fetch_practice_top_drugs(con, practice, months, by = "nic", limit = 5, after = NA), first
  )
})

test_that("an unknown id returns no rows, with the same columns", {
  con <- fixture_app()
  months <- c(202609L, 202609L)
  unknown <- 2147483647L
  chemical <- id_of(con, "chemical", "0212000B0")
  presentation <- id_of(con, "presentation", "0212000B0AAABAB")
  practice <- id_of(con, "practice", "N81655")
  other <- id_of(con, "practice", "Y03965")
  # Each call with an unknown id, beside the same call with a known one
  pairs <- list(
    function(id) fetch_drug_series(con, "chemical", id, months, "items"),
    function(id) fetch_drug_series(con, "presentation", id, months, "items"),
    function(id) fetch_drug_presentations(con, id, months),
    function(id) fetch_practice_profile(con, id),
    function(id) fetch_practice_series(con, id, months),
    function(id) fetch_practice_top_drugs(con, id, months),
    function(id) fetch_region_comparison(con, "chemical", id, months, "nic"),
    function(id) fetch_region_comparison(con, "presentation", id, months, "nic")
  )
  known <- list(chemical, presentation, chemical, practice, practice, practice, chemical,
                presentation)
  for (i in seq_along(pairs)) {
    found <- pairs[[i]](known[[i]])
    none <- pairs[[i]](unknown)
    expect_gt(nrow(found), 0L, label = i)
    expect_identical(nrow(none), 0L, label = i)
    expect_identical(col_types(none), col_types(found), label = i)
  }
  # An `after` that is not in the ranking: unknown, or from another practice's
  expect_identical(nrow(fetch_practice_top_drugs(con, practice, months, after = unknown)), 0L)
  theirs <- fetch_practice_top_drugs(con, other, months, limit = 1000)
  ours <- fetch_practice_top_drugs(con, practice, months, limit = 1000)
  foreign <- setdiff(theirs$presentation_id, ours$presentation_id)[1]
  expect_false(is.na(foreign))
  expect_identical(nrow(fetch_practice_top_drugs(con, practice, months, after = foreign)), 0L)
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
  refused(fetch_practice_top_drugs(con, 1, months, after = integer()))
  refused(fetch_practice_top_drugs(con, 1, months, after = data.frame(x = 1:2)))
  refused(fetch_practice_profile(con, tibble::tibble(practice_id = 1:2)))
  refused(fetch_region_comparison(con, "chemical", 1, months, "total_quantity"))
  refused(fetch_region_comparison(con, "chemical", 1, months, "items", per = "per_1000"))
})

test_that("a search matches %, _ and \\ as themselves", {
  con <- fixture_app()
  owner <- local_test_db("owner", dbname = local_fixture_db())
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
  # Names that start with the text come first: "Metformin hydrochloride"
  # before "Sitagliptin/metformin", which is shorter and more similar to it;
  # within each group, by similarity
  for (q in c("metformin", "sodium")) {
    res <- fetch_search_drugs(con, q, limit = 100)
    starts <- startsWith(tolower(res$name), q)
    expect_true(any(starts) && !all(starts), label = q)
    expect_identical(starts, sort(starts, decreasing = TRUE), label = q)
  }
  practices <- fetch_search_practices(con, "st", limit = 100)
  expect_identical(practices$practice_name[1], "ST WERBURGH'S MEDICAL PRACTICE HOMELESS")
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
  # No function that builds or edits text, and SQL reaches the database only
  # as a query file's text, in run_fetch()
  builders <- paste0(
    "\\b(paste0?|sprintf|format|formatC|gsub|sub|regmatches|glue[a-z_]*|str_[a-z_]+|",
    "stri_[a-z_]+|sqlInterpolate|SQL|DBI::SQL|toupper|tolower|trimws|strtoi|chartr)\\s*\\("
  )
  expect_false(any(grepl(builders, code)), label = grep(builders, code, value = TRUE)[1])
  calls <- grep("DBI::db[A-Za-z]+\\(", code, value = TRUE)
  expect_true(all(grepl("DBI::dbGetQuery\\(con, sql", calls)), label = calls[1])
  expect_identical(sum(grepl("sql <- query_sql\\(query\\)", code)), 1L)
})

test_that("the fetch functions take the app's pool as well as a connection", {
  pool <- local_test_pool(local_fixture_db())
  con <- fixture_app()
  months <- c(202609L, 202609L)
  practice <- id_of(con, "practice", "N81655")
  expect_identical(fetch_window(pool), fetch_window(con))
  expect_identical(
    fetch_practice_series(pool, practice, months), fetch_practice_series(con, practice, months)
  )
  expect_identical(fetch_search_drugs(pool, "atorva"), fetch_search_drugs(con, "atorva"))
})

test_that("fetch_regions() gives the NHS regions, not the prescribers without one", {
  con <- fixture_app()
  regions <- fetch_regions(con)
  expect_identical(names(regions), c("region_code", "region_name"))
  expect_false("-" %in% regions$region_code)
  expect_identical(regions$region_code, sort(regions$region_code))
  known <- DBI::dbGetQuery(con, "
    SELECT region_code, region_name FROM app.v_region
    WHERE region_code <> '-' ORDER BY region_code")
  expect_identical(as.data.frame(regions), known)
})
