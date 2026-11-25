# The Region view (P4-06), with fake fetches: the arguments it passes, the
# unidentified prescribers apart from the regions, its three states and
# current_view(); then on the fixture database.

region_window <- tibble::tibble(
  first_month = 202510L, last_month = 202609L, months = 12L, loaded_at = Sys.time()
)

region_matches <- tibble::tibble(
  level = c("chemical", "presentation"), id = c(57L, 300L),
  code = c("0212000B0", "0212000B0AAABAB"),
  name = c("Atorvastatin", "Atorvastatin 20mg tablets"),
  chemical_id = c(57L, 57L), chemical_name = c("Atorvastatin", "Atorvastatin"),
  is_generic = c(NA, TRUE)
)

region_rows <- tibble::tibble(
  region_code = c("-", "Y56", "Y58", "Y63"),
  region_name = c("UNIDENTIFIED", "LONDON", "SOUTH WEST", "NORTH EAST AND YORKSHIRE"),
  measure = "items", value = c(20, 300, 180, 500)
)

nhs_regions <- tibble::tibble(
  region_code = c("Y56", "Y58", "Y59", "Y60", "Y61", "Y62", "Y63"),
  region_name = c(
    "LONDON", "SOUTH WEST", "SOUTH EAST", "MIDLANDS", "EAST OF ENGLAND", "NORTH WEST",
    "NORTH EAST AND YORKSHIRE"
  )
)

# The rows the view shows for region_rows: every region, those without a row
# at 0, in order of their codes
region_rows_filled <- function(measure = "items") {
  tibble::tibble(
    region_code = c("-", "Y56", "Y58", "Y59", "Y60", "Y61", "Y62", "Y63"),
    region_name = c(
      "UNIDENTIFIED", "LONDON", "SOUTH WEST", "SOUTH EAST", "MIDLANDS", "EAST OF ENGLAND",
      "NORTH WEST", "NORTH EAST AND YORKSHIRE"
    ),
    measure = measure, value = c(20, 300, 180, 0, 0, 0, 0, 500)
  )
}

# Fake fetches that record their arguments; `state` sets what the
# comparison does: "rows", "none", "na" (no values: no ADQ) or "fail", and
# `nhs` what the regions' fetch does: "rows" or "fail"
fake_region_fetches <- function() {
  calls <- new.env(parent = emptyenv())
  calls$regions <- list()
  calls$state <- "rows"
  calls$nhs <- "rows"
  fetches <- list(
    search_drugs = function(q) region_matches,
    regions = function() {
      if (calls$nhs == "fail") {
        stop("the database is down")
      }
      nhs_regions
    },
    region_comparison = function(level, id, months, measure) {
      calls$regions[[length(calls$regions) + 1L]] <- list(
        level = level, id = id, months = months, measure = measure
      )
      # Not transform(): it would read `measure` from the rows
      rows <- region_rows
      rows$measure <- rep(measure, nrow(rows))
      if (calls$state == "na") {
        rows$value <- NA_real_
      }
      switch(calls$state,
        rows = rows,
        na = rows,
        none = rows[0, ],
        fail = stop("the database is down")
      )
    }
  )
  list(fetches = fetches, calls = calls)
}

pick_region_drug <- function(session, value) {
  session$setInputs(`search-query` = "atorva")
  session$elapse(400)
  session$setInputs(`search-pick` = value)
}

# The rows of the regions table, read from the view's HTML
region_table_rows <- function(html) {
  json <- regmatches(html, regexpr(
    "(?s)<script type=\"application/json\"[^>]*>.*?</script>", html, perl = TRUE
  ))
  json <- sub("(?s)^<script[^>]*>(.*)</script>$", "\\1", json, perl = TRUE)
  jsonlite::fromJSON(json)$x$tag$attribs
}

region_args <- function(fake) {
  list(fetches = fake$fetches, window = shiny::reactive(region_window))
}

test_that("with nothing picked the view asks for a drug", {
  fake <- fake_region_fetches()
  shiny::testServer(mod_region_server, args = region_args(fake), {
    expect_match(output$body$html, "Search for a chemical substance or a presentation")
    expect_identical(output$title, "Region")
    expect_null(session$returned())
    expect_length(fake$calls$regions, 0L)
  })
})

test_that("the regions come for the drug, months and measure chosen, as bars and a table", {
  fake <- fake_region_fetches()
  shiny::testServer(mod_region_server, args = region_args(fake), {
    pick_region_drug(session, "chemical:57")
    expect_identical(
      fake$calls$regions[[length(fake$calls$regions)]],
      list(level = "chemical", id = 57L, months = c(202510L, 202609L), measure = "items")
    )
    expect_identical(output$title, "Atorvastatin by region, Oct 2025 \u2013 Sep 2026")
    body <- output$body$html
    expect_match(body, "id=\"[a-z0-9]+-chart\"")
    table <- region_table_rows(body)
    # The regions largest first, those that did not prescribe it at 0, then the
    # prescribers without a region
    expect_identical(
      table$data$region,
      c(
        "NORTH EAST AND YORKSHIRE", "LONDON", "SOUTH WEST", "SOUTH EAST", "MIDLANDS",
        "EAST OF ENGLAND", "NORTH WEST", "No region: unidentified prescribers"
      )
    )
    expect_identical(table$data$value, c(500L, 300L, 180L, 0L, 0L, 0L, 0L, 20L))
    expect_identical(table$data$share, c(0.5, 0.3, 0.18, 0, 0, 0, 0, 0.02))
    expect_match(body, "count in England's total only", fixed = TRUE)
    # The chart has the regions only
    chart <- output$chart
    expect_s3_class(chart, "json")
    expect_no_match(as.character(chart), "UNIDENTIFIED", fixed = TRUE)
    expect_match(as.character(chart), "NORTH EAST AND YORKSHIRE", fixed = TRUE)
    session$setInputs(from = "202609", to = "202607", measure = "nic")
    expect_identical(
      fake$calls$regions[[length(fake$calls$regions)]],
      list(level = "chemical", id = 57L, months = c(202607L, 202609L), measure = "nic")
    )
    # Quantity for a presentation only
    expect_no_match(output$measure_ui$html, "total_quantity", fixed = TRUE)
    pick_region_drug(session, "presentation:300")
    expect_match(output$measure_ui$html, "total_quantity", fixed = TRUE)
  })
})

test_that("the table's footer is England's total, in the measure's form", {
  table <- region_table(transform(region_rows, measure = "nic"), "nic")
  columns <- table$x$tag$attribs$columns
  footers <- vapply(columns, function(column) as.character(column$footer), "")
  expect_identical(unname(footers), c("England", "\u00a31,000.00", "100.0%"))
  expect_identical(columns[[2]]$name, "Net ingredient cost")
  expect_false(table$x$tag$attribs$sortable)
  # Without a region row, no note; with nothing but zeros, no shares
  regional <- region_rows[region_rows$region_code != "-", ]
  expect_identical(region_shares(regional)$region[3], "SOUTH WEST")
  expect_true(all(is.na(region_shares(within(regional, value <- 0))$share)))
})

test_that("no rows say so, and an error offers to try again", {
  fake <- fake_region_fetches()
  shiny::testServer(mod_region_server, args = region_args(fake), {
    fake$calls$state <- "none"
    pick_region_drug(session, "chemical:57")
    expect_match(
      output$body$html, "Atorvastatin was not prescribed in Oct 2025 \u2013 Sep 2026.",
      fixed = TRUE
    )
    expect_null(session$returned())
    fake$calls$state <- "na"
    session$setInputs(measure = "adq_usage")
    expect_match(output$body$html, "No ADQ is defined for Atorvastatin", fixed = TRUE)
    expect_null(session$returned())

    fake$calls$state <- "fail"
    session$setInputs(measure = "nic")
    expect_match(output$body$html, "The data could not be fetched.", fixed = TRUE)
    expect_match(output$body$html, "id=\"[a-z0-9]+-retry\"")
    expect_null(session$returned())

    fake$calls$state <- "rows"
    session$setInputs(retry = 1)
    expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")
  })
})

test_that("current_view() carries the view, its parameters and the totals shown", {
  fake <- fake_region_fetches()
  shiny::testServer(mod_region_server, args = region_args(fake), {
    pick_region_drug(session, "presentation:300")
    session$setInputs(measure = "total_quantity")
    expect_identical(
      session$returned(),
      list(
        view = "region",
        params = list(
          level = "presentation", id = 300L, code = "0212000B0AAABAB",
          label = "Atorvastatin 20mg tablets", months = c(202510L, 202609L),
          measure = "total_quantity"
        ),
        data = region_rows_filled("total_quantity")
      )
    )
  })
})

test_that("the view shows a drug's regions on the fixture database", {
  con <- fixture_app()
  chemical <- id_of(con, "chemical", "0212000B0")
  fetches <- app_fetches(con)
  window <- fetches$window()
  # Not `months`: in testServer() that name is the module's own reactive
  span <- c(window$first_month, window$last_month)
  expected <- fill_regions(
    fetch_region_comparison(con, "chemical", chemical, span, "items"), fetch_regions(con)
  )
  expect_gt(nrow(expected), 1L)
  shiny::testServer(
    mod_region_server,
    args = list(fetches = fetches, window = shiny::reactive(window)),
    {
      session$setInputs(`search-query` = "atorva")
      session$elapse(400)
      session$setInputs(`search-pick` = paste0("chemical:", chemical))
      body <- output$body$html
      expect_match(body, "id=\"[a-z0-9]+-chart\"")
      table <- region_table_rows(body)
      expect_equal(sum(table$data$value), sum(expected$value))
      expect_length(table$data$region, nrow(expected))
      expect_identical(session$returned()$data, expected)
    }
  )
})

test_that("the app's Region tab is the Region view", {
  page <- htmltools::renderTags(app_ui(NULL))$html
  expect_match(page, "id=\"region-search-pick\"", fixed = TRUE)
  expect_match(page, "id=\"region-body\"", fixed = TRUE)
})

test_that("every region shows, at 0 where the drug was not prescribed", {
  rows <- tibble::tibble(
    region_code = c("Y58", "-", "Y56"), region_name = c("SOUTH WEST", "UNIDENTIFIED", "LONDON"),
    measure = "adq_usage", value = c(2.85, 0.024, NA)
  )
  filled <- fill_regions(rows, nhs_regions)
  expect_identical(filled$region_code, c("-", nhs_regions$region_code))
  # A region that prescribed it without a value (no ADQ) keeps its NA
  expect_identical(filled$value, c(0.024, NA, 2.85, 0, 0, 0, 0, 0))
  expect_identical(fill_regions(region_rows_filled(), nhs_regions), region_rows_filled())
})

test_that("the value column writes each measure in its form", {
  rows <- tibble::tibble(
    region_code = c("Y56", "Y58", "Y59"), region_name = c("LONDON", "SOUTH WEST", "SOUTH EAST"),
    measure = "adq_usage", value = c(2.85, 0.024, NA)
  )
  columns <- region_table(rows, "adq_usage")$x$tag$attribs$columns
  expect_identical(unlist(columns[[2]]$cell), c("2.85", "0.024", "\u2013"))
  cost <- region_table(transform(rows, value = c(10, 20, 30)), "nic")$x$tag$attribs$columns
  expect_identical(cost[[2]]$format$cell$prefix, "\u00a3")
})

test_that("a drug prescribed only without a region has no chart, but its table and note", {
  fake <- fake_region_fetches()
  fake$fetches$region_comparison <- function(level, id, months, measure) {
    region_rows[region_rows$region_code == "-", ]
  }
  shiny::testServer(mod_region_server, args = region_args(fake), {
    pick_region_drug(session, "chemical:57")
    body <- output$body$html
    expect_no_match(body, "-chart\"")
    expect_match(body, "count in England's total only", fixed = TRUE)
    expect_false(is.null(session$returned()))
  })
  # Regions only: no note
  fake <- fake_region_fetches()
  fake$fetches$region_comparison <- function(level, id, months, measure) {
    region_rows[region_rows$region_code != "-", ]
  }
  shiny::testServer(mod_region_server, args = region_args(fake), {
    pick_region_drug(session, "chemical:57")
    expect_no_match(output$body$html, "England's total only", fixed = TRUE)
  })
})

test_that("the regions' own fetch failing is an error, with Try again", {
  fake <- fake_region_fetches()
  shiny::testServer(mod_region_server, args = region_args(fake), {
    fake$calls$nhs <- "fail"
    suppressMessages(pick_region_drug(session, "chemical:57"))
    body <- suppressMessages(output$body$html)
    expect_match(body, "The data could not be fetched.", fixed = TRUE)
    expect_null(suppressMessages(session$returned()))
    fake$calls$nhs <- "rows"
    session$setInputs(retry = 1)
    expect_match(output$body$html, "id=\"[a-z0-9]+-chart\"")
  })
})

test_that("a failure is fetched once, and a measure sent again not at all", {
  fake <- fake_region_fetches()
  shiny::testServer(mod_region_server, args = region_args(fake), {
    fake$calls$state <- "fail"
    suppressMessages(pick_region_drug(session, "chemical:57"))
    suppressMessages(output$body)
    fetched <- length(fake$calls$regions)
    # A Try again drawn again sends 0
    session$setInputs(retry = structure(0L, class = "shinyActionButtonValue"))
    expect_length(fake$calls$regions, fetched)
    fake$calls$state <- "rows"
    session$setInputs(measure = "nic")
    output$body
    fetched <- length(fake$calls$regions)
    session$setInputs(measure = "nic")
    output$body
    expect_length(fake$calls$regions, fetched)
  })
})

test_that("without a window, the region view says why", {
  fake <- fake_region_fetches()
  shiny::testServer(
    mod_region_server, args = list(fetches = fake$fetches, window = shiny::reactive(NULL)),
    {
      pick_region_drug(session, "chemical:57")
      expect_match(
        output$body$html, "The data could not be fetched. The app is trying again.", fixed = TRUE
      )
      expect_null(session$returned())
    }
  )
})

test_that("the CSV is the drug's totals by region", {
  fake <- fake_region_fetches()
  shiny::testServer(mod_region_server, args = region_args(fake), {
    pick_region_drug(session, "chemical:57")
    path <- output$csv
    expect_identical(
      basename(path), "prexp-region-0212000B0-atorvastatin-items-202510-202609.csv"
    )
    expect_equal(
      utils::read.csv(path, na.strings = ""), as.data.frame(session$returned()$data),
      ignore_attr = TRUE
    )
  })
})

test_that("Add to report pins the region view with its parameters", {
  fake <- fake_region_fetches()
  pinned <- shiny::reactiveVal(new_report())
  local_mocked_bindings(showNotification = function(ui, ...) invisible(NULL), .package = "shiny")
  shiny::testServer(
    mod_region_server,
    args = list(fetches = fake$fetches, window = shiny::reactive(region_window), report = pinned),
    {
      pick_region_drug(session, "presentation:300")
      session$setInputs(pin = structure(1L, class = "shinyActionButtonValue"))
      expect_length(pinned()$items, 1L)
      expect_identical(pinned()$items[[1]]$view, "region")
      expect_identical(pinned()$items[[1]]$params, session$returned()$params)
    }
  )
})
