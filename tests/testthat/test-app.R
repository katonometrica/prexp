# The app shell (spec section 5.3; P4-01): five tabs, the footer with the data
# window and the attribution, the robots meta, the About tab, the theme, and
# run_app() opening and closing the pool.

test_that("the page has the five tabs, the robots meta in its head, and the footer", {
  ui <- app_ui(NULL)
  rendered <- htmltools::renderTags(ui)
  expect_match(
    rendered$head, "<meta name=\"robots\" content=\"noindex, nofollow\"/>", fixed = TRUE
  )
  expect_identical(attr(ui, "lang"), "en")
  expect_s3_class(attr(ui, "bs_theme"), "bs_theme")
  page <- rendered$html
  for (tab in app_tabs) {
    expect_match(page, paste0("data-value=\"", tab, "\""), fixed = TRUE, label = tab)
  }
  footer <- regmatches(page, regexpr("<footer class=\"prexp-footer\">.*?</footer>", page))
  expect_length(footer, 1L)
  expect_match(footer, "id=\"window\"", fixed = TRUE)
  expect_match(footer, "NHSBSA Copyright 2021-2026", fixed = TRUE)
  expect_match(
    footer,
    paste0(
      "<a href=\"https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/\">",
      "Open Government Licence v3.0</a>."
    ),
    fixed = TRUE
  )
})

test_that("the tabs are the page's main landmark, and each tab has an h1", {
  page <- htmltools::renderTags(app_ui(NULL))$html
  count <- function(pattern) lengths(regmatches(page, gregexpr(pattern, page, perl = TRUE)))
  expect_identical(count("role=\"main\""), 1L)
  expect_identical(count("<div class=\"tab-content[^\"]*\"[^>]*role=\"main\""), 1L)
  # The navbar comes before the main landmark and the footer after it, so
  # neither is inside it
  main_at <- regexpr("role=\"main\"", page)
  expect_lt(regexpr("<nav ", page), main_at)
  expect_gt(regexpr("<footer class=\"prexp-footer\">", page), main_at)
  headings <- regmatches(page, gregexpr("<h1 class=\"visually-hidden\">[^<]*</h1>", page))[[1]]
  expect_identical(
    sub("<h1 class=\"visually-hidden\">([^<]*)</h1>", "\\1", headings),
    c("Drug", "Practice", "Region", "Report", "About the data")
  )
  # A view's own tabs stay plain
  nested <- main_landmark(bslib::page_navbar(
    title = "x", id = "tab", lang = "en",
    bslib::nav_panel("A", bslib::navset_tab(bslib::nav_panel("B", "b"), bslib::nav_panel("C", "c")))
  ))
  expect_identical(lengths(gregexpr("role=\"main\"", as.character(nested))), 1L)
  expect_identical(attr(nested, "lang"), "en")
})

test_that("the About tab shows every section, measure and limitation, and the source", {
  about <- as.character(about_ui())
  sections <- methods_sections()
  for (section in sections) {
    expect_match(about, section$title, fixed = TRUE)
  }
  # Each measure's label goes with its own definition
  measures <- measure_info()
  expect_identical(
    measures$measure, c("items", "total_quantity", "adq_usage", "nic", "actual_cost")
  )
  points <- sections[[2L]]$points
  expect_identical(vapply(points, `[[`, "", "term"), measures$label)
  expect_identical(vapply(points, `[[`, "", "text"), measures$definition)
  for (label in measures$label) {
    expect_match(about, paste0("<strong>", label, ".</strong>"), fixed = TRUE)
  }
  definitions <- stats::setNames(measures$definition, measures$measure)
  expect_match(definitions[["items"]], "Prescription items", fixed = TRUE)
  expect_match(definitions[["total_quantity"]], "single presentation only", fixed = TRUE)
  expect_match(definitions[["adq_usage"]], "average daily dose", fixed = TRUE)
  expect_match(definitions[["nic"]], "Drug Tariff", fixed = TRUE)
  expect_match(definitions[["actual_cost"]], "net ingredient cost less the discount", fixed = TRUE)
  limits <- c(
    "Community dispensing only", "hospital site codes", "No patient detail",
    "not what the NHS paid", "not comparable across forms", "follow the commissioner",
    "count in national totals but cannot be searched as practices"
  )
  for (limit in limits) {
    expect_match(about, limit, fixed = TRUE)
  }
  # Actual cost comes after the discount, so not every cost is a list price
  expect_no_match(about, "list prices before discounts", fixed = TRUE)
  expect_match(about, "which the NHS Business Services Authority (NHSBSA) publishes", fixed = TRUE)
  expect_match(about, "the last month it prescribed in", fixed = TRUE)
  # The source, the attribution and the licence, with their links
  attribution <- data_attribution()
  expect_identical(attribution$statement, "NHSBSA Copyright 2021-2026")
  expect_identical(
    attribution$licence_url,
    "https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/"
  )
  expect_identical(
    attribution$source_url,
    "https://opendata.nhsbsa.net/dataset/english-prescribing-dataset-epd-with-snomed-code"
  )
  source <- sections[[4L]]
  expect_identical(source$title, "Source and licence")
  expect_identical(
    source$text[[1L]],
    "Source: English Prescribing Dataset (EPD) with SNOMED Code, NHS Business Services Authority."
  )
  expect_match(
    source$text[[2L]],
    paste(
      "NHSBSA Copyright 2021-2026 \u00b7 Contains public sector information licensed under the",
      "Open Government Licence v3.0."
    ),
    fixed = TRUE
  )
  expect_identical(
    vapply(source$links, `[[`, "", "url"), c(attribution$source_url, attribution$licence_url)
  )
  for (url in c(attribution$source_url, attribution$licence_url)) {
    expect_match(about, paste0("href=\"", url, "\""), fixed = TRUE)
  }
})

test_that("the theme loads no web font and keeps the navbar's text readable", {
  theme <- prexp_theme()
  navbar <- c("navbar-light-color", "navbar-light-hover-color", "navbar-light-active-color")
  vars <- bslib::bs_get_variables(
    theme, c("font-family-base", "font-family-monospace", "navbar-bg", navbar)
  )
  expect_identical(unname(vars[["font-family-base"]]), "var(--bs-font-sans-serif)")
  expect_no_match(vars[["font-family-monospace"]], "Source Code Pro", fixed = TRUE)
  # WCAG AA for the tab names on the navbar's blue, open or not
  for (colour in navbar) {
    expect_gte(contrast_ratio(vars[[colour]], vars[["navbar-bg"]]), 4.5, label = colour)
  }
  deps <- bslib::bs_theme_dependencies(theme)
  bootstrap <- deps[[which(vapply(deps, function(dep) dep$name, "") == "bootstrap")]]
  css <- paste(
    readLines(file.path(bootstrap$src$file, "bootstrap.min.css"), warn = FALSE),
    collapse = "\n"
  )
  expect_no_match(css, "@import", fixed = TRUE)
  expect_no_match(css, "Open Sans", fixed = TRUE)
  expect_match(css, "--bs-body-font-family: var(--bs-font-sans-serif)", fixed = TRUE)
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
  # The database cannot be reached: the page says so, the log says why
  local_test_db("app")
  closed <- db_connect("app", dbname = local_fixture_db())
  DBI::dbDisconnect(closed)
  expect_message(
    shiny::testServer(app_server(closed), {
      expect_identical(output$window, "Data window unavailable")
    }),
    "The data window could not be fetched: "
  )
})

test_that("a bookmark can open the app's tabs only", {
  # The page's tabs, in order, are the ones a bookmark may name
  page <- htmltools::renderTags(app_ui(NULL))$html
  values <- regmatches(page, gregexpr("data-value=\"[^\"]*\"", page))[[1L]]
  expect_identical(unique(sub("data-value=\"([^\"]*)\"", "\\1", values)), app_tabs)
  for (tab in app_tabs) {
    expect_true(known_tab(tab), label = tab)
  }
  for (tab in list("nosuchtab", NULL, NA_character_, c("drug", "about"), 1L, "")) {
    expect_false(known_tab(tab), label = deparse(tab))
  }
})

test_that("run_app() opens the pool when the app starts and closes it when the app stops", {
  dbname <- local_fixture_db()
  owner <- local_test_db("owner", dbname = dbname)
  withr::local_envvar(PREXP_DB_NAME = dbname, PREXP_LOG = "off")
  withr::local_options(shiny.sanitize.errors = NULL)
  connected <- function() {
    DBI::dbGetQuery(owner, "
      SELECT count(*)::int4 AS n FROM pg_stat_activity
      WHERE datname = current_database() AND application_name = 'prexp-app'")$n
  }
  app <- run_app(port = httpuv::randomPort(), launch.browser = FALSE)
  expect_s3_class(app, "shiny.appobj")
  expect_identical(app$appOptions$bookmarkStore, "url")
  while_running <- NA_integer_
  sanitized <- NA
  later::later(function() {
    while_running <<- connected()
    sanitized <<- getOption("shiny.sanitize.errors")
    shiny::stopApp()
  }, 0.5)
  shiny::runApp(app, quiet = TRUE)
  expect_identical(while_running, 1L)
  # While it runs, errors reach the page without their details; after, the
  # option is as it was
  expect_true(sanitized)
  expect_null(getOption("shiny.sanitize.errors"))
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
