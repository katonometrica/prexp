# Argument checks shared by the loader and, later, the app's fetch functions.

# A month as an integer YYYYMM, from a number or a string like "202609"; stops
# for anything else, naming the argument.
check_year_month <- function(year_month, arg = "year_month") {
  ok <- length(year_month) == 1L && !is.na(year_month) &&
    grepl("^[0-9]{6}$", as.character(year_month))
  ym <- if (ok) as.integer(year_month) else NA_integer_
  if (!ok || ym %/% 100L < 2000L || !(ym %% 100L) %in% 1:12) {
    stop(
      "`", arg, "` must be one month as YYYYMM, for example 202609, not ",
      paste(format(year_month), collapse = ", "), ".",
      call. = FALSE
    )
  }
  ym
}
