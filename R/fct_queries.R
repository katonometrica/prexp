# The app's data access (spec section 5.2): one fetch_*() function per query.
# Each takes a pool from db_pool() or a connection first, checks its arguments
# (utils_validate.R), runs its SQL file from inst/sql/queries/, read through
# query_sql(), the same file the plan check runs, with the values bound as
# parameters, and returns a tibble with the columns documented below. SQL is
# never built from strings here: the values only ever travel as parameters.
# Each fetch writes a line to the timing log (utils_log.R).

# Runs a fetch's query file with these values bound, and logs it under the
# fetch's name, with `args` as the arguments to hash: by default the values
# bound. Sums of whole numbers arrive as 64-bit integers and become doubles,
# which hold them exactly up to 2^53; numeric sums arrive as doubles.
run_fetch <- function(con, fetch, query, params = list(), args = params) {
  sql <- query_sql(query)
  started <- Sys.time()
  # A failed or interrupted query logs its line, then goes on failing
  failed <- function(condition) log_fetch(fetch, args, NULL, started, error = TRUE)
  rows <- withCallingHandlers(
    if (length(params) == 0L) {
      DBI::dbGetQuery(con, sql)
    } else {
      DBI::dbGetQuery(con, sql, params = unname(params))
    },
    error = failed,
    interrupt = failed
  )
  for (col in names(rows)) {
    if (inherits(rows[[col]], "integer64")) {
      rows[[col]] <- as.numeric(rows[[col]])
    }
  }
  rows <- tibble::as_tibble(rows)
  log_fetch(fetch, args, nrow(rows), started)
  rows
}

# The rollup query of a drug at a level. The fetches below build their
# tibbles from plain lists: tibble() would let the new measure column hide the
# measure argument from the columns after it.
drug_query <- function(kind, level) {
  switch(kind,
    series = switch(level,
      chemical = "drug_series_chemical",
      presentation = "drug_series_presentation"
    ),
    regions = switch(level,
      chemical = "region_comparison_chemical",
      presentation = "region_comparison_presentation"
    )
  )
}

#' The months loaded
#'
#' The data window, for the app's month range and as part of its cache keys.
#'
#' @param con A pool from [db_pool()], or a DBI connection that can read the
#'   app views.
#' @return A tibble with one row: `first_month` and `last_month` (integer,
#'   YYYYMM), `months` (integer, how many months are loaded) and `loaded_at`
#'   (POSIXct, when the latest load finished). Before the first load, the
#'   months are `NA` and `months` is 0.
#' @family fetch functions
#' @examples
#' \dontrun{
#' pool <- db_pool()
#' fetch_window(pool)
#' pool::poolClose(pool)
#' }
#' @export
fetch_window <- function(con) {
  run_fetch(con, "fetch_window", "window")
}

#' Search chemical substances and presentations
#'
#' Matches names that contain `q`, ignoring case, and BNF codes that start
#' with it. Two characters match a name that starts with them, or has a word,
#' after a space, that does. A code typed in full ranks first, then names by
#' their similarity to `q`, then matches by code alone. Only codes with data
#' in the window are searched.
#'
#' @inheritParams fetch_window
#' @param q Search text, 2 to 100 characters once spaces at either end and
#'   control characters are removed. `%`, `_` and `\` match themselves.
#' @param limit The most matches to return, from 1 to 100.
#' @return A tibble, best match first: `level` (`"chemical"` or
#'   `"presentation"`), `id` (integer, the chemical's or presentation's id:
#'   chemicals and presentations number their ids apart, so a match is known
#'   by `level` and `id` together), `code` (BNF code), `name`, `chemical_id`
#'   (integer), `chemical_name` and `is_generic` (logical: `NA` for a
#'   chemical, and for an appliance, BNF chapters 20 to 23, which is neither
#'   brand nor generic).
#' @family fetch functions
#' @examples
#' \dontrun{
#' pool <- db_pool()
#' fetch_search_drugs(pool, "atorva")
#' pool::poolClose(pool)
#' }
#' @export
fetch_search_drugs <- function(con, q, limit = 20L) {
  q <- validate_search(q)
  limit <- validate_limit(limit, max = 100L)
  run_fetch(con, "fetch_search_drugs", "search_drugs", list(q, limit))
}

#' Search practices
#'
#' Matches practice names as [fetch_search_drugs()] matches drug names, and
#' practice codes that start with `q`. Leaves out the unidentified prescribers
#' and practices with no data in the window.
#'
#' @inheritParams fetch_search_drugs
#' @return A tibble, best match first: `practice_id` (integer),
#'   `practice_code`, `practice_name`, `postcode`, `icb_name` and
#'   `region_name`.
#' @family fetch functions
#' @examples
#' \dontrun{
#' pool <- db_pool()
#' fetch_search_practices(pool, "N81655")
#' pool::poolClose(pool)
#' }
#' @export
fetch_search_practices <- function(con, q, limit = 20L) {
  q <- validate_search(q)
  limit <- validate_limit(limit, max = 100L)
  run_fetch(con, "fetch_search_practices", "search_practices", list(q, limit))
}

#' A drug's national monthly totals
#'
#' @inheritParams fetch_window
#' @param level `"chemical"` or `"presentation"`.
#' @param id The chemical's or the presentation's id.
#' @param months The first and last month, as YYYYMM: `c(first, last)`.
#' @param measure `"items"`, `"adq_usage"`, `"nic"`, `"actual_cost"`, or, for
#'   a presentation only, `"total_quantity"`: a chemical's presentations count
#'   quantity in different units. An ADQ, the assumed average daily dose, is
#'   defined for some presentations only: `"adq_usage"` is `NA` for a
#'   presentation without one, and for a chemical it sums only the
#'   presentations that have one.
#' @return A tibble with one row per month that has prescribing, in order:
#'   `year_month` (integer), `measure` (the measure asked for), `value`
#'   (double, the national total) and `practices` (integer, how many practices
#'   prescribed it). A month without prescribing has no row, rather than a
#'   row of zeros, and an unknown id has none at all.
#' @family fetch functions
#' @examples
#' \dontrun{
#' pool <- db_pool()
#' fetch_drug_series(pool, "chemical", 123, c(202510, 202609), "items")
#' pool::poolClose(pool)
#' }
#' @export
fetch_drug_series <- function(con, level, id, months, measure) {
  level <- validate_choice(level, c("chemical", "presentation"), "level")
  id <- validate_id(id)
  months <- validate_months(months)
  measure <- validate_measure(measure, level)
  rows <- run_fetch(
    con, "fetch_drug_series", drug_query("series", level), list(id, months[1], months[2]),
    args = list(level, id, months, measure)
  )
  tibble::as_tibble(list(
    year_month = rows$year_month,
    measure = rep(measure, nrow(rows)),
    value = rows[[measure]],
    practices = rows$practices
  ))
}

#' A chemical substance's presentations
#'
#' National totals over the months of each presentation of one chemical
#' substance, brand or generic.
#'
#' @inheritParams fetch_drug_series
#' @param chemical_id The chemical substance's id.
#' @return A tibble, most items first: `presentation_id` (integer),
#'   `bnf_code`, `bnf_description`, `is_generic` (logical, `NA` for an
#'   appliance), and the totals `items`, `total_quantity`, `adq_usage`, `nic`
#'   and `actual_cost` (double). `adq_usage` is `NA` for a presentation with
#'   no ADQ. No rows for an unknown id.
#' @family fetch functions
#' @examples
#' \dontrun{
#' pool <- db_pool()
#' fetch_drug_presentations(pool, 123, c(202510, 202609))
#' pool::poolClose(pool)
#' }
#' @export
fetch_drug_presentations <- function(con, chemical_id, months) {
  chemical_id <- validate_id(chemical_id, "chemical_id")
  months <- validate_months(months)
  run_fetch(
    con, "fetch_drug_presentations", "drug_presentations", list(chemical_id, months[1], months[2])
  )
}

#' A practice's profile
#'
#' @inheritParams fetch_window
#' @param practice_id The practice's id.
#' @return A tibble with one row, or none for an unknown id: `practice_id`
#'   (integer), `practice_code`, `practice_name`, `address`, `postcode`,
#'   `icb_code`, `icb_name`, `region_code`, `region_name`, `is_unidentified`
#'   (logical), and `first_seen` and `last_seen` (integer, YYYYMM), the first
#'   and last months it prescribed in. The name and address are as in the
#'   latest month loaded.
#' @family fetch functions
#' @examples
#' \dontrun{
#' pool <- db_pool()
#' fetch_practice_profile(pool, 42)
#' pool::poolClose(pool)
#' }
#' @export
fetch_practice_profile <- function(con, practice_id) {
  practice_id <- validate_id(practice_id, "practice_id")
  run_fetch(con, "fetch_practice_profile", "practice_profile", list(practice_id))
}

#' A practice's monthly totals
#'
#' @inheritParams fetch_practice_profile
#' @inheritParams fetch_drug_series
#' @return A tibble with one row per month that has prescribing, in order:
#'   `year_month` (integer), `presentations` (integer, how many it
#'   prescribed), and `items`, `nic` and `actual_cost` (double). No rows for
#'   an unknown id.
#' @family fetch functions
#' @examples
#' \dontrun{
#' pool <- db_pool()
#' fetch_practice_series(pool, 42, c(202510, 202609))
#' pool::poolClose(pool)
#' }
#' @export
fetch_practice_series <- function(con, practice_id, months) {
  practice_id <- validate_id(practice_id, "practice_id")
  months <- validate_months(months)
  run_fetch(
    con, "fetch_practice_series", "practice_series", list(practice_id, months[1], months[2])
  )
}

#' A practice's top drugs, a page at a time
#'
#' The practice's presentations over the months, ranked by a measure. Pages
#' follow on by keyset: pass the `presentation_id` of the last row of a page
#' as `after` to get the next one, which starts exactly after it, with no row
#' repeated or skipped.
#'
#' @inheritParams fetch_practice_series
#' @param by The ranking measure: `"items"`, `"nic"` or `"actual_cost"`.
#' @param limit The page size, from 1 to 1,000.
#' @param after `NULL` (or `NA`) for the first page; then the
#'   `presentation_id` of the last row of the previous page. A page that comes
#'   back short or empty is the last: there is no row to pass on from an empty
#'   one, and a zero-length `after` is refused. An `after` that is not in this
#'   ranking, for example one kept from other months, gives no rows.
#' @return A tibble, highest total first, ties by `presentation_id`
#'   descending: `presentation_id` (integer), `bnf_code`, `bnf_description`,
#'   `chemical_id` (integer), `chemical_name`, `is_generic` (logical, `NA` for
#'   an appliance), the totals `items`, `adq_usage` (`NA` without an ADQ),
#'   `nic` and `actual_cost` (double), and `total` (double), the ranking
#'   measure's total. No rows for an unknown id or after the last page.
#' @family fetch functions
#' @examples
#' \dontrun{
#' pool <- db_pool()
#' page <- fetch_practice_top_drugs(pool, 42, c(202510, 202609), by = "nic")
#' fetch_practice_top_drugs(
#'   pool, 42, c(202510, 202609), by = "nic", after = page$presentation_id[nrow(page)]
#' )
#' pool::poolClose(pool)
#' }
#' @export
fetch_practice_top_drugs <- function(con, practice_id, months, by = "items", limit = 25L,
                                     after = NULL) {
  practice_id <- validate_id(practice_id, "practice_id")
  months <- validate_months(months)
  by <- validate_choice(by, c("items", "nic", "actual_cost"), "by")
  limit <- validate_limit(limit, max = 1000L)
  first_page <- is.null(after) || (is.atomic(after) && length(after) == 1L && is.na(after))
  after <- if (first_page) NA_integer_ else validate_id(after, "after")
  run_fetch(
    con, "fetch_practice_top_drugs", "practice_top_drugs",
    list(practice_id, months[1], months[2], by, limit, after)
  )
}

#' A drug's totals by NHS region
#'
#' @inheritParams fetch_drug_series
#' @param per `"total"`. Rates per 1,000 patients come with the practice
#'   variation model (v2).
#' @return A tibble with one row per region that prescribed the drug, in order
#'   of `region_code`: `region_code`, `region_name`, `measure` (the measure
#'   asked for) and `value` (double, the total over the months). A region that
#'   did not prescribe it has no row. Region `"-"` holds prescribers without an
#'   NHS region, such as the national unidentified prescriber, whose source
#'   rows name it `"UNIDENTIFIED"`. No rows for an unknown id.
#' @family fetch functions
#' @examples
#' \dontrun{
#' pool <- db_pool()
#' fetch_region_comparison(pool, "chemical", 123, c(202510, 202609), "nic")
#' pool::poolClose(pool)
#' }
#' @export
fetch_region_comparison <- function(con, level, id, months, measure, per = "total") {
  level <- validate_choice(level, c("chemical", "presentation"), "level")
  id <- validate_id(id)
  months <- validate_months(months)
  measure <- validate_measure(measure, level)
  validate_choice(per, "total", "per")
  rows <- run_fetch(
    con, "fetch_region_comparison", drug_query("regions", level), list(id, months[1], months[2]),
    args = list(level, id, months, measure, per)
  )
  tibble::as_tibble(list(
    region_code = rows$region_code,
    region_name = rows$region_name,
    measure = rep(measure, nrow(rows)),
    value = rows[[measure]]
  ))
}
