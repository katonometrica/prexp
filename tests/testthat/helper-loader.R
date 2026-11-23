# Helpers for the loader's tests: fixture hashes, staging rows, reading the
# loaded tables back as text, and comparing them with the oracle.

# The SHA-256 of a fixture month's CSV, as the portal publishes it for a month
fixture_sha256 <- function(ym) {
  dir <- withr::local_tempdir()
  csv <- utils::unzip(fixture_file(ym), exdir = dir, unzip = "internal")
  unname(tools::sha256sum(csv))
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
