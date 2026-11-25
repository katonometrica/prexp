# The report (spec section 5.5): an ordered list of pinned views, each with its
# view's parameters and a note. These functions hold all of its logic, with no
# Shiny, so that it is tested on its own; the report panel and the shareable
# link only call them. A report keeps parameters, not data: an export runs
# each item's fetch again.
#
# A report is list(items = list(item, ...), next_id), each item
# list(id, view, params, note, clamped): `id` a whole number, `view` one of
# report_views(), `params` that view's parameters as validate_item() returns
# them, `note` text, and `clamped` TRUE once clamp_report() has had to move its
# months into the data window. `next_id` is the id the next item gets, so no id
# is given twice in a session, even after its item is removed: the panel names
# an item by its id. Ids and `clamped` stay out of the link: opening a link
# numbers its items from 1 and clamps them again.

# At most 15 items, each with a note of at most 500 characters, and a link of
# at most 7,500 characters, which leaves room for the rest of a bookmark's URL
# under the 8,000 that RFC 9110 asks every server to accept. Notes of English
# prose at the first two limits take about 4,500; notes that compress poorly,
# such as Chinese text or codes, reach the link's limit first, and a pin, a
# note or a move that would pass it is refused (a link compresses better or
# worse as its items are ordered). A link is read only up to `link`
# characters, and only up to `json` bytes once unpacked, which no report within
# the other limits reaches.
report_limits <- function() {
  list(items = 15L, note = 500L, label = 200L, link = 7500L, json = 65536L)
}

# The views an item can pin, and the parameters each takes, in order
report_views <- function() {
  list(
    drug = c("level", "id", "code", "label", "months", "measure"),
    practice = c("id", "code", "label", "months", "measure"),
    region = c("level", "id", "code", "label", "months", "measure")
  )
}

# The version of the link's format, written into every link, and how deep its
# JSON nests: the report, its items, an item, its parameters, its months
report_format <- 1L
report_depth <- 5L

# An error from going past one of the report's limits, which the panel shows
# as it is
report_limit <- function(...) {
  stop(structure(
    class = c("prexp_report_limit", "error", "condition"),
    list(message = paste0(...), call = NULL)
  ))
}

# An error from a link that is not a report this app can read
invalid_report <- function(...) {
  stop(structure(
    class = c("prexp_invalid_report", "error", "condition"),
    list(message = paste0(...), call = NULL)
  ))
}

#' A new report, with no items
#'
#' @return A report: `list(items = list(), next_id = 1L)`.
#' @noRd
new_report <- function() {
  list(items = list(), next_id = 1L)
}

#' A report with one more item
#'
#' @param spec A report.
#' @param view The view the item pins: `"drug"`, `"practice"` or `"region"`.
#' @param params The view's parameters, as its `current()` gives them.
#' @return The report with the item last, its parameters checked by
#'   [validate_item()], its note empty and its id the report's `next_id`, which
#'   then goes up by one. A sixteenth item, or one that would make the report's
#'   link too long, is an error of class `prexp_report_limit`.
#' @noRd
report_add <- function(spec, view, params) {
  limit <- report_limits()$items
  if (length(spec$items) >= limit) {
    report_limit("A report holds at most ", limit, " items: remove one to add another.")
  }
  item <- validate_item(view, params)
  id <- spec$next_id
  spec$items <- c(spec$items, list(c(list(id = id), item, list(note = "", clamped = FALSE))))
  spec$next_id <- id + 1L
  within_link(spec)
}

#' A report without one of its items
#'
#' @param spec A report.
#' @param id The item's id.
#' @noRd
report_remove <- function(spec, id) {
  spec$items <- spec$items[-item_at(spec, id)]
  spec
}

#' A report with one item moved up or down
#'
#' @param spec A report.
#' @param id The item's id.
#' @param by How many places: negative moves it up, towards the first item.
#'   It stops at either end.
#' @return The report with the item moved. A move that would make the
#'   report's link too long, as the order of its items changes how well it
#'   compresses, is an error of class `prexp_report_limit`.
#' @noRd
report_move <- function(spec, id, by) {
  at <- item_at(spec, id)
  if (!is.numeric(by) || length(by) != 1L || !is.finite(by) || by != trunc(by)) {
    invalid_argument("`by` must be one whole number, not ", value_text(by), ".")
  }
  # In doubles, so that a `by` past the integers still stops at either end
  to <- as.integer(min(max(at + as.double(by), 1), length(spec$items)))
  if (to == at) {
    return(spec)
  }
  item <- spec$items[[at]]
  spec$items <- append(spec$items[-at], list(item), after = to - 1L)
  within_link(spec)
}

#' A report with one item's note set
#'
#' @param spec A report.
#' @param id The item's id.
#' @param note Text of at most 500 characters; more, or a note that would make
#'   the report's link too long, is an error of class `prexp_report_limit`.
#' @noRd
report_set_note <- function(spec, id, note) {
  at <- item_at(spec, id)
  spec$items[[at]]$note <- validate_note(note)
  within_link(spec)
}

# The report, if its link fits: encode_report() refuses one that does not
within_link <- function(spec) {
  encode_report(spec)
  spec
}

# The items' ids, in order
item_ids <- function(spec) {
  vapply(spec$items, function(item) item$id, integer(1))
}

# Where an item is in the report, by its id
item_at <- function(spec, id) {
  id <- validate_id(id)
  at <- match(id, item_ids(spec))
  if (is.na(at)) {
    invalid_argument("The report has no item ", id, ".")
  }
  at
}

# A note: one string of UTF-8 text, at most 500 characters, with no character
# that XML cannot hold (control characters other than tabs and line breaks,
# and U+FFFE and U+FFFF): the exports write notes into Office files, which are
# XML
validate_note <- function(note) {
  if (!is.character(note) || length(note) != 1L || is.na(note)) {
    invalid_argument("`note` must be one string, not ", value_shape(note), ".")
  }
  note <- enc2utf8(note)
  if (!validUTF8(note)) {
    invalid_argument("`note` must be text in UTF-8.")
  }
  points <- utf8ToInt(note)
  if (any(unheld_text(points, line_breaks = TRUE))) {
    invalid_argument(
      "`note` must be text without control characters other than tabs and line breaks."
    )
  }
  limit <- report_limits()$note
  n <- length(points)
  if (n > limit) {
    report_limit("A note holds at most ", limit, " characters; this one has ", n, ".")
  }
  note
}

#' An item's view and parameters, checked
#'
#' Each view takes a fixed set of parameters, the ones its `current()` gives:
#' the drug and region views `level`, `id`, `code`, `label`, `months` and
#' `measure`; the practice view the same without `level`. A missing or extra
#' parameter is an error, as is any value its check refuses.
#'
#' @param view `"drug"`, `"practice"` or `"region"`.
#' @param params A named list of the view's parameters.
#' @return `list(view, params)`, the parameters in their order, ids and months
#'   as integers. Errors are of class `prexp_invalid_argument`.
#' @noRd
validate_item <- function(view, params) {
  views <- report_views()
  view <- validate_choice(view, names(views), "view")
  wanted <- views[[view]]
  given <- names(params)
  if (!is.list(params) || length(params) > 0L && (is.null(given) || anyNA(given))) {
    invalid_argument("`params` must be a named list, not ", value_shape(params), ".")
  }
  if (!setequal(given, wanted) || anyDuplicated(given) > 0L) {
    invalid_argument(
      "A ", view, " item takes ", paste(wanted, collapse = ", "), "; it was given ",
      if (length(given) > 0L) paste(given, collapse = ", ") else "none", "."
    )
  }
  level <- if ("level" %in% wanted) {
    validate_choice(params$level, c("chemical", "presentation"), "level")
  }
  checked <- list(
    level = level,
    id = validate_id(params$id),
    code = validate_code(params$code),
    label = validate_label(params$label),
    months = validate_months(params$months),
    measure = if (view == "practice") {
      validate_choice(params$measure, c("items", "nic", "actual_cost"), "measure")
    } else {
      validate_measure(params$measure, level)
    }
  )
  list(view = view, params = checked[wanted])
}

# Which characters, as code points, XML cannot hold or a line of text should
# not: control characters (C0, DEL and C1), and U+FFFE and U+FFFF. Code
# points rather than a regular expression: R matches text that is all ASCII
# byte by byte, where U+FFFF cannot be named. A note may hold tabs and line
# breaks.
unheld_text <- function(points, line_breaks) {
  kept <- if (line_breaks) c(9L, 10L, 13L) else integer()
  (points < 32L | points >= 127L & points <= 159L) & !points %in% kept |
    points %in% c(65534L, 65535L)
}

# A BNF or practice code, as the search gives it: letters and digits, or
# missing
validate_code <- function(code) {
  if (is.null(code) || length(code) == 1L && is.na(code)) {
    return(NA_character_)
  }
  if (!is.character(code) || length(code) != 1L || !grepl("^[0-9A-Za-z]{1,20}$", code)) {
    invalid_argument(
      "`code` must be one code of 1 to 20 letters and digits, not ", value_text(code), "."
    )
  }
  code
}

# A drug's or a practice's name: one line of UTF-8 text, 1 to 200 characters,
# with no character that XML cannot hold, as in a note (control characters,
# and U+FFFE and U+FFFF): the exports write titles into Office files
validate_label <- function(label) {
  limit <- report_limits()$label
  ok <- is.character(label) && length(label) == 1L && !is.na(label) &&
    validUTF8(enc2utf8(label)) && nchar(enc2utf8(label)) %in% seq_len(limit) &&
    !any(unheld_text(utf8ToInt(enc2utf8(label)), line_breaks = FALSE))
  if (!ok) {
    invalid_argument(
      "`label` must be one line of text, 1 to ", limit, " characters, not ",
      value_shape(label), "."
    )
  }
  enc2utf8(label)
}

#' A report as the text of its link
#'
#' Compact JSON of its items' views, parameters and notes, compressed with
#' deflate (`memCompress(type = "gzip")`) and written in base64url, which a URL
#' holds as it is. A report at the limits, with notes of English prose, takes
#' about 4,500 characters. Notes that compress poorly can make it longer than
#' `report_limits()$link`: that is an error of class `prexp_report_limit`,
#' which [report_add()], [report_set_note()] and [report_move()] raise as soon
#' as a change would cause it.
#'
#' @param spec A report.
#' @return One string of letters, digits, `-` and `_`.
#' @noRd
encode_report <- function(spec) {
  items <- lapply(spec$items, function(item) item[c("view", "params", "note")])
  json <- jsonlite::toJSON(
    list(v = report_format, items = items),
    auto_unbox = TRUE, digits = NA, na = "null", null = "null"
  )
  raw <- memCompress(charToRaw(enc2utf8(as.character(json))), type = "gzip")
  text <- chartr("+/", "-_", jsonlite::base64_enc(raw))
  text <- sub("=+$", "", gsub("[\r\n]", "", text))
  limit <- report_limits()$link
  if (nchar(text) > limit) {
    report_limit(
      "The report's link would be ", nchar(text), " characters, more than the ", limit,
      " a link can have: shorten its notes."
    )
  }
  text
}

#' A report from the text of its link
#'
#' The reverse of [encode_report()], then every item checked as
#' [report_add()] and [report_set_note()] check them. Anything else, a link
#' that is cut short, too long, not compressed JSON, of another format, nested
#' deeper than the format, holding what an R string cannot, or with any item
#' that fails a check, is an error of class `prexp_invalid_report`, never part
#' of a report.
#'
#' @param text The link's text.
#' @return A report, its items numbered from 1 in order, every item's
#'   `clamped` FALSE.
#' @noRd
decode_report <- function(text) {
  limits <- report_limits()
  if (!is.character(text) || length(text) != 1L || is.na(text)) {
    invalid_report("A report's link must be one string, not ", value_shape(text), ".")
  }
  if (nchar(text, type = "bytes") > limits$link) {
    invalid_report("The report's link is longer than ", limits$link, " characters.")
  }
  if (!grepl("^[A-Za-z0-9_-]*$", text)) {
    invalid_report("The report's link holds characters that base64url does not use.")
  }
  padded <- paste0(chartr("-_", "+/", text), strrep("=", (4L - nchar(text) %% 4L) %% 4L))
  raw <- tryCatch(jsonlite::base64_dec(padded), error = function(e) NULL)
  json <- tryCatch(memDecompress(raw, type = "gzip"), error = function(e) NULL)
  if (length(json) == 0L) {
    invalid_report("The report's link is not a compressed report: it may be cut short.")
  }
  if (length(json) > limits$json) {
    invalid_report("The report's link unpacks to more than ", limits$json, " bytes.")
  }
  # A NUL byte, at which rawToChar() stops with an error of its own: no report
  # has one
  if (any(json == as.raw(0L))) {
    invalid_report("The report's link does not hold a report of this app's format.")
  }
  json <- rawToChar(json)
  Encoding(json) <- "UTF-8"
  # Valid JSON first, checked in one pass: no unclosed string or comment can
  # slow the checks after it, nor hide nesting from json_depth(). Then
  # parse_json(), which reads its text as JSON only, never as a URL to fetch
  # or a file to read, as fromJSON() does with text that is not JSON.
  valid <- validUTF8(json) && isTRUE(jsonlite::validate(json)) && !json_unheld(json) &&
    json_depth(json) <= report_depth
  data <- if (valid) {
    tryCatch(jsonlite::parse_json(json, simplifyVector = FALSE), error = function(e) NULL)
  }
  ours <- is.list(data) && identical(data$v, report_format) && is.list(data$items) &&
    setequal(names(data), c("v", "items"))
  if (!ours) {
    invalid_report("The report's link does not hold a report of this app's format.")
  }
  tryCatch(
    report_from_items(data$items),
    prexp_invalid_argument = function(e) {
      invalid_report("The report's link holds an item that is not valid: ", conditionMessage(e))
    },
    prexp_report_limit = function(e) {
      invalid_report("The report's link goes past a report's limits: ", conditionMessage(e))
    }
  )
}

# Whether JSON escapes U+0000, at which jsonlite cuts a string short, or any
# surrogate: jsonlite writes a lone one as "?", and the app writes none, as it
# writes every character as it is. A backslash escaped before "u0000" is
# text, not an escape.
json_unheld <- function(json) {
  slash <- "\\\\"
  pattern <- paste0("(?<!", slash, ")(?:", slash, slash, ")*", slash, "u(?:0000|[dD][89a-fA-F])")
  grepl(pattern, json, perl = TRUE)
}

# How deep valid JSON nests, outside its strings: read before parsing, so that
# no value nested thousands deep, which takes R seconds to walk and can
# overflow its C stack, reaches the checks. Valid JSON only: its every string
# ends, so each is matched once.
json_depth <- function(json) {
  bare <- gsub("\"(?:[^\"\\\\]++|\\\\.)*+\"", "\"\"", json, perl = TRUE)
  marks <- strsplit(gsub("[^][{}]", "", bare), "")[[1L]]
  if (length(marks) == 0L) {
    return(0L)
  }
  as.integer(max(cumsum(ifelse(marks %in% c("[", "{"), 1L, -1L))))
}

# The items read from a link, each checked as if added and noted in turn, and
# numbered from 1 in order: an id names an item only within a session
report_from_items <- function(items) {
  if (length(items) > report_limits()$items) {
    report_limit("A report holds at most ", report_limits()$items, " items.")
  }
  spec <- new_report()
  for (item in items) {
    if (!is.list(item) || !setequal(names(item), c("view", "params", "note"))) {
      invalid_argument("each item must have a view, parameters and a note.")
    }
    params <- item$params
    # Months come as a JSON array of two numbers, which R reads as a list
    months <- if (is.list(params)) params$months
    if (is.list(months) && length(months) == 2L && all(vapply(months, is_scalar, TRUE))) {
      params$months <- unlist(months)
    }
    checked <- validate_item(item$view, params)
    spec$items <- c(spec$items, list(c(
      list(id = spec$next_id), checked,
      list(note = validate_note(item$note), clamped = FALSE)
    )))
    spec$next_id <- spec$next_id + 1L
  }
  spec
}

# A single number or string
is_scalar <- function(x) {
  is.atomic(x) && length(x) == 1L
}

#' A report's months moved into the data window
#'
#' The window rolls, so a link can name months that have since been dropped.
#' Each item keeps the part of its months that the window still holds; an
#' item with none of them left gets the whole window. Items whose months
#' change are marked `clamped`, which the report panel shows.
#'
#' @param spec A report.
#' @param window The data window, as [fetch_window()] gives it. With no months
#'   loaded, the report is returned as it is.
#' @noRd
clamp_report <- function(spec, window) {
  if (is.null(window) || nrow(window) == 0L || is.na(window$first_month[1])) {
    return(spec)
  }
  first <- as.integer(window$first_month[1])
  last <- as.integer(window$last_month[1])
  spec$items <- lapply(spec$items, function(item) {
    months <- item$params$months
    kept <- c(max(months[1], first), min(months[2], last))
    if (kept[1] > kept[2]) {
      kept <- c(first, last)
    }
    if (!identical(kept, months)) {
      item$params$months <- kept
      item$clamped <- TRUE
    }
    item
  })
  spec
}
