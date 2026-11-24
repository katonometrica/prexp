# The background workers (P4-07): a fetch run on a mirai daemon through the
# fetch_task() wrapper, on the daemon's own connection, the daemons' start and
# stop, and the timing lines they leave in the app's output.

# What a daemon runs first, so that it loads the package these tests run: the
# source under development, or the installed package (as under covr)
worker_setup <- function() {
  if (pkgload::is_dev_package("prexp")) {
    bquote(pkgload::load_all(.(getNamespaceInfo("prexp", "path")), quiet = TRUE))
  } else {
    bquote(.libPaths(.(.libPaths())))
  }
}

# Runs the event loop until the task is no longer running
wait_for <- function(task, timeout = 60) {
  deadline <- Sys.time() + timeout
  while (shiny::isolate(task$status()) == "running" && Sys.time() < deadline) {
    later::run_now(0.1)
  }
  shiny::isolate(task$status())
}

# Runs `code` in an Rscript of its own, with the package loaded and one worker
# started on `dbname`, and gives back the lines of its standard output, where
# the worker's go too
run_with_worker <- function(code, dbname, before = character()) {
  script <- tempfile(fileext = ".R")
  out <- tempfile(fileext = ".log")
  load <- if (pkgload::is_dev_package("prexp")) deparse(worker_setup()) else "library(prexp)"
  writeLines(c(
    load,
    "ns <- asNamespace('prexp')",
    before,
    sprintf(
      "ns$start_workers(1L, setup = quote(%s), dbname = '%s')",
      paste(deparse(worker_setup()), collapse = " "), dbname
    ),
    "run_task <- function(task) {",
    "  deadline <- Sys.time() + 60",
    "  while (shiny::isolate(task$status()) == 'running' && Sys.time() < deadline) {",
    "    later::run_now(0.1)",
    "  }",
    "  cat('STATUS', shiny::isolate(task$status()), '\\n')",
    "}",
    code,
    "ns$stop_workers()"
  ), script)
  processx::run(
    file.path(R.home("bin"), "Rscript"), script,
    env = c(
      "current", PREXP_LOG = "on", PREXP_DB_NAME = dbname,
      R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)
    ),
    stdout = out, stderr = "|", timeout = 180
  )
  readLines(out)
}

timing_lines <- function(lines) grep("{\"time\":", lines, fixed = TRUE, value = TRUE)

test_that("a worker fetches on its own connection", {
  dbname <- local_fixture_db()
  app <- local_test_db("app", dbname = dbname)
  worker_connect(dbname)
  withr::defer({
    DBI::dbDisconnect(worker$con)
    worker$con <- NULL
  })
  expect_identical(worker_fetch("fetch_window", list()), fetch_window(app))
  expect_error(fetch_task("db_connect"), "No fetch function is called db_connect.")
  expect_error(fetch_task("fetch_nothing"), "No fetch function is called fetch_nothing.")
})

test_that("a fetch task runs on a daemon, with its arguments, and stops with the workers", {
  dbname <- local_fixture_db()
  app <- local_test_db("app", dbname = dbname)
  owner <- local_test_db("owner", dbname = dbname)
  own <- DBI::dbGetQuery(app, "SELECT pg_backend_pid() AS pid")$pid
  connected <- "
    SELECT count(*)::int4 AS n FROM pg_stat_activity
    WHERE datname = current_database() AND application_name = 'prexp-app' AND pid <> $1"
  workers_connected <- function() DBI::dbGetQuery(owner, connected, params = list(own))$n
  start_workers(1L, setup = worker_setup(), dbname = dbname)
  withr::defer(stop_workers())
  expect_identical(workers_connected(), 1L)
  window <- fetch_task("fetch_window")
  shiny::isolate(window$invoke())
  expect_identical(wait_for(window), "success")
  expect_identical(shiny::isolate(window$result()), fetch_window(app))
  # A fetch with arguments
  chemical <- id_of(app, "chemical", "0212000B0")
  loaded <- fetch_window(app)
  span <- c(loaded$first_month, loaded$last_month)
  series <- fetch_task("fetch_drug_series")
  shiny::isolate(series$invoke("chemical", chemical, span, "items"))
  expect_identical(wait_for(series), "success")
  expect_identical(
    shiny::isolate(series$result()), fetch_drug_series(app, "chemical", chemical, span, "items")
  )
  # An error comes back as the task's, and its cause goes to the log
  profile <- fetch_task("fetch_practice_profile")
  shiny::isolate(profile$invoke(NA))
  expect_identical(wait_for(profile), "error")
  expect_message(
    expect_error(shiny::isolate(profile$result()), "`practice_id` must be one id", fixed = TRUE),
    "A fetch failed: "
  )
  # Stopping the workers closes their connections
  stop_workers()
  expect_identical(mirai::status()$connections, 0L)
  for (i in 1:50) {
    if (workers_connected() == 0L) break
    Sys.sleep(0.1)
  }
  expect_identical(workers_connected(), 0L)
  # No daemons for none
  expect_identical(start_workers(0L), 0L)
})

test_that("a task answers its latest call only", {
  dbname <- local_fixture_db()
  app <- local_test_db("app", dbname = dbname)
  start_workers(1L, setup = worker_setup(), dbname = dbname)
  withr::defer(stop_workers())
  chemical <- id_of(app, "chemical", "0212000B0")
  span <- c(fetch_window(app)$first_month, fetch_window(app)$last_month)
  series <- fetch_task("fetch_drug_series")
  shiny::isolate(series$invoke("chemical", chemical, span, "items"))
  shiny::isolate(series$invoke("chemical", chemical, span, "nic"))
  seen <- character()
  deadline <- Sys.time() + 60
  repeat {
    status <- shiny::isolate(series$status())
    seen <- c(seen, status)
    if (status != "running" || Sys.time() > deadline) break
    later::run_now(0.05)
  }
  # Never the first call's result as the latest's
  expect_identical(unique(seen), c("running", "success"))
  expect_identical(
    shiny::isolate(series$result()), fetch_drug_series(app, "chemical", chemical, span, "nic")
  )
})

test_that("workers that cannot connect stop the start, and leave no daemon", {
  dbname <- local_fixture_db()
  local_test_db("app", dbname = dbname)
  expect_error(
    start_workers(1L, setup = worker_setup(), dbname = "prexp_no_such_database"),
    "A background worker could not start"
  )
  expect_identical(mirai::status()$connections, 0L)
})

test_that("a fetch run through the task leaves exactly one whole timing line", {
  dbname <- local_fixture_db()
  local_test_db("app", dbname = dbname)
  lines <- run_with_worker(
    c("task <- ns$fetch_task('fetch_window')", "shiny::isolate(task$invoke())", "run_task(task)"),
    dbname
  )
  expect_true("STATUS success " %in% lines)
  timing <- timing_lines(lines)
  expect_length(timing, 1L)
  record <- jsonlite::fromJSON(timing)
  expect_identical(record[["function"]], "fetch_window")
  expect_identical(record$rows, 1L)
  # As timing_summary() reads it back
  out <- withr::local_tempfile(fileext = ".log")
  writeLines(lines, out)
  expect_identical(timing_summary(out)$count, 1L)
})

test_that("the workers log with the app's key, and not at all when its log is off", {
  dbname <- local_fixture_db()
  local_test_db("app", dbname = dbname)
  # Without PREXP_LOG_KEY, the app's key, which it draws, is the workers' too:
  # the same request logs the same hash in every process
  lines <- run_with_worker(
    c(
      sprintf("con <- ns$db_connect('app', dbname = '%s')", dbname),
      "invisible(ns$fetch_window(con))",
      "task <- ns$fetch_task('fetch_window')", "shiny::isolate(task$invoke())", "run_task(task)"
    ),
    dbname, before = "Sys.unsetenv('PREXP_LOG_KEY')"
  )
  records <- lapply(timing_lines(lines), jsonlite::fromJSON)
  expect_length(records, 2L)
  expect_identical(records[[1]]$args, records[[2]]$args)
  # The log off in the app is off in its workers, whatever their environment
  lines <- run_with_worker(
    c("task <- ns$fetch_task('fetch_window')", "shiny::isolate(task$invoke())", "run_task(task)"),
    dbname, before = "Sys.setenv(PREXP_LOG = 'off')"
  )
  expect_true("STATUS success " %in% lines)
  expect_length(timing_lines(lines), 0L)
})
