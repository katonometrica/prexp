# validate_header() and reading monthly files (spec section 4, step 3).

row <- paste0(
  '"2099-01","NORTH EAST AND YORKSHIRE","Y63",',
  '"NHS NORTH EAST AND NORTH CUMBRIA INTEGRATED CARE BOARD","QHM",',
  '"NHS NORTH EAST AND NORTH CUMBRIA ICB - 00L","00L","TEST PRACTICE","A00001",',
  '"1 TEST STREET","","","","NE1 1AA","0212000B0","Atorvastatin","0212000B0AAABAB",',
  '"Atorvastatin 20mg tablets","02: Cardiovascular System","28.",1,"28.","28.",',
  '"0.98","0.91234","N","320000000000000"'
)

test_that("the expected columns are the 27 of the current source format (no database)", {
  cols <- epd_columns()
  expect_identical(cols$position, as.character(1:27))
  expect_identical(
    cols$name[c(1, 17, 21, 27)],
    c("YEAR_MONTH", "BNF_PRESENTATION_CODE", "ITEMS", "SNOMED_CODE")
  )
  expect_identical(sum(cols$source_type == "text"), 21L)
})

test_that("a matching header passes, in a ZIP or a plain CSV", {
  zip <- local_source_file(c(source_header(), row))
  expect_true(is_zip(zip))
  expect_identical(validate_header(zip), epd_columns()$name)
  csv <- local_source_file(c(source_header(), row), zip = FALSE)
  expect_false(is_zip(csv))
  expect_identical(validate_header(csv), epd_columns()$name)
})

test_that("a byte-order mark and a change of letter case are accepted", {
  expect_no_error(validate_header(local_source_file(c(source_header(), row), bom = TRUE)))
  expect_no_error(validate_header(local_source_file(c(tolower(source_header()), row))))
})

test_that("a missing column is named", {
  names <- setdiff(epd_columns()$name, "BNF_PRESENTATION_CODE")
  expect_error(
    validate_header(local_source_file(source_header(names))),
    "missing 'BNF_PRESENTATION_CODE'.", fixed = TRUE
  )
})

test_that("an extra column is named", {
  names <- c(epd_columns()$name, "DISPENSER_CODE")
  expect_error(
    validate_header(local_source_file(source_header(names))),
    "unexpected 'DISPENSER_CODE'.", fixed = TRUE
  )
})

test_that("a renamed column is named twice, as missing and as unexpected", {
  names <- epd_columns()$name
  names[names == "ADQ_USAGE"] <- "ADQUSAGE"
  expect_error(
    validate_header(local_source_file(source_header(names))),
    "missing 'ADQ_USAGE'; unexpected 'ADQUSAGE'.", fixed = TRUE
  )
})

test_that("a moved column is named alone, and a repeated one is reported", {
  names <- epd_columns()$name
  moved <- c("ITEMS", setdiff(names, "ITEMS"))
  expect_error(
    validate_header(local_source_file(source_header(moved))),
    paste(
      "The header of EPD_SNOMED_209901.zip does not match",
      "inst/extdata/epd_columns.csv: reordered 'ITEMS'."
    ),
    fixed = TRUE
  )
  swapped <- names
  swapped[c(24, 25)] <- names[c(25, 24)]
  expect_error(
    validate_header(local_source_file(source_header(swapped))),
    "reordered 'NIC'.", fixed = TRUE
  )
  twice <- c(names, "NIC")
  expect_error(
    validate_header(local_source_file(source_header(twice))),
    "repeated 'NIC'.", fixed = TRUE
  )
})

test_that("out_of_order() keeps a longest run in order (no database)", {
  expect_identical(out_of_order(c("a", "b", "c"), c("a", "b", "c")), character())
  expect_identical(out_of_order(c("d", "a", "b", "c"), c("a", "b", "c", "d")), "d")
  expect_identical(out_of_order(c("b", "a"), c("a", "b")), "a")
  expect_identical(out_of_order(character(), "a"), character())
})

test_that("archives with other than one file, corrupt archives and empty files are refused", {
  skip_without_bsdtar()
  dir <- withr::local_tempdir()
  writeBin(charToRaw("a\r\n"), file.path(dir, "one.csv"))
  writeBin(charToRaw("b\r\n"), file.path(dir, "two.csv"))
  two <- file.path(dir, "two.zip")
  processx::run("bsdtar", c("--format", "zip", "-cf", two, "-C", dir, "one.csv", "two.csv"))
  expect_error(
    validate_header(two),
    "Expected one file in the archive .* found 2: one.csv, two.csv"
  )

  corrupt <- file.path(dir, "corrupt.zip")
  writeBin(c(as.raw(c(0x50, 0x4b, 0x03, 0x04)), as.raw(rep(0, 40))), corrupt)
  expect_error(validate_header(corrupt), "Could not read the archive")

  empty <- local_source_file(character(), zip = FALSE)
  expect_error(validate_header(empty), "Could not read a header line")
  expect_error(validate_header(file.path(dir, "nowhere.zip")), "File not found")
})
