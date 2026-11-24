# The app's cache of fetch results (P4-07): a second identical request is not
# fetched again; other arguments, another window or an error are.

cache_window <- tibble::tibble(
  first_month = 202510L, last_month = 202609L, months = 12L,
  loaded_at = as.POSIXct("2026-10-20 10:00:00", tz = "UTC")
)

# The timing lines a call writes, with the log on
timing_lines <- function(expr) {
  withr::local_envvar(PREXP_LOG = "on")
  to <- textConnection(NULL, "w")
  withr::defer(close(to))
  withr::local_options(prexp.log_to = to)
  force(expr)
  textConnectionValue(to)
}

test_that("a second identical request is served from the cache, not the fetch", {
  calls <- 0L
  window <- cache_window
  fetch <- function(id, months, after = NULL) {
    calls <<- calls + 1L
    tibble::tibble(id = id, call = calls)
  }
  cache <- app_cache()
  cached <- cache_fetch(cache, "practice_top_drugs", fetch, function() window)
  first <- cached(12L, c(202510L, 202609L))
  expect_identical(cached(12L, c(202510L, 202609L)), first)
  expect_identical(calls, 1L)
  # Other arguments are another request
  cached(12L, c(202601L, 202609L))
  expect_identical(calls, 2L)
  cached(12L, c(202510L, 202609L), after = 1003L)
  expect_identical(calls, 3L)
  # So is another fetch with the same arguments
  other <- cache_fetch(cache, "practice_series", fetch, function() window)
  other(12L, c(202510L, 202609L))
  expect_identical(calls, 4L)
  # A month loaded changes the window, and so does a month loaded again
  window$last_month <- 202610L
  cached(12L, c(202510L, 202609L))
  expect_identical(calls, 5L)
  window$loaded_at <- window$loaded_at + 60
  cached(12L, c(202510L, 202609L))
  expect_identical(calls, 6L)
  expect_length(cache$keys(), 6L)
  expect_match(cache$keys(), "^[0-9a-f]{64}$")
})

test_that("an error is not kept: the next request fetches again", {
  calls <- 0L
  fail <- TRUE
  fetch <- function(x) {
    calls <<- calls + 1L
    if (fail) stop("the database is down")
    x
  }
  cache <- app_cache()
  cached <- cache_fetch(cache, "search_drugs", fetch, function() NULL)
  expect_error(cached("atorva"), "the database is down")
  expect_length(cache$keys(), 0L)
  fail <- FALSE
  expect_identical(cached("atorva"), "atorva")
  expect_identical(cached("atorva"), "atorva")
  expect_identical(calls, 2L)
})

test_that("the app's fetches go through the cache, all but the window's", {
  con <- fixture_app()
  window <- fetch_window(con)
  chemical <- id_of(con, "chemical", "0212000B0")
  span <- c(window$first_month, window$last_month)
  cache <- app_cache()
  fetches <- app_fetches(con, cache, function() window)
  lines <- timing_lines({
    first <- fetches$drug_series("chemical", chemical, span, "items")
    second <- fetches$drug_series("chemical", chemical, span, "items")
  })
  expect_length(lines, 1L)
  expect_identical(second, first)
  expect_identical(first, fetch_drug_series(con, "chemical", chemical, span, "items"))
  # The window is part of every key, so it is always fetched
  expect_length(timing_lines(for (i in 1:2) fetches$window()), 2L)
  expect_length(cache$keys(), 1L)
  # Without a cache, every request is fetched
  plain <- app_fetches(con)
  expect_length(timing_lines(for (i in 1:2) plain$drug_presentations(chemical, span)), 2L)
})

test_that("two sessions asking the same regions fetch them once", {
  con <- fixture_app()
  chemical <- id_of(con, "chemical", "0212000B0")
  cache <- app_cache()
  session_regions <- function() {
    shiny::testServer(app_server(con, cache), {
      session$setInputs(`region-search-query` = "atorva")
      session$elapse(400)
      session$setInputs(`region-search-pick` = paste0("chemical:", chemical))
      expect_match(output[["region-body"]]$html, "id=\"region-chart\"", fixed = TRUE)
    })
  }
  lines <- timing_lines({
    session_regions()
    session_regions()
  })
  fetched <- vapply(lines, function(line) jsonlite::fromJSON(line)[["function"]], "")
  expect_identical(sum(fetched == "fetch_region_comparison"), 1L)
  expect_identical(sum(fetched == "fetch_search_drugs"), 1L)
  # Each session fetches its window
  expect_identical(sum(fetched == "fetch_window"), 2L)
})
