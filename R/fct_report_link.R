# The shareable link (P5-03; spec section 5.5). A bookmark's URL holds the
# active tab, the view's selections and the report, and no other input: the
# report and the selections as two values, each the text of a report's link
# (fct_report_spec.R), which decode_report() checks whole when the link is
# opened. The selections are those of the view last shown, as the Copy link
# button is on the Report tab, or, in a session opened from a link that has
# shown no view yet, those the link put back.
#
# Opening a link takes each drug's and practice's id and name from the
# database by its code ([fetch_subject()]), never from the link, which could
# name any id anything: ids also change when the database is rebuilt, and
# codes do not. The logic is in the functions below, which report_link()
# wires to the session.

#' What a bookmark keeps beside the active tab
#'
#' @param report The session's report.
#' @param view The selections to keep, as a view's `current_view()` gives
#'   them, or `NULL`.
#' @return A named list: `report`, the report's link text, when it has items;
#'   `view`, the view's selections as a one-item report, when it shows data
#'   that the report takes.
#' @noRd
link_values <- function(report, view = NULL) {
  values <- list()
  if (length(report$items) > 0L) {
    values$report <- encode_report(report)
  }
  if (!is.null(view)) {
    params <- view$params
    params$label <- pin_label(params$label)
    one <- tryCatch(
      report_add(new_report(), view$view, params),
      prexp_invalid_argument = function(e) NULL
    )
    if (!is.null(one)) {
      values$view <- encode_report(one)
    }
  }
  values
}

#' A bookmark's values read back
#'
#' Each part is decoded and clamped to the window, and each of its items
#' takes its subject's id and name from the database by its code. An item
#' whose code the data does not hold is left out.
#'
#' @param values The bookmark's values, as `onRestore()` gets them.
#' @param window The data window, as [fetch_window()] gives it.
#' @param subject A function of a kind (`"chemical"`, `"presentation"` or
#'   `"practice"`) and a code, as `fetch_subject()` takes them after the
#'   connection.
#' @param sent The names in the link's query string. Shiny reads each value as
#'   JSON and drops one it cannot read before `onRestore()`, as the last value
#'   of a link cut short, which has lost its closing quote: a name sent without
#'   a value was not read.
#' @return A list: `report`, the report, or `NULL`; `view`, the selections as
#'   an item, or `NULL`; `refused`, the parts that were not read, named by
#'   part, each `"unread"` (not what this app writes) or `"unfetched"` (a
#'   subject could not be looked up); `left_out`, how many of the report's
#'   items name a drug or practice the data does not hold; `view_left_out`,
#'   whether the selections did.
#' @noRd
link_restore <- function(values, window, subject, sent = character()) {
  restored <- list(
    report = NULL, view = NULL, refused = character(), left_out = 0L, view_left_out = FALSE
  )
  # The parts refused, and why, as they are found
  refusals <- new.env(parent = emptyenv())
  refusals$why <- character()
  refuse <- function(name, why) {
    refusals$why[[name]] <- why
    NULL
  }
  read <- function(name) {
    spec <- tryCatch(
      clamp_report(decode_report(values[[name]]), window),
      prexp_invalid_report = function(e) refuse(name, "unread")
    )
    if (is.null(spec)) {
      return(NULL)
    }
    owned <- tryCatch(
      lapply(spec$items, own_subject, subject = subject),
      error = function(e) {
        base::message("A link's subjects could not be looked up: ", conditionMessage(e))
        refuse(name, "unfetched")
      }
    )
    if (is.null(owned) && length(spec$items) > 0L) {
      return(NULL)
    }
    kept <- Filter(Negate(is.null), owned)
    left_out <- length(owned) - length(kept)
    spec$items <- kept
    list(spec = spec, left_out = left_out)
  }
  for (name in intersect(c("report", "view"), sent)) {
    if (is.null(values[[name]])) {
      refuse(name, "unread")
    }
  }
  if (!is.null(values$report)) {
    report <- read("report")
    if (!is.null(report)) {
      restored$left_out <- report$left_out
      if (length(report$spec$items) > 0L) {
        restored$report <- report$spec
      }
    }
  }
  if (!is.null(values$view)) {
    view <- read("view")
    if (!is.null(view) && length(view$spec$items) + view$left_out != 1L) {
      refuse("view", "unread")
    } else if (!is.null(view)) {
      restored$view_left_out <- view$left_out == 1L
      if (!restored$view_left_out) {
        restored$view <- view$spec$items[[1]]
      }
    }
  }
  restored$refused <- refusals$why
  restored
}

# An item with its subject's id, code and name as the database holds them,
# by the item's code, or NULL when the data does not hold that code
own_subject <- function(item, subject) {
  params <- item$params
  if (is.na(params$code)) {
    return(NULL)
  }
  kind <- if (identical(item$view, "practice")) "practice" else params$level
  found <- subject(kind, params$code)
  if (nrow(found) != 1L) {
    return(NULL)
  }
  name <- if (is.na(found$name) || !nzchar(found$name)) found$code else found$name
  item$params$id <- as.integer(found$id)
  item$params$code <- found$code
  item$params$label <- pin_label(name)
  item
}

# The names in a link's query string, as Shiny reads them
link_sent <- function(search) {
  if (!is.character(search) || length(search) != 1L || is.na(search)) {
    return(character())
  }
  tryCatch(
    names(suppressWarnings(shiny::parseQueryString(search))),
    error = function(e) character()
  ) %||% character()
}

#' The selections a link keeps
#'
#' @param last The name of the view last shown, or `NULL`.
#' @param current That view's `current_view()`, or `NULL`.
#' @param carried The selections the session's link put back, or `NULL`.
#' @return The view last shown's selections, or, when no view has been shown,
#'   those the link put back.
#' @noRd
link_view <- function(last, current, carried) {
  if (is.null(last)) carried else current
}

#' What a bookmark writes
#'
#' Every input but the tab, whose value a bookmark keeps as the page's own, is
#' excluded as the URL is written, so that an input that first arrives with
#' the click is left out too.
#'
#' @param state The bookmark's state, as `onBookmark()` gets it.
#' @param report The session's report.
#' @param view The selections to keep, as [link_view()] gives them.
#' @return Invisibly, the values written.
#' @noRd
link_bookmark <- function(state, report, view) {
  state$exclude <- union(state$exclude, setdiff(names(state$input), "tab"))
  values <- link_values(report, view)
  for (name in names(values)) {
    state$values[[name]] <- values[[name]]
  }
  invisible(values)
}

#' What opening a link does
#'
#' The report goes to the panel and the selections to their view, which a
#' link with nothing pinned opens on; the user is told what was opened, warned
#' when a part was refused, which the log then names.
#'
#' @inheritParams link_restore
#' @param report The session's report, a `reactiveVal()`.
#' @param restoring The views' `reactiveVal()`s of an item to put back.
#' @param session The session.
#' @return Invisibly, what [link_restore()] gave.
#' @noRd
link_open <- function(values, window, subject, sent, report, restoring, session) {
  restored <- link_restore(values, window, subject, sent)
  if (!is.null(restored$report)) {
    report(restored$report)
  }
  if (!is.null(restored$view)) {
    restoring[[restored$view$view]](restored$view)
    # A link made with nothing pinned holds only the selections: open on
    # their view, not on an empty Report tab
    if (is.null(values$report) && !"report" %in% sent) {
      bslib::nav_select("tab", restored$view$view, session = session)
    }
  }
  said <- link_restore_message(restored)
  if (!is.null(said)) {
    refused <- length(restored$refused) > 0L
    if (refused) {
      base::message("A link was refused: ", paste(names(restored$refused), collapse = ", "))
    }
    warn <- refused || restored$left_out > 0L || restored$view_left_out
    shiny::showNotification(said, type = if (warn) "warning" else "message", session = session)
    announce(session, said)
  }
  invisible(restored)
}

#' An item's subject as the option its view's search would offer
#'
#' @param item A report item, whose subject the database has given
#'   ([link_restore()]).
#' @return A list as [search_options()] gives each option.
#' @noRd
search_option <- function(item) {
  params <- item$params
  code <- if (is.na(params$code)) "" else params$code
  if (item$view == "practice") {
    return(list(
      value = paste0("practice:", params$id), label = params$label, meta = code,
      level = "practice", id = params$id, code = params$code
    ))
  }
  kind <- if (params$level == "chemical") "Chemical substance" else "Presentation"
  list(
    value = paste0(params$level, ":", params$id), label = params$label,
    meta = paste(kind, "\u00b7", code), level = params$level, id = params$id, code = params$code
  )
}

#' What a view puts back from a link
#'
#' The item's pick goes to the view's search as soon as it comes. Its months
#' and its measure wait until their controls are drawn with choices that hold
#' them, which for a presentation's quantity is after the pick, and are then
#' dropped, so that the user's own changes rule after that. Until the controls
#' are drawn, as on a tab not yet shown, the view's months and measure are the
#' link's, so that what it fetches meanwhile is what it will show.
#'
#' @param restore The view's `reactiveVal()` of an item to put back, or `NULL`.
#' @return A list: `pick`, a reactive of the search option to select;
#'   `months(from, to, choices)`, the months to draw the controls with, as
#'   `list(from, to)`; `measure(selected, choices)`, the measure to draw its
#'   control with; `view_months(from, to, window)` and
#'   `view_measure(measure, measures)`, the view's months and measure, as
#'   [chosen_months()] and [chosen_measure()] give them once the controls are
#'   drawn.
#' @noRd
view_restorer <- function(restore) {
  pick <- shiny::reactiveVal(NULL)
  held <- shiny::reactiveVal(NULL)
  pending <- new.env(parent = emptyenv())
  if (!is.null(restore)) {
    # Before the view's outputs, so that their first drawing has it
    shiny::observeEvent(restore(), {
      item <- restore()
      pending$months <- as.character(item$params$months)
      pending$measure <- item$params$measure
      held(list(months = as.integer(item$params$months), measure = item$params$measure))
      pick(search_option(item))
    }, priority = 10)
  }
  list(
    pick = pick,
    months = function(from, to, choices) {
      months <- pending$months
      if (!is.null(months) && all(months %in% choices)) {
        pending$months <- NULL
        return(list(from = months[[1]], to = months[[2]]))
      }
      list(from = from, to = to)
    },
    measure = function(selected, choices) {
      measure <- pending$measure
      if (!is.null(measure) && measure %in% choices) {
        pending$measure <- NULL
        return(measure)
      }
      selected
    },
    view_months = function(from, to, window) {
      kept <- held()
      if (is.null(from) && is.null(to) && !is.null(kept) &&
            all(kept$months %in% months_of_window(window))) {
        return(kept$months)
      }
      chosen_months(from, to, window)
    },
    view_measure = function(measure, measures) {
      kept <- held()
      if (is.null(measure) && !is.null(kept) && kept$measure %in% measures) {
        return(kept$measure)
      }
      chosen_measure(measure, measures)
    }
  )
}

#' The link's wiring: what a bookmark keeps, and what opening one puts back
#'
#' @param input The app's input.
#' @param session The app's session.
#' @param report The session's report, a `reactiveVal()`.
#' @param views The views' `current_view()` reactives, by name.
#' @param restoring The views' `reactiveVal()`s of an item to put back, by
#'   name.
#' @param window A reactive: the data window, or `NULL` while it cannot be
#'   fetched.
#' @param subject A function of a kind and a code, giving the subject as
#'   [fetch_subject()] does.
#' @return Nothing.
#' @noRd
report_link <- function(input, session, report, views, restoring, window, subject) {
  # The view last shown, and the selections a link put back, kept until a
  # view is shown
  last <- shiny::reactiveVal(NULL)
  carried <- shiny::reactiveVal(NULL)
  shiny::observeEvent(input$tab, {
    if (isTRUE(input$tab %in% names(views))) {
      last(input$tab)
      carried(NULL)
    }
  })
  shiny::onBookmark(function(state) {
    shiny::isolate({
      view <- last()
      current <- if (!is.null(view)) views[[view]]()
      link_bookmark(state, report(), link_view(view, current, carried()))
    })
  })
  shiny::onRestore(function(state) {
    values <- state$values
    sent <- link_sent(shiny::isolate(session$clientData$url_search))
    when_window(window, function(window) {
      restored <- link_open(values, window, subject, sent, report, restoring, session)
      if (!is.null(restored$view)) {
        carried(restored$view)
      }
    })
  })
  # The URL to the browser, which copies it (report.js), instead of Shiny's
  # dialog
  shiny::onBookmarked(function(url) session$sendCustomMessage("prexp-copy-link", url))
  invisible(NULL)
}

#' Runs `open` with the data window, once there is one
#'
#' While the window cannot be fetched, window() tries again: a link waits for
#' it, so that its months are clamped to it, and is put back before the views'
#' controls are drawn with it (a priority above theirs).
#'
#' @param window A reactive: the data window, or `NULL`.
#' @param open A function of the window.
#' @return Nothing.
#' @noRd
when_window <- function(window, open) {
  now <- shiny::isolate(window())
  if (!is.null(now)) {
    open(now)
  } else {
    shiny::observeEvent(window(), open(window()), once = TRUE, priority = 20)
  }
  invisible(NULL)
}

# What opening a link says: that a part of it could not be read, or what was
# opened, how many of its items had their months moved into the data window,
# and what was left out because the data does not hold its drug or practice
link_restore_message <- function(restored) {
  if ("unread" %in% restored$refused) {
    return("The link could not be read whole: it may have been cut short.")
  }
  if ("unfetched" %in% restored$refused) {
    return("The link could not be opened whole: the data could not be fetched. Open it again.")
  }
  said <- character()
  if (!is.null(restored$report)) {
    n <- length(restored$report$items)
    moved <- sum(vapply(restored$report$items, function(item) isTRUE(item$clamped), TRUE))
    said <- paste0(
      "Opened the report from the link: ", n, if (n == 1L) " item" else " items",
      if (moved > 0L) paste0(", ", moved, " of them with months moved into the data window"),
      "."
    )
  }
  left <- restored$left_out
  if (left > 0L) {
    said <- c(said, if (left == 1L) {
      "1 item was left out: the data does not hold its drug or practice."
    } else {
      paste0(left, " items were left out: the data does not hold their drugs or practices.")
    })
  }
  if (isTRUE(restored$view_left_out)) {
    said <- c(said, "The view's selections were left out: the data does not hold their subject.")
  }
  if (length(said) == 0L) NULL else paste(said, collapse = " ")
}
