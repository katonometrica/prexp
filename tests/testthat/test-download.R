# epd_resources() and download_month(), offline: the portal is mocked with
# httr2::local_mocked_responses() and the saved package_show response in
# fixtures/package_show.json (P1-03).

zip_link <- function(ym) sprintf("https://example.invalid/signed/EPD_SNOMED_%d.zip", ym)

# A mock portal. package_show answers with the saved response; a file link
# answers from `files`, keyed by the link without its query: a raw body, or a
# function of the request and the call number that returns a response or
# signals an error. Every requested URL is recorded in `log$urls`.
mock_portal <- function(files = list(), log = new.env()) {
  log$urls <- character()
  function(req) {
    log$urls <- c(log$urls, req$url)
    log$agent <- req$options$useragent
    if (startsWith(req$url, ckan_package_show)) {
      path <- testthat::test_path("fixtures", "package_show.json")
      return(httr2::response(
        200, url = req$url, headers = list(`Content-Type` = "application/json"),
        body = readBin(path, "raw", file.size(path))
      ))
    }
    key <- sub("[?].*$", "", req$url)
    hit <- files[[key]]
    if (is.null(hit)) {
      return(httr2::response(404, url = req$url))
    }
    if (is.function(hit)) {
      log$tries[[key]] <- (if (is.null(log$tries[[key]])) 0L else log$tries[[key]]) + 1L
      return(hit(req, log$tries[[key]]))
    }
    httr2::response(200, url = req$url, body = hit)
  }
}

# The condition httr2 signals when a request cannot be performed at all
network_failure <- function() {
  stop(structure(
    class = c("httr2_failure", "httr2_error", "error", "condition"),
    list(message = "Failed to perform HTTP request.", call = NULL)
  ))
}

saved_resources <- function() {
  saved <- jsonlite::read_json(testthat::test_path("fixtures", "package_show.json"))
  parse_resources(saved$result$resources)
}

calls_to_portal <- function(log) sum(startsWith(log$urls, ckan_package_show))

# Real ZIP bodies, since a download must be a readable archive to be kept
zip_body <- function(ym = 202609L) readBin(fixture_file(ym), "raw", file.size(fixture_file(ym)))
same_bytes <- function(file, body) identical(readBin(file, "raw", length(body) + 1L), body)

no_wait <- function(attempt) 0

test_that("epd_resources() lists the monthly files, oldest first", {
  log <- new.env()
  httr2::local_mocked_responses(mock_portal(log = log))
  res <- epd_resources()
  # The data dictionary is not a monthly file
  expect_identical(res$year_month, 202606:202609)
  expect_identical(res$name, paste0("EPD_SNOMED_", 202606:202609))
  expect_identical(is.na(res$zip_url), c(TRUE, FALSE, FALSE, FALSE))
  expect_identical(res$size[res$year_month == 202609L], 7701102484)
  expect_identical(
    res$sha256[res$year_month == 202609L],
    "5f9dcebaccaa3bce6bdfd5f6d609609e6b8ffaaa9cb1d649c7bde9f85b367841"
  )
  expect_s3_class(res$created, "POSIXct")
  expect_match(res$url[res$year_month == 202609L], "^https://opendata.nhsbsa.net/dataset/")
  # A generic user agent with the project's address, and nothing personal
  expect_identical(log$agent, "prexp (+https://github.com/katonometrica/prexp)")
})

test_that("epd_resources() stops when package_show does not succeed", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw('{"success": false}'))
  })
  expect_error(epd_resources(), "did not succeed")
})

test_that("epd_resources() stops when the portal lists no monthly file", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      200, headers = list(`Content-Type` = "application/json"),
      body = charToRaw('{"success": true, "result": {"resources": [{"name": "EPD_2026_09"}]}}')
    )
  })
  expect_error(epd_resources(), "The portal lists no monthly file named EPD_SNOMED_YYYYMM")
})

test_that("a month published twice keeps its latest resource (no database)", {
  resources <- list(
    list(name = "EPD_SNOMED_202311", url = "a", created = "2023-12-20T10:00:00.000000"),
    list(name = "EPD_SNOMED_202311", url = "b", created = "2026-01-14T09:00:00.000000"),
    list(name = "EPD_SNOMED_202312", url = "c", created = "2024-01-20T10:00:00")
  )
  res <- parse_resources(resources)
  expect_identical(res$year_month, c(202311L, 202312L))
  expect_identical(res$url, c("b", "c"))
  expect_true(all(is.na(res$sha256)) && all(is.na(res$size)))
})

test_that("download_month() fetches the ZIP through a fresh link and a .part file", {
  dir <- withr::local_tempdir()
  log <- new.env()
  files <- list()
  files[[zip_link(202609)]] <- zip_body()
  httr2::local_mocked_responses(mock_portal(files, log))
  expect_message(file <- download_month(202609, dir = dir, backoff = no_wait), "Downloaded")
  expect_identical(file, file.path(dir, "EPD_SNOMED_202609.zip"))
  expect_true(same_bytes(file, zip_body()))
  # No part file is left behind
  expect_identical(list.files(dir), "EPD_SNOMED_202609.zip")
  # The metadata came first, then the signed link
  expect_identical(calls_to_portal(log), 1L)
  expect_match(log$urls[2], "X-Amz-Signature=redacted", fixed = TRUE)
})

test_that("a complete ZIP already downloaded is used without calling the portal", {
  dir <- withr::local_tempdir()
  writeBin(charToRaw("earlier"), file.path(dir, "EPD_SNOMED_202609.zip"))
  log <- new.env()
  httr2::local_mocked_responses(mock_portal(log = log))
  expect_message(file <- download_month(202609, dir = dir), "downloaded before")
  expect_identical(readBin(file, "raw", 100), charToRaw("earlier"))
  expect_length(log$urls, 0L)
})

test_that("network and server errors are retried, each time with fresh metadata", {
  dir <- withr::local_tempdir()
  log <- new.env()
  files <- list()
  files[[zip_link(202609)]] <- function(req, n) {
    if (n == 1L) network_failure()
    if (n == 2L) return(httr2::response(503, url = req$url))
    httr2::response(200, url = req$url, body = zip_body())
  }
  httr2::local_mocked_responses(mock_portal(files, log))
  messages <- testthat::capture_messages(
    file <- download_month(202609, dir = dir, attempts = 3, backoff = no_wait)
  )
  expect_match(messages[1], "failed (attempt 1 of 3): Failed to perform HTTP request", fixed = TRUE)
  expect_match(messages[2], "failed (attempt 2 of 3): HTTP 503", fixed = TRUE)
  expect_true(same_bytes(file, zip_body()))
  expect_identical(calls_to_portal(log), 3L)
  expect_identical(list.files(dir), "EPD_SNOMED_202609.zip")
})

test_that("an interrupted download leaves no complete-looking file, and the next run downloads", {
  dir <- withr::local_tempdir()
  files <- list()
  files[[zip_link(202609)]] <- function(req, n) network_failure()
  httr2::local_mocked_responses(mock_portal(files))
  expect_error(
    suppressMessages(download_month(202609, dir = dir, attempts = 2, backoff = no_wait)),
    "Could not download EPD_SNOMED_202609: Failed to perform HTTP request"
  )
  # Neither a complete-looking file nor a part file
  expect_length(list.files(dir), 0L)

  files[[zip_link(202609)]] <- zip_body()
  httr2::local_mocked_responses(mock_portal(files))
  file <- suppressMessages(download_month(202609, dir = dir))
  expect_true(same_bytes(file, zip_body()))
})

test_that("a download that is not a readable archive is retried, and never kept", {
  dir <- withr::local_tempdir()
  files <- list()
  files[[zip_link(202609)]] <- function(req, n) {
    body <- if (n == 1L) charToRaw("<html>Service unavailable</html>") else raw()
    httr2::response(200, url = req$url, body = body)
  }
  httr2::local_mocked_responses(mock_portal(files))
  messages <- testthat::capture_messages(expect_error(
    download_month(202609, dir = dir, attempts = 2, backoff = no_wait),
    "Could not download EPD_SNOMED_202609: The download of EPD_SNOMED_202609.zip is empty."
  ))
  expect_match(messages[1], "is not a readable archive: not a ZIP file", fixed = TRUE)
  expect_length(list.files(dir), 0L)

  # A ZIP that holds two files is refused too
  two <- file.path(withr::local_tempdir(), "two.zip")
  extra <- dirname(two)
  writeBin(charToRaw("a\r\n"), file.path(extra, "a.csv"))
  writeBin(charToRaw("b\r\n"), file.path(extra, "b.csv"))
  processx::run("bsdtar", c("--format", "zip", "-cf", two, "-C", extra, "a.csv", "b.csv"))
  files[[zip_link(202609)]] <- readBin(two, "raw", file.size(two))
  httr2::local_mocked_responses(mock_portal(files))
  expect_error(
    suppressMessages(download_month(202609, dir = dir, attempts = 1, backoff = no_wait)),
    "Expected one file in the archive"
  )
  expect_length(list.files(dir), 0L)
})

test_that("a download folder written with ~ is expanded", {
  home <- withr::local_tempdir()
  withr::local_envvar(HOME = home)
  files <- list()
  files[[zip_link(202609)]] <- zip_body()
  httr2::local_mocked_responses(mock_portal(files))
  file <- suppressMessages(download_month(202609, dir = "~/epd", backoff = no_wait))
  expect_identical(file, file.path(home, "epd", "EPD_SNOMED_202609.zip"))
  expect_no_error(validate_header("~/epd/EPD_SNOMED_202609.zip"))
})

test_that("a missing file (404) is not retried", {
  dir <- withr::local_tempdir()
  log <- new.env()
  httr2::local_mocked_responses(mock_portal(log = log))
  expect_error(download_month(202608, dir = dir, backoff = no_wait), "HTTP 404")
  expect_identical(calls_to_portal(log), 1L)
})

test_that("without a ZIP the CSV is downloaded, and its size must match the portal's", {
  dir <- withr::local_tempdir()
  csv_link <- saved_resources()$url[1]
  files <- list()
  files[[csv_link]] <- function(req, n) {
    httr2::response(200, url = req$url, body = charToRaw(if (n == 1L) "short" else "ten bytes!"))
  }
  httr2::local_mocked_responses(mock_portal(files))
  messages <- testthat::capture_messages(
    file <- download_month(202606, dir = dir, attempts = 2, backoff = no_wait)
  )
  expect_match(messages[1], "has 5 bytes, not 10", fixed = TRUE)
  expect_identical(basename(file), "EPD_SNOMED_202606.csv")
  expect_identical(file.size(file), 10)
  # A complete CSV is used again, after checking its size against the portal's
  expect_message(download_month(202606, dir = dir), "downloaded before")
})

test_that("months must be valid and published", {
  httr2::local_mocked_responses(mock_portal())
  dir <- withr::local_tempdir()
  expect_error(
    download_month(209901, dir = dir),
    "EPD_SNOMED_209901 is not published on the portal. The latest month is 202609.",
    fixed = TRUE
  )
  expect_error(download_month("2026-09", dir = dir), "must be one month as YYYYMM")
})
