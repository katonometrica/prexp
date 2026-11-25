# The shareable link (P5-03): what a bookmark keeps, what opening one puts
# back (the report clamped to the window, a view's selections, each subject
# as the database names it), the search's preset, and the Copy link button
# and the script behind it. The browser's round trip is tested in P6-01.

link_window <- tibble::tibble(
  first_month = 202510L, last_month = 202609L, months = 12L, loaded_at = Sys.time()
)

link_drug <- list(
  view = "drug",
  params = list(
    level = "chemical", id = 57L, code = "0212000B0", label = "Atorvastatin",
    months = c(202601L, 202609L), measure = "nic"
  )
)

# The database's subjects, as fetch_subject() gives them by code
link_subjects <- tibble::tibble(
  kind = c("chemical", "practice", "presentation", "chemical"),
  id = c(57L, 12L, 300L, 981L),
  code = c("0212000B0", "N81655", "0212000B0AAABAB", "0407010H0"),
  name = c("Atorvastatin", "THE SURGERY", "Atorvastatin 20mg tablets", "Paracetamol")
)
link_subject <- function(kind, code) {
  link_subjects[link_subjects$kind == kind & link_subjects$code == code, c("id", "code", "name")]
}

link_report <- function() {
  spec <- report_add(new_report(), "drug", link_drug$params)
  spec <- report_add(spec, "practice", list(
    id = 12L, code = "N81655", label = "THE SURGERY", months = c(202510L, 202609L),
    measure = "items"
  ))
  report_set_note(spec, 1L, "Statins rose in winter.")
}

test_that("a bookmark keeps the report and the last view's selections, each as a report's link", {
  expect_identical(link_values(new_report()), list())
  spec <- link_report()
  values <- link_values(spec, link_drug)
  expect_identical(names(values), c("report", "view"))
  expect_identical(decode_report(values$report), spec)
  view <- decode_report(values$view)
  expect_length(view$items, 1L)
  expect_identical(view$items[[1]]$params, link_drug$params)
  # A name with a tab, as one presentation's has, is kept without it
  tabbed <- link_drug
  tabbed$params$label <- "Atorvastatin\t"
  expect_identical(
    decode_report(link_values(new_report(), tabbed)$view)$items[[1]]$params$label, "Atorvastatin"
  )
  # A view the report would refuse is left out, not made into a bad link
  odd <- link_drug
  odd$params$measure <- "total_quantity"
  expect_identical(link_values(new_report(), odd), list())
})

test_that("opening a link puts the report back clamped to the window, and the view's selections", {
  spec <- link_report()
  values <- link_values(spec, link_drug)
  restored <- link_restore(values, link_window, link_subject)
  expect_identical(restored$report, spec)
  expect_identical(restored$view$params, link_drug$params)
  expect_identical(restored$refused, character())
  expect_identical(link_restore_message(restored), "Opened the report from the link: 2 items.")
  # A window that has moved on: the months it no longer holds are moved into
  # it, and the items marked
  later <- tibble::tibble(first_month = 202602L, last_month = 202701L)
  moved <- link_restore(values, later, link_subject)
  expect_identical(moved$report$items[[1]]$params$months, c(202602L, 202609L))
  expect_true(moved$report$items[[1]]$clamped)
  expect_identical(moved$view$params$months, c(202602L, 202609L))
  expect_identical(
    link_restore_message(moved),
    "Opened the report from the link: 2 items, 2 of them with months moved into the data window."
  )
  one <- link_restore(
    list(report = encode_report(report_remove(spec, 2L))), link_window, link_subject
  )
  expect_identical(link_restore_message(one), "Opened the report from the link: 1 item.")
  # Nothing to restore, nothing said
  expect_identical(link_restore(list(), link_window, link_subject)$refused, character())
  expect_null(link_restore_message(link_restore(list(), link_window, link_subject)))
})

test_that("a link that is not what this app writes is refused, part by part, and said", {
  values <- link_values(link_report(), link_drug)
  cut <- list(report = substr(values$report, 1L, 40L), view = values$view)
  restored <- link_restore(cut, link_window, link_subject)
  expect_null(restored$report)
  expect_identical(restored$view$params, link_drug$params)
  expect_identical(restored$refused, c(report = "unread"))
  expect_identical(
    link_restore_message(restored), "The link could not be read whole: it may have been cut short."
  )
  # A view that is a report of two items, or values of the wrong kind
  two <- list(view = values$report)
  expect_identical(link_restore(two, link_window, link_subject)$refused, c(view = "unread"))
  odd <- list(report = list(1, 2), view = 3)
  expect_identical(
    link_restore(odd, link_window, link_subject)$refused,
    c(report = "unread", view = "unread")
  )
})

test_that("a link cut short at its end, whose last value Shiny drops, is refused and said", {
  values <- link_values(link_report(), link_drug)
  search <- paste0(
    "?_inputs_&tab=%22report%22&_values_&view=%22", values$view, "%22&report=%22",
    values$report, "%22"
  )
  cut <- substr(search, 1L, nchar(search) - 3L)
  sent <- link_sent(cut)
  expect_identical(sent, c("_inputs_", "tab", "_values_", "view", "report"))
  # Shiny cannot read the report, cut, as JSON, and drops it before onRestore()
  dropped <- suppressWarnings(shiny:::RestoreContext$new(cut))$values
  expect_identical(sort(ls(dropped)), "view")
  restored <- link_restore(dropped, link_window, link_subject, sent)
  expect_null(restored$report)
  expect_identical(restored$view$params, link_drug$params)
  expect_identical(restored$refused, c(report = "unread"))
  expect_identical(
    link_restore_message(restored), "The link could not be read whole: it may have been cut short."
  )
  # Whole, or a name not sent: nothing refused
  whole <- shiny:::RestoreContext$new(search)$values
  expect_identical(
    link_restore(whole, link_window, link_subject, link_sent(search))$refused, character()
  )
  expect_identical(
    link_restore(list(view = values$view), link_window, link_subject, c("tab", "view"))$refused,
    character()
  )
  expect_identical(link_sent(NULL), character())
  expect_identical(link_sent(""), character())
})

test_that("opening a link takes each subject's id and name from the database, by its code", {
  # Atorvastatin's code under another drug's id and name, as a forged link
  # could give it, and a code the data does not hold
  forged <- link_drug
  forged$params$id <- 981L
  forged$params$label <- "Paracetamol"
  gone <- forged$params
  gone$code <- "0499999Z0"
  spec <- report_add(report_add(new_report(), "drug", forged$params), "drug", gone)
  values <- link_values(spec, forged)
  restored <- link_restore(values, link_window, link_subject)
  expect_length(restored$report$items, 1L)
  expect_identical(restored$report$items[[1]]$params, link_drug$params)
  expect_identical(restored$report$items[[1]]$id, 1L)
  expect_identical(restored$report$next_id, 3L)
  expect_identical(restored$view$params, link_drug$params)
  expect_identical(restored$left_out, 1L)
  expect_identical(link_restore_message(restored), paste(
    "Opened the report from the link: 1 item.",
    "1 item was left out: the data does not hold its drug or practice."
  ))
  # So the view's search is handed the database's name, not the link's
  expect_identical(search_option(restored$view)$label, "Atorvastatin")
  # Selections whose subject the data does not hold: left out, and said
  elsewhere <- list(view = link_values(new_report(), list(view = "drug", params = gone))$view)
  restored <- link_restore(elsewhere, link_window, link_subject)
  expect_null(restored$view)
  expect_true(restored$view_left_out)
  expect_identical(
    link_restore_message(restored),
    "The view's selections were left out: the data does not hold their subject."
  )
  # Every item left out: no report
  none <- list(report = encode_report(report_add(new_report(), "drug", gone)))
  restored <- link_restore(none, link_window, link_subject)
  expect_null(restored$report)
  expect_identical(restored$left_out, 1L)
  two <- list(report = encode_report(
    report_add(report_add(new_report(), "drug", gone), "region", gone)
  ))
  expect_identical(
    link_restore_message(link_restore(two, link_window, link_subject)),
    "2 items were left out: the data does not hold their drugs or practices."
  )
  # A lookup that fails refuses the part, and says so
  failing <- function(kind, code) stop("no connection")
  expect_message(
    restored <- link_restore(values, link_window, failing), "could not be looked up"
  )
  expect_identical(restored$refused, c(report = "unfetched", view = "unfetched"))
  expect_identical(
    link_restore_message(restored),
    "The link could not be opened whole: the data could not be fetched. Open it again."
  )
})

test_that("a bookmark writes the report and the selections, and no input but the tab", {
  spec <- link_report()
  state <- new.env()
  state$input <- list(tab = "report", `report-copy` = 1L, `drug-from` = "202601")
  state$exclude <- "kept-out"
  state$values <- list()
  values <- link_bookmark(state, spec, link_drug)
  expect_setequal(state$exclude, c("kept-out", "report-copy", "drug-from"))
  expect_identical(state$values, values)
  expect_identical(decode_report(state$values$report), spec)
  expect_identical(decode_report(state$values$view)$items[[1]]$params, link_drug$params)
  # No selections to keep: the report only
  state$values <- list()
  expect_identical(names(link_bookmark(state, spec, NULL)), "report")
})

test_that("a link keeps the view last shown's selections, or else those its session opened with", {
  restored <- link_restore(link_values(link_report(), link_drug), link_window, link_subject)
  kept <- link_values(new_report(), link_view(NULL, NULL, restored$view))
  expect_identical(decode_report(kept$view)$items[[1]]$params, link_drug$params)
  # A view shown since: its own selections, or none when it shows nothing
  practice <- list(view = "practice", params = link_report()$items[[2]]$params)
  expect_identical(link_view("practice", practice, restored$view), practice)
  expect_null(link_view("practice", NULL, restored$view))
  expect_null(link_view(NULL, NULL, NULL))
})

test_that("opening a link fills the report and the view, and says so, as a warning when refused", {
  notes <- list()
  status <- list()
  tabs <- character()
  local_mocked_bindings(
    nav_select = function(id, selected = NULL, session) tabs <<- c(tabs, selected),
    .package = "bslib"
  )
  session <- list(
    sendNotification = function(type, message) notes[[length(notes) + 1L]] <<- message,
    sendCustomMessage = function(type, message) {
      status[[length(status) + 1L]] <<- list(type = type, message = message)
    }
  )
  report <- shiny::reactiveVal(new_report())
  restoring <- list(
    drug = shiny::reactiveVal(NULL), practice = shiny::reactiveVal(NULL),
    region = shiny::reactiveVal(NULL)
  )
  values <- link_values(link_report(), link_drug)
  sent <- c("_inputs_", "tab", "_values_", "view", "report")
  link_open(values, link_window, link_subject, sent, report, restoring, session)
  expect_identical(shiny::isolate(report()), link_report())
  expect_identical(shiny::isolate(restoring$drug())$params, link_drug$params)
  expect_null(shiny::isolate(restoring$practice()))
  expect_identical(notes[[1]]$type, "message")
  expect_identical(
    status[[1]], list(type = "prexp-status", message = "Opened the report from the link: 2 items.")
  )
  expect_identical(tabs, character())
  # A report that cannot be read: the user is warned, and the log names it
  cut <- list(report = substr(values$report, 1L, 40L))
  expect_message(
    link_open(cut, link_window, link_subject, "report", report, restoring, session),
    "A link was refused: report"
  )
  expect_identical(notes[[2]]$type, "warning")
  expect_identical(
    status[[2]]$message, "The link could not be read whole: it may have been cut short."
  )
  # A link made with nothing pinned opens on its view's tab, and says nothing
  link_open(list(view = values$view), link_window, link_subject, "view", report, restoring, session)
  expect_identical(tabs, "drug")
  expect_length(notes, 2L)
  # Nothing in the link: nothing done or said
  link_open(list(), link_window, link_subject, character(), report, restoring, session)
  expect_length(notes, 2L)
})

test_that("a link opened while the window cannot be fetched waits for it", {
  window <- shiny::reactiveVal(NULL)
  opened <- list()
  shiny::testServer(
    function(input, output, session) {
      when_window(window, function(w) opened[[length(opened) + 1L]] <<- w)
    },
    {
      session$flushReact()
      expect_length(opened, 0L)
      window(link_window)
      session$flushReact()
      expect_identical(opened, list(link_window))
      # Once only
      window(tibble::tibble(first_month = 202511L, last_month = 202610L))
      session$flushReact()
      expect_length(opened, 1L)
    }
  )
  # With the window: at once
  now <- list()
  when_window(shiny::reactiveVal(link_window), function(w) now[[1]] <<- w)
  expect_identical(now, list(link_window))
})

test_that("an item's subject is the option its view's search would offer", {
  expect_identical(
    search_option(link_drug),
    list(
      value = "chemical:57", label = "Atorvastatin", meta = "Chemical substance \u00b7 0212000B0",
      level = "chemical", id = 57L, code = "0212000B0"
    )
  )
  practice <- link_report()$items[[2]]
  practice$params$code <- NA_character_
  expect_identical(search_option(practice)[c("value", "meta", "level")], list(
    value = "practice:12", meta = "", level = "practice"
  ))
  presentation <- list(view = "region", params = list(
    level = "presentation", id = 300L, code = "0212000B0AAABAB",
    label = "Atorvastatin 20mg tablets",
    months = c(202510L, 202609L), measure = "total_quantity"
  ))
  expect_identical(search_option(presentation)$meta, "Presentation \u00b7 0212000B0AAABAB")
})

test_that("a preset puts its option in the search's picks and hands it to the box", {
  sent <- list()
  local_mocked_bindings(send_search_select = function(session, option) {
    sent[[length(sent) + 1L]] <<- list(id = session$ns("pick"), option = option)
  })
  preset <- shiny::reactiveVal(NULL)
  option <- search_option(link_drug)
  shiny::testServer(
    mod_search_server,
    args = list(fetch = function(q) stop("no search"), type = "drug", preset = preset),
    {
      expect_length(sent, 0L)
      preset(option)
      session$flushReact()
      expect_length(sent, 1L)
      expect_identical(sent[[1]]$option, option)
      # Now a pick, as if the box had offered it
      session$setInputs(pick = "chemical:57")
      expect_identical(session$returned(), list(
        type = "drug", id = 57L, label = "Atorvastatin", level = "chemical", code = "0212000B0"
      ))
    }
  )
})

test_that("a preset's option goes to its box, as the message search.js listens for", {
  messages <- list()
  session <- list(
    ns = shiny::NS("drug-search"),
    sendCustomMessage = function(type, message) {
      messages[[length(messages) + 1L]] <<- list(type = type, message = message)
    }
  )
  option <- search_option(link_drug)
  send_search_select(session, option)
  expect_identical(messages, list(list(
    type = "prexp-search-select", message = list(id = "drug-search-pick", option = option)
  )))
})

test_that("a view puts back a link's months and measure when its controls are drawn", {
  local_mocked_bindings(send_search_select = function(session, option) invisible(NULL))
  restore <- shiny::reactiveVal(NULL)
  fetches <- list(
    search_drugs = function(q) stop("no search"),
    drug_series = function(...) stop("not here"),
    drug_presentations = function(...) stop("not here")
  )
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fetches, window = shiny::reactive(link_window), restore = restore),
    {
      restore(link_drug)
      session$flushReact()
      months <- output$months_ui$html
      expect_match(months, "<option value=\"202601\" selected>", fixed = TRUE)
      expect_match(months, "<option value=\"202609\" selected>", fixed = TRUE)
      expect_match(output$measure_ui$html, "value=\"nic\" checked", fixed = TRUE)
    }
  )
})

test_that("a view not yet shown fetches with the link's months and measure", {
  local_mocked_bindings(send_search_select = function(session, option) invisible(NULL))
  restore <- shiny::reactiveVal(NULL)
  asked <- list()
  fetches <- list(
    search_drugs = function(q) stop("no search"),
    drug_series = function(level, id, months, measure) {
      asked[[length(asked) + 1L]] <<- list(months = months, measure = measure)
      tibble::tibble(year_month = 202601L, measure = measure, value = 1, practices = 1L)
    },
    drug_presentations = function(...) stop("not here")
  )
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fetches, window = shiny::reactive(link_window), restore = restore),
    {
      restore(link_drug)
      session$flushReact()
      # The pick, as the box sends it; the months and measure controls are
      # not drawn in the browser yet, so they send nothing
      session$setInputs(`search-pick` = "chemical:57")
      expect_identical(session$returned()$params$months, c(202601L, 202609L))
      expect_identical(session$returned()$params$measure, "nic")
      expect_gt(length(asked), 0L)
      for (call in asked) {
        expect_identical(call, list(months = c(202601L, 202609L), measure = "nic"))
      }
      # Once the controls send their values, they rule
      session$setInputs(from = "202603", to = "202609", measure = "items")
      expect_identical(session$returned()$params$months, c(202603L, 202609L))
      expect_identical(session$returned()$params$measure, "items")
    }
  )
})

test_that("the Practice and Region views put back a link's months and measure too", {
  local_mocked_bindings(send_search_select = function(session, option) invisible(NULL))
  practice <- list(view = "practice", params = list(
    id = 12L, code = "N81655", label = "THE SURGERY", months = c(202601L, 202609L),
    measure = "nic"
  ))
  region <- link_drug
  region$view <- "region"
  views <- list(
    list(server = mod_practice_server, item = practice, fetches = list(
      search_practices = function(q) stop("no search"),
      practice_profile = function(...) stop("not here"),
      practice_series = function(...) stop("not here"),
      practice_top_drugs = function(...) stop("not here")
    )),
    list(server = mod_region_server, item = region, fetches = list(
      search_drugs = function(q) stop("no search"),
      region_comparison = function(...) stop("not here"),
      regions = function() stop("not here")
    ))
  )
  for (view in views) {
    restore <- shiny::reactiveVal(NULL)
    shiny::testServer(
      view$server,
      args = list(
        fetches = view$fetches, window = shiny::reactive(link_window), restore = restore
      ),
      {
        restore(view$item)
        session$flushReact()
        months <- output$months_ui$html
        expect_match(months, "<option value=\"202601\" selected>", fixed = TRUE)
        expect_match(months, "<option value=\"202609\" selected>", fixed = TRUE)
        expect_match(output$measure_ui$html, "value=\"nic\" checked", fixed = TRUE)
      }
    )
  }
})

test_that("a presentation's quantity is put back once its pick allows it", {
  local_mocked_bindings(send_search_select = function(session, option) invisible(NULL))
  restore <- shiny::reactiveVal(NULL)
  presentation <- list(view = "drug", params = list(
    level = "presentation", id = 300L, code = "0212000B0AAABAB",
    label = "Atorvastatin 20mg tablets",
    months = c(202510L, 202609L), measure = "total_quantity"
  ))
  fetches <- list(
    search_drugs = function(q) stop("no search"),
    drug_series = function(...) stop("not here"),
    drug_presentations = function(...) stop("not here")
  )
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fetches, window = shiny::reactive(link_window), restore = restore),
    {
      restore(presentation)
      session$flushReact()
      # Before the pick, the measures are a chemical's: no quantity yet
      expect_no_match(output$measure_ui$html, "total_quantity", fixed = TRUE)
      session$setInputs(`search-pick` = "presentation:300")
      expect_match(output$measure_ui$html, "value=\"total_quantity\" checked", fixed = TRUE)
      expect_identical(session$returned(), NULL)
    }
  )
})

test_that("Copy link makes a link on a click, not for a value a link gives the button", {
  made <- 0L
  shiny::testServer(
    mod_report_server,
    args = list(report = shiny::reactiveVal(new_report())),
    {
      # The mock session cannot bookmark: count the calls instead
      root <- session$rootScope()
      root$doBookmark <- function() made <<- made + 1L
      # The value a link's `_inputs_` gives the button, sent as the page opens
      session$setInputs(copy = 1L)
      expect_identical(made, 0L)
      session$setInputs(copy = 2L)
      expect_identical(made, 1L)
    }
  )
})

test_that("the Report tab has the Copy link button and its box, which report.js fills", {
  ui <- htmltools::renderTags(mod_report_ui("report"))$html
  expect_match(ui, "id=\"report-copy\"", fixed = TRUE)
  expect_match(ui, ">Copy link</span></button>", fixed = TRUE)
  box <- regmatches(ui, regexpr("<div[^>]*class=\"prexp-link-box\"[^>]*>", ui))
  expect_match(box, "hidden", fixed = TRUE)
  link <- regmatches(ui, regexpr("<input[^>]*data-report-link[^>]*>", ui))
  expect_match(link, "readonly", fixed = TRUE)
  js <- paste(readLines(system.file("app", "www", "report.js", package = "prexp")), collapse = "\n")
  for (part in c(
    "addCustomMessageHandler('prexp-copy-link'", "navigator.clipboard.writeText",
    "input[data-report-link]", "[data-report-link-label]", "isSecureContext",
    "function hideLink()", "event.name === 'tab'"
  )) {
    expect_match(js, part, fixed = TRUE, label = part)
  }
  search_js <- system.file("app", "www", "search.js", package = "prexp")
  search <- paste(readLines(search_js), collapse = "\n")
  expect_match(search, "addCustomMessageHandler(\"prexp-search-select\"", fixed = TRUE)
})
