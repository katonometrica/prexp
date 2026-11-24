# How the app writes numbers, pounds and months: one place, so tables, charts,
# the footer and the exports agree. English month names whatever the locale.

#' A number with thousands separators
#'
#' @param x Numbers, or text that reads as numbers.
#' @param digits Decimal places.
#' @param na What to show for a missing value, or one that is not a finite
#'   number.
#' @return A character vector: `"1,234,567"`. A value that rounds to zero has
#'   no minus sign.
#' @noRd
format_number <- function(x, digits = 0L, na = "\u2013") {
  x <- round(suppressWarnings(as.numeric(x)), digits)
  x[!is.na(x) & x == 0] <- 0
  out <- formatC(x, format = "f", digits = digits, big.mark = ",")
  out[!is.finite(x)] <- na
  out
}

#' An amount in pounds
#'
#' @inheritParams format_number
#' @return A character vector: the pound sign and the amount with thousands
#'   separators and two decimals, a minus sign first for a negative amount.
#' @noRd
format_pounds <- function(x, digits = 2L, na = "\u2013") {
  x <- round(suppressWarnings(as.numeric(x)), digits)
  out <- paste0(
    ifelse(!is.na(x) & x < 0, "-", ""), "\u00a3", format_number(abs(x), digits = digits)
  )
  out[!is.finite(x)] <- na
  out
}

#' A value in its measure's form
#'
#' Pounds and pence for the costs, whole numbers for items, and three
#' significant figures for quantity and ADQ usage, which can be fractions: a
#' whole number would write 0.496 ADQs as 0.
#'
#' @inheritParams format_number
#' @param measure A measure's name, as in [measure_info()].
#' @return A character vector.
#' @noRd
format_measure <- function(x, measure, na = "\u2013") {
  if (measure %in% c("nic", "actual_cost")) {
    format_pounds(x, digits = 2L, na = na)
  } else if (measure == "items") {
    format_number(x, digits = 0L, na = na)
  } else {
    format_significant(x, na = na)
  }
}

#' A number to some significant figures
#'
#' @inheritParams format_number
#' @param digits Significant figures; a number with more whole digits keeps
#'   them all.
#' @return A character vector: `"0.496"`, `"1.62"`, `"123"`, `"1,234"`.
#' @noRd
format_significant <- function(x, digits = 3L, na = "\u2013") {
  x <- suppressWarnings(as.numeric(x))
  x[!is.na(x) & x == 0] <- 0
  out <- trimws(formatC(x, format = "fg", digits = digits, big.mark = ","))
  out[!is.finite(x)] <- na
  out
}

#' A month as its label
#'
#' @param ym Months as YYYYMM, numbers or text.
#' @return A character vector: `"Sep 2026"`; `NA` for a missing value or one
#'   that is not a month, by the validators' rule (`is_year_month()`).
#' @noRd
format_month <- function(ym) {
  ok <- is_year_month(ym)
  months <- as.integer(as.numeric(ym[ok]))
  out <- rep(NA_character_, length(ok))
  out[ok] <- paste(month.abb[months %% 100L], months %/% 100L)
  out
}

#' A range of months
#'
#' @param first,last The first and last months, as YYYYMM.
#' @return One string: `"Oct 2025 - Sep 2026"`, `"Jan - Sep 2026"` within a
#'   year, `"Sep 2026"` for one month. Months that are not a range raise a
#'   `prexp_invalid_argument` error.
#' @noRd
format_month_range <- function(first, last) {
  months <- validate_months(c(first, last), arg = "c(first, last)")
  first <- months[[1L]]
  last <- months[[2L]]
  if (first == last) {
    format_month(last)
  } else if (first %/% 100L == last %/% 100L) {
    paste(month.abb[first %% 100L], "\u2013", format_month(last))
  } else {
    paste(format_month(first), "\u2013", format_month(last))
  }
}
