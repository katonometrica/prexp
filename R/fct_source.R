# The source files: the expected columns, reading a monthly file, and checking
# its header (spec section 4, steps 1 to 3).
#
# A monthly file is the portal's ZIP, holding one CSV, or the CSV itself when a
# month has no ZIP. ZIPs are read with bsdtar (libarchive): Ubuntu's unzip
# cannot read these archives, writes nothing and still exits with status 0.

#' The expected columns of a monthly file
#'
#' @return A data frame with `position`, `name`, `source_type`, `load_as` and
#'   `description`, from `inst/extdata/epd_columns.csv`.
#' @noRd
epd_columns <- function() {
  path <- system.file("extdata", "epd_columns.csv", package = "prexp", mustWork = TRUE)
  utils::read.csv(path, colClasses = "character", na.strings = character(), encoding = "UTF-8")
}

# TRUE when the file starts with a ZIP local file header ("PK\3\4").
is_zip <- function(file) {
  magic <- readBin(file, "raw", n = 4L)
  identical(magic, as.raw(c(0x50, 0x4b, 0x03, 0x04)))
}

# A shell command that writes the file's CSV to standard output, with the file
# path as its first argument ("$1"), never spliced into the command.
source_stream_command <- function(file) {
  if (is_zip(file)) 'bsdtar -xOf "$1"' else 'cat -- "$1"'
}

# Runs a shell snippet with bash, passing args as $1, $2, ... A non-zero exit
# stops with the command's standard error.
run_bash <- function(script, args = character(), error_on_status = TRUE, ...) {
  res <- processx::run(
    "bash", c("-c", script, "bash", args),
    error_on_status = FALSE, encoding = "UTF-8", ...
  )
  if (error_on_status && res$status != 0L) {
    stop(trimws(res$stderr), call. = FALSE)
  }
  res
}

# The entries of a ZIP file, which must be exactly one file. Concatenated
# entries would load a second header as data.
check_archive <- function(file) {
  res <- run_bash('bsdtar -tf "$1"', file, error_on_status = FALSE)
  if (res$status != 0L) {
    stop("Could not read the archive ", file, ": ", trimws(res$stderr), call. = FALSE)
  }
  entries <- strsplit(res$stdout, "\n", fixed = TRUE)[[1]]
  entries <- entries[nzchar(entries) & !grepl("/$", entries)]
  if (length(entries) != 1L) {
    stop(
      "Expected one file in the archive ", file, ", found ", length(entries),
      if (length(entries) > 0L) paste0(": ", toString(entries)),
      call. = FALSE
    )
  }
  entries
}

# The first line of the file's CSV, without a trailing carriage return.
read_header_line <- function(file) {
  if (!file.exists(file)) {
    stop("File not found: ", file, call. = FALSE)
  }
  if (is_zip(file)) {
    check_archive(file)
  }
  # No pipefail: head stops reading after one line, and the extractor then exits
  # on a broken pipe. Its errors still reach standard error.
  res <- run_bash(paste(source_stream_command(file), "| head -n 1"), file, error_on_status = FALSE)
  line <- sub("\r$", "", strsplit(res$stdout, "\n", fixed = TRUE)[[1]][1])
  if (is.na(line) || !nzchar(line)) {
    stop("Could not read a header line from ", file, ": ", trimws(res$stderr), call. = FALSE)
  }
  line
}

#' Check a monthly file's header against the expected columns
#'
#' Reads the first line of the file's CSV and compares the column names and
#' their order with `inst/extdata/epd_columns.csv`. A byte-order mark is
#' ignored, and so is letter case, which does not change a column's meaning;
#' anything else stops, because loading shifted or repurposed columns would
#' load wrong numbers silently. The publisher renamed columns in May 2022 and
#' March 2025.
#'
#' @param file A monthly ZIP holding one CSV, or the CSV itself.
#' @return The column names as found, invisibly. On a mismatch, stops with one
#'   message listing the missing, unexpected, repeated and reordered columns.
#' @noRd
validate_header <- function(file) {
  line <- sub("^﻿", "", read_header_line(file))
  found <- scan(
    text = line, what = "", sep = ",", quote = "\"", na.strings = character(),
    strip.white = FALSE, quiet = TRUE, encoding = "UTF-8"
  )
  expected <- epd_columns()$name
  key <- toupper(found)
  if (identical(key, expected)) {
    return(invisible(found))
  }
  quoted <- function(x) toString(paste0("'", x, "'"))
  problems <- character()
  missing <- setdiff(expected, key)
  if (length(missing) > 0L) {
    problems <- c(problems, paste("missing", quoted(missing)))
  }
  unexpected <- found[!key %in% expected]
  if (length(unexpected) > 0L) {
    problems <- c(problems, paste("unexpected", quoted(unexpected)))
  }
  repeated <- unique(found[duplicated(key)])
  if (length(repeated) > 0L) {
    problems <- c(problems, paste("repeated", quoted(repeated)))
  }
  once <- key[key %in% expected & !key %in% key[duplicated(key)]]
  moved <- out_of_order(once, expected)
  if (length(moved) > 0L) {
    problems <- c(problems, paste("reordered", quoted(moved)))
  }
  stop(
    "The header of ", basename(file), " does not match inst/extdata/epd_columns.csv: ",
    paste(problems, collapse = "; "), ".",
    call. = FALSE
  )
}

# The names in `found` that are out of their order in `expected`: those outside
# a longest increasing run of their expected positions, so a single moved
# column is reported alone rather than every column it shifted.
out_of_order <- function(found, expected) {
  pos <- match(found, expected)
  n <- length(pos)
  if (n == 0L) {
    return(character())
  }
  run <- rep(1L, n)
  before <- rep(0L, n)
  for (i in seq_len(n)) {
    for (j in seq_len(i - 1L)) {
      if (pos[j] < pos[i] && run[j] + 1L > run[i]) {
        run[i] <- run[j] + 1L
        before[i] <- j
      }
    }
  }
  keep <- integer()
  i <- which.max(run)
  while (i > 0L) {
    keep <- c(i, keep)
    i <- before[i]
  }
  found[-keep]
}
