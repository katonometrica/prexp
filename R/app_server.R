#' The app's server
#'
#' Builds the server function for a pool or connection, so that the app runs
#' on the pool [run_app()] opens and the tests on a test database.
#'
#' @param con A pool from [db_pool()], or a connection that can read the app
#'   views.
#' @param cache The app's cache, from [app_cache()], or `NULL` for none. The
#'   window is always fetched: it is part of every other fetch's key.
#' @return A Shiny server function.
#' @noRd
app_server <- function(con, cache = NULL) {
  function(input, output, session) {
    # The window, or NULL when it cannot be fetched: the footer says so, and the
    # cause goes to the app's log, not to the page
    window <- shiny::reactive({
      tryCatch(fetch_window(con), error = function(e) {
        message("The data window could not be fetched: ", conditionMessage(e))
        # Try again in a while: the views wait for it
        shiny::invalidateLater(window_retry_ms)
        NULL
      })
    })
    fetches <- app_fetches(con, cache, window)
    mod_drug_server("drug", fetches, window)
    mod_practice_server("practice", fetches, window)
    mod_region_server("region", fetches, window)
    output$window <- shiny::renderText({
      if (is.null(window())) "Data window unavailable" else window_text(window())
    })
    # A bookmark can name a tab that does not exist, or no longer does: bslib
    # then shows no tab at all, so open the Drug tab
    shiny::onRestored(function(state) {
      if (!known_tab(state$input$tab)) {
        bslib::nav_select("tab", "drug", session = session)
      }
    })
  }
}

# How long the app waits before fetching the window again, when it could not
window_retry_ms <- 10000

# The footer's words for the window: its months, or that nothing is loaded
window_text <- function(window) {
  if (nrow(window) == 0L || is.na(window$first_month)) {
    return("No data loaded yet")
  }
  paste("Data:", format_month_range(window$first_month, window$last_month))
}

# Whether a restored tab is one of the app's
known_tab <- function(tab) {
  is.character(tab) && length(tab) == 1L && tab %in% app_tabs
}
