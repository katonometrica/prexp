# Helpers for the loader's tests: fixture hashes, staging rows, reading the
# loaded tables back as text, and comparing them with the oracle.

# The SHA-256 of a fixture month's CSV, as the portal publishes it for a month
fixture_sha256 <- function(ym) {
  dir <- withr::local_tempdir()
  csv <- utils::unzip(fixture_file(ym), exdir = dir, unzip = "internal")
  unname(tools::sha256sum(csv))
}

# Loads a fixture month with the real loader
load_fixture <- function(ym, dbname, ...) {
  load_month(ym, file = fixture_file(ym), sha256 = fixture_sha256(ym), dbname = dbname, ...)
}

# Mocks the portal: the months in `published` are listed, with the hashes in
# `hashes` (named by month; none by default), and a download copies the
# month's fixture file, or fails for the months in `broken`. The download is
# checked against the fixture's own hash, as the portal's would be.
local_portal <- function(dir, broken = integer(), published = fixture_months(),
                         hashes = character(), env = parent.frame()) {
  testthat::local_mocked_bindings(
    epd_resources = function() {
      data.frame(
        year_month = rev(published), name = "x",
        sha256 = unname(hashes[as.character(rev(published))])
      )
    },
    month_resource = function(year_month) {
      list(name = paste0("EPD_SNOMED_", year_month), url = "https://example.invalid/csv",
           sha256 = fixture_sha256(year_month))
    },
    download_month = function(year_month, ...) {
      if (year_month %in% broken) {
        stop("The portal did not answer.", call. = FALSE)
      }
      file <- file.path(dir, sprintf("EPD_SNOMED_%d.zip", year_month))
      file.copy(fixture_file(year_month), file)
      file
    },
    .env = env
  )
}

# A new migrated database with fixture months loaded by the real loader
local_loaded_db <- function(months, env = parent.frame()) {
  dbname <- local_migrated_db(env = env)
  for (ym in months) {
    suppressMessages(load_fixture(ym, dbname))
  }
  dbname
}

# The fact table's attached partitions
partitions <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT c.relname FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
    WHERE i.inhparent = 'core.prescribing'::regclass ORDER BY 1")$relname
}

# The months with a table or index of the fact table in core, attached or not
fact_months <- function(con) {
  names <- DBI::dbGetQuery(con, "
    SELECT relname FROM pg_class
    WHERE relnamespace = 'core'::regnamespace AND relname ~ '^prescribing_[0-9]{6}'")$relname
  sort(unique(as.integer(substr(names, 13L, 18L))))
}

# Everything in core that a load could change, but load_log
core_state <- function(con) {
  list(
    chemicals = DBI::dbGetQuery(con, "SELECT * FROM core.dim_chemical ORDER BY chemical_id"),
    presentations = DBI::dbGetQuery(
      con, "SELECT * FROM core.dim_presentation ORDER BY presentation_id"
    ),
    practices = DBI::dbGetQuery(con, "SELECT * FROM core.dim_practice ORDER BY practice_id"),
    fact = loaded_fact(con), presentation_month = loaded_presentation_month(con),
    chemical_month = loaded_chemical_month(con), practice_month = loaded_practice_month(con),
    partitions = partitions(con)
  )
}

# One staging row, as text, with every column; arguments override the defaults
staging_row <- function(...) {
  row <- list(
    year_month = "2026-01", regional_office_name = "LONDON", regional_office_code = "Y56",
    icb_name = "NHS TEST INTEGRATED CARE BOARD", icb_code = "QXX", pco_name = "NHS TEST ICB - 00X",
    pco_code = "00X", practice_name = "TEST PRACTICE", practice_code = "A00001",
    address_1 = "1 HIGH STREET", address_2 = "", address_3 = "", address_4 = "",
    postcode = "AB1 2CD", bnf_chemical_substance_code = "0212000B0",
    bnf_chemical_substance = "Atorvastatin", bnf_presentation_code = "0212000B0AAABAB",
    bnf_presentation_name = "Atorvastatin 20mg tablets",
    bnf_chapter_plus_code = "02: Cardiovascular System", quantity = "28.", items = "1",
    total_quantity = "28.", adq_usage = "28.", nic = "0.98", actual_cost = "0.91234",
    unidentified = "N", snomed_code = "320000000000000"
  )
  as.data.frame(utils::modifyList(row, list(...)))
}

# Replaces the staged rows
stage_rows <- function(con, ...) {
  rows <- do.call(rbind, list(...))
  DBI::dbExecute(con, "TRUNCATE raw.epd_staging")
  DBI::dbAppendTable(con, DBI::Id(schema = "raw", table = "epd_staging"), rows)
}

# The fact table and the rollups, keyed by codes, with measures as
# trim_scale() text: the shape of oracle_text()
loaded_fact <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT f.year_month, pr.practice_code, p.bnf_code, coalesce(pr.region_code, '-') AS region_code,
           c.chemical_code, f.items::text AS items,
           trim_scale(f.total_quantity)::text AS total_quantity,
           trim_scale(f.adq_usage)::text AS adq_usage, trim_scale(f.nic)::text AS nic,
           trim_scale(f.actual_cost)::text AS actual_cost
    FROM core.prescribing f
    JOIN core.dim_practice pr ON pr.practice_id = f.practice_id
    JOIN core.dim_presentation p ON p.presentation_id = f.presentation_id
    JOIN core.dim_chemical c ON c.chemical_id = p.chemical_id")
}

loaded_presentation_month <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT a.year_month, p.bnf_code, a.region_code, a.practices, a.items::text AS items,
           trim_scale(a.total_quantity)::text AS total_quantity,
           trim_scale(a.adq_usage)::text AS adq_usage, trim_scale(a.nic)::text AS nic,
           trim_scale(a.actual_cost)::text AS actual_cost
    FROM core.agg_presentation_month a
    JOIN core.dim_presentation p ON p.presentation_id = a.presentation_id")
}

loaded_chemical_month <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT a.year_month, c.chemical_code, a.region_code, a.practices, a.items::text AS items,
           trim_scale(a.adq_usage)::text AS adq_usage, trim_scale(a.nic)::text AS nic,
           trim_scale(a.actual_cost)::text AS actual_cost
    FROM core.agg_chemical_month a
    JOIN core.dim_chemical c ON c.chemical_id = a.chemical_id")
}

loaded_practice_month <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT a.year_month, pr.practice_code, a.presentations, a.items::text AS items,
           trim_scale(a.nic)::text AS nic, trim_scale(a.actual_cost)::text AS actual_cost
    FROM core.agg_practice_month a
    JOIN core.dim_practice pr ON pr.practice_id = a.practice_id")
}

# The same rows, whatever their order, with the expected columns
expect_same_rows <- function(actual, expected, keys) {
  tidy <- function(df) {
    df <- as.data.frame(dplyr::arrange(df, dplyr::across(dplyr::all_of(keys))))[names(expected)]
    rownames(df) <- NULL
    df
  }
  testthat::expect_identical(tidy(actual), tidy(expected))
}

# Every loaded table equals the oracle for these months
expect_loaded_as_oracle <- function(con, months) {
  expect_same_rows(
    loaded_fact(con), oracle_text(oracle_fact(months)), c("year_month", "practice_code", "bnf_code")
  )
  expect_same_rows(
    loaded_presentation_month(con), oracle_text(oracle_presentation_month(months)),
    c("year_month", "bnf_code", "region_code")
  )
  expect_same_rows(
    loaded_chemical_month(con), oracle_text(oracle_chemical_month(months)),
    c("year_month", "chemical_code", "region_code")
  )
  expect_same_rows(
    loaded_practice_month(con), oracle_text(oracle_practice_month(months)),
    c("year_month", "practice_code")
  )
}

load_log <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT year_month, status, source_rows::float8 AS source_rows,
           loaded_rows::float8 AS loaded_rows, error
    FROM core.load_log ORDER BY load_id")
}
