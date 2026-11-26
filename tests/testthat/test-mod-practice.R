# The Practice view (P4-05), with fake fetches: the arguments it passes, the
# top drugs paged by keyset and the paging started again when the ranking
# changes, its three states and current_view(); then on the fixture database.

practice_window <- tibble::tibble(
  first_month = 202510L, last_month = 202609L, months = 12L, loaded_at = Sys.time()
)

practice_matches <- tibble::tibble(
  practice_id = 12L, practice_code = "N81655", practice_name = "THE SURGERY",
  postcode = "CH1 1AA", icb_name = "NHS CHESHIRE AND MERSEYSIDE", region_name = "NORTH WEST"
)

practice_profile_row <- tibble::tibble(
  practice_id = 12L, practice_code = "N81655", practice_name = "THE SURGERY",
  address = "1 HIGH STREET, CHESTER", postcode = "CH1 1AA", icb_code = "QYG",
  icb_name = "NHS CHESHIRE AND MERSEYSIDE", region_code = "Y62", region_name = "NORTH WEST",
  is_unidentified = FALSE, first_seen = 202510L, last_seen = 202609L
)

practice_series_rows <- tibble::tibble(
  year_month = c(202608L, 202609L), presentations = c(40L, 42L), items = c(900, 950),
  nic = c(5000.5, 5100.25), actual_cost = c(4700, 4800)
)

# A practice's drugs, ranked: drug i has presentation_id 1000 + i
ranked_drugs <- function(n) {
  totals <- as.double(rev(seq_len(n)))
  tibble::tibble(
    presentation_id = 1000L + seq_len(n), bnf_code = sprintf("0101010A0AAA%03d", seq_len(n)),
    bnf_description = paste("Drug", seq_len(n)), chemical_id = 1L, chemical_name = "Chem",
    is_generic = TRUE, items = totals, adq_usage = NA_real_, nic = totals * 10,
    actual_cost = totals * 9, total = totals
  )
}

# Fake fetches that record their arguments. The top drugs are pages of
# `drugs` ranked drugs, by keyset as the real fetch pages them. The states set
# what the fetches do: "rows", "none" or "fail"; `state` for the monthly
# totals, `profile` for the profile and `top` for the top drugs.
fake_practice_fetches <- function(drugs = 7L) {
  calls <- new.env(parent = emptyenv())
  calls$series <- list()
  calls$top <- list()
  calls$state <- "rows"
  calls$profile <- "rows"
  calls$top_state <- "rows"
  ranked <- ranked_drugs(drugs)
  outcome <- function(state, rows) {
    switch(state, rows = rows, none = rows[0, ], fail = stop("the database is down"))
  }
  fetches <- list(
    search_practices = function(q) practice_matches,
    practice_profile = function(practice_id) outcome(calls$profile, practice_profile_row),
    practice_series = function(practice_id, months) {
      calls$series[[length(calls$series) + 1L]] <- list(practice_id = practice_id, months = months)
      outcome(calls$state, practice_series_rows)
    },
    practice_top_drugs = function(practice_id, months, by, limit, after) {
      calls$top[[length(calls$top) + 1L]] <- list(
        practice_id = practice_id, months = months, by = by, limit = limit, after = after
      )
      start <- if (is.null(after)) 0L else match(after, ranked$presentation_id)
      outcome(calls$top_state, utils::head(ranked[seq_len(nrow(ranked)) > start, ], limit))
    }
  )
  list(fetches = fetches, calls = calls)
}

# Picks the practice through the view's own search, as a user does
pick_practice <- function(session, value = "practice:12") {
  session$setInputs(`search-query` = "n81")
  session$elapse(400)
  session$setInputs(`search-pick` = value)
}

latest <- function(calls) calls[[length(calls)]]

# The rows a page of top drugs shows, read from the table's output
top_rows <- function(table) {
  as.data.frame(jsonlite::fromJSON(table)$x$tag$attribs$data)
}

# A page of top drugs: its rows, and which drugs it says it shows
top_page <- function(output) {
  list(rows = top_rows(output$top_table), range = output$top_range)
}

# Previous and Next as the view last set them, through set_paging()
local_paging <- function(env = parent.frame()) {
  state <- new.env(parent = emptyenv())
  state$previous <- NA
  state$more <- NA
  local_mocked_bindings(
    set_paging = function(session, previous, more) {
      state$previous <- previous
      state$more <- more
    },
    .env = env
  )
  state
}

# An action button's value as the browser sends it, which observeEvent()
# ignores at 0
clicked <- function(n) structure(as.integer(n), class = "shinyActionButtonValue")

practice_args <- function(fake, page_size = 3L) {
  list(fetches = fake$fetches, window = shiny::reactive(practice_window), page_size = page_size)
}

test_that("with nothing picked the view asks for a practice", {
  fake <- fake_practice_fetches()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    expect_match(output$body$html, "Search for a practice by its name, code or postcode.")
    expect_identical(output$title, "Practice")
    expect_null(session$returned())
    expect_length(fake$calls$series, 0L)
    expect_length(fake$calls$top, 0L)
  })
})

test_that("the profile, the totals and the top drugs come for the practice and months chosen", {
  fake <- fake_practice_fetches()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    pick_practice(session)
    body <- output$body$html
    profile <- output$profile$html
    for (text in c("N81655", "1 HIGH STREET, CHESTER, CH1 1AA", "NHS CHESHIRE AND MERSEYSIDE",
                   "NORTH WEST", "Oct 2025 \u2013 Sep 2026")) {
      expect_match(profile, text, fixed = TRUE, label = text)
    }
    expect_match(body, "id=\"[a-z0-9]+-profile\"")
    expect_match(body, "id=\"[a-z0-9]+-chart\"")
    expect_identical(output$title, "THE SURGERY, Oct 2025 \u2013 Sep 2026")
    expect_identical(
      latest(fake$calls$series), list(practice_id = 12L, months = c(202510L, 202609L))
    )
    expect_s3_class(output$chart, "json")
    expect_identical(output$top_title, "Top drugs by items")
    top <- top_page(output)
    # A page has one row more fetched than shown, to know there is a next one
    expect_identical(
      latest(fake$calls$top),
      list(practice_id = 12L, months = c(202510L, 202609L), by = "items", limit = 4L, after = NULL)
    )
    expect_identical(top$rows$presentation, paste("Drug", 1:3))
    expect_identical(top$rows$rank, 1:3)
    expect_identical(top$range, "Drugs 1 to 3")
    session$setInputs(from = "202609", to = "202607", measure = "nic")
    expect_identical(
      latest(fake$calls$series), list(practice_id = 12L, months = c(202607L, 202609L))
    )
    expect_identical(output$top_title, "Top drugs by net ingredient cost")
    output$top_table
    expect_identical(
      latest(fake$calls$top),
      list(practice_id = 12L, months = c(202607L, 202609L), by = "nic", limit = 4L, after = NULL)
    )
  })
})

test_that("Next and Previous carry the keyset, and a new ranking starts again at page one", {
  fake <- fake_practice_fetches(drugs = 7L)
  buttons <- local_paging()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    pick_practice(session)
    top <- top_page(output)
    expect_false(buttons$previous)
    expect_true(buttons$more)
    # Page two starts after the last drug of page one
    session$setInputs(next_page = 1)
    top <- top_page(output)
    expect_identical(latest(fake$calls$top)$after, 1003L)
    expect_identical(top$rows$presentation, paste("Drug", 4:6))
    expect_identical(top$rows$rank, 4:6)
    expect_identical(top$range, "Drugs 4 to 6")
    expect_true(buttons$previous)
    # The last page: one drug, and no Next
    session$setInputs(next_page = 2)
    top <- top_page(output)
    expect_identical(latest(fake$calls$top)$after, 1006L)
    expect_identical(top$rows$presentation, "Drug 7")
    expect_identical(top$range, "Drugs 7 to 7")
    expect_false(buttons$more)
    # Next on the last page stays there
    session$setInputs(next_page = 3)
    expect_identical(top_rows(output$top_table)$presentation, "Drug 7")
    # Previous goes back a page
    session$setInputs(previous_page = 1)
    top <- top_page(output)
    expect_identical(latest(fake$calls$top)$after, 1003L)
    expect_identical(top$rows$presentation, paste("Drug", 4:6))
    # Another ranking starts again at page one, and so do other months
    session$setInputs(measure = "actual_cost")
    top <- top_page(output)
    expect_identical(
      latest(fake$calls$top)[c("by", "after")], list(by = "actual_cost", after = NULL)
    )
    expect_identical(top$rows$rank, 1:3)
    session$setInputs(next_page = 4)
    expect_identical(top_rows(output$top_table)$rank, 4:6)
    session$setInputs(from = "202601")
    top <- top_page(output)
    expect_identical(
      latest(fake$calls$top)[c("months", "after")],
      list(months = c(202601L, 202609L), after = NULL)
    )
    expect_identical(top$rows$rank, 1:3)
    # Previous on page one stays there
    session$setInputs(previous_page = 2)
    expect_identical(top_rows(output$top_table)$rank, 1:3)
  })
})

test_that("a full last page offers no Next, since one row more was asked for", {
  fake <- fake_practice_fetches(drugs = 6L)
  buttons <- local_paging()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    pick_practice(session)
    session$setInputs(next_page = 1)
    top <- top_page(output)
    expect_identical(top$rows$presentation, paste("Drug", 4:6))
    expect_false(buttons$more)
  })
})

test_that("no rows say so, and an error offers to try again", {
  fake <- fake_practice_fetches()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    fake$calls$state <- "none"
    pick_practice(session)
    body <- output$body$html
    expect_match(body, "THE SURGERY did not prescribe in Oct 2025 \u2013 Sep 2026.", fixed = TRUE)
    # The profile still shows
    expect_match(body, "id=\"[a-z0-9]+-profile\"")
    expect_match(output$profile$html, "N81655", fixed = TRUE)
    expect_null(session$returned())

    fake$calls$state <- "fail"
    session$setInputs(from = "202601")
    expect_match(output$body$html, "The data could not be fetched.", fixed = TRUE)
    expect_match(output$body$html, "id=\"[a-z0-9]+-retry\"")
    expect_null(session$returned())

    # Once the database answers again, Try again shows the practice
    fake$calls$state <- "rows"
    session$setInputs(retry = 1)
    expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")

    # The top drugs can fail on their own
    fake$calls$top_state <- "fail"
    session$setInputs(measure = "nic")
    expect_match(output$top_message$html, "The top drugs could not be fetched.", fixed = TRUE)
    expect_match(output$top_message$html, "id=\"[a-z0-9]+-retry_top\"")
    fake$calls$top_state <- "rows"
    session$setInputs(retry_top = 1)
    expect_identical(top_rows(output$top_table)$rank, 1:3)

    # A practice the data does not have
    fake$calls$profile <- "none"
    session$setInputs(retry = 2)
    expect_match(output$body$html, "THE SURGERY is not in the data.", fixed = TRUE)
  })
})

test_that("current_view() carries the view, its parameters and the totals shown", {
  fake <- fake_practice_fetches()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    pick_practice(session)
    session$setInputs(measure = "actual_cost")
    expect_identical(
      session$returned(),
      list(
        view = "practice",
        params = list(
          id = 12L, code = "N81655", label = "THE SURGERY", months = c(202510L, 202609L),
          measure = "actual_cost"
        ),
        # Every month of the range: those without a row at 0, as the chart
        # draws them
        data = tibble::tibble(
          year_month = c(202510:202512, 202601:202609),
          presentations = c(rep(0L, 10L), 40L, 42L), items = c(rep(0, 10L), 900, 950),
          nic = c(rep(0, 10L), 5000.5, 5100.25), actual_cost = c(rep(0, 10L), 4700, 4800)
        )
      )
    )
  })
})

test_that("the chart shows the measure chosen, and the table numbers its rows", {
  expect_identical(
    measure_series(practice_series_rows, "nic"),
    tibble::tibble(year_month = c(202608L, 202609L), measure = "nic", value = c(5000.5, 5100.25))
  )
  expect_identical(names(practice_measures()), c("Items", "Net ingredient cost", "Actual cost"))
  table <- top_drugs_table(ranked_drugs(2L), first = 26L)
  # The tables' one theme, without stripes
  expect_identical(table$x$tag$attribs$theme, table_theme())
  expect_null(table$x$tag$attribs$striped)
  data <- jsonlite::fromJSON(as.character(table$x$tag$attribs$data))
  expect_identical(data$rank, 26:27)
  expect_identical(data$kind, c("Generic", "Generic"))
  expect_false(table$x$tag$attribs$pagination)
  expect_false(table$x$tag$attribs$sortable)
  # An address that is not given
  blank <- transform(practice_profile_row, address = "", postcode = NA)
  expect_match(as.character(practice_profile(blank)), "Not given", fixed = TRUE)
})

test_that("the view pages through a practice's drugs on the fixture database", {
  con <- fixture_app()
  practice <- id_of(con, "practice", "N81655")
  fetches <- app_fetches(con)
  window <- fetches$window()
  # Not `months`: in testServer() that name is the module's own reactive
  span <- c(window$first_month, window$last_month)
  all <- fetch_practice_top_drugs(con, practice, span, by = "items", limit = 1000L)
  expect_gt(nrow(all), 8L)
  shiny::testServer(
    mod_practice_server,
    args = list(fetches = fetches, window = shiny::reactive(window), page_size = 4L),
    {
      session$setInputs(`search-query` = "N81655")
      session$elapse(400)
      session$setInputs(`search-pick` = paste0("practice:", practice))
      expect_match(output$profile$html, "N81655", fixed = TRUE)
      expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")
      expect_identical(top_rows(output$top_table)$code, all$bnf_code[1:4])
      session$setInputs(next_page = 1)
      expect_identical(top_rows(output$top_table)$code, all$bnf_code[5:8])
      session$setInputs(previous_page = 1)
      expect_identical(top_rows(output$top_table)$code, all$bnf_code[1:4])
      expect_identical(session$returned()$data, fetch_practice_series(con, practice, span))
    }
  )
})

test_that("the app's Practice tab is the Practice view", {
  page <- htmltools::renderTags(app_ui(NULL))$html
  expect_match(page, "id=\"practice-search-pick\"", fixed = TRUE)
  expect_match(page, "id=\"practice-body\"", fixed = TRUE)
})

test_that("a profile that cannot be fetched shows the error, and nothing to download", {
  fake <- fake_practice_fetches()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    fake$calls$profile <- "fail"
    suppressMessages(pick_practice(session))
    body <- suppressMessages(output$body$html)
    expect_match(body, "The data could not be fetched.", fixed = TRUE)
    expect_match(body, "id=\"[a-z0-9]+-retry\"")
    expect_null(suppressMessages(session$returned()))
    fake$calls$profile <- "rows"
    session$setInputs(retry = clicked(1))
    expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")
    expect_false(is.null(session$returned()))
  })
})

test_that("the top drugs' Try again fetches them only, and a redrawn button nothing", {
  fake <- fake_practice_fetches()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    pick_practice(session)
    output$body
    fake$calls$top_state <- "fail"
    suppressMessages(session$setInputs(measure = "nic"))
    suppressMessages(output$top_message)
    tops <- length(fake$calls$top)
    series <- length(fake$calls$series)
    session$setInputs(retry_top = clicked(0))
    expect_length(fake$calls$top, tops)
    fake$calls$top_state <- "rows"
    session$setInputs(retry_top = clicked(1))
    output$top_table
    expect_length(fake$calls$top, tops + 1L)
    expect_length(fake$calls$series, series)
  })
})

test_that("the chart follows the measure and the months", {
  fake <- fake_practice_fetches()
  # The chart's name and description, read from its SVG
  chart_text <- function(chart, tag) {
    html <- jsonlite::fromJSON(as.character(chart), simplifyVector = FALSE)$x$html
    found <- regmatches(html, regexpr(paste0("<", tag, "[^>]*>[^<]*</", tag, ">"), html))
    sub("^<[^>]*>([^<]*)</[^>]*>$", "\\1", found)
  }
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    pick_practice(session)
    expect_identical(chart_text(output$chart, "title"), "THE SURGERY")
    expect_match(
      chart_text(output$chart, "desc"), "^Items by month, Oct 2025 \u2013 Sep 2026: 0 items"
    )
    session$setInputs(measure = "nic", from = "202601")
    expect_match(
      chart_text(output$chart, "desc"),
      "^Net ingredient cost by month, Jan \u2013 Sep 2026: \u00a30.00 in Jan 2026"
    )
  })
})

test_that("the table shows each drug's figures, and page one of another practice", {
  fake <- fake_practice_fetches()
  two <- rbind(practice_matches, transform(practice_matches, practice_id = 13L))
  fake$fetches$search_practices <- function(q) two
  buttons <- local_paging()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    pick_practice(session)
    shown <- top_rows(output$top_table)
    expected <- ranked_drugs(7L)[1:3, ]
    expect_identical(shown$items, as.integer(expected$items))
    expect_equal(shown$nic, expected$nic)
    expect_equal(shown$actual_cost, expected$actual_cost)
    session$setInputs(next_page = 1)
    expect_identical(top_rows(output$top_table)$rank, 4:6)
    # Another practice: page one
    session$setInputs(`search-pick` = "practice:13")
    expect_identical(top_rows(output$top_table)$rank, 1:3)
    expect_identical(
      fake$calls$top[[length(fake$calls$top)]][c("practice_id", "after")],
      list(practice_id = 13L, after = NULL)
    )
    expect_false(buttons$previous)
  })
})

test_that("back on an earlier ranking, the view is on its page one", {
  fake <- fake_practice_fetches()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    pick_practice(session)
    session$setInputs(next_page = 1)
    expect_identical(top_rows(output$top_table)$rank, 4:6)
    session$setInputs(measure = "nic")
    expect_identical(top_rows(output$top_table)$rank, 1:3)
    session$setInputs(measure = "items")
    expect_identical(top_rows(output$top_table)$rank, 1:3)
  })
})

test_that("a practice with no drugs in the months says so", {
  fake <- fake_practice_fetches()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    fake$calls$top_state <- "none"
    pick_practice(session)
    expect_match(output$top_message$html, "No drugs to show.", fixed = TRUE)
  })
})

test_that("without a window, the practice view says why", {
  fake <- fake_practice_fetches()
  shiny::testServer(
    mod_practice_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(NULL), page_size = 3L),
    {
      pick_practice(session)
      expect_match(
        output$body$html, "The data could not be fetched. The app is trying again.", fixed = TRUE
      )
      expect_identical(output$title, "THE SURGERY")
      expect_null(session$returned())
    }
  )
})

test_that("the CSV is the practice's monthly totals", {
  fake <- fake_practice_fetches()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    pick_practice(session)
    path <- output$csv
    expect_identical(basename(path), "prexp-practice-N81655-the-surgery-202510-202609.csv")
    expect_equal(
      utils::read.csv(path), as.data.frame(session$returned()$data), ignore_attr = TRUE
    )
    expect_identical(nrow(utils::read.csv(path)), 12L)
  })
})

test_that("Add to report pins the practice view with its parameters", {
  fake <- fake_practice_fetches()
  pinned <- shiny::reactiveVal(new_report())
  local_mocked_bindings(showNotification = function(ui, ...) invisible(NULL), .package = "shiny")
  shiny::testServer(
    mod_practice_server,
    args = list(
      fetches = fake$fetches, window = shiny::reactive(practice_window), report = pinned
    ),
    {
      pick_practice(session)
      session$setInputs(pin = clicked(1))
      expect_length(pinned()$items, 1L)
      expect_identical(pinned()$items[[1]]$view, "practice")
      expect_identical(pinned()$items[[1]]$params, session$returned()$params)
    }
  )
})

test_that("months, measure and another practice change the frame's outputs in place", {
  fake <- fake_practice_fetches()
  other <- transform(
    practice_matches, practice_id = 13L, practice_code = "B86034", practice_name = "OTHER SURGERY"
  )
  fake$fetches$search_practices <- function(q) rbind(practice_matches, other)
  fake$fetches$practice_profile <- function(practice_id) {
    if (identical(practice_id, 13L)) {
      transform(practice_profile_row, practice_id = 13L, practice_code = "B86034")
    } else {
      practice_profile_row
    }
  }
  frames <- 0L
  body <- practice_body
  local_mocked_bindings(practice_body = function(ns, state) {
    if (identical(state$kind, "results")) frames <<- frames + 1L
    body(ns, state)
  })
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    pick_practice(session)
    output$body
    expect_identical(frames, 1L)
    expect_match(output$profile$html, "N81655", fixed = TRUE)
    session$setInputs(from = "202601")
    session$setInputs(measure = "nic")
    expect_s3_class(output$chart, "json")
    expect_identical(output$top_title, "Top drugs by net ingredient cost")
    session$setInputs(`search-pick` = "practice:13")
    expect_match(output$profile$html, "B86034", fixed = TRUE)
    expect_no_match(output$profile$html, "N81655", fixed = TRUE)
    expect_identical(frames, 1L)
  })
})

test_that("after Try again, the paging buttons are set for the page shown", {
  fake <- fake_practice_fetches()
  buttons <- local_paging()
  shiny::testServer(mod_practice_server, args = practice_args(fake), {
    fake$calls$state <- "fail"
    suppressMessages(pick_practice(session))
    expect_match(output$body$html, "The data could not be fetched.", fixed = TRUE)
    # The body drawn anew draws its buttons off: they must be set again
    buttons$more <- NA
    fake$calls$state <- "rows"
    session$setInputs(retry = clicked(1))
    expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")
    expect_true(buttons$more)
    expect_false(buttons$previous)
  })
})
