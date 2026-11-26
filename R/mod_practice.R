# The Practice view (spec section 5.3; P4-05): a practice search, the month
# range and a measure; the practice's profile, its monthly totals of the
# measure, and its top drugs ranked by it, a page at a time.

#' The Practice view
#'
#' @param id The module's id.
#' @return Shiny UI.
#' @noRd
mod_practice_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_columns(
    col_widths = c(4, 8),
    bslib::card(
      bslib::card_body(
        mod_search_ui(ns("search"), "practice"),
        shiny::uiOutput(ns("months_ui")),
        shiny::uiOutput(ns("measure_ui"))
      )
    ),
    bslib::card(
      view_header(ns),
      view_body(ns)
    )
  )
}

#' The Practice view's server
#'
#' The top drugs come a page at a time by keyset (see
#' [fetch_practice_top_drugs()]): each page after the first starts after the
#' last drug of the page before it, so the view keeps those drugs, one per page
#' turned, to go back and forth. They hold for one practice, months and
#' ranking: a change to any of them starts again at the first page. A page is
#' fetched with one row more than it shows, which says whether there is a next
#' page.
#'
#' @param id The module's id.
#' @param fetches The app's fetch functions, as [app_fetches()] returns them.
#' @param window A reactive: the data window, from `fetches$window()`.
#' @param report The session's report, a `reactiveVal()` that its "Add to
#'   report" button adds to ([report_pin()]), or `NULL` for none.
#' @param restore A `reactiveVal()` of an item to put back from a link
#'   ([view_restorer()]), or `NULL`.
#' @param page_size The top drugs on a page.
#' @return A reactive `current_view()`: `NULL` until a practice's monthly
#'   totals are shown, then a list with `view` (`"practice"`), `params` (`id`,
#'   `label`, `months`, `measure`) and `data` (the monthly totals).
#' @noRd
mod_practice_server <- function(id, fetches, window, page_size = 25L, report = NULL,
                                restore = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    restorer <- view_restorer(restore)
    picked <- mod_search_server(
      "search", fetches$search_practices, "practice", restorer$pick
    )
    measures <- practice_measures()

    output$months_ui <- shiny::renderUI({
      chosen <- restorer$months(
        shiny::isolate(input$from), shiny::isolate(input$to), months_of_window(window())
      )
      months_controls(ns, window(), chosen$from, chosen$to)
    })
    output$measure_ui <- shiny::renderUI({
      measure_control(ns, measures, restorer$measure(shiny::isolate(input$measure), measures))
    })
    # Told only when they change, before their readers (priority 100): a
    # control's first value, the same as the view already shows, then draws
    # nothing again
    months <- changes_only(
      shiny::reactive(restorer$view_months(input$from, input$to, window())),
      priority = 110
    )
    measure <- changes_only(
      shiny::reactive(restorer$view_measure(input$measure, measures)),
      priority = 110
    )
    # Two Try again buttons: the practice's (profile and totals), and its top
    # drugs', each fetching only what failed
    retries <- retry_clicks(input, "retry")
    retries_top <- retry_clicks(input, "retry_top")

    profile <- shiny::reactive({
      pick <- picked()
      shiny::req(pick)
      retries()
      try_fetch(fetches$practice_profile(pick$id))
    })
    series <- shiny::reactive({
      pick <- picked()
      shiny::req(pick, months())
      retries()
      try_fetch(fetches$practice_series(pick$id, months()))
    })

    # The ranking the pages belong to, and the last drug of each page turned
    ranking <- shiny::reactive({
      pick <- picked()
      shiny::req(pick, months())
      list(id = pick$id, months = months(), by = measure())
    })
    paging <- shiny::reactiveVal(list(ranking = NULL, after = list()))
    # Another ranking starts at page one, forgetting the pages turned: back on
    # an earlier ranking, the view is on its page one too. This runs before the
    # outputs, so only page one is fetched.
    shiny::observeEvent(ranking(), {
      if (!identical(paging()$ranking, ranking())) {
        paging(list(ranking = ranking(), after = list()))
      }
    }, priority = 1)
    afters <- shiny::reactive({
      state <- paging()
      if (identical(state$ranking, ranking())) state$after else list()
    })
    top <- shiny::reactive({
      ranked <- ranking()
      after <- afters()
      retries_top()
      try_fetch(fetches$practice_top_drugs(
        ranked$id, ranked$months, ranked$by, page_size + 1L,
        if (length(after) == 0L) NULL else after[[length(after)]]
      ))
    })
    shiny::observeEvent(input$next_page, {
      rows <- top()
      if (!inherits(rows, "error") && nrow(rows) > page_size) {
        after <- c(afters(), list(rows$presentation_id[[page_size]]))
        paging(list(ranking = ranking(), after = after))
      }
    })
    shiny::observeEvent(input$previous_page, {
      after <- afters()
      if (length(after) > 0L) {
        paging(list(ranking = ranking(), after = after[-length(after)]))
      }
    })

    output$title <- shiny::renderText({
      pick <- picked()
      if (is.null(pick)) {
        return("Practice")
      }
      if (is.null(months())) {
        return(pick$label)
      }
      paste0(pick$label, ", ", format_month_range(months()[1], months()[2]))
    })

    # What the body shows, told only when that changes: a message, or the
    # practice's frame, whose profile, chart and top drugs then change in place
    frame <- changes_only(shiny::reactive({
      pick <- picked()
      if (is.null(pick)) {
        return(list(kind = "prompt"))
      }
      if (is.null(months())) {
        return(list(kind = "no_window", fetched = !is.null(window())))
      }
      found <- profile()
      rows <- series()
      if (inherits(found, "error") || inherits(rows, "error")) {
        return(list(kind = "error"))
      }
      if (nrow(found) == 0L) {
        return(list(kind = "missing", text = paste0(pick$label, " is not in the data.")))
      }
      if (nrow(rows) == 0L) {
        return(list(kind = "no_rows", text = paste0(
          pick$label, " did not prescribe in ", format_month_range(months()[1], months()[2]),
          "."
        )))
      }
      list(kind = "results")
    }))
    output$body <- shiny::renderUI(practice_body(ns, frame()))
    retry_feedback(session, retries, function() identical(frame()$kind, "error"))
    retry_feedback(session, retries_top, function() inherits(top(), "error"))

    output$profile <- shiny::renderUI({
      found <- profile()
      shiny::req(!inherits(found, "error"), nrow(found) > 0L)
      practice_profile(found)
    })

    # The chart and the top drugs only when the frame shows them: not behind
    # a message
    width <- chart_width(session)
    output$chart <- ggiraph::renderGirafe({
      shiny::req(identical(frame()$kind, "results"))
      rows <- series()
      drawn_at <- width()
      shiny::req(drawn_at)
      label <- picked()$label
      by <- measure()
      shown <- months()
      keep_chart(fetches, list("practice", rows, by, shown, drawn_at, label), function() {
        render_girafe(
          chart_series(measure_series(rows, by), shown, width = drawn_at),
          width = drawn_at, height = chart_height, title = label
        )
      })
    })

    output$top_title <- shiny::renderText({
      shiny::req(identical(frame()$kind, "results"))
      paste("Top drugs by", tolower(names(measures)[measures == measure()]))
    })

    # The page of top drugs shown: its rows, the number of its first drug, and
    # whether there are more
    page <- shiny::reactive({
      rows <- top()
      shiny::req(!inherits(rows, "error"), nrow(rows) > 0L)
      list(
        rows = utils::head(rows, page_size),
        first = length(afters()) * page_size + 1L,
        more = nrow(rows) > page_size
      )
    })

    output$top_message <- shiny::renderUI({
      shiny::req(identical(frame()$kind, "results"))
      rows <- top()
      if (inherits(rows, "error")) {
        return(view_message("The top drugs could not be fetched.", retry = ns("retry_top")))
      }
      if (nrow(rows) == 0L) {
        return(view_message("No drugs to show."))
      }
      NULL
    })

    output$top_table <- reactable::renderReactable({
      shiny::req(identical(frame()$kind, "results"))
      shown <- page()
      top_drugs_table(shown$rows, shown$first)
    })

    output$top_range <- shiny::renderText({
      shiny::req(identical(frame()$kind, "results"))
      shown <- page()
      paste0("Drugs ", shown$first, " to ", shown$first + nrow(shown$rows) - 1L)
    })
    # The paging buttons, set again whenever the frame is drawn anew (as after
    # Try again), since it draws them off
    shiny::observe({
      frame()
      rows <- top()
      shown <- if (inherits(rows, "error") || nrow(rows) == 0L) NULL else page()
      set_paging(
        session,
        previous = !is.null(shown) && shown$first > 1L,
        more = !is.null(shown) && shown$more
      )
    })

    # As the body: nothing to download unless it shows the practice's totals
    current <- shiny::reactive({
      pick <- picked()
      if (is.null(pick) || is.null(months())) {
        return(NULL)
      }
      found <- profile()
      rows <- series()
      if (inherits(found, "error") || inherits(rows, "error") || nrow(found) == 0L ||
            nrow(rows) == 0L) {
        return(NULL)
      }
      list(
        view = "practice",
        params = list(
          id = pick$id, code = pick$code, label = pick$label, months = months(),
          measure = measure()
        ),
        # Every month, as the chart draws it: a month without prescribing at 0
        data = complete_months(
          rows, months(), list(presentations = 0L, items = 0, nic = 0, actual_cost = 0)
        )
      )
    })
    csv_download(output, ns, current, "Download the monthly totals of every measure, as CSV")
    compute_always(output, c(
      "csv", "profile", "chart", "top_title", "top_message", "top_table", "top_range"
    ))
    report_pin(input, session, current, report)
    current
  })
}

# The body for what the view shows (frame() above): a message, or the
# practice's frame, its profile, chart, and top drugs with their paging
practice_body <- function(ns, state) {
  switch(state$kind,
    prompt = view_message("Search for a practice by its name, code or postcode."),
    no_window = no_window_message(state$fetched),
    error = view_message("The data could not be fetched.", retry = ns("retry")),
    missing = view_message(state$text),
    no_rows = shiny::tagList(shiny::uiOutput(ns("profile")), view_message(state$text)),
    results = shiny::tagList(
      shiny::uiOutput(ns("profile")),
      ggiraph::girafeOutput(ns("chart"), height = paste0(chart_height, "px")),
      shiny::h3(class = "h6 mt-3", shiny::textOutput(ns("top_title"), inline = TRUE)),
      # The table and the paging stay on the page and change in place from
      # page to page, so the page does not jump and Next keeps the focus; the
      # messages are drawn beside them
      shiny::uiOutput(ns("top_message")),
      reactable::reactableOutput(ns("top_table")),
      paging_controls(ns)
    )
  )
}

# The measures a practice's totals and top drugs can show, named by their
# labels: no quantity, whose units differ between presentations, and no ADQ
# usage, which the practice totals do not hold
practice_measures <- function() {
  info <- measure_info()
  keep <- c("items", "nic", "actual_cost")
  structure(keep, names = info$label[match(keep, info$measure)])
}

# A practice's monthly totals of one measure, as chart_series() takes them
measure_series <- function(rows, measure) {
  # The value first: inside tibble(), `measure` would be the new column
  value <- rows[[measure]]
  tibble::tibble(year_month = rows$year_month, measure = measure, value = value)
}

# The practice's profile: its code, address, ICB, region and the months it
# prescribed in
practice_profile <- function(profile) {
  practice <- profile[1L, ]
  address <- c(practice$address, practice$postcode)
  address <- address[!is.na(address) & nzchar(address)]
  item <- function(term, text) {
    shiny::tagList(
      shiny::tags$dt(class = "col-sm-3", term),
      shiny::tags$dd(class = "col-sm-9", text)
    )
  }
  shiny::tags$dl(
    class = "prexp-profile row mb-2",
    item("Code", practice$practice_code),
    item("Address", if (length(address) > 0L) paste(address, collapse = ", ") else "Not given"),
    item("ICB", practice$icb_name),
    item("Region", practice$region_name),
    item("Prescribing", format_month_range(practice$first_seen, practice$last_seen))
  )
}

# A page of top drugs, numbered from `first`, in the order ranked: no paging
# or sorting of its own, since the server ranks and pages
top_drugs_table <- function(rows, first = 1L) {
  data <- data.frame(
    rank = seq.int(first, length.out = nrow(rows)),
    presentation = rows$bnf_description, code = rows$bnf_code,
    kind = brand_or_generic(rows$is_generic), items = rows$items, adq_usage = rows$adq_usage,
    nic = rows$nic, actual_cost = rows$actual_cost
  )
  reactable::reactable(
    data,
    columns = list(
      rank = reactable::colDef(name = "#", width = 56, align = "right"),
      presentation = reactable::colDef(name = "Presentation", minWidth = 220),
      code = reactable::colDef(name = "BNF code", minWidth = 140),
      kind = reactable::colDef(name = "Brand or generic", minWidth = 90),
      items = count_column("Items"),
      adq_usage = measure_column("ADQ usage", "adq_usage"),
      nic = pounds_column("Net ingredient cost"),
      actual_cost = pounds_column("Actual cost")
    ),
    pagination = FALSE, sortable = FALSE, compact = TRUE, striped = TRUE, highlight = TRUE
  )
}

# Previous and Next, and which drugs the page shows. They are drawn once, and
# set_paging() turns the buttons on and off from page to page.
paging_controls <- function(ns) {
  button <- function(id, label) {
    shiny::actionButton(ns(id), label, class = "btn-outline-primary btn-sm", disabled = TRUE)
  }
  shiny::div(
    class = "prexp-paging d-flex align-items-center gap-2 mt-2",
    button("previous_page", "Previous"),
    shiny::span(class = "text-muted small", shiny::textOutput(ns("top_range"), inline = TRUE)),
    button("next_page", "Next")
  )
}

# Turns Previous and Next on or off
set_paging <- function(session, previous, more) {
  shiny::updateActionButton(session, "previous_page", disabled = !previous)
  shiny::updateActionButton(session, "next_page", disabled = !more)
}
