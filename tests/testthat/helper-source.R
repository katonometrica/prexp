# Helpers that write small monthly source files for tests.

skip_without_bsdtar <- function() {
  testthat::skip_if_not(nzchar(Sys.which("bsdtar")), "bsdtar is not installed (libarchive-tools)")
}

# The source header as the publisher writes it: text column names quoted,
# numeric ones not.
source_header <- function(names = epd_columns()$name) {
  cols <- epd_columns()
  text <- cols$name[cols$source_type == "text"]
  paste(ifelse(names %in% text, paste0('"', names, '"'), names), collapse = ",")
}

# One source line for January 2099, quoted as the publisher quotes it.
# Arguments named as source columns replace values, quotes included:
# source_line(ITEMS = "0", PRACTICE_CODE = '"A00002"').
source_line <- function(...) {
  values <- c(
    '"2099-01"', '"NORTH EAST AND YORKSHIRE"', '"Y63"', '"NHS TEST ICB"', '"QHM"',
    '"NHS TEST ICB - 00L"', '"00L"', '"TEST PRACTICE"', '"A00001"', '"1 TEST STREET"',
    '""', '""', '""', '"NE1 1AA"', '"0212000B0"', '"Atorvastatin"', '"0212000B0AAABAB"',
    '"Atorvastatin 20mg tablets"', '"02: Cardiovascular System"', '"28."', "1", '"28."',
    '"28."', '"0.98"', '"0.91234"', '"N"', '"320000000000000"'
  )
  names(values) <- epd_columns()$name
  changes <- list(...)
  stopifnot(all(names(changes) %in% names(values)))
  values[names(changes)] <- unlist(changes)
  paste(values, collapse = ",")
}

# Writes the lines with CRLF endings, as the source does, to a CSV in a new
# temporary folder, and zips it with bsdtar unless zip = FALSE. Returns the path
# of the ZIP, or of the CSV.
local_source_file <- function(lines, zip = TRUE, bom = FALSE, name = "EPD_SNOMED_209901",
                              env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  csv <- file.path(dir, paste0(name, ".csv"))
  bytes <- charToRaw(enc2utf8(paste0(lines, "\r\n", collapse = "")))
  if (bom) {
    bytes <- c(as.raw(c(0xef, 0xbb, 0xbf)), bytes)
  }
  writeBin(bytes, csv)
  if (!zip) {
    return(csv)
  }
  skip_without_bsdtar()
  out <- file.path(dir, paste0(name, ".zip"))
  processx::run("bsdtar", c("--format", "zip", "-cf", out, "-C", dir, basename(csv)))
  out
}
