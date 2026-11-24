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
