# The report panel (P5-02): items listed with their titles and counter, moved,
# removed and noted through the module's two inputs, the limits refused, the
# list kept while a note is typed, what each change did said in the status
# region, and the markup report.js reads. The pin buttons are tested with each
# view, and the two together in test-app.R.

panel_params <- list(
  drug = list(
    level = "chemical", id = 57L, code = "0212000B0", label = "Atorvastatin",
    months = c(202510L, 202609L), measure = "items"
  ),
  practice = list(
    id = 12L, code = "N81655", label = "THE SURGERY", months = c(202601L, 202609L),
    measure = "nic"
  ),
  region = list(
    level = "presentation", id = 300L, code = "0212000B0AAABAB",
    label = "Atorvastatin 20mg tablets", months = c(202609L, 202609L), measure = "adq_usage"
  )
)

panel_report <- function(n = 3L) {
  spec <- new_report()
  for (view in rep(names(panel_params), length.out = n)) {
    spec <- report_add(spec, view, panel_params[[view]])
  }
  spec
}

# The titles the panel lists, in order
listed <- function(html) {
  titles <- regmatches(html, gregexpr("<h2[^>]*>[^<]*</h2>", html))[[1L]]
  gsub("<[^>]+>", "", titles)
}

# Each tag's attributes, by name, in any order
tag_attributes <- function(html, tag) {
  tags <- regmatches(html, gregexpr(sprintf("<%s\\s[^>]*>", tag), html))[[1L]]
  lapply(tags, function(one) {
    pairs <- regmatches(one, gregexpr("[a-z-]+=\"[^\"]*\"", one))[[1L]]
    value <- sub("^[^=]+=\"(.*)\"$", "\\1", pairs)
    names(value) <- sub("=.*$", "", pairs)
    value[["disabled"]] <- if (grepl("\\sdisabled[\\s>]", one, perl = TRUE)) "disabled" else ""
    value
  })
}

# Whether an item's button for an action is off
button_off <- function(html, act, id) {
  buttons <- tag_attributes(html, "button")
  mine <- Filter(function(b) b[["data-report-act"]] == act && b[["data-report-id"]] == id, buttons)
  stopifnot(length(mine) == 1L)
  nzchar(mine[[1]][["disabled"]])
}

# The counters' numbers, as the panel draws them
counted <- function(html) {
  numbers <- regmatches(html, gregexpr("prexp-note-count\">[0-9]+</span>/500", html))[[1L]]
  as.integer(sub(".*>([0-9]+)</span>.*", "\\1", numbers))
}

dot <- function(...) paste(..., sep = " \u00b7 ")

# What the status region was told, in order
local_announced <- function(env = parent.frame()) {
  said <- new.env(parent = emptyenv())
  said$all <- character()
  local_mocked_bindings(
    announce = function(session, text) said$all <- c(said$all, text),
    .env = env
  )
  said
}

test_that("an item's title and summary name its subject, measure, months and code", {
  spec <- panel_report()
  expect_identical(
    report_item_title(spec$items[[1]]), dot("Atorvastatin", "items", "Oct 2025 to Sep 2026")
  )
  expect_identical(
    report_item_title(spec$items[[2]]),
    dot("THE SURGERY", "net ingredient cost", "Jan 2026 to Sep 2026")
  )
  # A region item says so; one month alone; a measure that keeps its capitals
  expect_identical(
    report_item_title(spec$items[[3]]),
    dot("Atorvastatin 20mg tablets by region", "ADQ usage", "Sep 2026")
  )
  expect_identical(
    report_item_summary(spec$items[[1]]), dot("Drug view", "chemical substance 0212000B0")
  )
  expect_identical(report_item_summary(spec$items[[2]]), dot("Practice view", "practice N81655"))
  expect_identical(
    report_item_summary(spec$items[[3]]), dot("Region view", "presentation 0212000B0AAABAB")
  )
  codeless <- utils::modifyList(panel_params$practice, list(code = NA))
  nameless <- report_add(new_report(), "practice", codeless)
  expect_identical(report_item_summary(nameless$items[[1]]), dot("Practice view", "practice"))
})

test_that("a drug item and a region item of the same drug have different titles and names", {
  spec <- report_add(new_report(), "drug", panel_params$drug)
  spec <- report_add(spec, "region", panel_params$drug)
  expect_identical(
    report_item_title(spec$items[[2]]),
    dot("Atorvastatin by region", "items", "Oct 2025 to Sep 2026")
  )
  names_of <- function(item) {
    html <- as.character(report_item_ui(shiny::NS("report"), item, first = FALSE, last = FALSE))
    regmatches(html, gregexpr("aria-label=\"[^\"]*\"", html))[[1L]]
  }
  drug <- names_of(spec$items[[1]])
  region <- names_of(spec$items[[2]])
  expect_length(drug, 5L)
  expect_length(intersect(drug, region), 0L)
})

test_that("the panel lists each item with its title, counter and buttons, or says it is empty", {
  pinned <- shiny::reactiveVal(new_report())
  shiny::testServer(mod_report_server, args = list(report = pinned), {
    expect_match(output$items$html, "Nothing is pinned yet.", fixed = TRUE)
    expect_match(output$count$html, ">0/15<", fixed = TRUE)
    expect_match(output$count$html, "0 of at most 15 items", fixed = TRUE)
    pinned(panel_report())
    session$flushReact()
    html <- output$items$html
    expect_identical(listed(html), c(
      dot("Atorvastatin", "items", "Oct 2025 to Sep 2026"),
      dot("THE SURGERY", "net ingredient cost", "Jan 2026 to Sep 2026"),
      dot("Atorvastatin 20mg tablets by region", "ADQ usage", "Sep 2026")
    ))
    expect_match(output$count$html, ">3/15<", fixed = TRUE)
    # The first cannot move up and the last cannot move down
    expect_true(button_off(html, "up", "1"))
    expect_false(button_off(html, "down", "1"))
    expect_false(button_off(html, "up", "3"))
    expect_true(button_off(html, "down", "3"))
    expect_false(button_off(html, "remove", "1"))
    # Each note has its counter, at 0 of 500; no maxlength, which counts
    # UTF-16 units, not characters
    expect_identical(counted(html), c(0L, 0L, 0L))
    expect_no_match(html, "maxlength", fixed = TRUE)
    expect_no_match(html, "Months clamped", fixed = TRUE)
    # An item whose months were clamped says so, to a screen reader too
    pinned(clamp_report(pinned(), tibble::tibble(first_month = 202602L, last_month = 202609L)))
    session$flushReact()
    expect_match(output$items$html, "Months clamped", fixed = TRUE)
    expect_match(output$items$html, "so they were moved into it", fixed = TRUE)
    # The last item removed: the panel is empty again
    for (id in item_ids(pinned())) {
      session$setInputs(act = list(id = id, act = "remove"))
    }
    expect_match(output$items$html, "Nothing is pinned yet.", fixed = TRUE)
    expect_match(output$count$html, ">0/15<", fixed = TRUE)
  })
})

test_that("items move and are removed through the panel's buttons, which the status region says", {
  said <- local_announced()
  pinned <- shiny::reactiveVal(panel_report())
  region <- dot("Atorvastatin 20mg tablets by region", "ADQ usage", "Sep 2026")
  shiny::testServer(mod_report_server, args = list(report = pinned), {
    session$setInputs(act = list(id = 3, act = "up"))
    expect_identical(item_ids(pinned()), c(1L, 3L, 2L))
    session$setInputs(act = list(id = 1, act = "down"))
    expect_identical(item_ids(pinned()), c(3L, 1L, 2L))
    session$setInputs(act = list(id = 3, act = "remove"))
    expect_identical(item_ids(pinned()), c(1L, 2L))
    expect_length(listed(output$items$html), 2L)
    expect_match(output$count$html, ">2/15<", fixed = TRUE)
    expect_identical(said$all, c(
      paste0("Moved up: ", region, ", now 2 of 3."),
      paste0("Moved down: ", dot("Atorvastatin", "items", "Oct 2025 to Sep 2026"), ", now 2 of 3."),
      paste0("Removed: ", region, ". 2 items left.")
    ))
    # An item no longer there, another action, not an action, or a move past
    # either end: nothing changes, and nothing is said
    before <- pinned()
    session$setInputs(act = list(id = 3, act = "up"))
    session$setInputs(act = list(id = 1, act = "sideways"))
    session$setInputs(act = "up")
    session$setInputs(act = list(id = 2))
    session$setInputs(act = list(id = 1, act = "up"))
    expect_identical(pinned(), before)
    expect_length(said$all, 3L)
    session$setInputs(act = list(id = 1, act = "remove"))
    expect_match(utils::tail(said$all, 1L), ". 1 item left.", fixed = TRUE)
  })
})

test_that("a note is kept, and one over 500 characters is refused, said once until one fits", {
  toasts <- character()
  local_mocked_bindings(
    showNotification = function(ui, ...) {
      toasts <<- c(toasts, ui)
      invisible(NULL)
    },
    .package = "shiny"
  )
  said <- local_announced()
  pinned <- shiny::reactiveVal(panel_report())
  shiny::testServer(mod_report_server, args = list(report = pinned), {
    session$setInputs(note = list(id = 2, note = "Costs rose in winter."))
    expect_identical(pinned()$items[[2]]$note, "Costs rose in winter.")
    session$setInputs(note = list(id = 2, note = strrep("a", 501L)))
    session$setInputs(note = list(id = 2, note = strrep("a", 502L)))
    expect_identical(pinned()$items[[2]]$note, "Costs rose in winter.")
    expect_length(toasts, 2L)
    expect_match(toasts, "at most 500 characters; this one has 50", fixed = TRUE)
    expect_length(said$all, 1L)
    # Within the limit again, then over it: said again
    session$setInputs(note = list(id = 2, note = "Shorter."))
    session$setInputs(note = list(id = 2, note = strrep("b", 501L)))
    expect_identical(pinned()$items[[2]]$note, "Shorter.")
    expect_length(said$all, 2L)
    # A note for an item no longer there, or not a note, changes nothing
    session$setInputs(note = list(id = 9, note = "x"))
    session$setInputs(note = "x")
    expect_identical(pinned()$items[[2]]$note, "Shorter.")
  })
})

test_that("typing a note does not draw the list again, and moving an item does", {
  pinned <- shiny::reactiveVal(panel_report(2L))
  shiny::testServer(mod_report_server, args = list(report = pinned), {
    drawn <- output$items$html
    session$setInputs(note = list(id = 1, note = "First thoughts."))
    expect_identical(output$items$html, drawn)
    expect_match(output$count$html, ">2/15<", fixed = TRUE)
    session$setInputs(act = list(id = 2, act = "up"))
    expect_match(output$items$html, "First thoughts.", fixed = TRUE)
    expect_identical(counted(output$items$html), c(0L, 15L))
  })
})

test_that("a note's box holds the note as it is, a first line break too", {
  spec <- report_set_note(panel_report(1L), 1L, "\nAfter a blank line")
  item <- report_item_ui(shiny::NS("report"), spec$items[[1]], TRUE, TRUE)
  html <- htmltools::renderTags(item)$html
  # The parser drops the line break right after <textarea>: the panel's own
  expect_match(html, ">\n\nAfter a blank line</textarea>", fixed = TRUE)
  expect_match(html, "Note\\s*<span class=\"visually-hidden\"> on Atorvastatin")
})

test_that("the page loads report.js and has a status region, and the markup names what both read", {
  page <- htmltools::renderTags(app_ui(NULL))
  expect_match(page$head, "prexp/report.js", fixed = TRUE)
  expect_true(nzchar(system.file("app", "www", "report.js", package = "prexp")))
  status <- regmatches(page$html, regexpr("<div[^>]*id=\"prexp-status\"[^>]*>", page$html))
  expect_match(status, "role=\"status\"", fixed = TRUE)
  expect_match(status, "visually-hidden", fixed = TRUE)
  # The list is no live region
  ui <- htmltools::renderTags(mod_report_ui("report"))$html
  expect_match(
    regmatches(ui, regexpr("<div[^>]*id=\"report-items\"[^>]*>", ui)), "aria-live=\"off\"",
    fixed = TRUE
  )
  pinned <- shiny::reactiveVal(panel_report())
  shiny::testServer(mod_report_server, args = list(report = pinned), {
    html <- output$items$html
    ids <- vapply(pinned()$items, function(item) as.character(item$id), "")
    titles <- vapply(pinned()$items, report_item_title, "")
    buttons <- tag_attributes(html, "button")
    boxes <- tag_attributes(html, "textarea")
    expect_length(buttons, 9L)
    expect_length(boxes, 3L)
    # One input of the module for the buttons, one for the notes
    expect_identical(unique(vapply(buttons, `[[`, "", "data-report-input")), session$ns("act"))
    expect_identical(unique(vapply(boxes, `[[`, "", "data-report-input")), session$ns("note"))
    # Each button names its action and its item to a screen reader, the
    # arrows too
    actions <- c(up = "Move up", down = "Move down", remove = "Remove")
    for (button in buttons) {
      title <- titles[match(button[["data-report-id"]], ids)]
      label <- paste0(actions[[button[["data-report-act"]]]], ": ", title)
      expect_identical(unname(button["aria-label"]), label)
    }
    # Each note names its item and its counter
    expect_identical(unname(vapply(boxes, `[[`, "", "data-report-id")), ids)
    for (box in boxes) {
      counter <- box[["data-report-counter"]]
      expect_identical(unname(box[["aria-describedby"]]), unname(counter))
      expect_identical(unname(box[["data-report-limit"]]), "500")
      expect_match(html, sprintf("<div[^>]*id=\"%s\"", counter))
    }
  })
})

test_that("report.js reads the attributes the panel writes, and says what the server sends", {
  js <- paste(readLines(system.file("app", "www", "report.js", package = "prexp")), collapse = "\n")
  for (name in c("reportInput", "reportId", "reportAct", "reportCounter", "reportLimit")) {
    expect_match(js, paste0("dataset.", name), fixed = TRUE, label = name)
  }
  for (selector in c(
    "button[data-report-act]", "textarea[data-report-input]", ".prexp-note-count",
    ".prexp-report-item", "prexp-status"
  )) {
    expect_match(js, selector, fixed = TRUE, label = selector)
  }
  # The message the server sends for the status region
  expect_match(js, "addCustomMessageHandler('prexp-status'", fixed = TRUE)
})

test_that("a note pasted with a word processor's breaks is saved with line breaks", {
  pinned <- shiny::reactiveVal(panel_report(1L))
  shiny::testServer(mod_report_server, args = list(report = pinned), {
    pasted <- paste0("One", intToUtf8(11L), "two", intToUtf8(12L), "three", intToUtf8(1L), "!")
    session$setInputs(note = list(id = 1, note = pasted))
    expect_identical(pinned()$items[[1]]$note, "One\ntwo\nthree!")
  })
  kept <- paste0("a", intToUtf8(c(9L, 13L, 10L, 133L, 65535L)), "b")
  expect_identical(clean_note(kept), "a\t\r\nb")
  expect_identical(clean_note(""), "")
  expect_identical(clean_note(NA_character_), NA_character_)
  expect_identical(clean_note(1), 1)
})

test_that("a move that would make the report's link too long is refused, with a toast", {
  toasts <- character()
  local_mocked_bindings(
    showNotification = function(ui, ...) {
      toasts <<- c(toasts, ui)
      invisible(NULL)
    },
    .package = "shiny"
  )
  said <- local_announced()
  local_mocked_bindings(
    report_move = function(...) report_limit("The report's link would be 7503 characters")
  )
  pinned <- shiny::reactiveVal(panel_report(2L))
  shiny::testServer(mod_report_server, args = list(report = pinned), {
    session$setInputs(act = list(id = 2, act = "up"))
    expect_identical(item_ids(pinned()), 1:2)
    expect_identical(toasts, "The report's link would be 7503 characters")
    expect_identical(said$all, toasts)
  })
})
