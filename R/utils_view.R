# What the views share (P4-04 to P4-06): the fetch functions they call, the
# month range and measure controls, and their states besides the normal one:
# nothing selected, no rows, and an error with a retry button (spec 5.3).

#' The fetch functions of the app, on one pool or connection
#'
#' The views call these, never the fetch functions themselves, so that the
#' tests can pass fakes and P4-07 can wrap them with its cache.
#'
#' @param con A pool from [db_pool()], or a connection.
#' @return A named list of functions.
#' @noRd
app_fetches <- function(con) {
  list(
    window = function() fetch_window(con),
    search_drugs = function(q) fetch_search_drugs(con, q, limit = 20L),
    search_practices = function(q) fetch_search_practices(con, q, limit = 20L),
    drug_series = function(level, id, months, measure) {
      fetch_drug_series(con, level, id, months, measure)
    },
    drug_presentations = function(chemical_id, months) {
      fetch_drug_presentations(con, chemical_id, months)
    },
    practice_profile = function(practice_id) fetch_practice_profile(con, practice_id),
    practice_series = function(practice_id, months) {
      fetch_practice_series(con, practice_id, months)
    },
    practice_top_drugs = function(practice_id, months, by, limit, after) {
      fetch_practice_top_drugs(con, practice_id, months, by = by, limit = limit, after = after)
    },
    region_comparison = function(level, id, months, measure) {
      fetch_region_comparison(con, level, id, months, measure)
    },
    regions = function() fetch_regions(con)
  )
}

# The months of a window, latest first, named by their labels, for a select
months_of_window <- function(window) {
  if (is.null(window) || nrow(window) == 0L || is.na(window$first_month)) {
    return(integer())
  }
  months <- index_month(seq(month_index(window$first_month), month_index(window$last_month)))
  months <- rev(months)
  structure(months, names = format_month(months))
}

#' The month range controls, rendered by the server from the window
#'
#' @param ns The view's namespace function.
#' @param window The window, from fetch_window().
#' @param from,to The months the user had chosen, kept when the controls are
#'   drawn again; the whole window by default.
#' @return Shiny UI.
#' @noRd
months_controls <- function(ns, window, from = NULL, to = NULL) {
  choices <- months_of_window(window)
  if (length(choices) == 0L) {
    return(shiny::p(class = "text-muted", "No months are loaded yet."))
  }
  keep <- function(value, default) if (!is.null(value) && value %in% choices) value else default
  bslib::layout_columns(
    col_widths = c(6, 6),
    shiny::selectInput(ns("from"), "From", choices, selected = keep(from, min(choices))),
    shiny::selectInput(ns("to"), "To", choices, selected = keep(to, max(choices)))
  )
}

# The months chosen, first and last, in order; the whole window until the
# controls exist
chosen_months <- function(from, to, window) {
  months <- months_of_window(window)
  if (length(months) == 0L) {
    return(NULL)
  }
  from <- if (is.null(from)) min(months) else as.integer(from)
  to <- if (is.null(to)) max(months) else as.integer(to)
  sort(c(from, to))
}

# The measures a drug at a level can show: quantity only for a presentation,
# whose units are one
measures_for_level <- function(level) {
  info <- measure_info()
  allowed <- info$measure
  if (!identical(level, "presentation")) {
    allowed <- setdiff(allowed, "total_quantity")
  }
  structure(allowed, names = info$label[match(allowed, info$measure)])
}

#' The measure control, rendered by the server for the level
#'
#' @param ns The view's namespace function.
#' @param measures The measures to offer, named by their labels.
#' @param selected The measure the user had chosen, kept if still offered.
#' @return Shiny UI.
#' @noRd
measure_control <- function(ns, measures, selected = NULL) {
  selected <- if (!is.null(selected) && selected %in% measures) selected else measures[[1]]
  shiny::radioButtons(ns("measure"), "Measure", measures, selected = selected)
}

# The measure to show: the one chosen if the level allows it, else the first
chosen_measure <- function(measure, measures) {
  if (!is.null(measure) && measure %in% measures) measure else unname(measures[[1]])
}

# The height of a view's chart, in CSS pixels; its width is the page's
chart_height <- 320L

# The width of a view's output in the browser, in CSS pixels, as Shiny reports
# it, so that a chart is drawn at the size it is shown at; 768 until the
# browser has said (and in tests)
output_width <- function(session, id) {
  width <- session$clientData[[paste0("output_", session$ns(id), "_width")]]
  if (!is.numeric(width) || length(width) != 1L || is.na(width) || width <= 0) {
    return(768)
  }
  width
}

#' A view's message in place of its results
#'
#' @param text What to say.
#' @param retry The id of a retry button to show under it, or `NULL`.
#' @return Shiny UI.
#' @noRd
view_message <- function(text, retry = NULL) {
  shiny::div(
    class = "prexp-view-message", role = "status",
    shiny::p(text),
    if (!is.null(retry)) shiny::actionButton(retry, "Try again", class = "btn-outline-primary")
  )
}

# Brand, generic, or neither for an appliance
brand_or_generic <- function(is_generic) {
  ifelse(is.na(is_generic), "\u2013", ifelse(is_generic, "Generic", "Brand"))
}

# A table cell kept on one line: a number or a code split across two reads as
# two. Its column is also given the width the longest needs, since a table
# hides what overflows a cell; the table scrolls sideways instead.
nowrap <- list(whiteSpace = "nowrap")

# Table columns of counts and of pounds, written the British way whatever the
# browser's language (1,234,567 and GBP 1,234.56), as the rest of the app is
count_column <- function(name, ..., min_width = 125) {
  reactable::colDef(
    name = name, ..., minWidth = min_width, style = nowrap,
    format = reactable::colFormat(separators = TRUE, digits = 0, locales = "en-GB")
  )
}

# Wide enough for GBP 999,999,999.99
pounds_column <- function(name, ..., min_width = 140) {
  reactable::colDef(
    name = name, ..., minWidth = min_width, style = nowrap,
    format = reactable::colFormat(
      prefix = "\u00a3", separators = TRUE, digits = 2, locales = "en-GB"
    )
  )
}

# A column of a measure in its form: pounds for the costs, whole numbers for
# items, and three significant figures for quantity and ADQ usage, as
# format_measure() writes them (a whole number would show 0.4 ADQs as 0). The
# cells sort by their values.
measure_column <- function(name, measure, ...) {
  if (measure %in% c("nic", "actual_cost")) {
    return(pounds_column(name, ...))
  }
  if (measure == "items") {
    return(count_column(name, ...))
  }
  reactable::colDef(
    name = name, ..., minWidth = 125, style = nowrap, align = "right",
    cell = function(value) format_measure(value, measure)
  )
}

# A reactive's value that tells its readers only of a new one: a control drawn
# again sends the value it had, which read directly would fetch again. The
# observer runs before the outputs (priority 100), so they never read a stale
# value.
changes_only <- function(r) {
  value <- shiny::reactiveVal()
  shiny::observe(value(r()), priority = 100)
  function() value()
}

# Clicks on a view's Try again button, counted. Read directly, the button's
# value also changes when it is drawn again (back to 0), which would fetch
# again unasked
retry_clicks <- function(input, id = "retry") {
  clicks <- shiny::reactiveVal(0L)
  shiny::observeEvent(input[[id]], clicks(clicks() + 1L))
  clicks
}

# Why a view has no months to show: the window could not be fetched (the app
# tries again), or no month is loaded yet
no_window_message <- function(window) {
  if (is.null(window)) {
    view_message("The data could not be fetched. The app is trying again.")
  } else {
    view_message("No data is loaded yet.")
  }
}

# A fetch's result, or the error it raised, so the view can show it. The
# app's log gets the cause, not the page: the error's message, or only its
# class for a refused argument, whose message quotes the value (spec section
# 5.4 keeps what users type out of the log).
try_fetch <- function(expr) {
  tryCatch(expr, error = function(e) {
    cause <- if (inherits(e, "prexp_invalid_argument")) class(e)[[1L]] else conditionMessage(e)
    message("A fetch failed: ", cause)
    e
  })
}
