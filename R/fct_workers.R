# The app's background workers (spec section 5.4; P4-07): mirai daemons that
# run slow fetches and, from P5, the exports, so that one slow request does
# not hold up the other sessions of the app's process. Each daemon opens its
# own connection as the app, since a pool cannot be shared across processes.
# The daemons' standard output is the app's (output = TRUE), so the timing
# lines of the fetches they run reach the app's log.

# On a daemon: its connection to the database
worker <- new.env(parent = emptyenv())

#' Starts the background workers
#'
#' Each daemon runs `setup`, then opens its connection; the start waits for
#' them and fails if one could not, as [db_pool()] fails at the app's start
#' rather than at its first query. The daemons get the app's database and its
#' log settings (on or off, and the key), rather than reading their own
#' environment, which can differ from the app's (an `Renviron.site` sets
#' variables in every new R process): so identical requests log the same hash
#' in every process.
#'
#' @param n How many daemons; none for 0.
#' @param setup An expression each daemon runs before it connects, or `NULL`;
#'   the tests load the package under development with it.
#' @param dbname The database the daemons connect to: the app's, from
#'   `PREXP_DB_NAME`, by default.
#' @param timeout How long to wait for them to start, in seconds.
#' @return Invisibly, `n`.
#' @noRd
start_workers <- function(n = 2L, setup = NULL, dbname = NULL, timeout = 60) {
  if (n < 1L) {
    return(invisible(n))
  }
  dbname <- dbname %||% db_config("app")$dbname
  log <- c(PREXP_LOG = if (log_enabled()) "on" else "off", PREXP_LOG_KEY = log_key())
  mirai::daemons(n, output = TRUE)
  tryCatch(
    {
      if (!is.null(setup)) {
        workers_started(mirai::everywhere(.expr = setup, .min = n), timeout)
      }
      workers_started(
        mirai::everywhere(
          worker_connect(dbname, log),
          worker_connect = worker_connect, dbname = dbname, log = log, .min = n
        ),
        timeout
      )
    },
    error = function(e) {
      mirai::daemons(0L)
      stop(e)
    }
  )
  invisible(n)
}

# Waits for the daemons' start-up calls, and stops if one failed or did not
# finish in time
workers_started <- function(calls, timeout) {
  deadline <- Sys.time() + timeout
  while (mirai::unresolved(calls) && Sys.time() < deadline) {
    Sys.sleep(0.05)
  }
  if (mirai::unresolved(calls)) {
    stop("The background workers did not start within ", timeout, " s.", call. = FALSE)
  }
  failed <- Filter(mirai::is_error_value, calls[])
  if (length(failed) > 0L) {
    stop("A background worker could not start: ", conditionMessage(failed[[1L]]), call. = FALSE)
  }
  invisible(TRUE)
}

#' Stops the background workers, and with them their connections
#'
#' @return Invisibly, `NULL`.
#' @noRd
stop_workers <- function() {
  mirai::daemons(0L)
  invisible(NULL)
}

# On a daemon: takes the app's log settings, and opens its connection as the
# app
worker_connect <- function(dbname = NULL, log = NULL) {
  if (length(log) > 0L) {
    do.call(Sys.setenv, as.list(log))
  }
  worker$con <- db_connect("app", dbname = dbname)
  invisible(TRUE)
}

# On a daemon: one of the package's fetch functions, on the daemon's
# connection
worker_fetch <- function(name, args) {
  fetch <- getExportedValue("prexp", name)
  do.call(fetch, c(list(worker$con), args))
}

#' A fetch as a background task
#'
#' Runs one of the fetch functions on a worker, for a fetch over 100 ms in
#' the timing log, through a [shiny::ExtendedTask]. It answers the latest call
#' only: a call that a newer one replaced reads as still running, so that its
#' result is never shown for the newer arguments.
#'
#' @param name The fetch function's name, such as `"fetch_drug_series"`.
#' @return A list of functions: `invoke(...)` takes the fetch's arguments
#'   after the connection; `status()` gives "initial", "running", "success"
#'   or "error"; `result()` gives the latest call's tibble, or raises its
#'   error, whose cause the app's log gets as try_fetch() logs it.
#' @noRd
fetch_task <- function(name) {
  if (!name %in% getNamespaceExports("prexp") || !startsWith(name, "fetch_")) {
    stop("No fetch function is called ", name, ".", call. = FALSE)
  }
  latest <- shiny::reactiveVal(0L)
  task <- shiny::ExtendedTask$new(function(call, args) {
    promises::then(
      mirai::mirai(
        worker_fetch(name, args),
        worker_fetch = worker_fetch, name = name, args = args
      ),
      onFulfilled = function(data) list(call = call, data = data),
      onRejected = function(error) list(call = call, error = error)
    )
  })
  list(
    invoke = function(...) {
      call <- shiny::isolate(latest()) + 1L
      latest(call)
      task$invoke(call, list(...))
    },
    status = function() {
      status <- task$status()
      if (!identical(status, "success")) {
        return(status)
      }
      value <- task$result()
      if (!identical(value$call, latest())) {
        "running"
      } else if (is.null(value$error)) {
        "success"
      } else {
        "error"
      }
    },
    result = function() {
      value <- task$result()
      shiny::req(identical(value$call, latest()), cancelOutput = "progress")
      if (!is.null(value$error)) {
        message("A fetch failed: ", conditionMessage(value$error))
        stop(value$error)
      }
      value$data
    }
  )
}
