# The search module (P4-03): fewer than two characters fetch nothing; rapid
# typing fetches once, after the 300 ms debounce; the pick is returned; a
# failed fetch shows a message. The fetch is a fake, except in the last test.

drug_rows <- tibble::tibble(
  level = c("chemical", "presentation"), id = c(57L, 300L),
  code = c("0212000B0", "0212000B0AAABAB"),
  name = c("Atorvastatin", "Atorvastatin 20mg tablets"),
  chemical_id = c(57L, 57L), chemical_name = c("Atorvastatin", "Atorvastatin"),
  is_generic = c(NA, TRUE)
)

practice_rows <- tibble::tibble(
  practice_id = 12L, practice_code = "N81655", practice_name = "THE SURGERY",
  postcode = "AB1 2CD", icb_name = "NHS TEST ICB", region_name = "NORTH WEST"
)

# A fake fetch that returns `rows` and remembers each text it was asked for
fake_fetch <- function(rows) {
  asked <- character()
  list(
    fetch = function(q) {
      asked <<- c(asked, q)
      rows
    },
    asked = function() asked
  )
}

# The options the module sends to the dropdown, captured
local_sent <- function(env = parent.frame()) {
  sent <- new.env(parent = emptyenv())
  sent$options <- list()
  local_mocked_bindings(
    send_search_results = function(session, options) {
      sent$options[[length(sent$options) + 1L]] <- options
    },
    .env = env
  )
  sent
}

test_that("fewer than two characters fetch nothing", {
  fake <- fake_fetch(drug_rows)
  shiny::testServer(mod_search_server, args = list(fetch = fake$fetch, type = "drug"), {
    session$setInputs(query = "a")
    session$elapse(400)
    session$setInputs(query = "  a  ")
    session$elapse(400)
    expect_length(fake$asked(), 0L)
    expect_identical(output$message, "")
  })
})

test_that("rapid typing fetches once, 300 ms after the last key", {
  fake <- fake_fetch(drug_rows)
  shiny::testServer(mod_search_server, args = list(fetch = fake$fetch, type = "drug"), {
    # A session starts with no text: its first flush comes before any typing
    session$flushReact()
    session$setInputs(query = "at")
    session$elapse(100)
    session$setInputs(query = "ato")
    session$elapse(100)
    session$setInputs(query = "ator")
    session$elapse(290)
    expect_length(fake$asked(), 0L)
    session$elapse(20)
    expect_identical(fake$asked(), "ator")
  })
})

test_that("the dropdown gets the matches in the fetch's order, with level and code", {
  sent <- local_sent()
  fake <- fake_fetch(drug_rows)
  shiny::testServer(mod_search_server, args = list(fetch = fake$fetch, type = "drug"), {
    session$setInputs(query = "atorva")
    session$elapse(400)
  })
  options <- sent$options[[length(sent$options)]]
  expect_identical(
    options,
    list(
      list(
        value = "chemical:57", label = "Atorvastatin", meta = "Chemical substance \u00b7 0212000B0"
      ),
      list(
        value = "presentation:300", label = "Atorvastatin 20mg tablets",
        meta = "Presentation \u00b7 0212000B0AAABAB"
      )
    )
  )
  practices <- search_options(practice_rows, "practice")
  expect_identical(
    practices,
    list(list(value = "practice:12", label = "THE SURGERY", meta = "N81655 \u00b7 NHS TEST ICB"))
  )
})

test_that("the pick is returned as type, id, label and level", {
  fake <- fake_fetch(drug_rows)
  shiny::testServer(mod_search_server, args = list(fetch = fake$fetch, type = "drug"), {
    expect_null(session$returned())
    session$setInputs(query = "atorva")
    session$elapse(400)
    session$setInputs(pick = "presentation:300")
    expect_identical(
      session$returned(),
      list(type = "drug", id = 300L, label = "Atorvastatin 20mg tablets", level = "presentation")
    )
    session$setInputs(pick = "")
    expect_null(session$returned())
  })
})

test_that("a failed fetch shows a message, not an error, and the next search clears it", {
  failing <- TRUE
  fetch <- function(q) if (failing) stop("no such surgery as ", q) else practice_rows
  shiny::testServer(mod_search_server, args = list(fetch = fetch, type = "practice"), {
    # The log says a search failed, without the text searched for
    logged <- testthat::capture_messages({
      session$setInputs(query = "surgery")
      session$elapse(400)
      shown <- output$message
    })
    expect_identical(logged, "A search failed: simpleError\n")
    expect_identical(shown, "The search failed. Please try again in a moment.")
    failing <<- FALSE
    session$setInputs(query = "surgery hall")
    session$elapse(400)
    expect_identical(output$message, "")
  })
})

test_that("no match says so", {
  fake <- fake_fetch(drug_rows[0, ])
  shiny::testServer(mod_search_server, args = list(fetch = fake$fetch, type = "drug"), {
    session$setInputs(query = "zzzz")
    session$elapse(400)
    expect_identical(output$message, "No matches.")
  })
})

test_that("on the fixture database, matches arrive while typing", {
  sent <- local_sent()
  con <- fixture_app()
  fetch <- function(q) fetch_search_drugs(con, q, limit = 20L)
  shiny::testServer(mod_search_server, args = list(fetch = fetch, type = "drug"), {
    session$setInputs(query = "ator")
    session$elapse(400)
    session$setInputs(query = "atorva")
    session$elapse(400)
  })
  labels <- vapply(sent$options[[length(sent$options)]], function(o) o$label, "")
  expect_true("Atorvastatin" %in% labels)
  expect_true(all(grepl("atorva", labels, ignore.case = TRUE)))
})

test_that("the search box is a selectize input that loads through search.js", {
  ui <- as.character(mod_search_ui("drug_search", "drug"))
  expect_match(ui, "id=\"drug_search-pick\"", fixed = TRUE)
  expect_match(ui, "prexpSearch.load(this, 'drug_search-query'", fixed = TRUE)
  expect_match(ui, "Find a drug", fixed = TRUE)
  expect_match(ui, "aria-live=\"polite\"", fixed = TRUE)
  expect_match(as.character(mod_search_ui("p", "practice")), "Find a practice", fixed = TRUE)
  page <- htmltools::renderTags(app_ui(NULL))$head
  expect_match(page, "prexp/search.js", fixed = TRUE)
})
