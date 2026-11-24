# Argument checks (no database)

test_that("check_year_month() takes one month as YYYYMM", {
  expect_identical(check_year_month(202609), 202609L)
  expect_identical(check_year_month("202601"), 202601L)
  expect_identical(check_year_month(209912L), 209912L)
  for (bad in list(202613, 202600, 199912, "2026-09", 20260, c(202609, 202610), NA, NULL)) {
    expect_error(check_year_month(bad), "must be one month as YYYYMM", label = format(bad))
  }
  expect_error(check_year_month(1, arg = "from"), "`from` must be one month")
  expect_error(check_year_month("2026-09"), class = "prexp_invalid_argument")
})

test_that("validate_months() takes two months, the first not after the last", {
  expect_identical(validate_months(c(202510, 202609)), c(202510L, 202609L))
  expect_identical(validate_months(c(first = "202609", last = "202609")), c(202609L, 202609L))
  bad_values <- list(
    c(202609, 202510), 202609, c(202510, 202613), c(202510, NA), c("2025-10", "2026-09"),
    list(202510, 202609), NULL, c(202510.5, 202609), c(202510, 202609, 202610)
  )
  for (bad in bad_values) {
    expect_error(validate_months(bad), class = "prexp_invalid_argument", label = describe(bad))
  }
  expect_error(validate_months(c(202609, 202510)), "the first not after the last", fixed = TRUE)
  expect_error(validate_months(1, arg = "range"), "`range` must be two months")
})

test_that("validate_id() takes one whole number from 1 to 2147483647", {
  expect_identical(validate_id(5), 5L)
  expect_identical(validate_id(5L), 5L)
  expect_identical(validate_id(1e5), 100000L)
  expect_identical(validate_id("123456"), 123456L)
  expect_identical(validate_id(2147483647), 2147483647L)
  bad_values <- list(
    0, -1, 1.5, "1.5", "a", "", " 1", NA, NA_integer_, NULL, c(1, 2), 2147483648,
    "99999999999", TRUE, Inf, list(1)
  )
  for (bad in bad_values) {
    expect_error(validate_id(bad), class = "prexp_invalid_argument", label = describe(bad))
  }
  expect_error(validate_id(0, "practice_id"), "`practice_id` must be one id")
})

test_that("validate_search() cleans the text, which must then be 2 to 100 characters", {
  expect_identical(validate_search("  atorva  "), "atorva")
  expect_identical(validate_search("co\tcodamol\r\n"), "co codamol")
  expect_identical(validate_search("ator​va\u0007"), "atorva")
  expect_identical(validate_search("a   b"), "a b")
  expect_identical(validate_search("1% cream"), "1% cream")
  expect_identical(validate_search(strrep("é", 100)), strrep("é", 100))
  bad_values <- list(
    "Z", " Z ", "\t\n", strrep("Z", 101), NA_character_, character(), c("ab", "cd"), 12, NULL
  )
  for (bad in bad_values) {
    error <- expect_error(
      validate_search(bad), class = "prexp_invalid_argument", label = describe(bad)
    )
    # The message never repeats the search text
    expect_no_match(conditionMessage(error), "Z", fixed = TRUE)
  }
  expect_error(validate_search("Z"), "it has 1", fixed = TRUE)
  expect_error(validate_search(strrep("Z", 101)), "it has 101", fixed = TRUE)
})

test_that("validate_choice(), validate_limit() and validate_measure() keep to their sets", {
  expect_identical(validate_choice("nic", c("items", "nic"), "by"), "nic")
  expect_error(
    validate_choice("NIC", c("items", "nic"), "by"),
    "`by` must be one of \"items\", \"nic\", not \"NIC\".", fixed = TRUE
  )
  expect_error(validate_choice(NA_character_, "total", "per"), "`per` must be \"total\"")
  expect_error(validate_choice(c("items", "nic"), c("items", "nic"), "by"), "must be one of")

  expect_identical(validate_limit(20, max = 100), 20L)
  expect_identical(validate_limit(1L, max = 100), 1L)
  for (bad in list(0, 101, 2.5, NA, "20", NULL, c(1, 2))) {
    expect_error(
      validate_limit(bad, max = 100), class = "prexp_invalid_argument", label = describe(bad)
    )
  }
  expect_error(validate_limit(0, max = 100), "from 1 to 100", fixed = TRUE)

  expect_identical(validate_measure("total_quantity", "presentation"), "total_quantity")
  expect_identical(validate_measure("adq_usage", "chemical"), "adq_usage")
  expect_error(
    validate_measure("total_quantity", "chemical"), "only valid for a single presentation"
  )
  expect_error(validate_measure("quantity", "presentation"), class = "prexp_invalid_argument")
})

test_that("describe() shows a value as R would, cut short", {
  expect_identical(describe(NULL), "NULL")
  expect_identical(describe("a"), "\"a\"")
  expect_identical(describe(c(1, 2)), "c(1, 2)")
  expect_identical(nchar(describe(strrep("a", 100))), 40L)
})
