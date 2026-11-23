# stage_month(): streaming a monthly file into staging (spec section 4, step 4;
# P1-05). Each test stages into a new migrated database.

staged_rows <- function(dbname) {
  con <- local_test_db("loader", dbname = dbname)
  DBI::dbGetQuery(con, "SELECT count(*)::int AS n FROM raw.epd_staging")$n
}

test_that("staging a fixture month gives its CSV's row count and SHA-256", {
  dbname <- local_migrated_db()
  res <- stage_month(fixture_file(202609L), fixture_sha256(202609L), dbname = dbname)
  expect_identical(res$rows, 3984)
  expect_identical(res$sha256, fixture_sha256(202609L))
  expect_identical(staged_rows(dbname), 3984L)
  # Staging is truncated first
  stage_month(fixture_file(202608L), dbname = dbname)
  expect_identical(staged_rows(dbname), 3984L)
})

test_that("a plain CSV stages too", {
  dbname <- local_migrated_db()
  row <- paste0('"2026-09",', paste(rep('"x"', 19), collapse = ","), ",1,",
                paste(rep('"0."', 6), collapse = ","))
  csv <- local_source_file(c(source_header(), row), zip = FALSE)
  expect_identical(stage_month(csv, dbname = dbname)$rows, 1)
})

test_that("a blank value is staged as an empty string, never NULL", {
  dbname <- local_migrated_db()
  row <- paste0('"2026-09",', paste(rep('"x"', 19), collapse = ","), ",,",
                paste(rep('"0."', 6), collapse = ","))
  csv <- local_source_file(c(source_header(), row), zip = FALSE)
  stage_month(csv, dbname = dbname)
  con <- local_test_db("loader", dbname = dbname)
  staged <- DBI::dbGetQuery(con, "
    SELECT items, items IS NULL AS null_items,
           count(*) FILTER (WHERE address_2 IS NULL)::int AS nulls
    FROM raw.epd_staging GROUP BY items")
  expect_identical(staged$items, "")
  expect_false(staged$null_items)
  expect_identical(staged$nulls, 0L)
})

test_that("a malformed row fails with psql's message and line number", {
  dbname <- local_migrated_db()
  row <- paste(rep('"x"', 27), collapse = ",")
  zip <- local_source_file(c(source_header(), row, paste0(row, ',"one too many"')))
  error <- expect_error(stage_month(zip, dbname = dbname), "Staging EPD_SNOMED_209901.zip failed")
  expect_match(conditionMessage(error), "extra data after last expected column")
  expect_match(conditionMessage(error), "line 3")
  expect_identical(staged_rows(dbname), 0L)
})

test_that("a damaged archive fails the step, though psql loaded what came", {
  skip_without_bsdtar()
  dbname <- local_migrated_db()
  dir <- withr::local_tempdir()
  damaged <- file.path(dir, "EPD_SNOMED_202609.zip")
  bytes <- readBin(fixture_file(202609L), "raw", file.size(fixture_file(202609L)))
  writeBin(bytes[seq_len(length(bytes) %/% 2L)], damaged)
  expect_error(stage_month(damaged, dbname = dbname), "Staging EPD_SNOMED_202609.zip failed")
})

test_that("a SHA-256 that differs from the portal's stops", {
  dbname <- local_migrated_db()
  expect_error(
    stage_month(fixture_file(202609L), strrep("0", 64), dbname = dbname),
    "differs from the portal's"
  )
})

test_that("a file with a header and no rows is refused", {
  dbname <- local_migrated_db()
  expect_error(
    stage_month(local_source_file(source_header()), dbname = dbname),
    "loaded no rows"
  )
})
