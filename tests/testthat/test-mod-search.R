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

# The answers the module sends to the dropdown, captured: their options, and
# the text each answers
local_sent <- function(env = parent.frame()) {
  sent <- new.env(parent = emptyenv())
  sent$options <- list()
  sent$queries <- character()
  local_mocked_bindings(
    send_search_results = function(session, options, query) {
      sent$options[[length(sent$options) + 1L]] <- options
      sent$queries <- c(sent$queries, query)
    },
    .env = env
  )
  sent
}

test_that("fewer than two characters fetch nothing, and answer with no options", {
  sent <- local_sent()
  fake <- fake_fetch(drug_rows)
  shiny::testServer(mod_search_server, args = list(fetch = fake$fetch, type = "drug"), {
    session$setInputs(query = "a")
    session$elapse(400)
    session$setInputs(query = "  a  ")
    session$elapse(400)
    expect_length(fake$asked(), 0L)
    expect_identical(output$message, "")
    # Two are enough
    session$setInputs(query = "at")
    session$elapse(400)
    expect_identical(fake$asked(), "at")
  })
  # Each short text had its answer, so the dropdown's load ends
  expect_identical(sent$queries[sent$queries != "at"], c("a", "  a  "))
  expect_identical(sent$options[1:2], list(list(), list()))
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
        value = "chemical:57", label = "Atorvastatin", meta = "Chemical substance \u00b7 0212000B0",
        level = "chemical", id = 57L, code = "0212000B0"
      ),
      list(
        value = "presentation:300", label = "Atorvastatin 20mg tablets",
        meta = "Presentation \u00b7 0212000B0AAABAB", level = "presentation", id = 300L,
        code = "0212000B0AAABAB"
      )
    )
  )
  # The answer names the text it answers, as it was sent
  expect_identical(sent$queries[length(sent$queries)], "atorva")
  practices <- search_options(practice_rows, "practice")
  expect_identical(
    practices,
    list(list(
      value = "practice:12", label = "THE SURGERY", meta = "N81655 \u00b7 NHS TEST ICB",
      level = "practice", id = 12L, code = "N81655"
    ))
  )
})

test_that("an answer goes to its box, as the custom message search.js listens for", {
  messages <- list()
  session <- list(
    ns = shiny::NS("drug_search"),
    sendCustomMessage = function(type, message) {
      messages[[length(messages) + 1L]] <<- list(type = type, message = message)
    }
  )
  send_search_results(session, list(list(value = "chemical:57")), " atorva")
  expect_identical(
    messages,
    list(list(
      type = "prexp-search-results",
      message = list(
        id = "drug_search-query", query = " atorva", options = list(list(value = "chemical:57"))
      )
    ))
  )
})

test_that("a practice search answers with practices, and returns the one picked", {
  sent <- local_sent()
  fake <- fake_fetch(practice_rows)
  shiny::testServer(mod_search_server, args = list(fetch = fake$fetch, type = "practice"), {
    session$setInputs(query = "n81")
    session$elapse(400)
    session$setInputs(pick = "practice:12")
    expect_identical(
      session$returned(),
      list(
        type = "practice", id = 12L, label = "THE SURGERY", level = "practice", code = "N81655"
      )
    )
  })
  expect_identical(sent$options[[length(sent$options)]][[1]]$value, "practice:12")
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
      list(
        type = "drug", id = 300L, label = "Atorvastatin 20mg tablets", level = "presentation",
        code = "0212000B0AAABAB"
      )
    )
    session$setInputs(pick = "")
    expect_null(session$returned())
    # A value never offered is no pick: set from the browser's console, say
    for (forged in list("chemical:999", "practice:57", "chemical:57x", c("a", "b"))) {
      session$setInputs(pick = forged)
      expect_null(session$returned(), label = paste(forged, collapse = " "))
    }
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

test_that("a refused search says what to type, not to try again", {
  sent <- local_sent()
  fetch <- function(q) validate_search(q)
  shiny::testServer(mod_search_server, args = list(fetch = fetch, type = "drug"), {
    logged <- testthat::capture_messages({
      session$setInputs(query = strrep("a", 101))
      session$elapse(400)
      shown <- output$message
    })
    expect_identical(logged, "A search was refused: prexp_invalid_argument\n")
    expect_identical(shown, "Type between 2 and 100 characters.")
  })
  expect_identical(sent$options[[length(sent$options)]], list())
})

test_that("text cut back below two characters clears the last message", {
  fake <- fake_fetch(drug_rows[0, ])
  shiny::testServer(mod_search_server, args = list(fetch = fake$fetch, type = "drug"), {
    session$setInputs(query = "zzzz")
    session$elapse(400)
    expect_identical(output$message, "No matches.")
    # search.js sends the text when it becomes too short to search
    session$setInputs(query = "")
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
  expect_match(ui, "prexpSearch.typed(this, 'drug_search-query', text)", fixed = TRUE)
  expect_match(ui, "role=\\\"option\\\" id=\\\"drug_search-option-", fixed = TRUE)
  expect_match(ui, "clear_button", fixed = TRUE)
  expect_match(ui, "Find a drug", fixed = TRUE)
  expect_match(ui, "aria-live=\"polite\"", fixed = TRUE)
  expect_match(as.character(mod_search_ui("p", "practice")), "Find a practice", fixed = TRUE)
  page <- htmltools::renderTags(app_ui(NULL))$head
  expect_match(page, "prexp/search.js", fixed = TRUE)
})

test_that("the box counts characters as the search does", {
  fake <- fake_fetch(drug_rows)
  shiny::testServer(mod_search_server, args = list(fetch = fake$fetch, type = "drug"), {
    # One letter and a zero-width space, which the search drops
    session$setInputs(query = paste0("a", intToUtf8(0x200B)))
    session$elapse(400)
    expect_length(fake$asked(), 0L)
    expect_identical(output$message, "")
  })
  expect_identical(clean_search(paste0(" a", intToUtf8(c(0x00A0, 0x200B)), "  b ")), "a b")
})
