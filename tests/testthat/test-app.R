# The app shell (spec section 5.3; P4-01): the header, katonometrica.com's bar
# over the five tabs; the footer with the data window and the attribution, the
# robots meta, the About tab, the theme, and run_app() opening and closing the
# pool.

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
  # The source, linked from every page: the repository in DESCRIPTION
  expect_identical(source_url(), "https://github.com/katonometrica/prexp")
  expect_match(
    footer, "<a href=\"https://github.com/katonometrica/prexp\">Source on GitHub</a>",
    fixed = TRUE
  )
  # Last, KATONOMETRICA's wordmark, linking its site
  expect_match(
    footer,
    "<a class=\"prexp-wordmark\" href=\"https://katonometrica.com\">KATONOMETRICA</a>\\s*</footer>"
  )
})

test_that("the header is katonometrica.com's bar over the app's name and tabs", {
  rendered <- htmltools::renderTags(app_ui(NULL))
  doc <- xml2::read_html(rendered$html)
  find <- function(node, xpath) xml2::xml_find_all(node, xpath)
  class_is <- function(name) sprintf("contains(concat(' ', @class, ' '), ' %s ')", name)
  # First on the page, the site's skip link, to the tabs' content, the main
  # landmark
  skip <- find(doc, "//body/*[1]")
  expect_identical(xml2::xml_name(skip), "a")
  expect_identical(xml2::xml_attr(skip, "class"), "kat-skip-link")
  expect_identical(xml2::xml_attr(skip, "href"), "#main-content")
  expect_identical(xml2::xml_text(skip), "Skip to main content")
  expect_identical(xml2::xml_attr(find(doc, "//*[@id='main-content']"), "role"), "main")
  # Then one header, before everything else on the page: the drawer's
  # backdrop, hidden from screen readers, then two navigation landmarks named
  # apart
  header <- find(doc, "//header")
  expect_length(header, 1L)
  expect_identical(xml2::xml_attr(header, "id"), "kat-navbar")
  expect_identical(xml2::xml_name(find(doc, "//body/*[2]")), "header")
  expect_identical(xml2::xml_name(find(header, "./*")), c("div", "nav", "nav"))
  backdrop <- find(header, "./div")
  expect_identical(xml2::xml_attr(backdrop, "id"), "kat-nav-menu-backdrop")
  expect_identical(xml2::xml_attr(backdrop, "aria-hidden"), "true")
  navs <- find(header, "./nav")
  expect_identical(
    xml2::xml_attr(navs, "aria-label"), c("katonometrica.com", "Prescription Explorer")
  )
  site <- navs[[1L]]
  # The site's bar: the wordmark, the site's four sections and Book a call,
  # each leading to katonometrica.com in the same tab, as the site's do
  links <- find(site, ".//a")
  expect_identical(
    xml2::xml_text(links),
    c("KATONOMETRICA", "What we do", "Work", "How it works", "Contact", "Book a call")
  )
  expect_identical(xml2::xml_attr(links, "href"), c(
    "https://katonometrica.com/", "https://katonometrica.com/#services",
    "https://katonometrica.com/#work", "https://katonometrica.com/#how",
    "https://katonometrica.com/#contact", "https://katonometrica.com/#contact"
  ))
  expect_true(all(is.na(xml2::xml_attr(links, "target"))))
  expect_identical(
    xml2::xml_attr(links, "class"),
    c("kat-nav-logo", rep("kat-nav-link", 4L), "kat-btn kat-btn-primary kat-btn-nav")
  )
  items <- sprintf(".//ul[@id='kat-nav-menu']/li[%s]/a", class_is("kat-nav-item"))
  expect_length(find(site, items), 4L)
  # Its actions: the theme button, then Book a call; no language menu, as the
  # app is in English
  actions <- find(site, ".//div[@id='kat-nav-actions']/*")
  expect_identical(xml2::xml_attr(actions, "id")[[1L]], "prexp-theme-toggle")
  expect_identical(xml2::xml_attr(actions, "class")[[1L]], "kat-theme-toggle")
  expect_identical(xml2::xml_text(actions[[2L]]), "Book a call")
  expect_length(find(site, ".//select"), 0L)
  # The hamburger, for a phone: named for the bar it opens, with the drawer's
  # state and its two parts, the links and the actions
  burger <- find(site, ".//button[@id='kat-nav-toggle']")
  expect_length(burger, 1L)
  expect_identical(xml2::xml_attr(burger, "type"), "button")
  expect_identical(xml2::xml_attr(burger, "aria-label"), "katonometrica.com menu")
  expect_identical(xml2::xml_attr(burger, "aria-expanded"), "false")
  expect_identical(xml2::xml_attr(burger, "aria-controls"), "kat-nav-menu kat-nav-actions")
  expect_length(find(burger, sprintf("./span[%s]", class_is("kat-hamburger-line"))), 3L)
  # The app's row: its name as text, then the five tabs, which no menu button
  # hides, as the site's links and not Bootstrap's underlined tabs
  app <- navs[[2L]]
  name <- find(app, sprintf(".//*[%s]", class_is("prexp-app-name")))
  expect_identical(xml2::xml_name(name), "span")
  expect_identical(xml2::xml_text(name), "Prescription Explorer")
  tabs <- find(app, ".//ul[@id='tab']")
  expect_identical(xml2::xml_attr(find(tabs, "./li/a"), "data-value"), app_tabs)
  expect_no_match(xml2::xml_attr(tabs, "class"), "nav-underline", fixed = TRUE)
  expect_length(find(app, ".//button"), 0L)
  expect_length(find(app, sprintf(".//*[%s]", class_is("collapse"))), 0L)
  # The window's title is still the app's
  expect_match(rendered$head, "<title>Prescription Explorer</title>", fixed = TRUE)
})

test_that("navbar.js gives the header the site's behaviour, at the site's widths", {
  www <- system.file("app", "www", package = "prexp")
  js <- paste(readLines(file.path(www, "navbar.js")), collapse = "\n")
  css <- paste(readLines(file.path(www, "prexp.css")), collapse = "\n")
  # The site's background once the page has scrolled 50 px, and the page's
  # colour before that, from the first pixel
  expect_match(js, "var SCROLLED = 50;", fixed = TRUE)
  expect_match(
    js, "header.classList.toggle('kat-scrolled', window.scrollY > SCROLLED)", fixed = TRUE
  )
  expect_match(css, ".kat-navbar.kat-scrolled::before {", fixed = TRUE)
  expect_match(js, "header.classList.toggle('kat-moved', window.scrollY > 0)", fixed = TRUE)
  expect_match(
    css, ".kat-navbar.kat-moved::before {\n  background: var(--prexp-bg);\n}", fixed = TRUE
  )
  # Where both apply, the scrolled background, which comes later
  expect_lt(
    regexpr(".kat-navbar.kat-moved::before {", css, fixed = TRUE),
    regexpr(".kat-navbar.kat-scrolled::before {", css, fixed = TRUE)
  )
  # The drawer below 900 px, in the script as in the stylesheet; it says
  # whether it is open, and Escape closes it
  expect_match(js, "var DRAWER = 900;", fixed = TRUE)
  expect_match(css, "@media (max-width: 900px) {", fixed = TRUE)
  expect_match(js, "button.setAttribute('aria-expanded', 'true')", fixed = TRUE)
  expect_match(js, "button.setAttribute('aria-expanded', 'false')", fixed = TRUE)
  expect_match(js, "e.key === 'Escape' && isOpen()", fixed = TRUE)
})

test_that("the tabs are the page's main landmark, and each tab has an h1", {
  page <- htmltools::renderTags(app_ui(NULL))$html
  count <- function(pattern) lengths(regmatches(page, gregexpr(pattern, page, perl = TRUE)))
  expect_identical(count("role=\"main\""), 1L)
  expect_identical(count("<div class=\"tab-content[^\"]*\"[^>]*role=\"main\""), 1L)
  # The header comes before the main landmark and the footer after it, so
  # neither is inside it
  main_at <- regexpr("role=\"main\"", page)
  expect_lt(regexpr("</header>", page), main_at)
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
    "count in national totals but cannot be searched as practices", "(under 0.1% of",
    "Actual cost changed method in April 2024", "about a third of items",
    "reorganised in April 2026, from 42 to 36", "keeps its old ICB, which no longer exists"
  )
  for (limit in limits) {
    expect_match(about, limit, fixed = TRUE)
  }
  # Actual cost comes after the discount, so not every cost is a list price
  expect_no_match(about, "list prices before discounts", fixed = TRUE)
  # A prescriber that stopped before April 2026 keeps an ICB that no longer
  # exists, so not every ICB is today's
  expect_no_match(about, "shown in today", fixed = TRUE)
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

test_that("the theme is in the brand's fonts, square, and fetches no font itself", {
  theme <- prexp_theme()
  vars <- bslib::bs_get_variables(theme, c(
    "font-family-base", "font-family-sans-serif", "font-family-monospace", "navbar-bg",
    "border-radius", "card-border-radius", "headings-font-weight", "font-weight-bold",
    "bslib-enable-shadows"
  ))
  expect_identical(unname(vars[["font-family-base"]]), "var(--bs-font-sans-serif)")
  # Sass writes the names in double quotes
  expect_match(vars[["font-family-sans-serif"]], "^\"IBM Plex Sans\", \"Segoe UI\", system-ui")
  expect_match(vars[["font-family-monospace"]], "^\"IBM Plex Mono\", Consolas, monospace")
  expect_no_match(vars[["font-family-monospace"]], "Source Code Pro", fixed = TRUE)
  # No colour for the navbar: the header draws its own, from the tokens
  # (prexp.css)
  expect_true(is.na(vars[["navbar-bg"]]) || identical(unname(vars[["navbar-bg"]]), "null"))
  # Square corners, no shadows, weights up to the font's 600
  expect_identical(unname(vars[c("border-radius", "card-border-radius")]), c("0", "0"))
  expect_identical(unname(vars[c("headings-font-weight", "font-weight-bold")]), c("600", "600"))
  expect_identical(unname(vars[["bslib-enable-shadows"]]), "false")
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
  # No workers here: test-workers.R tests them, and their connections would count
  app <- run_app(port = httpuv::randomPort(), workers = 0L, launch.browser = FALSE)
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
  app <- run_app(port = httpuv::randomPort(), workers = 0L, launch.browser = FALSE)
  expect_error(shiny::runApp(app, quiet = TRUE), class = "prexp_writable_login")
})

test_that("a window that cannot be fetched is fetched again in a while", {
  local_test_db("app")
  closed <- db_connect("app", dbname = local_fixture_db())
  DBI::dbDisconnect(closed)
  logged <- testthat::capture_messages(
    shiny::testServer(app_server(closed), {
      expect_identical(output$window, "Data window unavailable")
      session$elapse(window_retry_ms)
      expect_identical(output$window, "Data window unavailable")
    })
  )
  expect_length(grep("The data window could not be fetched", logged, fixed = TRUE), 2L)
})

test_that("run_app() starts and stops the workers, and gives every session one cache of 200 MB", {
  dbname <- local_fixture_db()
  local_test_db("app", dbname = dbname)
  withr::local_envvar(PREXP_DB_NAME = dbname, PREXP_LOG = "off")
  withr::local_options(shiny.sanitize.errors = NULL)
  calls <- character()
  caches <- list()
  local_mocked_bindings(
    start_workers = function(n = 2L, ...) {
      calls <<- c(calls, paste("start", n))
      invisible(n)
    },
    stop_workers = function() {
      calls <<- c(calls, "stop")
      invisible(NULL)
    },
    from_source = function() FALSE,
    app_server = function(con, cache = NULL) {
      caches <<- c(caches, list(cache))
      function(input, output, session) NULL
    }
  )
  app <- run_app(port = httpuv::randomPort(), launch.browser = FALSE)
  later::later(function() {
    # Two sessions
    server <- app$serverFuncSource()
    for (i in 1:2) server(list(), list(), list())
    shiny::stopApp()
  }, 0.5)
  shiny::runApp(app, quiet = TRUE)
  expect_identical(calls, c("start 2", "stop"))
  expect_length(caches, 2L)
  expect_true(identical(caches[[1]], caches[[2]]))
  expect_identical(caches[[1]]$info()$max_size, 200 * 1024^2)
})

test_that("run from its source, the app starts no workers, which could not load it", {
  expect_identical(from_source(), pkgload::is_dev_package("prexp"))
})

test_that("a view pinned on its tab is listed on the Report tab", {
  app <- fixture_app()
  chemical <- id_of(app, "chemical", "0212000B0")
  local_mocked_bindings(showNotification = function(ui, ...) invisible(NULL), .package = "shiny")
  shiny::testServer(app_server(app), {
    expect_match(output$`report-items`$html, "Nothing is pinned yet.", fixed = TRUE)
    session$setInputs(`drug-search-query` = "atorva")
    session$elapse(400)
    session$setInputs(`drug-search-pick` = paste0("chemical:", chemical))
    session$setInputs(`drug-pin` = structure(1L, class = "shinyActionButtonValue"))
    title <- paste("Atorvastatin", "items", "Oct 2025 to Sep 2026", sep = " \u00b7 ")
    expect_match(output$`report-items`$html, title, fixed = TRUE)
    expect_match(output$`report-count`$html, ">1/15<", fixed = TRUE)
  })
})
