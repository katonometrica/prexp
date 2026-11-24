# How the app writes numbers, pounds and months (P4-01)

test_that("format_number() adds thousands separators and shows a missing value as a dash", {
  expect_identical(format_number(c(0, 1234567, -1234.4)), c("0", "1,234,567", "-1,234"))
  expect_identical(format_number(1234.567, digits = 2), "1,234.57")
  expect_identical(format_number(NA), "\u2013")
  expect_identical(format_number(c(1, NA), na = "n/a"), c("1", "n/a"))
  expect_identical(format_number(numeric()), character())
})

test_that("format_pounds() writes pounds and pence, the sign before the pound sign", {
  expect_identical(
    format_pounds(c(1234.5, -12.3, 0.991)), c("\u00a31,234.50", "-\u00a312.30", "\u00a30.99")
  )
  expect_identical(format_pounds(NA), "\u2013")
  expect_identical(format_pounds(1e9, digits = 0), "\u00a31,000,000,000")
})

test_that("format_measure() writes costs in pounds and the rest as numbers", {
  expect_identical(format_measure(1234.4, "nic"), "\u00a31,234.40")
  expect_identical(format_measure(1234.4, "actual_cost"), "\u00a31,234.40")
  for (measure in c("items", "total_quantity", "adq_usage")) {
    expect_identical(format_measure(1234.4, measure), "1,234", label = measure)
  }
})

test_that("format_month() and format_month_range() write months in English", {
  expect_identical(format_month(c(202609L, 202601L, NA)), c("Sep 2026", "Jan 2026", NA))
  expect_identical(format_month("202512"), "Dec 2025")
  expect_identical(format_month_range(202510L, 202609L), "Oct 2025 \u2013 Sep 2026")
  expect_identical(format_month_range(202601L, 202609L), "Jan \u2013 Sep 2026")
  expect_identical(format_month_range(202609L, 202609L), "Sep 2026")
})

test_that("format_number() and format_pounds() read text, and drop the sign of a zero", {
  expect_identical(format_number(c("1234", "abc")), c("1,234", "\u2013"))
  expect_identical(format_number(c(-0.4, -0.0001)), c("0", "0"))
  expect_identical(format_number(-0.004, digits = 2), "0.00")
  expect_identical(format_pounds(c(-0.001, 0)), c("\u00a30.00", "\u00a30.00"))
  expect_identical(format_pounds("abc"), "\u2013")
})

test_that("format_measure() passes its placeholder for a missing value", {
  expect_identical(format_measure(NA, "nic", na = "n/a"), "n/a")
  expect_identical(format_measure(NA, "items", na = "n/a"), "n/a")
})

test_that("format_month() gives NA for what is not a month, and leaves the others alone", {
  expect_identical(
    format_month(c(202600L, 202609L, 202613L, 202610L)), c(NA, "Sep 2026", NA, "Oct 2026")
  )
  expect_identical(format_month(c(-202609L, 0L)), c(NA_character_, NA_character_))
  expect_identical(format_month("abc"), NA_character_)
})

test_that("numbers that are not finite show as missing", {
  expect_identical(format_number(c(Inf, -Inf, NaN)), rep("\u2013", 3L))
  expect_identical(format_pounds(c(-Inf, 1)), c("\u2013", "\u00a31.00"))
})

test_that("format_month_range() refuses months that are not a range", {
  expect_error(format_month_range(202609L, 202510L), class = "prexp_invalid_argument")
  expect_error(format_month_range(202613L, 202609L), class = "prexp_invalid_argument")
  expect_identical(format_month_range("202510", 202609), "Oct 2025 \u2013 Sep 2026")
})

test_that("quantity and ADQ usage keep three significant figures; items are whole", {
  expect_identical(
    format_measure(c(0.496, 0.008, 1.624, 0, NA), "adq_usage"),
    c("0.496", "0.008", "1.62", "0", "\u2013")
  )
  expect_identical(format_measure(c(2.5, 123456.7), "total_quantity"), c("2.5", "123,457"))
  expect_identical(format_measure(2.5, "items"), "2")
  expect_identical(format_significant(c(-0, Inf)), c("0", "\u2013"))
})
