#' Run Prescription Explorer
#'
#' Builds the Shiny app. When it starts, it opens the app's pool of read-only
#' connections with [db_pool()], once for the process; when it stops, it closes
#' the pool. A login that can write stops the app from starting.
#'
#' @param host,port Where the app listens. The `app` container listens on
#'   `0.0.0.0`, port 3838.
#' @param ... Other options for [shiny::runApp()], such as `launch.browser`.
#' @return A Shiny app object. Printing it runs the app, as
#'   `Rscript -e "prexp::run_app()"` does.
#' @examples
#' \dontrun{
#' run_app(launch.browser = TRUE)
#' }
#' @export
run_app <- function(host = getOption("shiny.host", "127.0.0.1"),
                    port = getOption("shiny.port", 3838L), ...) {
  shiny::addResourcePath("prexp", system.file("app", "www", package = "prexp"))
  state <- new.env(parent = emptyenv())
  shiny::shinyApp(
    ui = app_ui,
    server = function(input, output, session) {
      app_server(state$pool)(input, output, session)
    },
    onStart = function() {
      state$pool <- db_pool()
      # Errors reach the page without their details, which can name the
      # database's host; the app's log keeps them. A session that has set the
      # option (to debug) keeps its setting; either way the app puts it back
      # when it stops.
      old <- options(shiny.sanitize.errors = getOption("shiny.sanitize.errors", TRUE))
      shiny::onStop(function() {
        pool::poolClose(state$pool)
        options(old)
      })
    },
    options = list(host = host, port = port, ...),
    enableBookmarking = "url"
  )
}
