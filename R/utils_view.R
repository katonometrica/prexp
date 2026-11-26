# What the views share (P4-04 to P4-06): the fetch functions they call, the
# month range and measure controls, and their states besides the normal one:
# nothing selected, no rows, and an error with a retry button (spec 5.3).

#' The fetch functions of the app, on one pool or connection
#'
#' The views call these, never the fetch functions themselves, so that the
#' tests can pass fakes, and so that with a cache every fetch but the window's
#' is kept in it. With a cache, `chart` keeps the charts the views draw too
#' ([keep_chart()]).
#'
#' @param con A pool from [db_pool()], or a connection.
#' @param cache The app's cache, from [app_cache()], or `NULL` for none.
#' @param window With a cache, a function giving the data window, part of
#'   every key ([cache_fetch()]).
#' @return A named list of functions.
#' @noRd
app_fetches <- function(con, cache = NULL, window = NULL) {
  fetches <- plain_fetches(con)
  if (is.null(cache)) {
    return(fetches)
  }
  kept <- setdiff(names(fetches), "window")
  fetches[kept] <- lapply(kept, function(name) {
    cache_fetch(cache, name, fetches[[name]], window)
  })
  fetches$chart <- cache_value(cache, "chart", window)
  fetches
}

#' A view's chart, drawn once for every session asking the same
#'
#' A chart takes most of a lookup's time on the server, so with the app's
#' cache ([app_fetches()]) a chart drawn is kept, keyed on what it is drawn
#' from; without one, as in the tests' fakes, it is drawn every time.
#'
#' @param fetches The app's fetch functions.
#' @param key A list of everything the chart is drawn from: its view, data,
#'   measure, months, width and name.
#' @param draw A function drawing the chart.
#' @return The chart.
#' @noRd
keep_chart <- function(fetches, key, draw) {
  if (is.null(fetches$chart)) draw() else fetches$chart(key, draw)
}

# The fetch functions on a pool or connection, as the views call them
plain_fetches <- function(con) {
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
    regions = function() fetch_regions(con),
    subject = function(kind, code) fetch_subject(con, kind, code)
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
  # Side by side where the controls' card is wide enough for both months,
  # one above the other below that. The grid's twelve columns keep eleven
  # gaps, which at bslib's 24 px each were wider than a narrow card.
  bslib::layout_columns(
    col_widths = bslib::breakpoints(sm = c(12, 12), lg = c(6, 6)), gap = "0.75rem",
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
# it; NULL until the browser has said, and while the output is not shown
# (a tab not shown reports 0)
output_width <- function(session, id) {
  width <- session$clientData[[paste0("output_", session$ns(id), "_width")]]
  if (!is.numeric(width) || length(width) != 1L || is.na(width) || width <= 0) {
    return(NULL)
  }
  width
}

#' A view's results card body: the body output, which reports its width
#' whenever it changes, so that the charts in it are drawn at that width
#' ([chart_width()]). prexp.css gives it a box of its own: Shiny would make a
#' uiOutput with content a box of none, whose width it never reports.
#'
#' @param ns The view's namespace function.
#' @return Shiny UI.
#' @noRd
view_body <- function(ns) {
  bslib::card_body(shiny::uiOutput(ns("body"), class = "shiny-report-size"))
}

#' A view's results card header: its title, the CSV button once there is data
#' to download, and the "Add to report" button, off until there is a view to
#' pin ([report_pin()])
#'
#' @param ns The view's namespace function.
#' @return Shiny UI.
#' @noRd
view_header <- function(ns) {
  bslib::card_header(
    class = "d-flex justify-content-between align-items-center gap-2",
    shiny::textOutput(ns("title"), inline = TRUE),
    shiny::div(
      class = "d-flex gap-2 flex-shrink-0",
      shiny::uiOutput(ns("csv_ui"), inline = TRUE),
      shiny::actionButton(ns("pin"), "Add to report", class = "btn-primary btn-sm", disabled = TRUE)
    )
  )
}

#' The CSV download of a view: the data of its current view
#'
#' The button is drawn when data appears or goes, not again on every change of
#' measure, months or pick, which would lose the keyboard's focus and announce
#' it again. It reads "CSV", and "Download CSV" to a screen reader.
#'
#' @param output The view's output.
#' @param ns The view's namespace function.
#' @param current The view's `current_view()` reactive.
#' @param title What the file holds, for the button's tooltip.
#' @return Nothing: it sets the outputs `csv_ui` and `csv`.
#' @noRd
csv_download <- function(output, ns, current, title) {
  has_data <- shiny::reactiveVal(FALSE)
  shiny::observe(has_data(!is.null(current())))
  output$csv_ui <- shiny::renderUI({
    if (!has_data()) {
      return(NULL)
    }
    shiny::downloadButton(
      ns("csv"), shiny::tagList(shiny::span(class = "visually-hidden", "Download"), "CSV"),
      class = "btn-outline-primary btn-sm", icon = NULL, title = title
    )
  })
  output$csv <- shiny::downloadHandler(
    filename = function() csv_name(current()),
    content = function(file) write_view_csv(current(), file),
    contentType = "text/csv"
  )
  invisible(NULL)
}

# A CSV's file name: the app, the view, its subject's code and name, the
# measure and the months, as in
# "prexp-drug-0212000B0-atorvastatin-items-202510-202609.csv". Two subjects
# with the same name have different codes. The Practice file holds every
# measure, so its name names none.
csv_name <- function(view) {
  params <- view$params
  slug <- function(x) gsub("^-+|-+$", "", gsub("[^a-z0-9]+", "-", tolower(x)))
  code <- if (length(params$code) == 1L && !is.na(params$code) && nzchar(params$code)) {
    gsub("[^A-Za-z0-9]", "", params$code)
  } else {
    as.character(params$id)
  }
  name <- if (length(params$label) == 1L && !is.na(params$label)) {
    sub("-+$", "", substr(slug(params$label), 1L, 40L))
  }
  measure <- if (!identical(view$view, "practice")) slug(params$measure)
  parts <- c("prexp", view$view, code, name[nzchar(name)], measure, params$months[1:2])
  paste0(paste(parts, collapse = "-"), ".csv")
}

# The view's data as CSV, in UTF-8, a missing value as an empty field, and
# every number in full: write.csv() writes 400000 as 4e+05 by default, which a
# spreadsheet then shows as 4.00E+05 among plain numbers
write_view_csv <- function(view, file) {
  old <- options(scipen = 100L)
  on.exit(options(old), add = TRUE)
  utils::write.csv(
    as.data.frame(view$data), file, row.names = FALSE, na = "", fileEncoding = "UTF-8"
  )
}

# Every month of the range, in order, a month without a row as `zeros` (named
# values by column), as chart_series() draws a month without prescribing
complete_months <- function(rows, months, zeros) {
  all <- index_month(seq(month_index(as.integer(months[1])), month_index(as.integer(months[2]))))
  out <- rows[match(all, rows$year_month), ]
  out$year_month <- all
  gap <- !all %in% rows$year_month
  for (column in names(zeros)) {
    out[[column]][gap] <- zeros[[column]]
  }
  out
}

#' A view's message in place of its results
#'
#' @param text What to say.
#' @param retry The id of a retry button to show under it, or `NULL`.
#' @param error Whether it says that something failed, which a rule in the
#'   error colour marks: by default, when it offers a retry.
#' @return Shiny UI.
#' @noRd
view_message <- function(text, retry = NULL, error = !is.null(retry)) {
  shiny::div(
    class = paste(c("prexp-view-message", if (error) "prexp-view-error"), collapse = " "),
    role = "status",
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

# A code, such as a BNF code, on one line in the brand's mono font, which it
# keeps for such details
code_style <- list(
  whiteSpace = "nowrap", fontFamily = "var(--bs-font-monospace)", fontSize = "13px"
)

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
# cells sort by their values. Quantity and ADQ usage are written by an R
# function, once per row, unless `label` names a column of the table's data
# that holds them already, written for the whole column at once: the browser
# then shows that column's text. A long table needs it, as those calls took
# most of the time of a chemical's 2,068 presentations (#101).
measure_column <- function(name, measure, ..., label = NULL) {
  if (measure %in% c("nic", "actual_cost")) {
    return(pounds_column(name, ...))
  }
  if (measure == "items") {
    return(count_column(name, ...))
  }
  cell <- if (is.null(label)) {
    function(value) format_measure(value, measure)
  } else {
    js <- sprintf("function(cell) { return cell.row[%s] }", encodeString(label, quote = "\""))
    reactable::JS(js)
  }
  reactable::colDef(
    name = name, ..., minWidth = 125, style = nowrap, align = "right", cell = cell
  )
}

# A reactive's value that tells its readers only of a new one: a control drawn
# again sends the value it had, which read directly would fetch again. The
# observer runs before the outputs (priority 100), so they never read a stale
# value. One read by another runs first, with a higher priority: within a
# priority, Shiny's order is not the order they were made in.
changes_only <- function(r, priority = 100) {
  value <- shiny::reactiveVal()
  shiny::observe(value(r()), priority = priority)
  function() value()
}

# The width a view's charts are drawn at: its body's width (view_body()),
# which the browser reports before any pick, to the nearest `step` px; NULL
# until it has, so a chart on a tab not yet shown waits to be drawn at its
# width. A chart's own element is new each time its frame is drawn, so its
# width would come a round trip later. The chart is drawn again only when the
# width moves by `tolerance` px or more: the SVG scales to fit, and a long
# table giving the page a scroll bar takes about 15 px. While the body is
# not shown (another tab), the width stays as it was.
chart_width <- function(session, id = "body", step = 10, tolerance = 30) {
  value <- shiny::reactiveVal()
  shiny::observe({
    width <- output_width(session, id)
    if (!is.null(width)) {
      width <- step * round(width / step)
      drawn <- shiny::isolate(value())
      if (is.null(drawn) || abs(width - drawn) >= tolerance) {
        value(width)
      }
    }
  }, priority = 100)
  function() value()
}

# Outputs computed whether or not the browser reports them shown. Shiny
# suspends an output until the browser reports it shown, which for one drawn
# in a renderUI comes only after it is drawn: a view's chart and table would
# come a round trip after their frame. Computed always, they come with it.
compute_always <- function(output, names) {
  for (name in names) {
    shiny::outputOptions(output, name, suspendWhenHidden = FALSE)
  }
  invisible(NULL)
}

# Clicks on a view's Try again button, counted. Read directly, the button's
# value also changes when it is drawn again (back to 0), which would fetch
# again unasked
retry_clicks <- function(input, id = "retry") {
  clicks <- shiny::reactiveVal(0L)
  shiny::observeEvent(input[[id]], clicks(clicks() + 1L))
  clicks
}

# Says when a Try again fails again. The message on the page stays as it is,
# so the button keeps the focus, and the page's status region tells screen
# readers (announce()) what nothing on the page would. `failed` says whether
# the view still shows the error; it is read after the view has fetched
# again (a priority below the outputs').
retry_feedback <- function(session, retries, failed) {
  shiny::observeEvent(retries(), {
    if (isTRUE(failed())) {
      announce(session, "The data could still not be fetched.")
    }
  }, ignoreInit = TRUE, priority = -10)
}

# Why a view has no months to show: the window could not be fetched (the app
# tries again), or it was and no month is loaded yet
no_window_message <- function(fetched) {
  if (fetched) {
    view_message("No data is loaded yet.")
  } else {
    view_message("The data could not be fetched. The app is trying again.", error = TRUE)
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
