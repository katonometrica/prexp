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
