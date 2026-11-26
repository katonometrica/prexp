#' Run Prescription Explorer
#'
#' Builds the Shiny app. When it starts, it opens the app's pool of read-only
#' connections with [db_pool()], a cache of fetch results of 200 MB shared by
#' every session, and the background workers (mirai daemons, each with its own
#' connection), all once for the process; when it stops, it closes them. A
#' login that can write, or a worker that cannot connect, stops the app from
#' starting.
#'
#' @param host,port Where the app listens. The `app` container listens on
#'   `0.0.0.0`, port 3838.
#' @param workers How many background workers to start. None when the
#'   package runs from its source (`devtools::load_all()`), which the workers,
#'   new R processes, could not load.
#' @param ... Other options for [shiny::runApp()], such as `launch.browser`.
#' @return A Shiny app object. Printing it runs the app, as
#'   `Rscript -e "prexp::run_app()"` does.
#' @examples
#' \dontrun{
#' run_app(launch.browser = TRUE)
#' }
#' @export
run_app <- function(host = getOption("shiny.host", "127.0.0.1"),
                    port = getOption("shiny.port", 3838L), workers = 2L, ...) {
  shiny::addResourcePath("prexp", system.file("app", "www", package = "prexp"))
  state <- new.env(parent = emptyenv())
  shiny::shinyApp(
    ui = app_ui,
    server = function(input, output, session) {
      app_server(state$pool, state$cache)(input, output, session)
    },
    onStart = function() {
      # The charts' font, the page's own copy, for measuring their text
      use_chart_font()
      state$pool <- db_pool()
      # One cache for the process, shared by every session
      state$cache <- app_cache()
      # Errors reach the page without their details, which can name the
      # database's host; the app's log keeps them. A session that has set the
      # option (to debug) keeps its setting; either way the app puts it back
      # when it stops.
      old <- options(shiny.sanitize.errors = getOption("shiny.sanitize.errors", TRUE))
      # Before the workers start: if they fail to, the app stops, and this
      # closes the pool
      shiny::onStop(function() {
        stop_workers()
        pool::poolClose(state$pool)
        options(old)
      })
      start_workers(if (from_source()) 0L else workers)
    },
    options = list(host = host, port = port, ...),
    enableBookmarking = "url"
  )
}

# Whether the package runs from its source (devtools::load_all()) rather than
# installed
from_source <- function() {
  exists(".__DEVTOOLS__", envir = asNamespace("prexp"), inherits = FALSE)
}
