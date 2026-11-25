# Argument checks shared by the loader and the app's fetch functions. Each
# returns the value it checked, converted (an id or a month becomes an
# integer, search text is cleaned), or stops with an error of class
# prexp_invalid_argument whose message names the argument and says what it
# must be, so the app can tell a request it refused from a query that failed.

invalid_argument <- function(...) {
  stop(structure(
    class = c("prexp_invalid_argument", "error", "condition"),
    list(message = paste0(...), call = NULL)
  ))
}

# A value for an error message, as R would print it, cut short. A classed
# value (a factor, a date, a 64-bit integer) is shown as it prints, not as
# what it is stored as. Any other value, such as a list, is shown by its
# shape: printing a list walks all of it, and one nested thousands deep, as
# JSON from a report's link can be, takes seconds and can overflow the C
# stack, which ends the process whatever handles the error.
value_text <- function(x) {
  if (is.null(x)) {
    return("NULL")
  }
  if (!is.atomic(x)) {
    return(value_shape(x))
  }
  x <- utils::head(x, 5L)
  if (!is.null(oldClass(x))) {
    x <- format(x)
  }
  text <- deparse1(x, collapse = " ")
  if (nchar(text) > 40L) paste0(substr(text, 1L, 37L), "...") else text
}

# What a value is, without what it holds: for search text, which stays out of
# messages and so out of logs
value_shape <- function(x) {
  if (is.null(x)) {
    return("NULL")
  }
  if (is.atomic(x) && length(x) == 1L && is.na(x)) {
    return("NA")
  }
  kind <- if (is.atomic(x) && is.null(oldClass(x))) paste(typeof(x), "vector") else class(x)[1]
  paste0("a ", kind, " of length ", length(x))
}

# Whether each value is a month as YYYYMM: six digits, a year from 2000 and a
# month from 01 to 12. Numbers must be whole; text must be the digits alone.
is_year_month <- function(x) {
  if (inherits(x, "integer64")) {
    x <- as.numeric(x)
  }
  if (!is.numeric(x) && !is.character(x)) {
    return(rep(FALSE, length(x)))
  }
  text <- if (is.numeric(x)) {
    ifelse(!is.na(x) & x == trunc(x), sprintf("%.0f", x), "")
  } else {
    x
  }
  ym <- suppressWarnings(as.integer(ifelse(grepl("^[0-9]{6}$", text), text, NA)))
  !is.na(ym) & ym %/% 100L >= 2000L & ym %% 100L %in% 1:12
}

# A month as an integer YYYYMM, from a number or a string like "202609"
check_year_month <- function(year_month, arg = "year_month") {
  if (length(year_month) != 1L || !is_year_month(year_month)) {
    invalid_argument(
      "`", arg, "` must be one month as YYYYMM, for example 202609, not ",
      value_text(year_month), "."
    )
  }
  as.integer(as.numeric(year_month))
}

# A range of months, c(first, last), as integers YYYYMM, the first not after
# the last. The queries would read a reversed range as no prescribing.
validate_months <- function(months, arg = "months") {
  ok <- length(months) == 2L && all(is_year_month(months))
  checked <- if (ok) unname(as.integer(as.numeric(months))) else NULL
  if (!ok || checked[1] > checked[2]) {
    invalid_argument(
      "`", arg, "` must be two months as YYYYMM, the first not after the last, ",
      "for example c(202510, 202609), not ", value_text(months), "."
    )
  }
  checked
}

# One id of a chemical, presentation or practice: a whole number in the range
# of the database's integer ids, from a number or a string of digits
validate_id <- function(id, arg = "id") {
  value <- NA_real_
  if (length(id) == 1L && (is.numeric(id) || is.character(id)) && !is.na(id)) {
    if (is.numeric(id)) {
      value <- as.numeric(id)
    } else if (grepl("^[0-9]{1,10}$", id)) {
      value <- as.numeric(id)
    }
  }
  if (is.na(value) || value != trunc(value) || value < 1 || value > .Machine$integer.max) {
    invalid_argument(
      "`", arg, "` must be one id, a whole number from 1 to 2147483647, not ",
      value_text(id), "."
    )
  }
  as.integer(value)
}

# Search text: spaces, tabs, line breaks and other separators become single
# spaces, other control and format characters (such as a zero-width space) are
# removed, and the ends are trimmed; then it must be 2 to 100 characters. Text
# over 1,000 bytes is refused before any of that. No message repeats the text,
# which stays out of logs.
# Search text as the search reads it: every kind of space a plain space,
# control and format characters (a zero-width space, say) gone, and no spaces
# doubled or at either end. The search module counts characters with it too.
clean_search <- function(q) {
  q <- gsub("[\\s\\p{Z}\\x{85}]", " ", q, perl = TRUE)
  q <- gsub("[\\p{Cc}\\p{Cf}]", "", q, perl = TRUE)
  trimws(gsub(" {2,}", " ", q))
}

validate_search <- function(q, arg = "q") {
  if (!is.character(q) || length(q) != 1L || is.na(q)) {
    invalid_argument("`", arg, "` must be one string of search text, not ", value_shape(q), ".")
  }
  if (nchar(q, type = "bytes") > 1000L) {
    invalid_argument("`", arg, "` must be 2 to 100 characters; it is over 1,000 bytes long.")
  }
  q <- enc2utf8(q)
  if (!validUTF8(q)) {
    invalid_argument("`", arg, "` must be text in UTF-8.")
  }
  q <- clean_search(q)
  n <- nchar(q)
  if (n < 2L || n > 100L) {
    invalid_argument(
      "`", arg, "` must be 2 to 100 characters, not counting spaces at either end ",
      "or control characters; it has ", n, "."
    )
  }
  q
}

# One of a fixed set of words
validate_choice <- function(x, choices, arg) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !x %in% choices) {
    invalid_argument(
      "`", arg, "` must be ", if (length(choices) > 1L) "one of ",
      paste0("\"", choices, "\"", collapse = ", "), ", not ", value_text(x), "."
    )
  }
  x
}

# A number of rows to return: a whole number from 1 to `max`
validate_limit <- function(limit, max, arg = "limit") {
  value <- if (is.numeric(limit) && length(limit) == 1L && !is.na(limit)) limit else NA
  if (is.na(value) || value != trunc(value) || value < 1 || value > max) {
    invalid_argument(
      "`", arg, "` must be a whole number from 1 to ", max, ", not ", value_text(limit), "."
    )
  }
  as.integer(value)
}

# A measure of a drug at a level: total quantity only for a presentation, since
# a chemical's presentations count quantity in different units (tablets,
# millilitres, grams)
validate_measure <- function(measure, level) {
  measure <- validate_choice(
    measure, c("items", "total_quantity", "adq_usage", "nic", "actual_cost"), "measure"
  )
  if (measure == "total_quantity" && level != "presentation") {
    invalid_argument(
      "`measure` \"total_quantity\" is only valid for a single presentation, not a ",
      level, ": its presentations count quantity in different units."
    )
  }
  measure
}
