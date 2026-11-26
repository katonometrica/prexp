# The Drug view (P4-04), with fake fetches: the arguments it passes, quantity
# hidden for a chemical substance, its three states, and current_view().

drug_window <- tibble::tibble(
  first_month = 202510L, last_month = 202609L, months = 12L, loaded_at = Sys.time()
)

drug_matches <- tibble::tibble(
  level = c("chemical", "presentation"), id = c(57L, 300L),
  code = c("0212000B0", "0212000B0AAABAB"),
  name = c("Atorvastatin", "Atorvastatin 20mg tablets"),
  chemical_id = c(57L, 57L), chemical_name = c("Atorvastatin", "Atorvastatin"),
  is_generic = c(NA, TRUE)
)

drug_series_rows <- tibble::tibble(
  year_month = c(202608L, 202609L), measure = "items", value = c(120, 130),
  practices = c(4L, 5L)
)

drug_presentation_rows <- tibble::tibble(
  presentation_id = 300L, bnf_code = "0212000B0AAABAB",
  bnf_description = "Atorvastatin 20mg tablets", is_generic = TRUE, items = 250,
  total_quantity = 7000, adq_usage = 7000, nic = 98.5, actual_cost = 91.2
)

# Fake fetches that record their arguments; `state` sets what the series
# fetch does: "rows", "none", "na" (rows without values) or "fail", and
# `listed` what the presentations fetch does: "rows" or "fail"
fake_drug_fetches <- function() {
  calls <- new.env(parent = emptyenv())
  calls$series <- list()
  calls$presentations <- list()
  calls$state <- "rows"
  calls$listed <- "rows"
  fetches <- list(
    search_drugs = function(q) drug_matches,
    drug_series = function(level, id, months, measure) {
      calls$series[[length(calls$series) + 1L]] <- list(
        level = level, id = id, months = months, measure = measure
      )
      switch(calls$state,
        rows = drug_series_rows,
        none = drug_series_rows[0, ],
        na = transform(drug_series_rows, value = NA_real_),
        fail = stop("the database is down")
      )
    },
    drug_presentations = function(chemical_id, months) {
      calls$presentations[[length(calls$presentations) + 1L]] <- list(
        chemical_id = chemical_id, months = months
      )
      if (calls$listed == "fail") {
        stop("the database is down")
      }
      drug_presentation_rows
    }
  )
  list(fetches = fetches, calls = calls)
}

# Picks a match through the view's own search, as a user does
pick_drug <- function(session, value) {
  session$setInputs(`search-query` = "atorva")
  session$elapse(400)
  session$setInputs(`search-pick` = value)
}

last_call <- function(calls) calls[[length(calls)]]

test_that("with nothing picked the view asks for a drug", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      expect_match(output$body$html, "Search for a chemical substance or a presentation")
      expect_identical(output$title, "Drug")
      expect_null(session$returned())
      expect_length(fake$calls$series, 0L)
    }
  )
})

test_that("the series is fetched with the drug, the months and the measure chosen", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      pick_drug(session, "chemical:57")
      expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")
      expect_identical(
        last_call(fake$calls$series),
        list(level = "chemical", id = 57L, months = c(202510L, 202609L), measure = "items")
      )
      # The chemical substance's presentations, over the same months
      expect_match(output$body$html, "id=\"[a-z0-9]+-presentations\"")
      expect_identical(
        last_call(fake$calls$presentations), list(chemical_id = 57L, months = c(202510L, 202609L))
      )
      session$setInputs(from = "202609", to = "202607", measure = "nic")
      expect_identical(
        last_call(fake$calls$series),
        list(level = "chemical", id = 57L, months = c(202607L, 202609L), measure = "nic")
      )
      expect_identical(output$title, "Atorvastatin, Jul \u2013 Sep 2026")
      expect_s3_class(output$chart, "json")
    }
  )
})

test_that("quantity is offered for a presentation only", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      pick_drug(session, "chemical:57")
      expect_no_match(output$measure_ui$html, "total_quantity", fixed = TRUE)
      # A quantity chosen before, kept by the browser, gives way to items
      session$setInputs(measure = "total_quantity")
      expect_identical(last_call(fake$calls$series)$measure, "items")
      pick_drug(session, "presentation:300")
      expect_match(output$measure_ui$html, "total_quantity", fixed = TRUE)
      session$setInputs(measure = "total_quantity")
      expect_identical(
        last_call(fake$calls$series),
        list(
          level = "presentation", id = 300L, months = c(202510L, 202609L),
          measure = "total_quantity"
        )
      )
      # No presentations table for a presentation
      expect_no_match(output$body$html, "-presentations\"", fixed = TRUE)
    }
  )
})

test_that("no rows say so, and an error offers to try again", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      fake$calls$state <- "none"
      pick_drug(session, "chemical:57")
      expect_match(
        output$body$html, "Atorvastatin was not prescribed in Oct 2025 \u2013 Sep 2026.",
        fixed = TRUE
      )
      expect_null(session$returned())
      session$setInputs(measure = "adq_usage")
      expect_match(output$body$html, "No ADQ is defined for Atorvastatin", fixed = TRUE)
      # Rows without values (a drug with no ADQ): no chart, and nothing to download
      fake$calls$state <- "na"
      session$setInputs(from = "202601")
      expect_match(output$body$html, "No ADQ is defined for Atorvastatin", fixed = TRUE)
      expect_null(session$returned())

      # The log says why a fetch failed; the page only that it did
      fake$calls$state <- "fail"
      logged <- testthat::capture_messages({
        session$setInputs(measure = "nic")
        body <- output$body$html
      })
      expect_identical(logged, "A fetch failed: the database is down\n")
      expect_match(body, "The data could not be fetched.", fixed = TRUE)
      expect_match(output$body$html, "id=\"[a-z0-9]+-retry\"")
      expect_null(session$returned())

      # Once the database answers again, Try again shows the series
      fake$calls$state <- "rows"
      session$setInputs(retry = 1)
      expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")
    }
  )
})

test_that("current_view() carries the view, its parameters and the data shown", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      pick_drug(session, "chemical:57")
      session$setInputs(measure = "actual_cost")
      expect_identical(
        session$returned(),
        list(
          view = "drug",
          params = list(
            level = "chemical", id = 57L, code = "0212000B0", label = "Atorvastatin",
            months = c(202510L, 202609L), measure = "actual_cost"
          ),
          # Every month of the range: those without a row at 0, as the chart
          # draws them
          data = tibble::tibble(
            year_month = c(202510:202512, 202601:202609),
            measure = c(rep("actual_cost", 10L), "items", "items"),
            value = c(rep(0, 10L), 120, 130), practices = c(rep(0L, 10L), 4L, 5L)
          )
        )
      )
    }
  )
})

test_that("the month controls offer the window's months, latest first", {
  ui <- as.character(months_controls(shiny::NS("drug"), drug_window))
  expect_match(ui, "<option value=\"202609\" selected>Sep 2026</option>", fixed = TRUE)
  expect_match(ui, "<option value=\"202510\" selected>Oct 2025</option>", fixed = TRUE)
  expect_identical(
    names(months_of_window(drug_window))[c(1, 12)], c("Sep 2026", "Oct 2025")
  )
  expect_match(as.character(months_controls(shiny::NS("x"), NULL)), "No months are loaded yet")
  expect_identical(chosen_months(NULL, NULL, drug_window), c(202510L, 202609L))
  expect_identical(chosen_months("202609", "202601", drug_window), c(202601L, 202609L))
  expect_null(chosen_months(NULL, NULL, NULL))
})

test_that("the presentations table marks brand, generic and neither", {
  rows <- rbind(
    drug_presentation_rows,
    transform(drug_presentation_rows, presentation_id = 301L, is_generic = FALSE),
    transform(drug_presentation_rows, presentation_id = 302L, is_generic = NA)
  )
  table <- presentations_table(rows)
  expect_s3_class(table, "reactable")
  data <- jsonlite::fromJSON(as.character(table$x$tag$attribs$data))
  expect_identical(data$kind, c("Generic", "Brand", "\u2013"))
})

test_that("the app's Drug tab is the Drug view", {
  page <- htmltools::renderTags(app_ui(NULL))$html
  expect_match(page, "id=\"drug-search-pick\"", fixed = TRUE)
  expect_match(page, "id=\"drug-body\"", fixed = TRUE)
})

test_that("tables write numbers the British way, whatever the browser's language", {
  expect_identical(count_column("Items")$format$cell$locales, "en-GB")
  expect_identical(pounds_column("Cost")$format$cell$locales, "en-GB")
  expect_identical(pounds_column("Cost")$format$cell$prefix, "\u00a3")
})

test_that("an output's width is the one the browser reports, none until it does", {
  session <- list(ns = shiny::NS("drug"), clientData = list(`output_drug-chart_width` = 500))
  expect_identical(output_width(session, "chart"), 500)
  # Not reported yet, or not shown (a tab not shown reports 0)
  session$clientData <- list()
  expect_null(output_width(session, "chart"))
  session$clientData <- list(`output_drug-chart_width` = 0)
  expect_null(output_width(session, "chart"))
})

test_that("charts are drawn at the body's width, to 10 px, and again only for 30 px or more", {
  sizes <- shiny::reactiveValues()
  fake_session <- list(ns = shiny::NS("view"), clientData = sizes)
  seen <- new.env()
  seen$widths <- numeric()
  shiny::testServer(
    function(id) {
      shiny::moduleServer(id, function(input, output, session) {
        width <- chart_width(fake_session)
        shiny::observe(seen$widths <- c(seen$widths, width()))
      })
    },
    {
      # Nothing until the body's width is known
      session$flushReact()
      expect_null(width())
      sizes[["output_view-body_width"]] <- 1222
      session$flushReact()
      expect_identical(width(), 1220)
      # A scroll bar appears: 15 px less is not drawn again
      sizes[["output_view-body_width"]] <- 1207
      session$flushReact()
      expect_identical(width(), 1220)
      # The tab is not shown: the width stays
      sizes[["output_view-body_width"]] <- 0
      session$flushReact()
      expect_identical(width(), 1220)
      # A narrower window is
      sizes[["output_view-body_width"]] <- 863
      session$flushReact()
      expect_identical(width(), 860)
      expect_identical(seen$widths, c(1220, 860))
    }
  )
})

test_that("compute_always() asks Shiny to compute each output, shown or not", {
  asked <- list()
  impl <- list(outputOptions = function(name, ...) asked[[name]] <<- list(...))
  output <- structure(list(impl = impl, ns = shiny::NS("drug")), class = "shinyoutput")
  compute_always(output, c("chart", "body"))
  computed <- list(suspendWhenHidden = FALSE)
  expect_identical(asked, list(`drug-chart` = computed, `drug-body` = computed))
})

test_that("each view's frame outputs come in the flush that draws the frame", {
  computed <- list()
  local_mocked_bindings(compute_always = function(output, names) {
    computed[[length(computed) + 1L]] <<- names
  })
  views <- list(
    drug = list(mod_drug_server, fake_drug_fetches()$fetches),
    region = list(mod_region_server, list(search_drugs = function(q) drug_matches)),
    practice = list(mod_practice_server, list(search_practices = function(q) drug_matches[0, ]))
  )
  for (view in views) {
    shiny::testServer(
      view[[1]], args = list(fetches = view[[2]], window = shiny::reactive(drug_window)), {}
    )
  }
  expect_length(computed, 3L)
  expect_setequal(computed[[1]], c("csv", "chart", "presentations"))
  expect_setequal(computed[[2]], c("csv", "chart", "table"))
  expect_setequal(
    computed[[3]],
    c("csv", "profile", "chart", "top_title", "top_message", "top_table", "top_range")
  )
})

test_that("a change of months or measure draws the chart and table again, not the body", {
  fake <- fake_drug_fetches()
  frames <- 0L
  body <- drug_body
  local_mocked_bindings(drug_body = function(ns, state) {
    if (identical(state$kind, "results")) frames <<- frames + 1L
    body(ns, state)
  })
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      pick_drug(session, "chemical:57")
      output$body
      expect_identical(frames, 1L)
      session$setInputs(from = "202601")
      session$setInputs(measure = "nic")
      expect_s3_class(output$chart, "json")
      expect_s3_class(output$presentations, "json")
      expect_identical(frames, 1L)
      # A presentation's results have no presentations: another frame
      pick_drug(session, "presentation:300")
      output$body
      expect_identical(frames, 2L)
    }
  )
})

test_that("the presentations are not built behind a message", {
  fake <- fake_drug_fetches()
  built <- 0L
  table <- presentations_table
  local_mocked_bindings(presentations_table = function(rows) {
    built <<- built + 1L
    table(rows)
  })
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      fake$calls$state <- "na"
      pick_drug(session, "chemical:57")
      expect_match(output$body$html, "was not prescribed", fixed = TRUE)
      expect_error(output$presentations)
      expect_identical(built, 0L)
      fake$calls$state <- "rows"
      session$setInputs(from = "202601")
      expect_s3_class(output$presentations, "json")
      expect_identical(built, 1L)
    }
  )
})

test_that("a measure the new level does not allow is never fetched", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      pick_drug(session, "presentation:300")
      session$setInputs(measure = "total_quantity")
      expect_identical(last_call(fake$calls$series)$measure, "total_quantity")
      before <- length(fake$calls$series)
      expect_no_message(pick_drug(session, "chemical:57"))
      after <- fake$calls$series[-seq_len(before)]
      expect_gt(length(after), 0L)
      for (call in after) {
        expect_identical(call$level, "chemical")
        expect_identical(call$measure, "items")
      }
    }
  )
})

test_that("a control's first value, the same as the view shows, fetches nothing again", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      pick_drug(session, "chemical:57")
      output$chart
      fetched <- length(fake$calls$series)
      session$setInputs(from = "202510", to = "202609", measure = "items")
      output$chart
      expect_length(fake$calls$series, fetched)
    }
  )
})

test_that("each chart is kept by what it is drawn from: data, months, measure, width", {
  fake <- fake_drug_fetches()
  fake$fetches$chart <- cache_value(app_cache(), "chart", function() drug_window)
  draws <- 0L
  draw <- render_girafe
  local_mocked_bindings(render_girafe = function(...) {
    draws <<- draws + 1L
    draw(...)
  })
  desc <- function(chart) {
    html <- jsonlite::fromJSON(chart)$x$html
    regmatches(html, regexpr("<desc[^>]*>[^<]*</desc>", html))
  }
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      pick_drug(session, "chemical:57")
      items <- desc(output$chart)
      expect_identical(draws, 1L)
      session$setInputs(measure = "nic")
      # The fake's rows are the same whatever the measure, so only the key
      # tells the two charts apart: each is drawn
      nic <- desc(output$chart)
      expect_identical(draws, 2L)
      session$setInputs(from = "202601")
      expect_identical(draws, 3L)
      # Back to a chart drawn before: kept, not drawn again
      session$setInputs(from = "202510", measure = "items")
      expect_identical(desc(output$chart), items)
      expect_identical(draws, 3L)
    }
  )
})

test_that("a Try again that fails again says so, and the message stays as it is", {
  fake <- fake_drug_fetches()
  said <- character()
  local_mocked_bindings(announce = function(session, text) said <<- c(said, text))
  frames <- 0L
  body <- drug_body
  local_mocked_bindings(drug_body = function(ns, state) {
    frames <<- frames + 1L
    body(ns, state)
  })
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      fake$calls$state <- "fail"
      suppressMessages(pick_drug(session, "chemical:57"))
      expect_match(output$body$html, "The data could not be fetched.", fixed = TRUE)
      drawn <- frames
      suppressMessages(session$setInputs(retry = 1))
      expect_identical(said, "The data could still not be fetched.")
      expect_identical(frames, drawn)
      # One that works draws the results, and says nothing
      fake$calls$state <- "rows"
      session$setInputs(retry = 2)
      expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")
      expect_length(said, 1L)
    }
  )
})

test_that("the view shows a drug's series and presentations on the fixture database", {
  con <- fixture_app()
  chemical <- id_of(con, "chemical", "0212000B0")
  fetches <- app_fetches(con)
  window <- fetches$window()
  # Not `months`: in testServer() that name is the module's own reactive
  span <- c(window$first_month, window$last_month)
  # Not `series` either: the module has one too
  expected <- fetch_drug_series(con, "chemical", chemical, span, "items")
  expect_gt(nrow(expected), 1L)
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fetches, window = shiny::reactive(window)),
    {
      session$setInputs(`search-query` = "atorva")
      session$elapse(400)
      session$setInputs(`search-pick` = paste0("chemical:", chemical))
      body <- output$body$html
      expect_match(body, "id=\"[a-z0-9]+-chart\"")
      expect_match(body, "id=\"[a-z0-9]+-presentations\"")
      expect_identical(session$returned()$data, expected)
      table <- output$presentations
      expect_s3_class(table, "json")
    }
  )
})

# An action button's value as the browser sends it, which observeEvent()
# ignores at 0
clicked <- function(n) structure(as.integer(n), class = "shinyActionButtonValue")

test_that("a presentation has no presentations fetched", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      pick_drug(session, "presentation:300")
      expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")
      expect_length(fake$calls$presentations, 0L)
    }
  )
})

test_that("presentations that cannot be fetched say so, under the series", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      fake$calls$listed <- "fail"
      suppressMessages(pick_drug(session, "chemical:57"))
      body <- suppressMessages(output$body$html)
      expect_match(body, "id=\"[a-z0-9]+-chart\"")
      expect_match(body, "The presentations could not be fetched.", fixed = TRUE)
      expect_match(body, "id=\"[a-z0-9]+-retry\"")
      # A button drawn again sends 0, which fetches nothing again
      fetched <- length(fake$calls$presentations)
      session$setInputs(retry = clicked(0))
      expect_length(fake$calls$presentations, fetched)
      # A click fetches both again
      fake$calls$listed <- "rows"
      series <- length(fake$calls$series)
      session$setInputs(retry = clicked(1))
      expect_match(output$body$html, "id=\"[a-z0-9]+-presentations\"")
      expect_length(fake$calls$presentations, fetched + 1L)
      expect_length(fake$calls$series, series + 1L)
    }
  )
})

test_that("without a window, the view says why, and has nothing to download", {
  fake <- fake_drug_fetches()
  window <- shiny::reactiveVal(NULL)
  shiny::testServer(
    mod_drug_server, args = list(fetches = fake$fetches, window = window),
    {
      pick_drug(session, "chemical:57")
      expect_match(
        output$body$html, "The data could not be fetched. The app is trying again.", fixed = TRUE
      )
      expect_identical(output$title, "Atorvastatin")
      expect_null(session$returned())
      expect_length(fake$calls$series, 0L)
      # No month loaded yet
      window(drug_window[0, ])
      session$flushReact()
      expect_match(output$body$html, "No data is loaded yet.", fixed = TRUE)
      # Once the window comes, the series follows
      window(drug_window)
      session$flushReact()
      expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")
    }
  )
})

test_that("quantity and ADQ usage keep their fractions in the table, and no cell wraps", {
  rows <- transform(drug_presentation_rows, adq_usage = 0.496, total_quantity = 2.5)
  table <- presentations_table(rows)
  columns <- table$x$tag$attribs$columns
  names(columns) <- vapply(columns, function(column) column$id, "")
  data <- jsonlite::fromJSON(as.character(table$x$tag$attribs$data))
  # The cells show the text written for the whole column, kept in hidden
  # columns, and sort by the values
  expect_identical(data$adq_text, "0.496")
  expect_identical(data$quantity_text, "2.5")
  expect_identical(
    as.character(columns$adq_usage$cell), "function(cell) { return cell.row[\"adq_text\"] }"
  )
  expect_identical(
    as.character(columns$total_quantity$cell),
    "function(cell) { return cell.row[\"quantity_text\"] }"
  )
  expect_false(columns$adq_text$show)
  expect_false(columns$quantity_text$show)
  expect_identical(c(data$adq_usage, data$total_quantity), c(0.496, 2.5))
  for (id in c("items", "nic", "adq_usage")) {
    expect_identical(columns[[id]]$style, list(whiteSpace = "nowrap"), label = id)
  }
  # The BNF code on one line too, in the brand's mono font
  expect_identical(columns$code$style, code_style)
  expect_identical(code_style$whiteSpace, "nowrap")
  expect_identical(code_style$fontFamily, "var(--bs-font-monospace)")
  # A table that gives no label writes its cells in R, as the short tables do
  expect_identical(measure_column("ADQ usage", "adq_usage")$cell(0.496), "0.496")
})

test_that("a chemical's thousands of presentations are written once per column (#101)", {
  rows <- drug_presentation_rows[rep(1L, 2000L), ]
  rows$total_quantity <- seq_len(2000L) / 7
  rows$adq_usage <- seq_len(2000L) / 3
  calls <- 0L
  format <- format_measure
  local_mocked_bindings(format_measure = function(...) {
    calls <<- calls + 1L
    format(...)
  })
  table <- presentations_table(rows)
  expect_identical(calls, 2L)
  data <- jsonlite::fromJSON(as.character(table$x$tag$attribs$data))
  expect_identical(data$quantity_text[c(1L, 2000L)], c("0.143", "286"))
  expect_identical(data$adq_text[c(1L, 2000L)], c("0.333", "667"))
})

test_that("a measure sent again, as a redrawn control does, fetches nothing again", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      pick_drug(session, "chemical:57")
      session$setInputs(measure = "nic")
      output$body
      fetched <- length(fake$calls$series)
      session$setInputs(measure = "nic")
      output$body
      expect_length(fake$calls$series, fetched)
      session$setInputs(measure = "items")
      output$body
      expect_length(fake$calls$series, fetched + 1L)
    }
  )
})

test_that("table columns are wide enough for their longest figures", {
  expect_identical(count_column("Items")$minWidth, 125)
  expect_identical(pounds_column("Cost")$minWidth, 140)
  expect_identical(measure_column("ADQ usage", "adq_usage")$minWidth, 125)
  expect_identical(measure_column("Cost", "nic")$format$cell$prefix, "\u00a3")
  expect_equal(measure_column("Items", "items")$format$cell$digits, 0)
})

test_that("the CSV is the current view's data, named by view, subject and months", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      expect_null(output$csv_ui)
      pick_drug(session, "chemical:57")
      expect_match(output$csv_ui$html, "id=\"[a-z0-9]+-csv\"")
      path <- output$csv
      expect_identical(basename(path), "prexp-drug-0212000B0-atorvastatin-items-202510-202609.csv")
      expect_equal(
        utils::read.csv(path), as.data.frame(session$returned()$data), ignore_attr = TRUE
      )
    }
  )
})

test_that("a CSV's name has the subject's code, name and measure, in letters and digits", {
  view <- function(label, code = "0407010F0", type = "region", measure = "nic") {
    list(view = type, params = list(
      label = label, id = 7L, code = code, months = c(202601L, 202609L), measure = measure
    ))
  }
  expect_identical(
    csv_name(view("Co-codamol 30mg/500mg tablets")),
    "prexp-region-0407010F0-co-codamol-30mg-500mg-tablets-nic-202601-202609.csv"
  )
  # The name to 40 characters; the practice's file holds every measure
  long <- csv_name(view(
    "ST WERBURGH'S MEDICAL PRACTICE FOR THE HOMELESS PEOPLE OF CHESTER", "N81655", "practice"
  ))
  expect_identical(
    long, "prexp-practice-N81655-st-werburgh-s-medical-practice-for-the-h-202601-202609.csv"
  )
  # A name of no letters or digits, a missing name, and no code
  expect_identical(
    csv_name(view(intToUtf8(c(0xb5, 0xb5)))), "prexp-region-0407010F0-nic-202601-202609.csv"
  )
  expect_identical(
    csv_name(view(NA_character_, code = NA_character_)), "prexp-region-7-nic-202601-202609.csv"
  )
  # Two subjects of the same name differ by their codes
  expect_false(identical(
    csv_name(view("High Street Surgery", "N81013")), csv_name(view("High Street Surgery", "Y00001"))
  ))
})

test_that("a CSV writes every number in full, never as 4e+05", {
  path <- withr::local_tempfile(fileext = ".csv")
  withr::local_options(scipen = 0)
  view <- list(data = tibble::tibble(
    region_code = c("-", "Y61", "Y62", "Y63"), measure = "items",
    value = c(NA, 4e5, 2e-4, 1234.5678)
  ))
  write_view_csv(view, path)
  expect_identical(readLines(path), c(
    "\"region_code\",\"measure\",\"value\"", "\"-\",\"items\",",
    "\"Y61\",\"items\",400000", "\"Y62\",\"items\",0.0002", "\"Y63\",\"items\",1234.5678"
  ))
  expect_equal(getOption("scipen"), 0)
})

test_that("a CSV holds every month of the range, those without a row at 0", {
  rows <- tibble::tibble(year_month = c(202602L, 202604L), value = c(5, 7), practices = 2L)
  filled <- complete_months(rows, c(202601L, 202605L), list(value = 0, practices = 0L))
  expect_identical(filled$year_month, 202601:202605)
  expect_identical(filled$value, c(0, 5, 0, 7, 0))
  expect_identical(filled$practices, c(0L, 2L, 0L, 2L, 0L))
})

test_that("the CSV button reads Download CSV to a screen reader, and says what the file holds", {
  fake <- fake_drug_fetches()
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window)),
    {
      pick_drug(session, "chemical:57")
      button <- output$csv_ui$html
      expect_match(button, "<span class=\"visually-hidden\">Download</span>", fixed = TRUE)
      expect_match(button, "title=\"Download the monthly totals, as CSV\"", fixed = TRUE)
    }
  )
})

test_that("Add to report pins the view with its parameters, off until there is one and when full", {
  fake <- fake_drug_fetches()
  pinned <- shiny::reactiveVal(new_report())
  toasts <- character()
  said <- character()
  offs <- logical()
  local_mocked_bindings(
    showNotification = function(ui, ...) {
      toasts <<- c(toasts, ui)
      invisible(NULL)
    },
    updateActionButton = function(session, ..., disabled = NULL) {
      offs <<- c(offs, disabled)
      invisible(NULL)
    },
    .package = "shiny"
  )
  local_mocked_bindings(announce = function(session, text) said <<- c(said, text))
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window), report = pinned),
    {
      session$flushReact()
      expect_identical(offs, TRUE)
      # A click with nothing shown pins nothing
      session$setInputs(pin = clicked(1))
      expect_length(pinned()$items, 0L)
      pick_drug(session, "chemical:57")
      expect_false(utils::tail(offs, 1L))
      session$setInputs(pin = clicked(2))
      expect_length(pinned()$items, 1L)
      expect_identical(pinned()$items[[1]]$view, "drug")
      expect_identical(pinned()$items[[1]]$params, session$returned()$params)
      # The toast, and the status region for a screen reader, say so
      expect_identical(utils::tail(toasts, 1L), paste0(
        "Added to the report: Atorvastatin \u00b7 items \u00b7 Oct 2025 to Sep 2026. ",
        "It holds 1 of 15 items."
      ))
      expect_identical(said, toasts)
      # Full: the button goes off, and a click is refused with a toast
      full <- pinned()
      while (length(full$items) < 15L) {
        full <- report_add(full, "drug", full$items[[1]]$params)
      }
      pinned(full)
      session$flushReact()
      expect_true(utils::tail(offs, 1L))
      session$setInputs(pin = clicked(3))
      expect_length(pinned()$items, 15L)
      expect_match(utils::tail(toasts, 1L), "at most 15 items", fixed = TRUE)
      expect_identical(utils::tail(said, 1L), utils::tail(toasts, 1L))
      # One item removed elsewhere: the button is on again
      pinned(report_remove(pinned(), 3L))
      session$flushReact()
      expect_false(utils::tail(offs, 1L))
    }
  )
})

test_that("a drug whose name ends in a tab pins, its label without it", {
  fake <- fake_drug_fetches()
  matches <- drug_matches
  matches$name[2] <- paste0(matches$name[2], "\t")
  fake$fetches$search_drugs <- function(q) matches
  pinned <- shiny::reactiveVal(new_report())
  local_mocked_bindings(showNotification = function(ui, ...) invisible(NULL), .package = "shiny")
  local_mocked_bindings(announce = function(session, text) invisible(NULL))
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window), report = pinned),
    {
      pick_drug(session, "presentation:300")
      expect_match(session$returned()$params$label, "\t$")
      session$setInputs(pin = clicked(1))
      expect_identical(pinned()$items[[1]]$params$label, "Atorvastatin 20mg tablets")
    }
  )
  expect_identical(pin_label(" a\tb\n\nc\t"), "a b c")
  expect_identical(pin_label(NA_character_), NA_character_)
  expect_identical(pin_label(intToUtf8(c(97L, 65535L, 133L, 98L))), "a b")
  expect_identical(pin_label(""), "")
})

test_that("a pin the report refuses says so in plain words, and logs only the error's class", {
  fake <- fake_drug_fetches()
  pinned <- shiny::reactiveVal(new_report())
  toasts <- character()
  local_mocked_bindings(
    showNotification = function(ui, ...) {
      toasts <<- c(toasts, ui)
      invisible(NULL)
    },
    .package = "shiny"
  )
  local_mocked_bindings(
    announce = function(session, text) invisible(NULL),
    report_add = function(...) invalid_argument("`label` must be one line of text")
  )
  shiny::testServer(
    mod_drug_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(drug_window), report = pinned),
    {
      pick_drug(session, "chemical:57")
      expect_message(
        session$setInputs(pin = clicked(1)), "A pin was refused: prexp_invalid_argument"
      )
      expect_length(pinned()$items, 0L)
      expect_identical(toasts, "This view could not be added to the report.")
    }
  )
})

test_that("the view's header has the Add to report button, off at first", {
  html <- htmltools::renderTags(mod_drug_ui("drug"))$html
  button <- regmatches(html, regexpr("<button[^>]*id=\"drug-pin\"[^>]*>", html))
  expect_match(button, "disabled", fixed = TRUE)
  expect_match(html, ">Add to report</span></button>", fixed = TRUE)
})
