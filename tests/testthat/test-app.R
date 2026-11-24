# The app shell (spec section 5.3; P4-01): five tabs, the footer with the data
# window and the attribution, the robots meta, the About tab, and run_app()
# opening and closing the pool.

test_that("the page has the five tabs, the robots meta in its head, and the footer", {
  ui <- app_ui(NULL)
  rendered <- htmltools::renderTags(ui)
  expect_match(
    rendered$head, "<meta name=\"robots\" content=\"noindex, nofollow\"/>", fixed = TRUE
  )
  expect_identical(attr(ui, "lang"), "en")
  page <- rendered$html
  for (tab in c("drug", "practice", "region", "report", "about")) {
    expect_match(page, paste0("data-value=\"", tab, "\""), fixed = TRUE, label = tab)
  }
  footer <- regmatches(page, regexpr("<footer class=\"prexp-footer\">.*?</footer>", page))
  expect_length(footer, 1L)
  expect_match(footer, "id=\"window\"", fixed = TRUE)
  expect_match(footer, data_attribution()$statement, fixed = TRUE)
  expect_match(footer, "Open Government Licence v3.0", fixed = TRUE)
})

test_that("the About tab shows every section, measure and limitation, and the licence", {
  about <- as.character(about_ui())
  for (section in methods_sections()) {
    expect_match(about, section$title, fixed = TRUE)
  }
  for (label in measure_info()$label) {
    expect_match(about, paste0("<strong>", label, ".</strong>"), fixed = TRUE)
  }
  limits <- c(
    "Community dispensing only", "No patient detail", "list prices before discounts",
    "not comparable across forms", "follow the commissioner", "unidentified prescribers"
  )
  for (limit in limits) {
    expect_match(about, limit, fixed = TRUE)
  }
  expect_match(about, data_attribution()$statement, fixed = TRUE)
  expect_match(about, data_attribution()$licence_url, fixed = TRUE)
  expect_identical(
    measure_info()$measure, c("items", "total_quantity", "adq_usage", "nic", "actual_cost")
  )
})

test_that("the footer shows the data window, or says why it cannot", {
  shiny::testServer(app_server(fixture_app()), {
    expect_identical(output$window, "Data: Oct 2025 \u2013 Sep 2026")
  })
  # No month loaded yet
  empty <- local_test_db("app", dbname = local_migrated_db())
  shiny::testServer(app_server(empty), {
    expect_identical(output$window, "No data loaded yet")
  })
  # The database cannot be reached
  local_test_db("app")
  closed <- db_connect("app", dbname = local_fixture_db())
  DBI::dbDisconnect(closed)
  shiny::testServer(app_server(closed), {
    expect_identical(output$window, "Data window unavailable")
  })
})

test_that("run_app() opens the pool when the app starts and closes it when the app stops", {
  dbname <- local_fixture_db()
  owner <- local_test_db("owner", dbname = dbname)
  withr::local_envvar(PREXP_DB_NAME = dbname, PREXP_LOG = "off")
  connected <- function() {
    DBI::dbGetQuery(owner, "
      SELECT count(*)::int4 AS n FROM pg_stat_activity
      WHERE datname = current_database() AND application_name = 'prexp-app'")$n
  }
  app <- run_app(port = httpuv::randomPort(), launch.browser = FALSE)
  expect_s3_class(app, "shiny.appobj")
  expect_identical(app$appOptions$bookmarkStore, "url")
  while_running <- NA_integer_
  later::later(function() {
    while_running <<- connected()
    shiny::stopApp()
  }, 0.5)
  shiny::runApp(app, quiet = TRUE)
  expect_identical(while_running, 1L)
  # A closed connection's backend can take a moment to go
  for (i in 1:50) {
    if (connected() == 0L) break
    Sys.sleep(0.1)
  }
  expect_identical(connected(), 0L)
})

test_that("the app does not start with a login that can write", {
  dbname <- local_fixture_db()
  withr::local_envvar(
    PREXP_DB_NAME = dbname, PREXP_APP_USER = "prexp_loader",
    PREXP_APP_PASSWORD = Sys.getenv("PREXP_LOADER_PASSWORD")
  )
  app <- run_app(port = httpuv::randomPort(), launch.browser = FALSE)
  expect_error(shiny::runApp(app, quiet = TRUE), class = "prexp_writable_login")
})
