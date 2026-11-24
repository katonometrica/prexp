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
      bslib::card_body(shiny::uiOutput(ns("body")))
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
#' @param page_size The top drugs on a page.
#' @return A reactive `current_view()`: `NULL` until a practice's monthly
#'   totals are shown, then a list with `view` (`"practice"`), `params` (`id`,
#'   `label`, `months`, `measure`) and `data` (the monthly totals).
#' @noRd
mod_practice_server <- function(id, fetches, window, page_size = 25L) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    picked <- mod_search_server("search", fetches$search_practices, "practice")
    measures <- practice_measures()

    output$months_ui <- shiny::renderUI({
      months_controls(ns, window(), shiny::isolate(input$from), shiny::isolate(input$to))
    })
    output$measure_ui <- shiny::renderUI({
      measure_control(ns, measures, shiny::isolate(input$measure))
    })
    months <- shiny::reactive(chosen_months(input$from, input$to, window()))
    measure <- shiny::reactive(chosen_measure(input$measure, measures))
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

    output$body <- shiny::renderUI({
      pick <- picked()
      if (is.null(pick)) {
        return(view_message("Search for a practice by its name, code or postcode."))
      }
      if (is.null(months())) {
        return(no_window_message(window()))
      }
      found <- profile()
      rows <- series()
      if (inherits(found, "error") || inherits(rows, "error")) {
        return(view_message("The data could not be fetched.", retry = ns("retry")))
      }
      if (nrow(found) == 0L) {
        return(view_message(paste0(pick$label, " is not in the data.")))
      }
      shiny::tagList(
        practice_profile(found),
        if (nrow(rows) == 0L) {
          view_message(paste0(
            pick$label, " did not prescribe in ", format_month_range(months()[1], months()[2]),
            "."
          ))
        } else {
          shiny::tagList(
            ggiraph::girafeOutput(ns("chart"), height = paste0(chart_height, "px")),
            shiny::h3(class = "h6 mt-3", shiny::textOutput(ns("top_title"), inline = TRUE)),
            # The table and the paging stay on the page and change in place
            # from page to page, so the page does not jump and Next keeps the
            # focus; the messages are drawn beside them
            shiny::uiOutput(ns("top_message")),
            reactable::reactableOutput(ns("top_table")),
            paging_controls(ns)
          )
        }
      )
    })

    output$chart <- ggiraph::renderGirafe({
      rows <- series()
      shiny::req(!inherits(rows, "error"), nrow(rows) > 0L)
      width <- output_width(session, "chart")
      render_girafe(
        chart_series(measure_series(rows, measure()), months(), width = width),
        width = width, height = chart_height, title = picked()$label
      )
    })

    output$top_title <- shiny::renderText({
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
      shown <- page()
      top_drugs_table(shown$rows, shown$first)
    })

    output$top_range <- shiny::renderText({
      shown <- page()
      paste0("Drugs ", shown$first, " to ", shown$first + nrow(shown$rows) - 1L)
    })
    shiny::observe({
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
    current
  })
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
