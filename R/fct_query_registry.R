# The app's queries (spec section 5.2): one SQL file per query in
# inst/sql/queries/, its parameters in order, and two sample argument sets for
# the plan check, large and small. The fetch functions (P3-02) and
# check_plans() read the same files, so the SQL that is checked is the SQL the
# app runs.
#
# A sample names its drug or practice by code, never by id, because ids differ
# between databases; resolve_sample() looks the codes up at run time. When a
# sample gives several codes, the first one in the database is used: the
# largest practice of the full data is not in the fixtures, so the largest
# fixture practice stands in for it there. A large sample asks for the whole
# window, a small one for its last three months, so the check sees partitions
# pruned.

#' The app's queries and their sample arguments
#'
#' @return A named list, one entry per query, each with `params` (the names of
#'   its parameters, in order) and `samples` (named lists of sample arguments:
#'   `chemical`, `presentation` and `practice` are codes, `months` the number
#'   of most recent months asked for, the whole window when absent; other names
#'   are parameters).
#' @noRd
query_registry <- function() {
  months <- c("first_month", "last_month")
  chemical <- list(
    large = list(chemical = "0212000B0"),
    small = list(chemical = "0404000W0", months = 3L)
  )
  presentation <- list(
    large = list(presentation = "0212000B0AAABAB"),
    small = list(presentation = "0404000W0BBAAAA", months = 3L)
  )
  practice <- list(
    large = list(practice = c("B83033", "N81655")),
    small = list(practice = "Y03965", months = 3L)
  )
  first_page <- list(limit = 25L, after_id = NA)
  list(
    window = list(params = character(), samples = list(window = list())),
    search_drugs = list(
      params = c("q", "limit"),
      samples = list(
        large = list(q = "se", limit = 20L), small = list(q = "pitolisant", limit = 20L)
      )
    ),
    search_practices = list(
      params = c("q", "limit"),
      samples = list(large = list(q = "he", limit = 20L), small = list(q = "N81655", limit = 20L))
    ),
    drug_series_chemical = list(params = c("chemical_id", months), samples = chemical),
    drug_series_presentation = list(params = c("presentation_id", months), samples = presentation),
    drug_presentations = list(params = c("chemical_id", months), samples = chemical),
    practice_profile = list(params = "practice_id", samples = practice),
    practice_series = list(params = c("practice_id", months), samples = practice),
    practice_top_drugs = list(
      params = c("practice_id", months, "by", "limit", "after_id"),
      samples = list(
        large = c(practice$large, list(by = "items"), first_page),
        small = c(practice$small, list(by = "actual_cost"), first_page)
      )
    ),
    region_comparison_chemical = list(params = c("chemical_id", months), samples = chemical),
    region_comparison_presentation = list(
      params = c("presentation_id", months), samples = presentation
    )
  )
}

#' The SQL of one of the app's queries
#'
#' @param query A name in [query_registry()].
#' @return The text of `inst/sql/queries/<query>.sql`.
#' @noRd
query_sql <- function(query) {
  if (!is.character(query) || length(query) != 1L || !query %in% names(query_registry())) {
    stop("Unknown query: ", paste(format(query), collapse = ", "), ".", call. = FALSE)
  }
  path <- system.file("sql", "queries", paste0(query, ".sql"), package = "prexp", mustWork = TRUE)
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

# The id for the first of the codes found in the database, or NA
lookup_id <- function(con, kind, codes) {
  sql <- switch(kind,
    chemical = "SELECT chemical_id AS id FROM app.v_chemical WHERE chemical_code = $1",
    presentation = "SELECT presentation_id AS id FROM app.v_presentation WHERE bnf_code = $1",
    practice = "SELECT practice_id AS id FROM app.v_practice WHERE practice_code = $1"
  )
  for (code in codes) {
    id <- DBI::dbGetQuery(con, sql, params = list(code))$id
    if (length(id) == 1L) {
      return(list(id = id, code = code))
    }
  }
  list(id = NA_integer_, code = codes[1])
}

# Months as a count from year 0, and back: 202609 is 24320, the month after
# 202512 is 202601
month_index <- function(ym) (ym %/% 100L) * 12L + ym %% 100L - 1L
index_month <- function(index) as.integer((index %/% 12L) * 100L + index %% 12L + 1L)

#' A sample's arguments, in the query's parameter order
#'
#' @param con A connection that can read the app views.
#' @param entry An entry of [query_registry()].
#' @param sample One of its samples.
#' @param window The window: a list with `first_month` and `last_month`.
#' @return A list with `params` (unnamed, in order, `NULL` when a code is not
#'   in the database), `codes` (the codes used, for the report), `months` (how
#'   many months the arguments span, the most partitions the plan may read; NA
#'   for a query without months) and `missing` (the code not found, or NA).
#' @noRd
resolve_sample <- function(con, entry, sample, window) {
  first <- window$first_month
  last <- window$last_month
  if (!is.null(sample$months)) {
    first <- max(first, index_month(month_index(last) - sample$months + 1L))
  }
  values <- c(sample, list(first_month = first, last_month = last))
  months <- if ("first_month" %in% entry$params) {
    as.integer(month_index(last) - month_index(first) + 1L)
  } else {
    NA_integer_
  }
  codes <- character()
  for (kind in intersect(names(sample), c("chemical", "presentation", "practice"))) {
    found <- lookup_id(con, kind, sample[[kind]])
    codes <- c(codes, found$code)
    if (is.na(found$id)) {
      return(list(
        params = NULL, codes = codes, months = months, missing = paste(kind, found$code)
      ))
    }
    values[[paste0(kind, "_id")]] <- found$id
  }
  list(
    params = unname(values[entry$params]), codes = codes, months = months,
    missing = NA_character_
  )
}
