# End-to-end flows (P6-01; spec section 6.2): the app as the app image runs
# it, the installed package with its background workers, on the fixture
# database, driven in Google Chrome by shinytest2. The flows assert on values
# and outputs, against the fetch functions' results, never on screenshots.
#
# Not one of the suite's test files: its name does not start with "test", so
# devtools::test() and the coverage run leave it out, and the app runs in its
# own process, where coverage could not count it anyway. It needs Chrome,
# which the ci and dev images have, and the package installed, which the
# app's workers load. CI runs it in a step of its own after the coverage run.
# By hand, in the dev container, from the package's folder (shinytest2 skips
# every flow unless NOT_CRAN is true, which CI sets):
#
#   R CMD INSTALL --no-docs .
#   NOT_CRAN=true Rscript -e 'testthat::test_file("tests/testthat/e2e-flows.R",
#     package = "prexp", load_package = "installed")'
#
# With PREXP_E2E_LOGS set to a folder, each app's log is written there, as CI
# does for the artifact of a failed run.

# The app (apps/prexp/app.R), started in its own R process on a port of its
# own, with the fixture database as its database, and stopped when the
# calling test ends
local_app <- function(name, env = parent.frame()) {
  withr::local_envvar(PREXP_E2E_DB = local_fixture_db(), .local_envir = env)
  app <- shinytest2::AppDriver$new(
    testthat::test_path("apps", "prexp"),
    name = name, width = 1400, height = 900, load_timeout = 120000, timeout = 30000,
    screenshot_args = FALSE, expect_values_screenshot_args = FALSE,
    shiny_args = list(port = httpuv::randomPort())
  )
  withr::defer(
    {
      logs <- Sys.getenv("PREXP_E2E_LOGS")
      if (nzchar(logs)) {
        dir.create(logs, showWarnings = FALSE, recursive = TRUE)
        writeLines(format(app$get_logs()), file.path(logs, paste0(name, ".log")))
      }
      app$stop()
    },
    envir = env
  )
  app
}

# The fixture's twelve months, as the app's window
window_span <- function(con) {
  window <- fetch_window(con)
  c(window$first_month, window$last_month)
}

# Types text into the element with the focus, key by key, as a person would
type_keys <- function(app, text) {
  session <- app$get_chromote_session()
  for (key in strsplit(text, "")[[1]]) {
    session$Input$dispatchKeyEvent(type = "keyDown", key = key, text = key)
    session$Input$dispatchKeyEvent(type = "keyUp", key = key)
  }
}

# Presses a key that types no character, with its modifiers (2 Ctrl, 8
# Shift), as a keyboard sends it: Chrome acts on it by its key code
press_key <- function(app, key, code, keycode, modifiers = 0L) {
  session <- app$get_chromote_session()
  for (type in c("rawKeyDown", "keyUp")) {
    session$Input$dispatchKeyEvent(
      type = type, key = key, code = code, windowsVirtualKeyCode = keycode,
      nativeVirtualKeyCode = keycode, modifiers = modifiers
    )
  }
}

# Presses Enter, which a button or a link acts on by the character it types,
# a carriage return
press_enter <- function(app) {
  session <- app$get_chromote_session()
  session$Input$dispatchKeyEvent(
    type = "keyDown", key = "Enter", code = "Enter", windowsVirtualKeyCode = 13L,
    nativeVirtualKeyCode = 13L, text = "\r"
  )
  session$Input$dispatchKeyEvent(
    type = "keyUp", key = "Enter", code = "Enter", windowsVirtualKeyCode = 13L,
    nativeVirtualKeyCode = 13L
  )
}

# Puts text on the browser's clipboard as a person copies it: Ctrl+C in a
# text box of its own, removed after
copy_text <- function(app, text) {
  app$run_js(sprintf(paste(
    "var copy = document.createElement('textarea'); copy.value = %s;",
    "document.body.appendChild(copy); copy.focus(); copy.select();"
  ), jsonlite::toJSON(text, auto_unbox = TRUE)))
  press_key(app, "c", "KeyC", 67L, 2L)
  app$run_js("document.activeElement.remove();")
}

# Picks a drug or a practice with a view's search box: types the text, over
# a pick the box holds too, waits for the server's matches in the box's own
# list, and clicks the option with the value given ("chemical:<id>",
# "practice:<id>")
search_pick <- function(app, view, text, value) {
  input <- paste0(view, "-search-pick")
  box <- sprintf("document.getElementById('%s').selectize", input)
  # The pick the box holds, if any: the wait below is for the new one
  before <- app$get_value(input = input)
  app$run_js(paste0(box, ".focus();"))
  type_keys(app, text)
  # The box took the keys
  expect_identical(app$get_js(paste0(box, ".$control_input.val()")), text)
  option <- sprintf("%s.$dropdown[0].querySelector(\"[data-value='%s']\")", box, value)
  app$wait_for_js(paste(option, "!== null"))
  app$run_js(paste0(option, ".click();"))
  app$wait_for_value(input = input, ignore = list(NULL, "", before))
  app$wait_for_idle()
  expect_identical(app$get_value(input = input), value)
}

# Presses Tab until the element the selector names has the focus, as a
# keyboard moves through the page: whether it got there
tab_to <- function(app, selector, presses = 12L) {
  at <- sprintf(
    "document.activeElement.matches(%s)", jsonlite::toJSON(selector, auto_unbox = TRUE)
  )
  for (i in seq_len(presses)) {
    press_key(app, "Tab", "Tab", 9L)
    if (isTRUE(app$get_js(at))) {
      return(TRUE)
    }
  }
  FALSE
}

# Opens a tab of the app
open_tab <- function(app, tab) {
  app$set_inputs(tab = tab, wait_ = FALSE)
  app$wait_for_idle()
}

# The text of a table's cells as the page shows them: a data frame of
# character columns, one row per row shown
table_cells <- function(app, selector) {
  rows <- app$get_js(sprintf(paste(
    "Array.from(document.querySelectorAll('%s .rt-tbody .rt-tr:not(.-padRow)'))",
    ".map(function (row) { return Array.from(row.querySelectorAll('.rt-td'))",
    ".map(function (cell) { return cell.innerText.trim(); }); })"
  ), selector))
  as.data.frame(do.call(rbind, lapply(rows, unlist)))
}

# Types a note into an item's box on the Report tab, then leaves the box,
# which sends it at once
type_note <- function(app, id, text) {
  app$run_js(sprintf("document.querySelector(\"textarea[data-report-id='%d']\").focus();", id))
  app$get_chromote_session()$Input$insertText(text = text)
  app$run_js("document.activeElement.blur();")
  app$wait_for_idle()
}

# The Report tab's items as the page shows them: their titles and notes
report_titles <- "Array.from(document.querySelectorAll('#report-items h2')).map(function (h) {
  return h.innerText; })"
report_notes <- "Array.from(document.querySelectorAll('#report-items textarea')).map(function (t) {
  return t.value; })"

# A new tab in the app's browser, opened on a URL: a session of its own, as
# when someone pastes a link. Closed when the calling test ends.
local_tab <- function(app, url, env = parent.frame()) {
  tab <- app$get_chromote_session()$new_session()
  withr::defer(tab$close(), envir = env)
  tab$Page$navigate(url)
  tab
}

# The value of a JavaScript expression in a tab
tab_js <- function(tab, js) {
  tab$Runtime$evaluate(js, returnByValue = TRUE)$result$value
}

# Opens the app's page again, as a reload does, and waits for the new page.
# The old one is marked first: both answer alike until the new one comes,
# and a page being replaced may not answer at all, so it is asked again.
reload_page <- function(app, timeout = 30) {
  app$run_js("window.e2eOldPage = true; window.location.reload();")
  ready <- paste(
    "window.e2eOldPage === undefined && document.readyState === 'complete' &&",
    "document.getElementById('prexp-theme-toggle') !== null"
  )
  deadline <- Sys.time() + timeout
  while (!isTRUE(tryCatch(app$get_js(ready), error = function(e) FALSE))) {
    if (Sys.time() > deadline) {
      stop("Timed out waiting for the page to open again.", call. = FALSE)
    }
    Sys.sleep(0.2)
  }
  invisible(app)
}

# Waits until a JavaScript condition holds in a tab
wait_tab <- function(tab, js, timeout = 30) {
  deadline <- Sys.time() + timeout
  while (!isTRUE(tab_js(tab, js))) {
    if (Sys.time() > deadline) {
      stop("Timed out waiting for: ", js, call. = FALSE)
    }
    Sys.sleep(0.2)
  }
  invisible(TRUE)
}

# A drug's regions as the Region view and the export list them, from the
# fetches alone: the seven NHS regions largest first (ties in region order),
# one that did not prescribe it at 0, then the prescribers without a region;
# each with its share of England's total, which counts them all
region_rows <- function(con, id, span, measure) {
  rows <- fetch_region_comparison(con, "chemical", id, span, measure)
  regions <- fetch_regions(con)
  expect_identical(nrow(regions), 7L)
  value <- rows$value[match(regions$region_code, rows$region_code)]
  value[is.na(value)] <- 0
  ranked <- order(-value, regions$region_code)
  outside <- rows$value[!rows$region_code %in% regions$region_code]
  out <- data.frame(
    region = c(
      regions$region_name[ranked], rep("No region: unidentified prescribers", length(outside))
    ),
    value = c(value[ranked], outside)
  )
  out$share <- out$value / sum(rows$value)
  out
}

test_that("flow 1: a drug's monthly series, then the same in another measure", {
  con <- fixture_app()
  span <- window_span(con)
  months <- fixture_window()
  drug <- fetch_subject(con, "chemical", "0212000B0")
  app <- local_app("drug")
  search_pick(app, "drug", "atorva", paste0("chemical:", drug$id))
  expect_identical(
    app$get_text("#drug-title"), paste0(drug$name, ", ", format_month_range(span[1], span[2]))
  )
  # In each measure, the chart drawn again and the series the view offers as
  # CSV: the fetch's, for every month of the window, 0 for a month without one
  for (measure in c("items", "nic")) {
    if (measure != "items") {
      app$set_inputs(`drug-measure` = measure)
      app$wait_for_idle()
    }
    rows <- fetch_drug_series(con, "chemical", drug$id, span, measure)
    value <- rows$value[match(months, rows$year_month)]
    value[is.na(value)] <- 0
    # The chart's points, one a month, each with its month's value as its tooltip
    tips <- app$get_js(paste(
      "Array.from(document.querySelectorAll('#drug-chart svg [data-id]'))",
      ".map(function (point) { return point.getAttribute('title'); })"
    ))
    expect_identical(unlist(tips), paste0(format_month(months), ": ", value_words(value, measure)))
    shown <- utils::read.csv(app$get_download("drug-csv"))
    expect_identical(unique(shown$measure), measure)
    expect_identical(shown$year_month, months)
    expect_equal(shown$value, value)
  }
  # Its presentations, most items first: the whole first page, of ten
  listed <- fetch_drug_presentations(con, drug$id, span)
  listed <- utils::head(listed[order(-listed$items), ], 10L)
  expect_gt(nrow(listed), 0L)
  shown <- table_cells(app, "#drug-presentations")
  expect_identical(nrow(shown), nrow(listed))
  expect_identical(shown[[2]], listed$bnf_code)
  expect_identical(shown[[4]], format_measure(listed$items, "items"))
  expect_identical(shown[[7]], format_measure(listed$nic, "nic"))
  # Another drug, typed straight over the first: a pick fills the box, and
  # typing over it starts a new search (flow 6 has the box's other cases)
  other <- fetch_search_drugs(con, "metformin")
  other <- other[other$level == "chemical", ]
  expect_gt(nrow(other), 0L)
  other <- other[1L, ]
  search_pick(app, "drug", "metformin", paste0("chemical:", other$id))
  expect_identical(
    app$get_text("#drug-title"),
    paste0(other$name, ", ", format_month_range(span[1], span[2]))
  )
})

test_that("flow 2: a practice's top drugs, page by page", {
  con <- fixture_app()
  span <- window_span(con)
  practice <- fetch_subject(con, "practice", "N81655")
  # Three pages to turn, and drugs after them, so Next stays on
  ranked <- fetch_practice_top_drugs(con, practice$id, span, by = "items", limit = 76L)
  expect_identical(nrow(ranked), 76L)
  app <- local_app("practice")
  open_tab(app, "practice")
  search_pick(app, "practice", "N81655", paste0("practice:", practice$id))
  expect_match(app$get_text("#practice-body"), "N81655", fixed = TRUE)
  expect_true(app$get_js("document.querySelector('#practice-chart svg') !== null"))
  page <- function(first) {
    shown <- table_cells(app, "#practice-top_table")
    rows <- first + 0:24
    expect_identical(app$get_text("#practice-top_range"), paste("Drugs", first, "to", first + 24L))
    expect_identical(shown[[1]], as.character(rows))
    expect_identical(shown[[3]], ranked$bnf_code[rows])
    expect_identical(shown[[5]], format_measure(ranked$items[rows], "items"))
    expect_identical(
      app$get_js("document.getElementById('practice-previous_page').disabled"), first == 1L
    )
    # app$click() would turn the page through a disabled button too:
    # shinytest2 triggers the button's click handler with jQuery
    expect_false(app$get_js("document.getElementById('practice-next_page').disabled"))
  }
  page(1L)
  app$click("practice-next_page")
  page(26L)
  app$click("practice-next_page")
  page(51L)
  app$click("practice-previous_page")
  page(26L)
})

test_that("flow 3: a drug compared across the regions", {
  con <- fixture_app()
  span <- window_span(con)
  drug <- fetch_subject(con, "chemical", "0212000B0")
  app <- local_app("region")
  open_tab(app, "region")
  search_pick(app, "region", "atorva", paste0("chemical:", drug$id))
  expect_identical(
    app$get_text("#region-title"),
    paste0(drug$name, " by region, ", format_month_range(span[1], span[2]))
  )
  expect_true(app$get_js("document.querySelector('#region-chart svg') !== null"))
  # Drawn at about the width it is shown at, on a tab not shown at load, and
  # again for a narrower window (the SVG's viewBox is in points, 3/4 px)
  drawn_and_shown <- function() {
    unlist(app$get_js(paste(
      "(function () { var c = document.getElementById('region-chart');",
      "var box = c.querySelector('svg').viewBox.baseVal;",
      "return [box.width * 4 / 3, c.getBoundingClientRect().width]; })()"
    )))
  }
  widths <- drawn_and_shown()
  expect_lt(abs(widths[[1]] - widths[[2]]), 35)
  app$set_window_size(width = 760, height = 900)
  app$wait_for_idle(duration = 1000)
  narrow <- drawn_and_shown()
  expect_lt(narrow[[2]], widths[[2]] - 100)
  expect_lt(abs(narrow[[1]] - narrow[[2]]), 35)
  app$set_window_size(width = 1400, height = 900)
  app$wait_for_idle(duration = 1000)
  for (measure in c("items", "nic")) {
    if (measure != "items") {
      app$set_inputs(`region-measure` = measure)
      app$wait_for_idle()
    }
    want <- region_rows(con, drug$id, span, measure)
    shown <- table_cells(app, "#region-body")
    expect_identical(shown[[1]], want$region)
    expect_identical(shown[[2]], format_measure(want$value, measure))
    # Shares to one decimal, as the browser rounds them
    expect_true(all(abs(as.numeric(sub("%", "", shown[[3]], fixed = TRUE)) - 100 * want$share) <=
                      0.05 + 1e-9))
    footer <- app$get_js(paste(
      "Array.from(document.querySelectorAll('#region-body .rt-tfoot .rt-td'))",
      ".map(function (cell) { return cell.innerText.trim(); })"
    ))
    expect_identical(
      unlist(footer), c("England", format_measure(sum(want$value), measure), "100.0%")
    )
  }
})

test_that("flow 4: two views pinned with notes export to Excel", {
  con <- fixture_app()
  span <- window_span(con)
  drug <- fetch_subject(con, "chemical", "0212000B0")
  app <- local_app("export")
  search_pick(app, "drug", "atorva", paste0("chemical:", drug$id))
  app$click("drug-pin")
  open_tab(app, "region")
  search_pick(app, "region", "atorva", paste0("chemical:", drug$id))
  app$click("region-pin")
  open_tab(app, "report")
  notes <- c("Costs rose in the spring.\nCheck the 20mg tablets.", "The regions differ.")
  type_note(app, 1L, notes[1])
  type_note(app, 2L, notes[2])
  expect_identical(unlist(app$get_js(report_notes)), notes)
  titles <- unlist(app$get_js(report_titles))
  app$set_inputs(`report-format` = "xlsx")
  app$click("report-prepare")
  app$wait_for_js(
    "document.getElementById('report-export_status').innerText.indexOf('Ready') === 0",
    timeout = 120000
  )
  # The button's URL comes in a flush after the one that draws it and says
  # Ready, and get_download() reads it only once
  app$wait_for_js("document.querySelector('#report-download[href]:not([href=\"\"])') !== null")
  path <- app$get_download("report-download")
  wb <- openxlsx2::wb_load(path)
  expect_identical(
    unname(openxlsx2::wb_get_sheet_names(wb)),
    c("Report", "1 Atorvastatin", "2 Atorvastatin by region", "Methods")
  )
  # Each item's sheet: its title as the Report tab shows it, and every line
  # of its note
  for (i in 1:2) {
    column <- openxlsx2::wb_to_df(wb, sheet = i + 1L, col_names = FALSE)[[1]]
    expect_identical(column[1], titles[i])
    for (line in strsplit(notes[i], "\n", fixed = TRUE)[[1]]) {
      expect_true(any(grepl(line, column, fixed = TRUE)), label = line)
    }
  }
  # Each item's table, read by its own range (the chart's data is beside it,
  # under the same headers): every row, in order. openxlsx2 lists the tables'
  # names in lower case
  item_table <- function(sheet, name) {
    tables <- openxlsx2::wb_get_tables(wb, sheet = sheet)
    ref <- tables$tab_ref[tolower(tables$tab_name) == tolower(name)]
    expect_length(ref, 1L)
    openxlsx2::wb_to_df(wb, sheet = sheet, dims = ref)
  }
  # The presentations, most items first, at most 25
  listed <- fetch_drug_presentations(con, drug$id, span)
  listed <- utils::head(listed[order(-listed$items), ], 25L)
  expect_gt(nrow(listed), 0L)
  table <- item_table(2L, "Table1")
  expect_identical(table[["BNF code"]], listed$bnf_code)
  expect_equal(table[["Items"]], listed$items)
  expect_equal(table[["Net ingredient cost"]], listed$nic)
  # The regions as the view lists them, each with its share, then England
  want <- region_rows(con, drug$id, span, "items")
  table <- item_table(3L, "Table2")
  expect_identical(table[["Region"]], c(want$region, "England"))
  expect_equal(table[["Items"]], c(want$value, sum(want$value)))
  expect_equal(table[["Share of England"]], c(want$share, 1))
})

test_that("flow 5: the report's link opens it again in a new session", {
  con <- fixture_app()
  span <- window_span(con)
  drug <- fetch_subject(con, "chemical", "0212000B0")
  practice <- fetch_subject(con, "practice", "N81655")
  app <- local_app("link")
  search_pick(app, "drug", "atorva", paste0("chemical:", drug$id))
  app$set_inputs(`drug-measure` = "nic")
  app$wait_for_idle()
  app$click("drug-pin")
  open_tab(app, "practice")
  search_pick(app, "practice", "N81655", paste0("practice:", practice$id))
  app$click("practice-pin")
  open_tab(app, "report")
  type_note(app, 2L, "A practice to watch.\nIts costs fell.")
  titles <- unlist(app$get_js(report_titles))
  notes <- unlist(app$get_js(report_notes))
  expect_identical(notes, c("", "A practice to watch.\nIts costs fell."))
  app$click("report-copy")
  app$wait_for_js("document.querySelector('input[data-report-link]').value !== ''")
  link <- app$get_js("document.querySelector('input[data-report-link]').value")
  expect_match(link, "^http://127[.]0[.]0[.]1:[0-9]+/[?]")
  tab <- local_tab(app, link)
  status <- "(document.getElementById('prexp-status') || {}).textContent"
  wait_tab(tab, paste(status, "=== 'Opened the report from the link: 2 items.'"))
  # The status is said 100 ms after its message, which the server sends before
  # the flush that draws the items, so the items can come after it
  wait_tab(tab, "document.querySelectorAll('#report-items h2').length === 2")
  expect_identical(
    tab_js(tab, "document.querySelector('.navbar .nav-link.active').dataset.value"), "report"
  )
  expect_identical(unlist(tab_js(tab, report_titles)), titles)
  expect_identical(unlist(tab_js(tab, report_notes)), notes)
  # The link puts back the selections of the view last shown too, the
  # Practice view's: search.js selects its practice in the box, and the view
  # shows it for the link's months. The title as JSON, which quotes the
  # apostrophe in the practice's name for JavaScript.
  tab_js(tab, "document.querySelector(\".navbar .nav-link[data-value='practice']\").click()")
  title <- paste0(practice$name, ", ", format_month_range(span[1], span[2]))
  wait_tab(tab, paste(
    "(document.getElementById('practice-title') || {}).innerText ===",
    jsonlite::toJSON(title, auto_unbox = TRUE)
  ))
  expect_identical(
    tab_js(tab, "document.getElementById('practice-search-pick').selectize.getValue()"),
    paste0("practice:", practice$id)
  )
})

test_that("flow 6: typing, pasting or a phone's keyboard over a picked drug, and Backspace", {
  con <- fixture_app()
  span <- window_span(con)
  drug <- fetch_subject(con, "chemical", "0212000B0")
  app <- local_app("search")
  value <- paste0("chemical:", drug$id)
  title <- paste0(drug$name, ", ", format_month_range(span[1], span[2]))
  search_pick(app, "drug", "atorva", value)
  box <- "document.getElementById('drug-search-pick').selectize"
  # What the page sends Shiny for the box from here: nothing, while its pick
  # is typed over and put back
  app$run_js(paste(
    "window.e2eSent = []; $(document).on('shiny:inputchanged', function (e) {",
    "if (e.name === 'drug-search-pick') window.e2eSent.push(e.value); });"
  ))
  # While the text is in the box, the box holds no pick but Shiny and the
  # view keep it; leaving the box puts it back, without the search's
  # message or matches
  kept <- function(text) {
    expect_identical(app$get_js(paste0(box, ".$control_input.val()")), text)
    expect_identical(app$get_js(paste0(box, ".getValue()")), "")
    expect_identical(app$get_value(input = "drug-search-pick"), value)
    expect_identical(app$get_text("#drug-title"), title)
    app$run_js("document.activeElement.blur();")
    app$wait_for_idle()
    expect_identical(app$get_js(paste0(box, ".getValue()")), value)
    expect_identical(app$get_value(input = "drug-search-pick"), value)
    expect_identical(app$get_text("#drug-title"), title)
    expect_identical(app$get_text("#drug-search-message"), "")
    expect_identical(app$get_js(paste0("Object.keys(", box, ".options)")), list(value))
  }
  # Typed
  app$run_js(paste0(box, ".focus();"))
  type_keys(app, "zz")
  app$wait_for_idle()
  kept("zz")
  # Pasted, with Ctrl+V and with Shift+Insert, the paste of Windows and Linux
  copy_text(app, "metformin")
  for (keys in list(list("v", "KeyV", 86L, 2L), list("Insert", "Insert", 45L, 8L))) {
    app$run_js(paste0(box, ".focus();"))
    press_key(app, keys[[1]], keys[[2]], keys[[3]], keys[[4]])
    app$wait_for_idle()
    kept("metformin")
  }
  # From a phone's keyboard or dictation: text that comes with no key
  app$run_js(paste0(box, ".focus();"))
  app$get_chromote_session()$Input$insertText(text = "metf")
  app$wait_for_idle()
  kept("metf")
  # Left at once, before selectize asks for the search (50 ms after the last
  # key): the late search changes nothing
  app$run_js(paste(
    paste0("var box = ", box, ";"),
    "box.$control_input.one('input', function () {",
    "  setTimeout(function () { document.activeElement.blur(); }, 0);",
    "});",
    "box.focus();"
  ))
  type_keys(app, "z")
  Sys.sleep(0.2)
  app$wait_for_idle()
  expect_identical(app$get_js(paste0(box, ".getValue()")), value)
  expect_identical(app$get_value(input = "drug-search-pick"), value)
  expect_identical(app$get_text("#drug-title"), title)
  # Shiny was never told
  expect_length(app$get_js("window.e2eSent"), 0L)
  # Backspace still clears the pick: the view is told, and leaving the box
  # puts nothing back
  app$run_js(paste0(box, ".focus();"))
  press_key(app, "Backspace", "Backspace", 8L)
  app$wait_for_idle()
  expect_identical(app$get_value(input = "drug-search-pick"), "")
  expect_identical(app$get_text("#drug-title"), "Drug")
  app$run_js("document.activeElement.blur();")
  app$wait_for_idle()
  expect_identical(app$get_js(paste0(box, ".getValue()")), "")
})

test_that("flow 7: dark at first, the theme button switches it, and the choice is kept", {
  con <- fixture_app()
  drug <- fetch_subject(con, "chemical", "0212000B0")
  app <- local_app("theme")
  theme <- "document.documentElement.getAttribute('data-bs-theme')"
  label <- "document.getElementById('prexp-theme-toggle').getAttribute('aria-label')"
  page <- "getComputedStyle(document.body).backgroundColor"
  # The page in its colours and fonts: the dark page, IBM Plex Sans loaded
  # from the app
  expect_identical(app$get_js(theme), "dark")
  expect_identical(app$get_js(label), "Switch to light theme")
  expect_identical(app$get_js(page), "rgb(11, 18, 34)")
  app$wait_for_js(paste(
    "Array.from(document.fonts).some(function (f) {",
    "return f.family.replace(/\"/g, '') === 'IBM Plex Sans' && f.status === 'loaded'; })"
  ))
  # A chart is drawn once, in the light theme's colours, and the page shows
  # its marks and its tick labels in the theme's own
  search_pick(app, "drug", "atorva", paste0("chemical:", drug$id))
  mark <- "getComputedStyle(document.querySelector('#drug-chart svg [data-id]')).fill"
  tick <- paste0(
    "getComputedStyle(document.querySelector(\"#drug-chart svg text[fill='#5A5650' i]\"))",
    ".fill"
  )
  expect_identical(app$get_js(mark), "rgb(103, 140, 207)")
  expect_identical(app$get_js(tick), "rgb(139, 133, 121)")
  # Focus is a gold outline, never a glow, on Shiny's radios too: the
  # keyboard's way to the measure chosen
  focus <- paste(
    "(function () { var s = getComputedStyle(document.activeElement);",
    "return [s.outlineStyle, s.outlineWidth, s.boxShadow]; })()"
  )
  expect_true(tab_to(app, "#drug-measure input:checked"))
  expect_identical(unlist(app$get_js(focus)), c("solid", "2px", "none"))
  app$run_js("document.getElementById('prexp-theme-toggle').click();")
  expect_identical(app$get_js(theme), "light")
  expect_identical(app$get_js(label), "Switch to dark theme")
  expect_identical(app$get_js("window.localStorage.getItem('theme')"), "light")
  expect_identical(app$get_js(page), "rgb(253, 252, 251)")
  expect_identical(app$get_js(mark), "rgb(53, 86, 149)")
  expect_identical(app$get_js(tick), "rgb(90, 86, 80)")
  # On a narrow screen the tabs go under the app's name, each inside the
  # tabs' list, which never scrolls: none is out of sight. The top, bottom,
  # left and right of an element:
  box <- function(selector) {
    as.numeric(unlist(app$get_js(sprintf(paste(
      "(function () { var r = document.querySelector(\"%s\").getBoundingClientRect();",
      "return [r.top, r.bottom, r.left, r.right]; })()"
    ), selector))))
  }
  tabs_under_name <- function(width) {
    name <- box(".navbar-brand")
    strip <- box(".navbar ul.navbar-nav")
    for (value in app_tabs) {
      tab <- box(sprintf(".navbar .nav-link[data-value='%s']", value))
      label <- paste(value, "at", width, "px")
      expect_gte(tab[[1L]], name[[2L]] - 1, label = paste(label, "under the name"))
      expect_gte(tab[[3L]], strip[[3L]] - 0.5, label = paste(label, "inside the list"))
      expect_lte(tab[[4L]], strip[[4L]] + 0.5, label = paste(label, "inside the list"))
    }
    expect_true(app$get_js(paste(
      "(function () { var s = document.querySelector('.navbar ul.navbar-nav');",
      "return s.scrollWidth <= s.clientWidth; })()"
    )), label = paste("the tabs' list does not overflow at", width, "px"))
  }
  # On a wide screen the header is one row: the wordmark, the name, the tabs
  # beside it, and the theme button after the last tab
  app$set_window_size(width = 1280, height = 900)
  app$wait_for_idle(duration = 1000)
  name <- box(".navbar-brand")
  expect_lt(box(".prexp-header-wordmark")[[4L]], name[[3L]])
  for (value in app_tabs) {
    tab <- box(sprintf(".navbar .nav-link[data-value='%s']", value))
    expect_lt(tab[[1L]], name[[2L]], label = paste(value, "beside the name"))
    expect_gt(tab[[3L]], name[[4L]], label = paste(value, "after the name"))
  }
  expect_gt(box("#prexp-theme-toggle")[[3L]], box(".navbar .nav-link[data-value='about']")[[4L]])
  # On a phone the app's name stands alone, as the footer carries the
  # wordmark, and the five tabs sit on one line under it
  app$set_window_size(width = 390, height = 800)
  app$wait_for_idle(duration = 1000)
  expect_identical(
    app$get_js("getComputedStyle(document.querySelector('.prexp-header-wordmark')).display"),
    "none"
  )
  tabs_under_name(390)
  tops <- vapply(app_tabs, function(value) {
    box(sprintf(".navbar .nav-link[data-value='%s']", value))[[1L]]
  }, numeric(1))
  expect_length(unique(tops), 1L)
  # At 320 px, a narrow phone or a page zoomed to 400 %, they wrap onto a
  # second line
  app$set_window_size(width = 320, height = 800)
  app$wait_for_idle(duration = 1000)
  tabs_under_name(320)
  # Opened again, the page is light from the start; here on a narrow screen,
  # where the tabs go under the app's name and no menu button hides them
  app$set_window_size(width = 760, height = 900)
  app$wait_for_idle(duration = 1000)
  reload_page(app)
  expect_identical(app$get_js(theme), "light")
  expect_identical(app$get_js(label), "Switch to dark theme")
  # The keyboard's first stop is the skip link, which comes into view at the
  # top of the page and shows its focus; the next is KATONOMETRICA's wordmark,
  # which links its site
  press_key(app, "Tab", "Tab", 9L)
  expect_true(app$get_js("document.activeElement.matches('.prexp-skip-link')"))
  expect_equal(app$get_js("document.activeElement.getBoundingClientRect().top"), 8)
  expect_identical(unlist(app$get_js(focus)), c("solid", "2px", "none"))
  press_key(app, "Tab", "Tab", 9L)
  expect_true(app$get_js("document.activeElement.matches('.prexp-header-wordmark')"))
  expect_identical(app$get_js("document.activeElement.href"), "https://katonometrica.com/")
  expect_identical(unlist(app$get_js(focus)), c("solid", "2px", "none"))
  # The skip link leads past the header: from it, the next stop is the open
  # tab's first control, the drug's search box
  press_key(app, "Tab", "Tab", 9L, modifiers = 8L)
  expect_true(app$get_js("document.activeElement.matches('.prexp-skip-link')"))
  press_enter(app)
  press_key(app, "Tab", "Tab", 9L)
  expect_true(app$get_js("document.activeElement.matches('#drug-search-pick-selectized')"))
  # One line for the name and the theme button, the five tabs under it; the
  # open tab marked by more than its colour, a gold rule under it
  name <- box(".navbar-brand")
  button <- box("#prexp-theme-toggle")
  expect_lt(button[[1L]], name[[2L]])
  expect_gt(button[[3L]], name[[4L]])
  tabs_under_name(760)
  rule <- paste(
    "(function () { var s = getComputedStyle(document.querySelector('.navbar .nav-link.active'));",
    "return [s.borderBottomStyle, s.borderBottomWidth, s.borderBottomColor]; })()"
  )
  expect_identical(unlist(app$get_js(rule)), c("solid", "2px", "rgb(125, 101, 35)"))
})
