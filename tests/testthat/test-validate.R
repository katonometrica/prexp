# Argument checks (no database)

test_that("check_year_month() takes one month as YYYYMM", {
  expect_identical(check_year_month(202609), 202609L)
  expect_identical(check_year_month("202601"), 202601L)
  expect_identical(check_year_month(209912L), 209912L)
  for (bad in list(202613, 202600, 199912, "2026-09", 20260, c(202609, 202610), NA, NULL)) {
    expect_error(check_year_month(bad), "must be one month as YYYYMM", label = format(bad))
  }
  expect_error(check_year_month(1, arg = "from"), "`from` must be one month")
})
