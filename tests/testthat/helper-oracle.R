# The test oracle (spec section 6.1): expected values computed from the fixture
# files with dplyr, never by the code under test. The files are read with R's
# own unzip, not with bsdtar or the loader.
#
# Sums are exact. Each measure becomes a whole number of its smallest unit
# (pennies for NIC, 10^-5 pounds for actual cost), which a double holds exactly,
# and oracle_text() turns the results back into decimal text as PostgreSQL
# prints trim_scale(numeric): "1234.5", "60", "0.75199". Tests compare that text
# with the loader's numeric results, so a single penny shows.
#
# The oracle aggregates as the loader does: one fact row per month x practice x
# presentation; the rollups by presentation, chemical or practice, and region,
# where a practice's region is its REGIONAL_OFFICE_CODE ('-' when empty).

fixture_months <- function() c(202509L:202512L, 202601L:202609L)

fixture_file <- function(ym) {
  testthat::test_path("fixtures", sprintf("EPD_SNOMED_%d.zip", ym))
}

# A fixture month's rows, every column as text
read_fixture <- function(ym) {
  dir <- withr::local_tempdir()
  csv <- utils::unzip(fixture_file(ym), exdir = dir, unzip = "internal")
  utils::read.csv(
    csv, colClasses = "character", na.strings = character(), check.names = FALSE,
    encoding = "UTF-8"
  )
}

# Decimal places of each measure in the source
measure_digits <- c(total_quantity = 2, adq_usage = 5, nic = 2, actual_cost = 5)

to_units <- function(x, digits) round(as.numeric(x) * 10^digits)

# Whole units back to decimal text without trailing zeros, as trim_scale()::text
units_text <- function(units, digits) {
  out <- rep(NA_character_, length(units))
  ok <- !is.na(units)
  whole <- format(units[ok] %/% 10^digits, scientific = FALSE, trim = TRUE)
  fraction <- formatC(units[ok] %% 10^digits, width = digits, format = "d", flag = "0")
  out[ok] <- sub("[.]?0+$", "", paste0(whole, ".", fraction))
  out
}

# The fixture rows of some months, typed, with measures in whole units
oracle_rows <- function(months = fixture_months()) {
  rows <- do.call(rbind, lapply(months, read_fixture))
  region <- rows$REGIONAL_OFFICE_CODE
  data.frame(
    year_month = as.integer(sub("-", "", rows$YEAR_MONTH, fixed = TRUE)),
    practice_code = rows$PRACTICE_CODE,
    region_code = ifelse(nzchar(region), region, "-"),
    bnf_code = rows$BNF_PRESENTATION_CODE,
    chemical_code = rows$BNF_CHEMICAL_SUBSTANCE_CODE,
    items = as.numeric(rows$ITEMS),
    total_quantity = to_units(rows$TOTAL_QUANTITY, measure_digits[["total_quantity"]]),
    adq_usage = to_units(rows$ADQ_USAGE, measure_digits[["adq_usage"]]),
    nic = to_units(rows$NIC, measure_digits[["nic"]]),
    actual_cost = to_units(rows$ACTUAL_COST, measure_digits[["actual_cost"]])
  )
}

# Sums of `measures` by `keys`; with `count`, also the number of distinct
# values of `distinct` in each group
oracle_sum <- function(df, keys, measures, count = NULL, distinct = NULL) {
  out <- dplyr::summarise(
    dplyr::group_by(df, dplyr::across(dplyr::all_of(keys))),
    dplyr::across(dplyr::all_of(measures), sum),
    .groups = "drop"
  )
  if (!is.null(count)) {
    n <- dplyr::count(
      dplyr::distinct(df, dplyr::across(dplyr::all_of(c(keys, distinct)))),
      dplyr::across(dplyr::all_of(keys)),
      name = count
    )
    out <- dplyr::left_join(out, n, by = keys)
    out[[count]] <- as.integer(out[[count]])
  }
  as.data.frame(dplyr::arrange(out, dplyr::across(dplyr::all_of(keys))))
}

all_measures <- c("items", "total_quantity", "adq_usage", "nic", "actual_cost")

# One row per month x practice x presentation, as the fact table. region_code
# and chemical_code follow from the practice and the presentation.
oracle_fact <- function(months = fixture_months()) {
  keys <- c("year_month", "practice_code", "bnf_code", "region_code", "chemical_code")
  oracle_sum(oracle_rows(months), keys, all_measures)
}

oracle_presentation_month <- function(months = fixture_months()) {
  oracle_sum(
    oracle_fact(months), c("year_month", "bnf_code", "region_code"), all_measures,
    count = "practices", distinct = "practice_code"
  )
}

oracle_chemical_month <- function(months = fixture_months()) {
  oracle_sum(
    oracle_fact(months), c("year_month", "chemical_code", "region_code"),
    c("items", "adq_usage", "nic", "actual_cost"),
    count = "practices", distinct = "practice_code"
  )
}

oracle_practice_month <- function(months = fixture_months()) {
  oracle_sum(
    oracle_fact(months), c("year_month", "practice_code"), c("items", "nic", "actual_cost"),
    count = "presentations", distinct = "bnf_code"
  )
}

oracle_region_month <- function(months = fixture_months()) {
  oracle_sum(oracle_fact(months), c("year_month", "region_code"), c("items", "nic", "actual_cost"))
}

# Per month: the source rows, the fact rows after aggregation, and every total
oracle_month_totals <- function(months = fixture_months()) {
  rows <- oracle_rows(months)
  out <- oracle_sum(rows, "year_month", all_measures)
  out$source_rows <- as.integer(table(rows$year_month)[as.character(out$year_month)])
  fact <- oracle_fact(months)
  out$fact_rows <- as.integer(table(fact$year_month)[as.character(out$year_month)])
  out
}

# Measures as decimal text (items as whole-number text), for comparison with
# SQL results selected as trim_scale(x)::text. A sum of ADQ of 0 means no ADQ
# is defined, which the loader stores as NULL.
oracle_text <- function(df) {
  if ("items" %in% names(df)) {
    df$items <- format(df$items, scientific = FALSE, trim = TRUE)
  }
  for (col in intersect(names(measure_digits), names(df))) {
    units <- df[[col]]
    if (col == "adq_usage") {
      units[units == 0] <- NA
    }
    df[[col]] <- units_text(units, measure_digits[[col]])
  }
  df
}
