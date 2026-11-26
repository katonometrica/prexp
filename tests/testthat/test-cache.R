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

test_that("a value is kept once made; one that fails to be made is not", {
  made <- 0L
  fail <- TRUE
  make <- function() {
    made <<- made + 1L
    if (fail) stop("the device failed")
    paste("chart", made)
  }
  cache <- app_cache()
  kept <- cache_value(cache, "chart", function() cache_window)
  expect_error(kept(list("drug", 57L), make), "the device failed")
  expect_length(cache$keys(), 0L)
  fail <- FALSE
  expect_identical(kept(list("drug", 57L), make), "chart 2")
  expect_identical(kept(list("drug", 57L), make), "chart 2")
  expect_identical(made, 2L)
  # Another key is another value
  expect_identical(kept(list("drug", 58L), make), "chart 3")
  # A fetch and a value with the same arguments are kept apart
  fetched <- cache_fetch(cache, "chart_like", function(...) "fetched", function() cache_window)
  expect_identical(fetched("drug", 57L), "fetched")
  expect_length(cache$keys(), 3L)
})

test_that("a view's chart is kept with the app's cache, and drawn every time without one", {
  draws <- 0L
  draw <- function() {
    draws <<- draws + 1L
    draws
  }
  plain <- list(drug_series = function(...) NULL)
  expect_identical(keep_chart(plain, list("drug", 57L), draw), 1L)
  expect_identical(keep_chart(plain, list("drug", 57L), draw), 2L)
  cached <- list(chart = cache_value(app_cache(), "chart", function() cache_window))
  expect_identical(keep_chart(cached, list("drug", 57L), draw), 3L)
  expect_identical(keep_chart(cached, list("drug", 57L), draw), 3L)
  expect_identical(keep_chart(cached, list("drug", 57L, 870), draw), 4L)
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

test_that("two sessions asking the same drug draw its chart once", {
  con <- fixture_app()
  chemical <- id_of(con, "chemical", "0212000B0")
  cache <- app_cache()
  draws <- 0L
  draw <- render_girafe
  local_mocked_bindings(render_girafe = function(...) {
    draws <<- draws + 1L
    draw(...)
  })
  session_drug <- function() {
    shiny::testServer(app_server(con, cache), {
      session$setInputs(`drug-search-query` = "atorva")
      session$elapse(400)
      session$setInputs(`drug-search-pick` = paste0("chemical:", chemical))
      expect_s3_class(output[["drug-chart"]], "json")
    })
  }
  session_drug()
  session_drug()
  expect_identical(draws, 1L)
  # Without the cache, each session draws it
  draws <- 0L
  for (i in 1:2) {
    shiny::testServer(app_server(con), {
      session$setInputs(`drug-search-query` = "atorva")
      session$elapse(400)
      session$setInputs(`drug-search-pick` = paste0("chemical:", chemical))
      expect_s3_class(output[["drug-chart"]], "json")
    })
  }
  expect_identical(draws, 2L)
})
