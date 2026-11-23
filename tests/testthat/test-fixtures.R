# The fixture months and the oracle that tests compare the loader with
# (spec section 6.1, P1-02). No database.

test_that("there are thirteen fixture months, under 2 MB in total", {
  files <- vapply(fixture_months(), fixture_file, character(1))
  expect_length(files, 13L)
  expect_true(all(file.exists(files)))
  expect_lt(sum(file.size(files)), 2e6)
})

test_that("every fixture month keeps the source's layout", {
  # 27 fields: all quoted but ITEMS, the 21st
  layout <- '^("[^"]*",){20}[0-9]+(,"[^"]*"){6}$'
  for (ym in fixture_months()) {
    file <- fixture_file(ym)
    expect_no_error(validate_header(file))
    dir <- withr::local_tempdir()
    csv <- utils::unzip(file, exdir = dir, unzip = "internal")
    expect_identical(basename(csv), sprintf("EPD_SNOMED_%d.csv", ym))
    bytes <- readBin(csv, "raw", file.size(csv))
    newlines <- which(bytes == as.raw(0x0a))
    expect_true(all(bytes[newlines - 1L] == as.raw(0x0d)), label = "CRLF line endings")
    lines <- readLines(csv, warn = FALSE)
    expect_true(all(grepl(layout, lines[-1L])), label = "quoted fields")
    rows <- read_fixture(ym)
    expect_identical(nrow(rows), 3984L)
    expect_true(all(rows$YEAR_MONTH == sprintf("%d-%02d", ym %/% 100L, ym %% 100L)))
  }
})

test_that("the fixtures hold the cases the loader must handle", {
  rows <- read_fixture(202609L)
  code <- rows$BNF_PRESENTATION_CODE
  regions <- setdiff(unique(rows$REGIONAL_OFFICE_CODE), "-")
  expect_length(regions, 7L)
  # The seven v2 groups (spec section 10)
  v2 <- c("0212", "0204|020505|020602|0202", "020802", "060101", "060102", "0301", "0302")
  for (prefix in v2) {
    expect_true(any(grepl(paste0("^(", prefix, ")"), code)), label = prefix)
  }
  # Brand and generic presentations of one substance
  drug <- nchar(code) == 15L
  generic <- drug & substr(code, 10L, 11L) == "AA"
  chemical <- rows$BNF_CHEMICAL_SUBSTANCE_CODE
  expect_gt(length(intersect(chemical[generic], chemical[drug & !generic])), 0L)
  # Appliances: chapters 20 to 23, with 11-character codes
  expect_true(any(substr(code, 1L, 2L) %in% c("20", "21", "22", "23") & nchar(code) == 11L))
  # No ADQ defined, and empty SNOMED codes
  expect_true(any(rows$ADQ_USAGE == "0."))
  expect_true(any(rows$SNOMED_CODE == ""))
  # Unidentified prescribers, including the national code
  expect_true(all(c("-", "07H998") %in% rows$PRACTICE_CODE[rows$UNIDENTIFIED == "Y"]))
  # One row written twice, and two keys repeated with different measures
  expect_identical(sum(duplicated(rows)), 1L)
  key <- paste(rows$PRACTICE_CODE, code, rows$SNOMED_CODE, rows$QUANTITY)
  expect_identical(sum(duplicated(key)) - sum(duplicated(rows)), 2L)
})

test_that("the months repeat the same rows with scaled measures", {
  real <- read_fixture(202609L)
  other <- read_fixture(202601L)
  changed <- c("YEAR_MONTH", "ITEMS", "TOTAL_QUANTITY", "ADQ_USAGE", "NIC", "ACTUAL_COST")
  same <- setdiff(names(real), changed)
  expect_identical(real[same], other[same])
  # TOTAL_QUANTITY stays QUANTITY x ITEMS
  expected <- round(as.numeric(other$QUANTITY) * as.numeric(other$ITEMS), 2)
  expect_equal(as.numeric(other$TOTAL_QUANTITY), expected)
  expect_false(identical(real$ITEMS, other$ITEMS))
})

test_that("units_text() writes exact decimals as trim_scale() does", {
  expect_identical(
    units_text(c(6000, 6050, 1, 0, NA, 123456789012), 2),
    c("60", "60.5", "0.01", "0", NA, "1234567890.12")
  )
  expect_identical(units_text(75199, 5), "0.75199")
})

test_that("the oracle's levels add up to the same month totals", {
  totals <- oracle_month_totals()
  expect_identical(totals$year_month, fixture_months())
  expect_true(all(totals$source_rows == 3984L))
  # Rows of the same practice and presentation are summed into one
  expect_true(all(totals$fact_rows < totals$source_rows))
  # Series are not flat
  expect_gt(length(unique(totals$items)), 10L)
  levels <- list(
    oracle_fact(), oracle_presentation_month(), oracle_chemical_month(),
    oracle_practice_month(), oracle_region_month()
  )
  summed <- c("items", "nic", "actual_cost")
  for (level in levels) {
    by_month <- oracle_sum(level, "year_month", summed)
    expect_identical(by_month[summed], totals[summed])
  }
  fact <- oracle_fact(202609L)
  expect_identical(nrow(fact), totals$fact_rows[totals$year_month == 202609L])
  text <- oracle_text(fact)
  expect_true(any(is.na(text$adq_usage)))
  expect_true(all(grepl("^[0-9]+([.][0-9]{1,2})?$", text$nic)))
})
