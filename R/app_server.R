#' The app's server
#'
#' Builds the server function for a pool or connection, so that the app runs
#' on the pool [run_app()] opens and the tests on a test database.
#'
#' @param con A pool from [db_pool()], or a connection that can read the app
#'   views.
#' @return A Shiny server function.
#' @noRd
app_server <- function(con) {
  function(input, output, session) {
    window <- shiny::reactive(fetch_window(con))
    output$window <- shiny::renderText({
      tryCatch(
        window_text(window()),
        error = function(e) "Data window unavailable"
      )
    })
  }
}

# The footer's words for the window: its months, or that nothing is loaded
window_text <- function(window) {
  if (nrow(window) == 0L || is.na(window$first_month)) {
    return("No data loaded yet")
  }
  paste("Data:", format_month_range(window$first_month, window$last_month))
}
