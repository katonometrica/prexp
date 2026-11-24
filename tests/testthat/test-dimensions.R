# prepare_dimensions() and apply_dimensions(): the month's chemicals,
# presentations and practices, worked out from staging and written to core by
# the swap (spec section 4, steps 5 and 8; P1-06).

dimension <- function(con, table, code_column) {
  DBI::dbGetQuery(con, sprintf("SELECT * FROM core.%s ORDER BY %s", table, code_column))
}

# Steps 5 and 8 for the staged month, without a build: the swap's transaction
# would write the dimensions together with the month's data
prepare_and_apply <- function(con, ym) {
  prepare_dimensions(con, ym)
  DBI::dbWithTransaction(con, apply_dimensions(con, ym))
}

test_that("a fixture month fills the three dimensions, and only when applied", {
  dbname <- local_migrated_db()
  stage_month(fixture_file(202609L), dbname = dbname)
  owner <- local_test_db("owner", dbname = dbname)
  counts <- prepare_dimensions(owner, 202609L)
  rows <- read_fixture(202609L)
  expect_identical(counts$dimension, c("chemical", "presentation", "practice"))
  expect_identical(counts$codes, c(
    length(unique(rows$BNF_CHEMICAL_SUBSTANCE_CODE)), length(unique(rows$BNF_PRESENTATION_CODE)),
    length(unique(rows$PRACTICE_CODE))
  ))
  expect_identical(counts$new, counts$codes)
  # Nothing in core yet
  for (table in c("dim_chemical", "dim_presentation", "dim_practice")) {
    expect_identical(nrow(dimension(owner, table, 1)), 0L, label = table)
  }

  DBI::dbWithTransaction(owner, apply_dimensions(owner, 202609L))
  practices <- dimension(owner, "dim_practice", "practice_code")
  expect_identical(practices$practice_code, sort(unique(rows$PRACTICE_CODE), method = "radix"))
  expect_identical(nrow(dimension(owner, "dim_presentation", "bnf_code")), counts$codes[2])
  expect_identical(nrow(dimension(owner, "dim_chemical", "chemical_code")), counts$codes[1])
  expect_true(all(practices$first_seen == 202609L & practices$last_seen == 202609L))
  national <- practices[practices$practice_code == "-", ]
  expect_true(national$is_unidentified)
  expect_identical(national$region_code, "-")
  expect_false(any(practices$is_unidentified[!practices$practice_code %in% c("-", "07H998")]))
  # The month's ids are the ones written
  ids <- DBI::dbGetQuery(owner, "
    SELECT count(*)::int AS n FROM pg_temp.month_practice m
    JOIN core.dim_practice d
      ON d.practice_id = m.practice_id AND d.practice_code = m.practice_code")$n
  expect_identical(ids, nrow(practices))
})

test_that("a renamed practice takes the newer name, and an older month never brings it back", {
  dbname <- local_migrated_db()
  owner <- local_test_db("owner", dbname = dbname)
  practice <- function() dimension(owner, "dim_practice", "practice_code")

  stage_rows(owner, staging_row(practice_name = "OLD NAME", regional_office_code = "Y56"))
  prepare_and_apply(owner, 202601L)
  stage_rows(owner, staging_row(practice_name = "NEW NAME", regional_office_code = "Y58",
                                regional_office_name = "SOUTH WEST"))
  prepare_dimensions(owner, 202602L)
  # Prepared, not yet applied: core still has the old name
  expect_identical(practice()$practice_name, "OLD NAME")
  DBI::dbWithTransaction(owner, apply_dimensions(owner, 202602L))
  expect_identical(practice()[c("practice_name", "region_code", "region_name")],
                   data.frame(practice_name = "NEW NAME", region_code = "Y58",
                              region_name = "SOUTH WEST"))
  expect_identical(c(practice()$first_seen, practice()$last_seen), c(202601L, 202602L))

  # Reloading the older month keeps the newer details, and counts the practice's
  # rows in its newer region
  stage_rows(owner, staging_row(practice_name = "OLD NAME", regional_office_code = "Y56"))
  prepare_dimensions(owner, 202601L)
  expect_identical(
    DBI::dbGetQuery(owner, "SELECT rollup_region FROM pg_temp.month_practice")$rollup_region,
    "Y58"
  )
  DBI::dbWithTransaction(owner, apply_dimensions(owner, 202601L))
  expect_identical(practice()$practice_name, "NEW NAME")
  expect_identical(practice()$region_code, "Y58")
  # An earlier month widens first_seen only
  stage_rows(owner, staging_row(practice_name = "OLDEST NAME"))
  prepare_and_apply(owner, 202512L)
  expect_identical(c(practice()$first_seen, practice()$last_seen), c(202512L, 202602L))
  expect_identical(practice()$practice_name, "NEW NAME")
  expect_identical(nrow(practice()), 1L)
})

test_that("a known code keeps its id, and a new code's id is taken from the sequence", {
  dbname <- local_migrated_db()
  owner <- local_test_db("owner", dbname = dbname)
  stage_rows(owner, staging_row())
  prepare_and_apply(owner, 202601L)
  known <- dimension(owner, "dim_practice", "practice_code")$practice_id

  # A prepared month that is never applied (a failed load) leaves only a gap
  stage_rows(owner, staging_row(practice_code = "B00002"))
  prepare_dimensions(owner, 202602L)
  stage_rows(owner, staging_row(), staging_row(practice_code = "B00002"))
  prepare_and_apply(owner, 202602L)
  practices <- dimension(owner, "dim_practice", "practice_code")
  expect_identical(practices$practice_code, c("A00001", "B00002"))
  expect_identical(practices$practice_id[1], known)
  expect_gt(practices$practice_id[2], known + 1L)
})

test_that("codes give the chapter, section, paragraph and generic flag; appliances have no flag", {
  dbname <- local_migrated_db()
  owner <- local_test_db("owner", dbname = dbname)
  stage_rows(
    owner,
    staging_row(),
    staging_row(
      bnf_presentation_code = "0212000B0BBAAAA", bnf_presentation_name = "Lipitor 10mg tablets"
    ),
    staging_row(
      bnf_chemical_substance_code = "2003", bnf_chemical_substance = "Bandages",
      bnf_presentation_code = "20030100211", bnf_presentation_name = "Test bandage 5cm x 4m",
      bnf_chapter_plus_code = "20: Dressings", adq_usage = "0."
    )
  )
  prepare_and_apply(owner, 202601L)
  pres <- DBI::dbGetQuery(owner, "
    SELECT p.bnf_code, c.chemical_code, p.bnf_chapter, p.bnf_chapter_name, p.bnf_section,
           p.bnf_paragraph, p.is_generic
    FROM core.dim_presentation p JOIN core.dim_chemical c ON c.chemical_id = p.chemical_id
    ORDER BY p.bnf_code")
  expect_identical(pres$bnf_code, c("0212000B0AAABAB", "0212000B0BBAAAA", "20030100211"))
  expect_identical(pres$chemical_code, c("0212000B0", "0212000B0", "2003"))
  expect_identical(pres$bnf_chapter, c("02", "02", "20"))
  expect_identical(
    pres$bnf_chapter_name, c("Cardiovascular System", "Cardiovascular System", "Dressings")
  )
  expect_identical(pres$bnf_section, c("0212", "0212", "2003"))
  expect_identical(pres$bnf_paragraph, c("021200", "021200", "200301"))
  expect_identical(pres$is_generic, c(TRUE, FALSE, NA))
})

test_that("a presentation moved to another substance takes it only from a newer month", {
  dbname <- local_migrated_db()
  owner <- local_test_db("owner", dbname = dbname)
  chemical_of <- function() {
    DBI::dbGetQuery(owner, "
      SELECT c.chemical_code FROM core.dim_presentation p
      JOIN core.dim_chemical c ON c.chemical_id = p.chemical_id")$chemical_code
  }
  stage_rows(owner, staging_row())
  prepare_and_apply(owner, 202602L)
  moved <- staging_row(bnf_chemical_substance_code = "0212000Y0",
                       bnf_chemical_substance = "Moved substance")
  stage_rows(owner, moved)
  prepare_and_apply(owner, 202601L)
  expect_identical(chemical_of(), "0212000B0")
  stage_rows(owner, moved)
  prepare_and_apply(owner, 202603L)
  expect_identical(chemical_of(), "0212000Y0")
})

test_that("empty values are loaded as NULL, and address lines are joined", {
  dbname <- local_migrated_db()
  owner <- local_test_db("owner", dbname = dbname)
  stage_rows(owner, staging_row(
    address_1 = "1 HIGH STREET", address_2 = "", address_3 = "TOWN", postcode = "",
    unidentified = "Y", practice_name = ""
  ))
  prepare_and_apply(owner, 202601L)
  practice <- dimension(owner, "dim_practice", "practice_code")
  expect_identical(practice$address, "1 HIGH STREET, TOWN")
  expect_true(is.na(practice$postcode))
  expect_true(is.na(practice$practice_name))
  expect_true(practice$is_unidentified)
})

# The fetch tests' oracle takes a practice's UNIDENTIFIED flag from its latest
# month, as the loader must
test_that("a practice's UNIDENTIFIED flag is the newest month's, never an older one's", {
  dbname <- local_migrated_db()
  owner <- local_test_db("owner", dbname = dbname)
  flag <- function() {
    DBI::dbGetQuery(owner, "SELECT is_unidentified FROM core.dim_practice")$is_unidentified
  }
  apply_month <- function(ym, unidentified) {
    stage_rows(owner, staging_row(unidentified = unidentified))
    prepare_and_apply(owner, ym)
  }
  apply_month(202601L, "Y")
  expect_true(flag())
  # A newer month clears it, and reloading the older month does not bring it back
  apply_month(202602L, "N")
  expect_false(flag())
  apply_month(202601L, "Y")
  expect_false(flag())
})
