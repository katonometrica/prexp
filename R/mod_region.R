# The Region view (spec section 5.3; P4-06): a drug search, the month range
# and a measure; the drug's totals in each NHS region, as bars and as a table
# with each region's share of England's total.

#' The Region view
#'
#' @param id The module's id.
#' @return Shiny UI.
#' @noRd
mod_region_ui <- function(id) {
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

#' The Region view's server
#'
#' The national unidentified prescriber has no NHS region (region `"-"`): it
#' counts in England's total, and the table shows it apart from the seven
#' regions; the chart shows the regions only.
#'
#' @param id The module's id.
#' @param fetches The app's fetch functions, as [app_fetches()] returns them.
#' @param window A reactive: the data window, from `fetches$window()`.
#' @return A reactive `current_view()`: `NULL` until a drug's regions are
#'   shown, then a list with `view` (`"region"`), `params` (`level`, `id`,
#'   `label`, `months`, `measure`) and `data` (the totals by region).
#' @noRd
mod_region_server <- function(id, fetches, window) {
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

    regions <- shiny::reactive({
      pick <- picked()
      shiny::req(pick, months())
      retries()
      try_fetch(fetches$region_comparison(pick$level, pick$id, months(), measure()))
    })
    nhs_regions <- shiny::reactive({
      window()
      retries()
      try_fetch(fetches$regions())
    })
    # The regions shown: those that prescribed the drug, and the others at 0,
    # once there is something to show
    shown <- shiny::reactive({
      rows <- regions()
      if (inherits(rows, "error") || nrow(rows) == 0L || all(is.na(rows$value))) {
        return(rows)
      }
      all <- nhs_regions()
      if (inherits(all, "error")) all else fill_regions(rows, all)
    })

    output$title <- shiny::renderText({
      pick <- picked()
      if (is.null(pick)) {
        return("Region")
      }
      if (is.null(months())) {
        return(pick$label)
      }
      paste0(pick$label, " by region, ", format_month_range(months()[1], months()[2]))
    })

    output$body <- shiny::renderUI({
      pick <- picked()
      if (is.null(pick)) {
        return(view_message("Search for a chemical substance or a presentation."))
      }
      if (is.null(months())) {
        return(no_window_message(window()))
      }
      rows <- shown()
      if (inherits(rows, "error")) {
        return(view_message("The data could not be fetched.", retry = ns("retry")))
      }
      if (nrow(rows) == 0L || all(is.na(rows$value))) {
        return(view_message(no_rows_text(pick, measure(), months())))
      }
      shiny::tagList(
        if (has_regional(rows)) {
          ggiraph::girafeOutput(ns("chart"), height = paste0(chart_height, "px"))
        },
        region_table(rows, measure()),
        if (any(!in_region(rows))) {
          shiny::p(
            class = "text-muted small mt-2",
            paste(
              "Prescriptions under the national unidentified prescriber code have no NHS",
              "region: they count in England's total only."
            )
          )
        }
      )
    })

    output$chart <- ggiraph::renderGirafe({
      rows <- shown()
      shiny::req(!inherits(rows, "error"), has_regional(rows))
      width <- output_width(session, "chart")
      render_girafe(
        chart_bars(rows[in_region(rows), ], width = width),
        width = width, height = chart_height, title = paste(picked()$label, "by region")
      )
    })

    current <- shiny::reactive({
      pick <- picked()
      rows <- if (is.null(pick) || is.null(months())) NULL else shown()
      if (is.null(rows) || inherits(rows, "error") || nrow(rows) == 0L ||
            all(is.na(rows$value))) {
        return(NULL)
      }
      list(
        view = "region",
        params = list(
          level = pick$level, id = pick$id, code = pick$code, label = pick$label,
          months = months(), measure = measure()
        ),
        data = rows
      )
    })
    csv_download(output, ns, current, "Download the totals by region, as CSV")
    current
  })
}

# Which rows are NHS regions: region "-" holds the prescribers without one
in_region <- function(rows) {
  rows$region_code != "-"
}

# Whether any region prescribed the drug: else there is no chart to draw
has_regional <- function(rows) {
  any(in_region(rows) & rows$value > 0, na.rm = TRUE)
}

# Every NHS region, a region that did not prescribe the drug at 0, as the
# series draws a month without prescribing: the fetch has no row for it. A
# region that prescribed it without a value (no ADQ) keeps its NA.
fill_regions <- function(rows, regions) {
  missing <- regions[!regions$region_code %in% rows$region_code, ]
  if (nrow(missing) == 0L) {
    return(rows)
  }
  zeros <- tibble::tibble(
    region_code = missing$region_code, region_name = missing$region_name,
    measure = rep(rows$measure[[1L]], nrow(missing)), value = 0
  )
  rows <- rbind(rows, zeros)
  rows[order(rows$region_code), ]
}

# The rows of the regions table: the regions largest first, then the
# prescribers without a region, each with its share of England's total
region_shares <- function(rows) {
  regional <- rows[in_region(rows), ]
  regional <- regional[order(regional$value, decreasing = TRUE, na.last = TRUE), ]
  outside <- rows[!in_region(rows), ]
  total <- sum(rows$value, na.rm = TRUE)
  data <- data.frame(
    region = c(
      regional$region_name,
      rep("No region: unidentified prescribers", nrow(outside))
    ),
    value = c(regional$value, outside$value)
  )
  data$share <- if (total > 0) data$value / total else rep(NA_real_, nrow(data))
  data
}

# The regions table, with England's total in its footer
region_table <- function(rows, measure) {
  data <- region_shares(rows)
  total <- sum(rows$value, na.rm = TRUE)
  info <- measure_info()
  label <- info$label[match(measure, info$measure)]
  reactable::reactable(
    data,
    columns = list(
      region = reactable::colDef(name = "Region", minWidth = 200, footer = "England"),
      value = measure_column(label, measure, footer = format_measure(total, measure)),
      share = reactable::colDef(
        name = "Share of England", footer = if (total > 0) "100.0%" else "",
        format = reactable::colFormat(percent = TRUE, digits = 1, locales = "en-GB")
      )
    ),
    pagination = FALSE, sortable = FALSE, compact = TRUE, striped = TRUE,
    defaultColDef = reactable::colDef(footerStyle = list(fontWeight = 600))
  )
}
