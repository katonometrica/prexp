# The Drug view (spec section 5.3; P4-04): a drug search, the month range and
# a measure; a chemical substance's or presentation's national monthly series,
# and for a chemical substance its presentations, brand or generic.

#' The Drug view
#'
#' @param id The module's id.
#' @return Shiny UI.
#' @noRd
mod_drug_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_columns(
    col_widths = c(4, 8),
    bslib::card(
      bslib::card_body(
        mod_search_ui(ns("search"), "drug"),
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

#' The Drug view's server
#'
#' @param id The module's id.
#' @param fetches The app's fetch functions, as [app_fetches()] returns them.
#' @param window A reactive: the data window, from `fetches$window()`.
#' @param report The session's report, a `reactiveVal()` that its "Add to
#'   report" button adds to ([report_pin()]), or `NULL` for none.
#' @param restore A `reactiveVal()` of an item to put back from a link
#'   ([view_restorer()]), or `NULL`.
#' @return A reactive `current_view()`: `NULL` until a drug's series is shown,
#'   then a list with `view` (`"drug"`), `params` (`level`, `id`, `label`,
#'   `months`, `measure`) and `data` (the series shown).
#' @noRd
mod_drug_server <- function(id, fetches, window, report = NULL, restore = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    restorer <- view_restorer(restore)
    picked <- mod_search_server("search", fetches$search_drugs, "drug", restorer$pick)

    output$months_ui <- shiny::renderUI({
      chosen <- restorer$months(
        shiny::isolate(input$from), shiny::isolate(input$to), months_of_window(window())
      )
      months_controls(ns, window(), chosen$from, chosen$to)
    })
    measures <- shiny::reactive({
      pick <- picked()
      measures_for_level(if (is.null(pick)) "chemical" else pick$level)
    })
    output$measure_ui <- shiny::renderUI({
      measure_control(ns, measures(), restorer$measure(shiny::isolate(input$measure), measures()))
    })
    # The months and the measure, told only when they change, before anything
    # that reads them (priority 100): a control's first value, the same as
    # the view already shows, then draws nothing again, and a measure the new
    # level does not allow is never fetched
    months <- changes_only(
      shiny::reactive(restorer$view_months(input$from, input$to, window())),
      priority = 110
    )
    measure <- changes_only(
      shiny::reactive(restorer$view_measure(input$measure, measures())),
      priority = 110
    )
    retries <- retry_clicks(input)

    series <- shiny::reactive({
      pick <- picked()
      shiny::req(pick, months())
      retries()
      try_fetch(fetches$drug_series(pick$level, pick$id, months(), measure()))
    })
    presentations <- shiny::reactive({
      pick <- picked()
      shiny::req(pick, identical(pick$level, "chemical"), months())
      retries()
      try_fetch(fetches$drug_presentations(pick$id, months()))
    })

    output$title <- shiny::renderText({
      pick <- picked()
      if (is.null(pick)) {
        return("Drug")
      }
      if (is.null(months())) {
        return(pick$label)
      }
      paste0(pick$label, ", ", format_month_range(months()[1], months()[2]))
    })

    # What the body shows, told only when that changes: a message, or the
    # results' frame, whose chart and table then change in place
    frame <- changes_only(shiny::reactive({
      pick <- picked()
      if (is.null(pick)) {
        return(list(kind = "prompt"))
      }
      if (is.null(months())) {
        return(list(kind = "no_window", fetched = !is.null(window())))
      }
      rows <- series()
      if (inherits(rows, "error")) {
        return(list(kind = "error"))
      }
      if (nrow(rows) == 0L || all(is.na(rows$value))) {
        return(list(kind = "empty", text = no_rows_text(pick, measure(), months())))
      }
      chemical <- identical(pick$level, "chemical")
      list(
        kind = "results", chemical = chemical,
        listed = !chemical || !inherits(presentations(), "error")
      )
    }))
    output$body <- shiny::renderUI(drug_body(ns, frame()))
    retry_feedback(session, retries, function() {
      state <- frame()
      identical(state$kind, "error") || isFALSE(state$listed)
    })

    width <- chart_width(session)
    output$chart <- ggiraph::renderGirafe({
      rows <- series()
      shiny::req(!inherits(rows, "error"), nrow(rows) > 0L, !all(is.na(rows$value)))
      drawn_at <- width()
      shiny::req(drawn_at)
      label <- picked()$label
      shown <- months()
      key <- list("drug", rows, measure(), shown, drawn_at, label)
      keep_chart(fetches, key, function() {
        render_girafe(
          chart_series(rows, shown, width = drawn_at),
          width = drawn_at, height = chart_height, title = label
        )
      })
    })

    # Only when the frame shows them: not behind a message
    output$presentations <- reactable::renderReactable({
      state <- frame()
      shiny::req(identical(state$kind, "results"), isTRUE(state$chemical), isTRUE(state$listed))
      presentations_table(presentations())
    })

    current <- shiny::reactive({
      pick <- picked()
      rows <- if (is.null(pick) || is.null(months())) NULL else series()
      if (is.null(rows) || inherits(rows, "error") || nrow(rows) == 0L ||
            all(is.na(rows$value))) {
        return(NULL)
      }
      list(
        view = "drug",
        params = list(
          level = pick$level, id = pick$id, code = pick$code, label = pick$label,
          months = months(), measure = measure()
        ),
        # Every month, as the chart draws it: a month without prescribing at 0
        data = complete_months(
          rows, months(), list(measure = measure(), value = 0, practices = 0L)
        )
      )
    })
    csv_download(output, ns, current, "Download the monthly totals, as CSV")
    compute_always(output, c("csv", "chart", "presentations"))
    report_pin(input, session, current, report)
    current
  })
}

# The body for what the view shows (frame() above): a message, or the
# results' frame, the chart and, for a chemical substance, its presentations
drug_body <- function(ns, state) {
  switch(state$kind,
    prompt = view_message("Search for a chemical substance or a presentation."),
    no_window = no_window_message(state$fetched),
    error = view_message("The data could not be fetched.", retry = ns("retry")),
    empty = view_message(state$text),
    results = shiny::tagList(
      ggiraph::girafeOutput(ns("chart"), height = paste0(chart_height, "px")),
      if (state$chemical) {
        shiny::tagList(
          shiny::h3(class = "h6 mt-3", "Presentations"),
          if (state$listed) {
            reactable::reactableOutput(ns("presentations"))
          } else {
            view_message("The presentations could not be fetched.", retry = ns("retry"))
          }
        )
      }
    )
  )
}

# Why a drug has no series to show
no_rows_text <- function(pick, measure, months) {
  range <- format_month_range(months[1], months[2])
  if (measure == "adq_usage") {
    paste0("No ADQ is defined for ", pick$label, ", or it was not prescribed in ", range, ".")
  } else {
    paste0(pick$label, " was not prescribed in ", range, ".")
  }
}

# A chemical substance's presentations, most items first. A chemical can have
# thousands (2003, dressings, has 2,068), so quantity and ADQ usage are written
# once for each whole column, into hidden columns whose text measure_column()
# shows in their cells
presentations_table <- function(rows) {
  data <- data.frame(
    presentation = rows$bnf_description, code = rows$bnf_code,
    kind = brand_or_generic(rows$is_generic),
    items = rows$items, total_quantity = rows$total_quantity, adq_usage = rows$adq_usage,
    nic = rows$nic, actual_cost = rows$actual_cost,
    quantity_text = format_measure(rows$total_quantity, "total_quantity"),
    adq_text = format_measure(rows$adq_usage, "adq_usage")
  )
  reactable::reactable(
    data,
    columns = list(
      presentation = reactable::colDef(name = "Presentation", minWidth = 220),
      code = reactable::colDef(name = "BNF code", minWidth = 160, style = nowrap),
      kind = reactable::colDef(name = "Brand or generic", minWidth = 90),
      items = count_column("Items"),
      total_quantity = measure_column("Quantity", "total_quantity", label = "quantity_text"),
      adq_usage = measure_column("ADQ usage", "adq_usage", label = "adq_text"),
      nic = pounds_column("Net ingredient cost"),
      actual_cost = pounds_column("Actual cost"),
      quantity_text = reactable::colDef(show = FALSE),
      adq_text = reactable::colDef(show = FALSE)
    ),
    defaultPageSize = 10, compact = TRUE, striped = TRUE, highlight = TRUE,
    defaultSorted = list(items = "desc")
  )
}
