# How the app writes numbers, pounds and months: one place, so tables, charts,
# the footer and the exports agree. English month names whatever the locale.

#' A number with thousands separators
#'
#' @param x Numbers.
#' @param digits Decimal places.
#' @param na What to show for a missing value.
#' @return A character vector: `"1,234,567"`.
#' @noRd
format_number <- function(x, digits = 0L, na = "\u2013") {
  out <- formatC(as.numeric(x), format = "f", digits = digits, big.mark = ",")
  out[is.na(x)] <- na
  out
}

#' An amount in pounds
#'
#' @inheritParams format_number
#' @return A character vector: the pound sign and the amount with thousands
#'   separators and two decimals, a minus sign first for a negative amount.
#' @noRd
format_pounds <- function(x, digits = 2L, na = "\u2013") {
  x <- as.numeric(x)
  out <- paste0(
    ifelse(!is.na(x) & x < 0, "-", ""), "\u00a3", format_number(abs(x), digits = digits)
  )
  out[is.na(x)] <- na
  out
}

#' A value in its measure's form: pounds for the costs, a number otherwise
#'
#' @inheritParams format_number
#' @param measure A measure's name, as in [measure_info()].
#' @return A character vector.
#' @noRd
format_measure <- function(x, measure, na = "\u2013") {
  if (measure %in% c("nic", "actual_cost")) {
    format_pounds(x, digits = 2L, na = na)
  } else {
    format_number(x, digits = 0L, na = na)
  }
}

#' A month as its label
#'
#' @param ym Months as YYYYMM.
#' @return A character vector: `"Sep 2026"`.
#' @noRd
format_month <- function(ym) {
  ym <- as.integer(ym)
  out <- paste(month.abb[ym %% 100L], ym %/% 100L)
  out[is.na(ym)] <- NA_character_
  out
}

#' A range of months
#'
#' @param first,last The first and last months, as YYYYMM.
#' @return One string: `"Oct 2025 - Sep 2026"`, `"Jan - Sep 2026"` within a
#'   year, `"Sep 2026"` for one month.
#' @noRd
format_month_range <- function(first, last) {
  first <- as.integer(first)
  last <- as.integer(last)
  if (first == last) {
    format_month(last)
  } else if (first %/% 100L == last %/% 100L) {
    paste(month.abb[first %% 100L], "\u2013", format_month(last))
  } else {
    paste(format_month(first), "\u2013", format_month(last))
  }
}
