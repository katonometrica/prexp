test_that("prexp_version() returns the package version as a string", {
  expect_match(prexp_version(), "^[0-9]+[.][0-9]+[.][0-9]+")
})
