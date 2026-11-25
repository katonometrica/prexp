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
      bslib::card_body(shiny::uiOutput(ns("body")))
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
#' @return A reactive `current_view()`: `NULL` until a drug's series is shown,
#'   then a list with `view` (`"drug"`), `params` (`level`, `id`, `label`,
#'   `months`, `measure`) and `data` (the series shown).
#' @noRd
mod_drug_server <- function(id, fetches, window, report = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    picked <- mod_search_server("search", fetches$search_drugs, "drug")

    output$months_ui <- shiny::renderUI({
      months_controls(ns, window(), shiny::isolate(input$from), shiny::isolate(input$to))
    })
    measures <- shiny::reactive({
      pick <- picked()
      measures_for_level(if (is.null(pick)) "chemical" else pick$level)
    })
    output$measure_ui <- shiny::renderUI({
      measure_control(ns, measures(), shiny::isolate(input$measure))
    })
    months <- shiny::reactive(chosen_months(input$from, input$to, window()))
    measure <- changes_only(shiny::reactive(chosen_measure(input$measure, measures())))
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

    output$body <- shiny::renderUI({
      pick <- picked()
      if (is.null(pick)) {
        return(view_message("Search for a chemical substance or a presentation."))
      }
      if (is.null(months())) {
        return(no_window_message(window()))
      }
      rows <- series()
      if (inherits(rows, "error")) {
        return(view_message("The data could not be fetched.", retry = ns("retry")))
      }
      if (nrow(rows) == 0L || all(is.na(rows$value))) {
        return(view_message(no_rows_text(pick, measure(), months())))
      }
      shiny::tagList(
        ggiraph::girafeOutput(ns("chart"), height = paste0(chart_height, "px")),
        if (identical(pick$level, "chemical")) {
          listed <- presentations()
          shiny::tagList(
            shiny::h3(class = "h6 mt-3", "Presentations"),
            if (inherits(listed, "error")) {
              view_message("The presentations could not be fetched.", retry = ns("retry"))
            } else {
              reactable::reactableOutput(ns("presentations"))
            }
          )
        }
      )
    })

    output$chart <- ggiraph::renderGirafe({
      rows <- series()
      shiny::req(!inherits(rows, "error"), nrow(rows) > 0L, !all(is.na(rows$value)))
      width <- output_width(session, "chart")
      render_girafe(
        chart_series(rows, months(), width = width),
        width = width, height = chart_height, title = picked()$label
      )
    })

    output$presentations <- reactable::renderReactable({
      rows <- presentations()
      shiny::req(!inherits(rows, "error"))
      presentations_table(rows)
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
    report_pin(input, session, current, report)
    current
  })
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
