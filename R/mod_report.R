# The report panel and the views' pin buttons (P5-02; spec sections 5.3 and
# 5.5). The report lives in one reactiveVal of the session, made in
# app_server(), which the views' "Add to report" buttons and the Report tab
# share. Every change goes through the report's pure functions
# (fct_report_spec.R). The panel's buttons and notes carry their item's id
# (report.js), so one input of the module, `act` or `note`, says what changed
# and no observer is made per item. What a change did is said in the page's
# status region (announce()) as well as shown: screen readers do not read
# Shiny's toasts.

#' The Report tab's user interface
#'
#' @param id The module's id.
#' @return Shiny UI.
#' @noRd
mod_report_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::card(
    bslib::card_header(
      class = "d-flex justify-content-between align-items-center gap-2",
      shiny::span("Pinned views"),
      shiny::div(
        class = "d-flex align-items-center gap-2",
        shiny::uiOutput(ns("count"), inline = TRUE),
        shiny::actionButton(ns("copy"), "Copy link", class = "btn-outline-primary btn-sm")
      )
    ),
    bslib::card_body(
      # The link, once made: report.js copies it and shows it here, ready to
      # copy by hand where the browser would not copy it
      shiny::div(
        class = "prexp-link-box", hidden = NA,
        shiny::tags$label(
          class = "form-label small w-100",
          shiny::span(`data-report-link-label` = NA, "The report's link"),
          shiny::tags$input(
            type = "text", class = "form-control form-control-sm mt-1", readonly = NA,
            `data-report-link` = NA
          )
        )
      ),
      # Not a live region, as Shiny makes an output: drawn again after a
      # move, the whole list would be read out. The status region says what
      # changed.
      shiny::uiOutput(ns("items"), `aria-live` = "off")
    ),
    report_export_ui(ns)
  )
}

#' The Report tab's server
#'
#' @param id The module's id.
#' @param report The session's report: a `reactiveVal()` holding a report
#'   ([new_report()]).
#' @param run The exports' runner, as [export_runner()] makes it, or `NULL`
#'   for none, which leaves Prepare off.
#' @return Nothing useful: it changes `report`.
#' @noRd
mod_report_server <- function(id, report, run = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    limit <- report_limits()$items
    # The number of items, drawn again only when it changes: the badge's
    # output is a live region, which a note saved must not make speak again
    count <- changes_only(shiny::reactive(length(report()$items)))
    output$count <- shiny::renderUI({
      n <- count()
      shiny::tagList(
        shiny::span(
          class = "badge text-bg-secondary", `aria-hidden` = "true", paste0(n, "/", limit)
        ),
        shiny::span(class = "visually-hidden", paste(n, "of at most", limit, "items"))
      )
    })
    # The list is drawn again when its items change, not when a note does:
    # drawing it again as a note is typed would lose the text box's focus
    shape <- changes_only(shiny::reactive(lapply(report()$items, function(item) {
      item[c("id", "view", "params", "clamped")]
    })))
    output$items <- shiny::renderUI({
      shape()
      items <- shiny::isolate(report()$items)
      if (length(items) == 0L) {
        return(report_empty())
      }
      shiny::tagList(lapply(seq_along(items), function(i) {
        report_item_ui(ns, items[[i]], first = i == 1L, last = i == length(items))
      }))
    })
    # The link: the bookmark, whose URL the app hands to report.js, as
    # report_link() sets up. Only on a click: a link's `_inputs_` can give
    # the button a value, which the page sends as it opens.
    shiny::observeEvent(input$copy, session$doBookmark(), ignoreInit = TRUE)
    # A move or a removal, as report.js sends them: anything else, or one for
    # an item no longer there, does nothing
    shiny::observeEvent(input$act, {
      act <- input$act
      kind <- if (is.list(act) && is.character(act$act) && length(act$act) == 1L) act$act else ""
      spec <- report()
      changed <- tryCatch(
        switch(kind,
          up = report_move(spec, act$id, -1L),
          down = report_move(spec, act$id, 1L),
          remove = report_remove(spec, act$id)
        ),
        prexp_invalid_argument = function(e) NULL,
        # A move that would make the report's link too long, as the order of
        # its items changes how well it compresses
        prexp_report_limit = function(e) {
          shiny::showNotification(conditionMessage(e), type = "warning")
          announce(session, conditionMessage(e))
          NULL
        }
      )
      if (is.null(changed) || identical(changed, spec)) {
        return()
      }
      title <- report_item_title(spec$items[[item_at(spec, act$id)]])
      report(changed)
      n <- length(changed$items)
      announce(session, switch(kind,
        remove = paste0("Removed: ", title, ". ", n, if (n == 1L) " item" else " items", " left."),
        paste0(
          if (kind == "up") "Moved up: " else "Moved down: ", title, ", now ",
          match(act$id, item_ids(changed)), " of ", n, "."
        )
      ))
    })
    # A note, cleaned of what a note cannot hold (clean_note()): one over the
    # limit is refused, with a toast and, once until a note within it is
    # saved, the status region
    over <- new.env(parent = emptyenv())
    shiny::observeEvent(input$note, {
      note <- input$note
      if (!is.list(note)) {
        return()
      }
      key <- paste(note$id)
      changed <- tryCatch(
        report_set_note(report(), note$id, clean_note(note$note)),
        prexp_report_limit = function(e) {
          shiny::showNotification(conditionMessage(e), type = "warning", id = ns("note-limit"))
          if (is.null(over[[key]])) {
            over[[key]] <- TRUE
            announce(session, conditionMessage(e))
          }
          NULL
        },
        prexp_invalid_argument = function(e) NULL
      )
      if (!is.null(changed)) {
        if (!is.null(over[[key]])) {
          rm(list = key, envir = over)
        }
        report(changed)
      }
    })
    report_export(input, output, session, report, run)
  })
}

# The panel with nothing pinned: focusable from script, for the focus after
# the last item is removed (report.js)
report_empty <- function() {
  shiny::p(
    class = "text-body-secondary mb-0", tabindex = "-1",
    "Nothing is pinned yet. \"Add to report\" on the Drug, Practice or Region view pins",
    "what it shows, with its months and measure."
  )
}

# One item of the panel: its title and summary, whether its months were
# clamped, the buttons to move and remove it, and its note with a counter
report_item_ui <- function(ns, item, first, last) {
  title <- report_item_title(item)
  limit <- report_limits()$note
  counter <- ns(paste0("note-count-", item$id))
  button <- function(act, label, text, disabled = FALSE) {
    shiny::tags$button(
      type = "button", class = "btn btn-outline-secondary",
      `data-report-input` = ns("act"), `data-report-id` = item$id, `data-report-act` = act,
      `aria-label` = paste0(label, ": ", title), title = label,
      disabled = if (disabled) NA,
      text
    )
  }
  shiny::tags$section(
    class = "prexp-report-item", `aria-label` = title,
    shiny::div(
      class = "d-flex justify-content-between align-items-start gap-2",
      shiny::div(
        # Focusable from script: report.js puts the focus here when the
        # button pressed is gone, after a removal
        shiny::h2(class = "h6 mb-1", tabindex = "-1", title),
        shiny::p(class = "small text-body-secondary mb-1", report_item_summary(item)),
        if (isTRUE(item$clamped)) {
          shiny::span(
            class = "badge text-bg-warning", "Months clamped",
            shiny::span(
              class = "visually-hidden",
              ": the data window no longer holds all of its months, so they were moved into it"
            )
          )
        }
      ),
      shiny::div(
        class = "btn-group btn-group-sm flex-shrink-0", role = "group",
        `aria-label` = paste0("Move or remove: ", title),
        button("up", "Move up", "\u2191", disabled = first),
        button("down", "Move down", "\u2193", disabled = last),
        button("remove", "Remove", "Remove")
      )
    ),
    shiny::tags$label(
      class = "form-label small mt-2 mb-0 w-100", "Note",
      shiny::span(class = "visually-hidden", paste0(" on ", title)),
      shiny::tags$textarea(
        class = "form-control mt-1", rows = 3,
        `data-report-input` = ns("note"), `data-report-id` = item$id,
        `data-report-counter` = counter, `data-report-limit` = limit,
        `aria-describedby` = counter,
        # The HTML parser drops a line break right after <textarea>: this
        # one, not one the note starts with
        paste0("\n", item$note)
      )
    ),
    # In one piece, as htmltools would put each part on a line of its own and
    # the page would show "19 /500"; it holds two numbers, nothing to escape
    shiny::div(
      id = counter, class = "form-text text-end mt-1",
      shiny::HTML(sprintf(
        paste0(
          "<span class=\"prexp-note-count\">%d</span>/%d",
          "<span class=\"visually-hidden\"> characters</span>"
        ),
        nchar(item$note), limit
      ))
    )
  )
}

#' An item's title: its subject, measure and months
#'
#' @param item A report item.
#' @return One string, as in "Atorvastatin \u00b7 items \u00b7 Oct 2025 to Sep 2026", or
#'   "Atorvastatin by region \u00b7 items \u00b7 Oct 2025 to Sep 2026" for a region
#'   item, as its view's own title says.
#' @noRd
report_item_title <- function(item) {
  params <- item$params
  info <- measure_info()
  measure <- info$label[match(params$measure, info$measure)]
  # "Items" in a title is "items"; "ADQ usage" keeps its capitals
  if (!grepl("^[A-Z]{2}", measure)) {
    measure <- paste0(tolower(substr(measure, 1L, 1L)), substring(measure, 2L))
  }
  span <- format_month_span(params$months)
  # Else a drug's region item would have the title, and its buttons the names,
  # of its Drug view item
  subject <- if (identical(item$view, "region")) paste(params$label, "by region") else params$label
  paste(subject, measure, span, sep = " \u00b7 ")
}

#' An item's summary: its view, the kind of subject and its code
#'
#' @param item A report item.
#' @return One string, as in "Drug view \u00b7 chemical substance 0212000B0".
#' @noRd
report_item_summary <- function(item) {
  params <- item$params
  view <- switch(item$view, drug = "Drug view", practice = "Practice view", region = "Region view")
  subject <- switch(item$view,
    practice = "practice",
    if (identical(params$level, "presentation")) "presentation" else "chemical substance"
  )
  code <- if (is.na(params$code)) subject else paste(subject, params$code)
  paste(view, code, sep = " \u00b7 ")
}

#' A view's "Add to report" button
#'
#' The button is in the view's header ([view_header()]), off until the view
#' shows data and off again while the report is full. A click pins the
#' current view with its parameters ([report_add()]), its label without
#' control characters ([pin_label()]), and a toast and the status region say
#' so, or say why it could not.
#'
#' @param input The view's input.
#' @param session The view's session.
#' @param current The view's `current_view()` reactive.
#' @param report The session's report, a `reactiveVal()`, or `NULL` for a view
#'   with no report (its button stays off).
#' @return Nothing.
#' @noRd
report_pin <- function(input, session, current, report) {
  if (is.null(report)) {
    return(invisible(NULL))
  }
  open <- changes_only(shiny::reactive({
    !is.null(current()) && length(report()$items) < report_limits()$items
  }))
  shiny::observe(shiny::updateActionButton(session, "pin", disabled = !open()))
  shiny::observeEvent(input$pin, {
    view <- current()
    if (is.null(view)) {
      return()
    }
    params <- view$params
    params$label <- pin_label(params$label)
    added <- tryCatch(
      report_add(report(), view$view, params),
      prexp_report_limit = function(e) conditionMessage(e),
      # Parameters refused are the app's fault, not the user's: the log gets
      # the error's class, as try_fetch() does, and the toast plain words
      prexp_invalid_argument = function(e) {
        base::message("A pin was refused: ", class(e)[[1L]])
        "This view could not be added to the report."
      }
    )
    if (is.character(added)) {
      shiny::showNotification(added, type = "warning")
      announce(session, added)
      return()
    }
    report(added)
    n <- length(added$items)
    text <- paste0(
      "Added to the report: ", report_item_title(added$items[[n]]), ". It holds ", n, " of ",
      report_limits()$items, " items."
    )
    shiny::showNotification(text, type = "message")
    announce(session, text)
    # Only on a click, as Copy link
  }, ignoreInit = TRUE)
  invisible(NULL)
}

# A name from the data as an item's label, which holds no character a label
# cannot (validate_label()): one presentation's name, as NHSBSA publishes it,
# ends in a tab. Each run of them becomes a space, and spaces at either end
# go.
pin_label <- function(label) {
  if (!is.character(label) || length(label) != 1L || is.na(label) || !validUTF8(label)) {
    return(label)
  }
  points <- utf8ToInt(enc2utf8(label))
  unheld <- unheld_text(points, line_breaks = FALSE)
  # The first of each run kept, as a space
  kept <- !unheld | c(TRUE, !unheld[-length(unheld)])
  points[unheld] <- 32L
  trimws(intToUtf8(points[kept]))
}

# A note as the panel saves it: a vertical tab or a form feed, which a word
# processor pastes for a line or page break, becomes a line break, and any
# other character a note cannot hold (validate_note()) goes. Anything that
# is not one string of UTF-8 text is left for validate_note() to refuse.
clean_note <- function(note) {
  if (!is.character(note) || length(note) != 1L || is.na(note) || !validUTF8(note)) {
    return(note)
  }
  points <- utf8ToInt(enc2utf8(note))
  points[points %in% c(11L, 12L)] <- 10L
  intToUtf8(points[!unheld_text(points, line_breaks = TRUE)])
}

# A status message for screen readers, said by the page's status region
# (app_ui(), report.js): Shiny's toasts have no role, so are not read out
announce <- function(session, text) {
  session$sendCustomMessage("prexp-status", text)
}

# The export (spec section 5.5; P5-05): a format, "Prepare", which runs the
# export as a background task (export_runner()), and, once it is ready, a
# download of the file. A file prepared for a report that has changed since,
# or in another format, is not offered: Prepare makes a new one.

# The export's controls, under the panel
report_export_ui <- function(ns) {
  formats <- export_formats()
  bslib::card_footer(
    shiny::div(
      class = "d-flex flex-wrap align-items-center gap-3",
      format_radio(
        ns("format"), "Export as",
        structure(formats$format, names = paste0(formats$label, " (.", formats$format, ")"))
      ),
      # Neither is a live region, as Shiny makes an output and a button it
      # updates: the status region says what Prepare did
      shiny::actionButton(
        ns("prepare"), "Prepare", class = "btn-primary btn-sm", disabled = TRUE,
        `aria-live` = "off"
      ),
      shiny::uiOutput(ns("download_ui"), inline = TRUE, `aria-live` = "off")
    ),
    shiny::p(class = "small text-muted mb-0", shiny::textOutput(ns("export_status"), inline = TRUE))
  )
}

# Inline radio buttons, the first checked, in shiny::radioButtons()' markup.
# radioButtons() itself takes its value from a link's `_inputs_` and stops
# when that has more than one element, so that the page would not open; a
# link keeps no format, and the server checks the one sent.
format_radio <- function(id, label, choices) {
  label_id <- paste0(id, "-label")
  shiny::div(
    id = id,
    class = "form-group shiny-input-radiogroup shiny-input-container shiny-input-container-inline",
    role = "radiogroup", `aria-labelledby` = label_id,
    shiny::tags$label(label, class = "control-label", id = label_id, `for` = id),
    shiny::div(class = "shiny-options-group", lapply(seq_along(choices), function(i) {
      shiny::tags$label(
        class = "radio-inline",
        shiny::tags$input(
          type = "radio", name = id, value = choices[[i]], checked = if (i == 1L) "checked"
        ),
        shiny::span(names(choices)[[i]])
      )
    }))
  )
}

# The export's server: what Prepare asked for (`job`), what was prepared
# (`ready`), and whether the last try failed
report_export <- function(input, output, session, report, run) {
  ns <- session$ns
  formats <- export_formats()
  # Set when the session ends: a file an export finishes after that is no
  # one's, so it goes as it arrives
  ended <- new.env(parent = emptyenv())
  task <- shiny::ExtendedTask$new(function(format, spec, path, exported) {
    promises::finally(run(format, spec, path, exported), function() {
      if (isTRUE(ended$yes)) {
        unlink(path)
      }
    })
  })
  job <- shiny::reactiveVal(NULL)
  ready <- shiny::reactiveVal(NULL)
  failed <- shiny::reactiveVal(FALSE)
  running <- shiny::reactive(identical(task$status(), "running"))
  empty <- changes_only(shiny::reactive(length(report()$items) == 0L))
  chosen <- shiny::reactive({
    if (isTRUE(input$format %in% formats$format)) input$format else formats$format[[1]]
  })
  label <- function(format) formats$label[match(format, formats$format)]
  # The file prepared, while it is the report's and the format's
  current <- shiny::reactive({
    prepared <- ready()
    if (!is.null(prepared) && identical(prepared$spec, report()) &&
          identical(prepared$format, chosen())) {
      prepared
    }
  })
  shiny::observe({
    busy <- running()
    shiny::updateActionButton(
      session, "prepare", label = if (busy) "Preparing\u2026" else "Prepare",
      disabled = is.null(run) || empty() || busy
    )
  })
  # Only on a click, as Copy link: a link's `_inputs_` can give the button a
  # value, which the page sends as it opens
  shiny::observeEvent(input$prepare, {
    spec <- report()
    if (is.null(run) || length(spec$items) == 0L || running()) {
      return()
    }
    asked <- list(
      format = chosen(), spec = spec, exported = Sys.time(),
      path = tempfile("report-", fileext = paste0(".", chosen()))
    )
    job(asked)
    failed(FALSE)
    n <- length(spec$items)
    announce(session, paste0(
      "Preparing the ", label(asked$format), " file of the report's ", n,
      if (n == 1L) " item." else " items."
    ))
    task$invoke(asked$format, asked$spec, asked$path, asked$exported)
  }, ignoreInit = TRUE)
  shiny::observeEvent(task$status(), {
    asked <- job()
    status <- task$status()
    if (identical(status, "success")) {
      before <- ready()
      if (!is.null(before)) {
        unlink(before$path)
      }
      ready(asked)
      # The report can change while its file is prepared: the panel and the
      # views' pins stay on
      same_report <- identical(asked$spec, report())
      same_format <- identical(asked$format, chosen())
      announce(session, paste0(
        "The ", label(asked$format), " file ",
        if (same_report && same_format) {
          "is ready: the Download button is next to Prepare."
        } else if (same_report) {
          paste0("is ready: choose ", label(asked$format), " to download it.")
        } else {
          "was prepared, but the report has changed since: prepare it again to download it."
        }
      ))
    } else if (identical(status, "error")) {
      error <- tryCatch(task$result(), error = function(e) e)
      base::message("An export failed: ", conditionMessage(error))
      unlink(asked$path)
      failed(TRUE)
      said <- paste(
        "The report could not be exported. Try again; if it fails again, the app's log has",
        "the cause."
      )
      shiny::showNotification(said, type = "error")
      announce(session, said)
    }
  })
  output$export_status <- shiny::renderText({
    if (running()) {
      return(paste0("Preparing the ", label(job()$format), " file\u2026"))
    }
    if (failed()) {
      return("The report could not be exported. Try again.")
    }
    prepared <- current()
    if (!is.null(prepared)) {
      return(paste0(
        "Ready: prepared at ", format(prepared$exported, "%H:%M %Z", tz = "Europe/London"), "."
      ))
    }
    before <- ready()
    if (!is.null(before) && identical(before$spec, report())) {
      # Only the format chosen differs: the file is still the report's
      return(paste0(
        "The ", label(before$format), " file is prepared: choose ", label(before$format),
        " to download it, or Prepare to make the ", label(chosen()), " file."
      ))
    }
    if (!is.null(before)) {
      return("The report has changed since it was prepared: prepare it again to download it.")
    }
    if (empty()) "Pin a view to export the report." else ""
  })
  output$download_ui <- shiny::renderUI({
    prepared <- current()
    if (is.null(prepared)) {
      return(NULL)
    }
    shiny::downloadButton(
      ns("download"), paste("Download", label(prepared$format)),
      class = "btn-outline-primary btn-sm"
    )
  })
  output$download <- shiny::downloadHandler(
    filename = function() {
      prepared <- shiny::isolate(ready())
      export_filename(prepared$format, prepared$exported)
    },
    content = function(file) {
      prepared <- shiny::isolate(ready())
      if (is.null(prepared) || !file.copy(prepared$path, file, overwrite = TRUE)) {
        stop("The prepared file is no longer there: prepare it again.", call. = FALSE)
      }
    }
  )
  # The files go with the session
  session$onSessionEnded(function() {
    ended$yes <- TRUE
    unlink(c(shiny::isolate(ready())$path, shiny::isolate(job())$path))
  })
  invisible(NULL)
}

# A prepared file's name: the app's, and the day it was made in the UK
export_filename <- function(format, exported) {
  day <- format(as.POSIXct(exported), "%Y-%m-%d", tz = "Europe/London")
  paste0("prescription-explorer-report-", day, ".", format)
}
