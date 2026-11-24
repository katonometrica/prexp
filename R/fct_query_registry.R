# The app's queries (spec section 5.2): one SQL file per query in
# inst/sql/queries/, its parameters in order, and two sample argument sets for
# the plan check, large and small. The fetch functions (P3-02) and
# check_plans() read the same files, so the SQL that is checked is the SQL the
# app runs.
#
# A large sample is the worst case the window holds, over the whole window: the
# chemical with the most presentations and the practice with the most
# prescribing rows are picked from the data when the check runs, so they follow
# the window as it moves; the searches use the two-letter text that matches
# the most names. A small sample asks for the window's last three months, so the
# check sees partitions pruned. A sample names its drug or practice by code,
# never by id, because ids differ between databases; resolve_sample() looks the
# codes up at run time, among those with data in the months asked for.

#' The app's queries and their sample arguments
#'
#' @return A named list, one entry per query, each with `params` (the names of
#'   its parameters, in order) and `samples` (named lists of sample arguments:
#'   `chemical`, `presentation` and `practice` are codes, in order of
#'   preference, or a function of the connection and the months that picks
#'   one; `months` is the number of most recent months asked for, the whole
#'   window when absent; other names are parameters).
#' @noRd
query_registry <- function() {
  months <- c("first_month", "last_month")
  chemical <- list(
    large = list(chemical = most_presentations),
    small = list(chemical = "0404000W0", months = 3L)
  )
  presentation <- list(
    large = list(presentation = "0212000B0AAABAB"),
    small = list(presentation = "0404000W0BBAAAA", months = 3L)
  )
  practice <- list(
    large = list(practice = most_prescribing),
    small = list(practice = "Y03965", months = 3L)
  )
  first_page <- list(limit = 25L, after_id = NA)
  list(
    window = list(params = character(), samples = list(window = list())),
    search_drugs = list(
      params = c("q", "limit"),
      samples = list(
        large = list(q = "co", limit = 20L), small = list(q = "pitolisant", limit = 20L)
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

# The chemical substance with the most presentations seen in the months: the
# most rows for a chemical's queries to read
most_presentations <- function(con, first, last) {
  DBI::dbGetQuery(con, "
    SELECT c.chemical_code FROM app.v_presentation p
    JOIN app.v_chemical c ON c.chemical_id = p.chemical_id
    WHERE p.last_seen >= $1 AND p.first_seen <= $2
    GROUP BY c.chemical_code
    ORDER BY count(*) DESC, c.chemical_code
    LIMIT 1", params = list(first, last))$chemical_code
}

# The identified practice with the most prescribing rows in the months: the
# most fact rows for a practice's queries to read
most_prescribing <- function(con, first, last) {
  DBI::dbGetQuery(con, "
    SELECT p.practice_code FROM app.v_practice_month m
    JOIN app.v_practice p ON p.practice_id = m.practice_id
    WHERE m.year_month BETWEEN $1 AND $2 AND NOT p.is_unidentified
    GROUP BY p.practice_code
    ORDER BY sum(m.presentations) DESC, p.practice_code
    LIMIT 1", params = list(first, last))$practice_code
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

# The id of the first of the codes with data from `first` on, or NA. Dimension
# rows are never deleted, so a code that has left the window still has one.
lookup_id <- function(con, kind, codes, first) {
  sql <- switch(kind,
    chemical = "SELECT chemical_id AS id FROM app.v_chemical
                WHERE chemical_code = $1 AND last_seen >= $2",
    presentation = "SELECT presentation_id AS id FROM app.v_presentation
                    WHERE bnf_code = $1 AND last_seen >= $2",
    practice = "SELECT practice_id AS id FROM app.v_practice
                WHERE practice_code = $1 AND last_seen >= $2"
  )
  for (code in codes) {
    id <- DBI::dbGetQuery(con, sql, params = list(code, first))$id
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
#'   in the database), `codes` (the codes or search text used, for the report),
#'   `months` (how many months the arguments span, the most partitions the
#'   plan may read; NA for a query without months) and `missing` (the code not
#'   found, or NA).
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
  codes <- if (is.null(sample$q)) character() else sample$q
  for (kind in intersect(names(sample), c("chemical", "presentation", "practice"))) {
    wanted <- sample[[kind]]
    if (is.function(wanted)) {
      wanted <- wanted(con, first, last)
    }
    found <- lookup_id(con, kind, wanted, first)
    codes <- c(codes, found$code)
    if (is.na(found$id)) {
      code <- if (is.na(found$code)) "(none with data in the months)" else found$code
      return(list(params = NULL, codes = codes, months = months, missing = paste(kind, code)))
    }
    values[[paste0(kind, "_id")]] <- found$id
  }
  list(
    params = unname(values[entry$params]), codes = codes, months = months,
    missing = NA_character_
  )
}
