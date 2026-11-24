# The fetch functions' values (spec section 6.1; P3-03). The fixture database
# holds the thirteen fixture months loaded by the real loader, and the window
# keeps the last twelve. Every fetch runs as the app, so these tests also prove
# the app role's grants. Expected values come from helper-oracle.R, which
# aggregates the fixture files with dplyr, never from the code under test.

# The oracles, over the window, computed once for this file
oracle <- new.env(parent = emptyenv())
from_oracle <- function(name, compute) {
  if (is.null(oracle[[name]])) {
    oracle[[name]] <- compute()
  }
  oracle[[name]]
}
chemical_month <- function() {
  from_oracle("chemical_month", function() oracle_chemical_month(fixture_window()))
}
presentation_month <- function() {
  from_oracle("presentation_month", function() oracle_presentation_month(fixture_window()))
}
practice_month <- function() {
  from_oracle("practice_month", function() oracle_practice_month(fixture_window()))
}
fact <- function() from_oracle("fact", function() oracle_fact(fixture_window()))
presentations <- function() from_oracle("presentations", oracle_presentations)
practices <- function() from_oracle("practices", oracle_practices)
region_names <- function() from_oracle("region_names", oracle_region_names)

# A fetched measure in whole units of its smallest decimal, as the oracle
# holds it; items are whole already. The database sums the decimals exactly,
# and the double read back rounds to the same whole number.
in_units <- function(x, measure) {
  if (measure == "items") x else round(x * 10^measure_digits[[measure]])
}

# An oracle sum as the database keeps it: no defined daily quantity, a sum of
# 0, is NULL
as_stored <- function(x, measure) {
  if (measure == "adq_usage") {
    x[x == 0] <- NA
  }
  x
}

# Codes spread over the sorted list, so that a sample reaches every chapter
spread <- function(codes, n) {
  codes <- sort(unique(codes), method = "radix")
  codes[unique(round(seq(1, length(codes), length.out = min(n, length(codes)))))]
}

# A sample of a rollup's codes: n spread over the list, and the first code
# with each case the queries must get right, which no spread is sure to reach:
# two practices of one region in one month, no ADQ at all, an appliance, and
# prescribing under region '-'
sample_codes <- function(agg, key, n) {
  first <- function(rows) sort(unique(rows[[key]]), method = "radix")[1]
  no_adq <- vapply(split(agg$adq_usage, agg[[key]]), function(x) all(x == 0), logical(1))
  cases <- c(
    shared = first(agg[agg$practices > 1L, ]),
    no_adq = sort(names(no_adq)[no_adq], method = "radix")[1],
    appliance = first(agg[substr(agg[[key]], 1L, 2L) %in% c("20", "21", "22", "23"), ]),
    no_region = first(agg[agg$region_code == "-", ])
  )
  stopifnot(!anyNA(cases))
  unique(c(spread(agg[[key]], n), unname(cases)))
}

# Month ranges: the whole window, its last three months, one month, and the
# month the window dropped, which has no rows left
ranges <- function() {
  w <- fixture_window()
  list(
    whole = c(w[1], w[12]), last3 = c(w[10], w[12]), one = c(w[4], w[4]),
    dropped = rep(fixture_months()[1], 2)
  )
}

within <- function(rows, r) rows[rows$year_month >= r[1] & rows$year_month <= r[2], ]

drug_measures <- function(level) {
  if (level == "chemical") {
    c("items", "adq_usage", "nic", "actual_cost")
  } else {
    c("items", "total_quantity", "adq_usage", "nic", "actual_cost")
  }
}

test_that("the fixture database is read-only for every login, once loaded", {
  owner <- local_test_db("owner", dbname = local_fixture_db())
  expect_error(
    DBI::dbExecute(owner, "CREATE TABLE public.not_allowed (x int)"), "read-only transaction"
  )
})

test_that("fetch_window() gives the twelve months the loads left", {
  con <- fixture_app()
  window <- fetch_window(con)
  expect_identical(window$first_month, fixture_window()[1])
  expect_identical(window$last_month, fixture_window()[12])
  expect_identical(window$months, 12L)
  expect_false(is.na(window$loaded_at))
})

# Each expectation costs a few milliseconds, so the tests below compare a whole
# subject at once: its rows for every range and measure in one data frame,
# with the range as a column. A failure shows the rows that differ.

# A result's measures in the oracle's whole units
as_oracle <- function(res, measures) {
  out <- as.data.frame(res)
  for (m in intersect(measures, names(out))) {
    out[[m]] <- in_units(out[[m]], m)
  }
  out
}

# An oracle's measures as the database keeps them
stored <- function(df, measures) {
  for (m in measures) {
    df[[m]] <- as_stored(df[[m]], m)
  }
  df
}

# Frames stacked, with plain row names
bind <- function(frames) {
  out <- do.call(rbind, unname(frames))
  rownames(out) <- NULL
  out
}

test_that("fetch_drug_series() gives the oracle's national monthly totals", {
  con <- fixture_app()
  for (level in c("chemical", "presentation")) {
    agg <- if (level == "chemical") chemical_month() else presentation_month()
    key <- if (level == "chemical") "chemical_code" else "bnf_code"
    measures <- drug_measures(level)
    for (code in sample_codes(agg, key, 12)) {
      id <- id_of(con, level, code)
      got <- list()
      expected <- list()
      for (range in names(ranges())) {
        r <- ranges()[[range]]
        sums <- oracle_sum(
          within(agg[agg[[key]] == code, ], r), "year_month", c(measures, "practices")
        )
        for (measure in measures) {
          res <- fetch_drug_series(con, level, id, r, measure)
          got[[length(got) + 1L]] <- data.frame(
            range = rep(range, nrow(res)), year_month = res$year_month, measure = res$measure,
            value = in_units(res$value, measure), practices = res$practices
          )
          expected[[length(expected) + 1L]] <- data.frame(
            range = rep(range, nrow(sums)), year_month = sums$year_month,
            measure = rep(measure, nrow(sums)), value = as_stored(sums[[measure]], measure),
            practices = sums$practices
          )
        }
      }
      expect_identical(bind(got), bind(expected), label = paste(level, code))
    }
  }
})

test_that("fetch_drug_presentations() gives each presentation's totals, most items first", {
  con <- fixture_app()
  info <- presentations()
  ids <- DBI::dbGetQuery(con, "SELECT bnf_code, presentation_id FROM app.v_presentation")
  agg <- presentation_month()
  agg$chemical_code <- info$chemical_code[match(agg$bnf_code, info$bnf_code)]
  measures <- drug_measures("presentation")
  columns <- c("range", "presentation_id", "bnf_code", "bnf_description", "is_generic", measures)
  for (code in sample_codes(agg, "chemical_code", 15)) {
    id <- id_of(con, "chemical", code)
    got <- list()
    expected <- list()
    for (range in names(ranges())) {
      r <- ranges()[[range]]
      res <- as_oracle(fetch_drug_presentations(con, id, r), measures)
      res$range <- rep(range, nrow(res))
      got[[range]] <- res[columns]
      sums <- oracle_sum(within(agg[agg$chemical_code %in% code, ], r), "bnf_code", measures)
      sums <- stored(sums, measures)
      sums$presentation_id <- ids$presentation_id[match(sums$bnf_code, ids$bnf_code)]
      described <- info[match(sums$bnf_code, info$bnf_code), ]
      sums$bnf_description <- described$bnf_description
      sums$is_generic <- described$is_generic
      sums$range <- rep(range, nrow(sums))
      expected[[range]] <- sums[order(-sums$items, sums$presentation_id), columns]
    }
    expect_identical(bind(got), bind(expected), label = code)
  }
})

test_that("fetch_practice_profile() describes each prescriber as the latest month does", {
  con <- fixture_app()
  expected <- practices()
  expect_gt(nrow(expected), 8L)
  for (i in seq_len(nrow(expected))) {
    profile <- as.list(expected[i, ])
    got <- fetch_practice_profile(con, id_of(con, "practice", profile$practice_code))
    expect_identical(nrow(got), 1L)
    expect_identical(as.list(got[names(profile)]), profile, label = profile$practice_code)
  }
})

test_that("fetch_practice_series() gives each prescriber's monthly totals", {
  con <- fixture_app()
  agg <- practice_month()
  measures <- c("items", "nic", "actual_cost")
  columns <- c("range", "year_month", "presentations", measures)
  for (code in unique(agg$practice_code)) {
    id <- id_of(con, "practice", code)
    got <- list()
    expected <- list()
    for (range in names(ranges())) {
      r <- ranges()[[range]]
      res <- as_oracle(fetch_practice_series(con, id, r), measures)
      res$range <- rep(range, nrow(res))
      got[[range]] <- res[columns]
      sums <- within(agg[agg$practice_code == code, ], r)
      sums$range <- rep(range, nrow(sums))
      expected[[range]] <- sums[columns]
    }
    expect_identical(bind(got), bind(expected), label = code)
  }
})

test_that("fetch_practice_top_drugs() pages through the oracle's ranking, no row twice or missed", {
  con <- fixture_app()
  info <- presentations()
  ids <- DBI::dbGetQuery(con, "SELECT bnf_code, presentation_id FROM app.v_presentation")
  chemical_ids <- DBI::dbGetQuery(con, "SELECT chemical_code, chemical_id FROM app.v_chemical")
  rows <- fact()
  measures <- c("items", "adq_usage", "nic", "actual_cost")
  columns <- c(
    "key", "presentation_id", "bnf_code", "bnf_description", "chemical_id", "chemical_name",
    "is_generic",
    measures, "total"
  )
  # Every page, the last one short or empty. At most one page more than the
  # ranking needs: a paging that ignored `after` must fail here, not loop.
  walk <- function(id, r, by, n) {
    pages <- list()
    after <- NULL
    for (i in seq_len(n %/% 25L + 2L)) {
      page <- fetch_practice_top_drugs(con, id, r, by = by, limit = 25L, after = after)
      pages[[i]] <- page
      if (nrow(page) < 25L) break
      after <- page$presentation_id[nrow(page)]
    }
    pages
  }
  for (code in unique(rows$practice_code)) {
    id <- id_of(con, "practice", code)
    got <- list()
    expected <- list()
    sizes <- list()
    for (range in c("whole", "last3")) {
      r <- ranges()[[range]]
      totals <- oracle_sum(within(rows[rows$practice_code == code, ], r), "bnf_code", measures)
      totals$presentation_id <- ids$presentation_id[match(totals$bnf_code, ids$bnf_code)]
      described <- info[match(totals$bnf_code, info$bnf_code), ]
      totals$bnf_description <- described$bnf_description
      totals$chemical_id <- chemical_ids$chemical_id[
        match(described$chemical_code, chemical_ids$chemical_code)
      ]
      totals$chemical_name <- described$chemical_name
      totals$is_generic <- described$is_generic
      for (by in c("items", "nic", "actual_cost")) {
        key <- paste(range, by)
        pages <- walk(id, r, by, nrow(totals))
        sizes[[key]] <- vapply(pages, nrow, integer(1))
        res <- as_oracle(do.call(rbind, pages), measures)
        res$total <- in_units(res$total, by)
        res$key <- rep(key, nrow(res))
        got[[key]] <- res[columns]
        ranked <- stored(totals, measures)
        ranked$total <- totals[[by]]
        ranked$key <- rep(key, nrow(ranked))
        expected[[key]] <- ranked[order(-totals[[by]], -totals$presentation_id), columns]
      }
    }
    expect_identical(bind(got), bind(expected), label = code)
    # Every page but the last is full
    full <- vapply(sizes, function(s) all(s[-length(s)] == 25L) && s[length(s)] < 25L, TRUE)
    expect_true(all(full), label = code)
  }
  # A page starts right after the previous page's last row
  code <- names(sort(table(rows$practice_code), decreasing = TRUE))[1]
  id <- id_of(con, "practice", code)
  whole <- ranges()$whole
  all_rows <- fetch_practice_top_drugs(con, id, whole, by = "nic", limit = 1000L)
  first <- fetch_practice_top_drugs(con, id, whole, by = "nic", limit = 10L)
  second <- fetch_practice_top_drugs(
    con, id, whole, by = "nic", limit = 10L, after = first$presentation_id[10]
  )
  expect_identical(first$presentation_id, all_rows$presentation_id[1:10])
  expect_identical(second$presentation_id, all_rows$presentation_id[11:20])
})

test_that("fetch_region_comparison() gives each region's totals, with its name", {
  con <- fixture_app()
  named <- region_names()
  for (level in c("chemical", "presentation")) {
    agg <- if (level == "chemical") chemical_month() else presentation_month()
    key <- if (level == "chemical") "chemical_code" else "bnf_code"
    measures <- drug_measures(level)
    for (code in sample_codes(agg, key, 10)) {
      id <- id_of(con, level, code)
      got <- list()
      expected <- list()
      for (range in names(ranges())) {
        r <- ranges()[[range]]
        sums <- oracle_sum(within(agg[agg[[key]] == code, ], r), "region_code", measures)
        # In order of region_code, as documented: the codes ('-' and Y56 to
        # Y63) sort the same in the database's collation as byte by byte
        sums <- sums[order(sums$region_code, method = "radix"), ]
        for (measure in measures) {
          res <- fetch_region_comparison(con, level, id, r, measure)
          got[[length(got) + 1L]] <- data.frame(
            range = rep(range, nrow(res)), region_code = res$region_code,
            region_name = res$region_name, measure = res$measure,
            value = in_units(res$value, measure)
          )
          expected[[length(expected) + 1L]] <- data.frame(
            range = rep(range, nrow(sums)), region_code = sums$region_code,
            region_name = unname(named[sums$region_code]), measure = rep(measure, nrow(sums)),
            value = as_stored(sums[[measure]], measure)
          )
        }
      }
      expect_identical(bind(got), bind(expected), label = paste(level, code))
    }
  }
})

# The ids the database gave each code, the only values the search tests take
# from it: the rest of each expected row comes from the fixture files
code_ids <- function(con) {
  list(
    chemical = with(
      DBI::dbGetQuery(con, "SELECT chemical_code, chemical_id FROM app.v_chemical"),
      structure(chemical_id, names = chemical_code)
    ),
    presentation = with(
      DBI::dbGetQuery(con, "SELECT bnf_code, presentation_id FROM app.v_presentation"),
      structure(presentation_id, names = bnf_code)
    ),
    practice = with(
      DBI::dbGetQuery(con, "SELECT practice_code, practice_id FROM app.v_practice"),
      structure(practice_id, names = practice_code)
    )
  )
}

# Rows in one order, with plain row names: a repeated row still shows
in_order <- function(df, keys) {
  df <- as.data.frame(df)
  df <- df[do.call(order, c(unname(as.list(df[keys])), method = "radix")), , drop = FALSE]
  rownames(df) <- NULL
  df
}

test_that("fetch_search_drugs() matches names and code prefixes, whatever the case", {
  con <- fixture_app()
  info <- presentations()
  ids <- code_ids(con)
  chemicals <- unique(info[c("chemical_code", "chemical_name")])
  drugs <- rbind(
    data.frame(
      level = "chemical", id = unname(ids$chemical[chemicals$chemical_code]),
      code = chemicals$chemical_code, name = chemicals$chemical_name,
      chemical_id = unname(ids$chemical[chemicals$chemical_code]),
      chemical_name = chemicals$chemical_name, is_generic = NA
    ),
    data.frame(
      level = "presentation", id = unname(ids$presentation[info$bnf_code]),
      code = info$bnf_code, name = info$bnf_description,
      chemical_id = unname(ids$chemical[info$chemical_code]),
      chemical_name = info$chemical_name, is_generic = info$is_generic
    )
  )
  matching <- function(q) {
    in_name <- grepl(tolower(q), tolower(drugs$name), fixed = TRUE)
    drugs[in_name | startsWith(drugs$code, toupper(q)), ]
  }
  keys <- c("level", "code")
  # A name that contains the text, ignoring case: every column of every row
  for (q in c("atorva", "ATORVA", "AtOrVa", "cream")) {
    expected <- matching(q)
    expect_gt(nrow(expected), 0L)
    expect_lte(nrow(expected), 100L)
    got <- fetch_search_drugs(con, q, limit = 100)
    expect_identical(in_order(got, keys), in_order(expected, keys), label = q)
  }
  expect_identical(fetch_search_drugs(con, "ATORVA"), fetch_search_drugs(con, "atorva"))
  # A code prefix, in either case: the chemical typed in full comes first
  for (q in c("0212000B0", "0212000b0")) {
    got <- fetch_search_drugs(con, q, limit = 100)
    expect_identical(got$code[1], "0212000B0")
    expect_identical(in_order(got, keys), in_order(matching(q), keys), label = q)
  }
  # The limit takes the best matches
  all_rows <- fetch_search_drugs(con, "tablets", limit = 100)
  expect_identical(nrow(all_rows), 100L)
  expect_identical(fetch_search_drugs(con, "tablets", limit = 5), all_rows[1:5, ])
  expect_identical(nrow(fetch_search_drugs(con, "tablets")), 20L)
  # Two characters at least, once the spaces at either end are gone
  expect_error(fetch_search_drugs(con, "a"), class = "prexp_invalid_argument")
  expect_error(fetch_search_drugs(con, "  a  "), "it has 1", fixed = TRUE)
  expect_gt(nrow(fetch_search_drugs(con, "at")), 0L)
})

test_that("fetch_search_practices() matches names and codes, never the unidentified", {
  con <- fixture_app()
  ids <- code_ids(con)
  known <- practices()[!practices()$is_unidentified, ]
  rows <- data.frame(
    practice_id = unname(ids$practice[known$practice_code]),
    known[c("practice_code", "practice_name", "postcode", "icb_name", "region_name")]
  )
  matching <- function(q) {
    in_name <- grepl(tolower(q), tolower(rows$practice_name), fixed = TRUE)
    rows[in_name | startsWith(rows$practice_code, toupper(q)), ]
  }
  # A word of four letters or more matches anywhere in a name: every column
  words <- unlist(strsplit(known$practice_name, " ", fixed = TRUE))
  name_word <- words[nchar(words) >= 4L][1]
  for (q in c(name_word, tolower(name_word), substr(known$practice_code[1], 1L, 3L))) {
    expected <- matching(q)
    expect_gt(nrow(expected), 0L)
    got <- fetch_search_practices(con, q, limit = 100)
    expect_identical(
      in_order(got, "practice_code"), in_order(expected, "practice_code"), label = q
    )
  }
  code <- known$practice_code[1]
  expect_identical(fetch_search_practices(con, tolower(code))$practice_code[1], code)
  # The limit takes the best matches, of a word several names share
  common <- names(sort(table(tolower(words[nchar(words) >= 4L])), decreasing = TRUE))[1]
  all_rows <- fetch_search_practices(con, common, limit = 100)
  expect_gt(nrow(all_rows), 1L)
  expect_identical(fetch_search_practices(con, common, limit = 1), all_rows[1, ])
  # The national unidentified prescriber's code, '-', is too short to search for
  unidentified <- practices()$practice_code[practices()$is_unidentified]
  expect_gt(sum(nchar(unidentified) >= 2L), 0L)
  for (q in c(unidentified[nchar(unidentified) >= 2L], "unidentified")) {
    found <- fetch_search_practices(con, q, limit = 100)$practice_code
    expect_false(any(found %in% unidentified), label = q)
  }
  expect_error(fetch_search_practices(con, "N"), "it has 1", fixed = TRUE)
})

# The fixture months repeat one month's codes, names and regions, so two rules
# need a database of their own, changed by hand: a region is named after its
# most recently seen practice, and the searches leave out codes last seen
# before the window
test_that("a region takes its name from its most recently seen practice", {
  dbname <- local_loaded_db(c(202608L, 202609L))
  owner <- local_test_db("owner", dbname = dbname)
  con <- local_test_db("app", dbname = dbname)
  shared <- DBI::dbGetQuery(owner, "
    SELECT region_code, array_agg(practice_id ORDER BY practice_id) AS ids
    FROM core.dim_practice WHERE region_code IS NOT NULL AND region_code <> '-'
    GROUP BY region_code HAVING count(*) >= 2 ORDER BY region_code LIMIT 1")
  expect_identical(nrow(shared), 1L)
  first <- as.integer(strsplit(gsub("[{}]", "", shared$ids), ",")[[1]][1:2])
  chemical <- DBI::dbGetQuery(
    owner, "SELECT chemical_id FROM core.agg_chemical_month WHERE region_code = $1 LIMIT 1",
    params = list(shared$region_code)
  )$chemical_id
  name_of <- function() {
    res <- fetch_region_comparison(con, "chemical", chemical, c(202608L, 202609L), "items")
    res$region_name[res$region_code == shared$region_code]
  }
  original <- name_of()
  # A later name on the second practice: a tie on last_seen keeps the first's
  DBI::dbExecute(
    owner, "UPDATE core.dim_practice SET region_name = 'RENAMED' WHERE practice_id = $1",
    params = list(first[2])
  )
  expect_identical(name_of(), original)
  # Seen more recently than the first, the second practice names the region
  DBI::dbExecute(
    owner, "UPDATE core.dim_practice SET last_seen = 202608 WHERE practice_id = $1",
    params = list(first[1])
  )
  expect_identical(name_of(), "RENAMED")
})

test_that("the searches leave out codes last seen before the window", {
  dbname <- local_loaded_db(c(202608L, 202609L))
  owner <- local_test_db("owner", dbname = dbname)
  con <- local_test_db("app", dbname = dbname)
  expect_true("0212000B0AAABAB" %in% fetch_search_drugs(con, "0212000B0", limit = 100)$code)
  expect_true("0212000B0" %in% fetch_search_drugs(con, "0212000B0", limit = 100)$code)
  expect_identical(fetch_search_practices(con, "N81655")$practice_code, "N81655")
  DBI::dbExecute(owner, "
    UPDATE core.dim_presentation SET first_seen = 202607, last_seen = 202607
    WHERE bnf_code = '0212000B0AAABAB'")
  DBI::dbExecute(owner, "
    UPDATE core.dim_chemical SET first_seen = 202607, last_seen = 202607
    WHERE chemical_code = '0212000B0'")
  DBI::dbExecute(owner, "
    UPDATE core.dim_practice SET first_seen = 202607, last_seen = 202607
    WHERE practice_code = 'N81655'")
  codes <- fetch_search_drugs(con, "0212000B0", limit = 100)$code
  expect_false("0212000B0AAABAB" %in% codes)
  expect_false("0212000B0" %in% codes)
  expect_identical(nrow(fetch_search_practices(con, "N81655")), 0L)
})

test_that("a refused argument says what it must be, before any query", {
  months <- c(202609L, 202609L)
  refused <- function(call, message) {
    expect_error(call, message, fixed = TRUE, class = "prexp_invalid_argument")
  }
  refused(
    fetch_drug_series(NULL, "chemical", 1, c(202609, 202510), "items"),
    paste0(
      "`months` must be two months as YYYYMM, the first not after the last, ",
      "for example c(202510, 202609), not c(202609, 202510)."
    )
  )
  refused(
    fetch_drug_series(NULL, "substance", 1, months, "items"),
    "`level` must be one of \"chemical\", \"presentation\", not \"substance\"."
  )
  refused(
    fetch_practice_profile(NULL, "abc"),
    "`practice_id` must be one id, a whole number from 1 to 2147483647, not \"abc\"."
  )
  refused(fetch_practice_series(NULL, "abc", months), "`practice_id` must be one id")
  refused(fetch_practice_top_drugs(NULL, "abc", months), "`practice_id` must be one id")
  refused(fetch_drug_presentations(NULL, "abc", months), "`chemical_id` must be one id")
  refused(fetch_drug_series(NULL, "chemical", "abc", months, "items"), "`id` must be one id")
  refused(fetch_search_drugs(NULL, "a"), "`q` must be 2 to 100 characters")
  refused(
    fetch_search_drugs(NULL, "atorva", limit = 101),
    "`limit` must be a whole number from 1 to 100, not 101."
  )
  refused(
    fetch_search_practices(NULL, "atorva", limit = 101),
    "`limit` must be a whole number from 1 to 100, not 101."
  )
  refused(
    fetch_practice_top_drugs(NULL, 1, months, by = "quantity"),
    "`by` must be one of \"items\", \"nic\", \"actual_cost\", not \"quantity\"."
  )
  refused(
    fetch_practice_top_drugs(NULL, 1, months, limit = 0),
    "`limit` must be a whole number from 1 to 1000, not 0."
  )
  refused(fetch_practice_top_drugs(NULL, 1, months, after = "x"), "`after` must be one id")
  refused(
    fetch_region_comparison(NULL, "chemical", 1, months, "total_quantity"),
    "\"total_quantity\" is only valid for a single presentation, not a chemical"
  )
  refused(
    fetch_region_comparison(NULL, "chemical", 1, months, "items", per = "per_1000"),
    "`per` must be \"total\", not \"per_1000\"."
  )
})
