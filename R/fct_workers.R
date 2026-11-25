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

#' The exports, as background tasks
#'
#' With the workers started, an export runs on one of them, on its own
#' connection, so that a report of fifteen items does not hold up the other
#' sessions; the file is written where the app's session can serve it. With
#' none, as when the package runs from its source, it runs here, on `con`.
#'
#' @param con A pool or connection that can read the app's views, for an
#'   export run here.
#' @param timeout How long an export on a worker may take, waiting for a
#'   worker included, in seconds. After that it fails, so that a lost or
#'   stuck worker ends as an error the Report tab shows, not as "Preparing"
#'   for ever.
#' @return A function of `format`, `spec`, `path` and `exported`, as
#'   [export_report()] takes them, that returns a promise of `path`.
#' @noRd
export_runner <- function(con, timeout = 120) {
  function(format, spec, path, exported) {
    if (mirai::daemons_set()) {
      return(mirai::mirai(
        worker_export(format, spec, path, exported),
        worker_export = worker_export, format = format, spec = spec, path = path,
        exported = exported, .timeout = timeout * 1000
      ))
    }
    promises::promise(function(resolve, reject) {
      resolve(export_report(format, spec, con, path, exported))
    })
  }
}

# On a daemon: an export, on the daemon's connection
worker_export <- function(format, spec, path, exported) {
  export_report(format, spec, worker$con, path, exported)
}
