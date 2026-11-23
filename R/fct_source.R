# The source files: finding and downloading a month on the portal, the
# expected columns, reading a monthly file and checking its header (spec
# section 4, steps 1 to 3).
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

# ---------------------------------------------------------------- the portal

# The NHSBSA open data portal runs CKAN. package_show lists one resource per
# month, named EPD_SNOMED_YYYYMM; resource ids are random, so a month is found
# by its name.
epd_dataset <- "english-prescribing-dataset-epd-with-snomed-code"
ckan_package_show <- "https://opendata.nhsbsa.net/api/3/action/package_show"
# A generic agent with the project's address, and nothing about the person
# running it
user_agent <- "prexp (+https://github.com/katonometrica/prexp)"

#' List the months published on the portal
#'
#' Calls the portal's CKAN `package_show` for the English Prescribing Dataset
#' (EPD) with SNOMED Code and returns one row per monthly file.
#'
#' The `zip_url` is a signed link that expires an hour after the call, so fetch
#' the list again shortly before downloading; [download_month()] does that on
#' every attempt.
#'
#' @return A data frame ordered by month, with `year_month` (integer `YYYYMM`,
#'   from the resource name `EPD_SNOMED_YYYYMM`), `name`, `url` (the CSV, a stable
#'   link), `zip_url` (the ZIP, `NA` when there is none), `size` (bytes of the
#'   CSV), `sha256` (of the CSV, which the ZIP holds) and `created` (the
#'   publication time, UTC). A month published twice keeps its latest resource.
#' @export
epd_resources <- function() {
  resp <- httr2::request(ckan_package_show) |>
    httr2::req_url_query(id = epd_dataset) |>
    httr2::req_user_agent(user_agent) |>
    httr2::req_timeout(60) |>
    httr2::req_retry(
      max_tries = 4, retry_on_failure = TRUE,
      is_transient = function(resp) httr2::resp_status(resp) %in% c(429L, 500L, 502L, 503L, 504L),
      backoff = function(attempt) min(30, 2^attempt)
    ) |>
    httr2::req_perform()
  body <- jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE)
  if (!isTRUE(body$success)) {
    stop("The portal's package_show call did not succeed.", call. = FALSE)
  }
  parse_resources(body$result$resources)
}

parse_resources <- function(resources) {
  field <- function(r, name, empty = NA) {
    value <- r[[name]]
    if (is.null(value) || identical(value, "")) empty else value
  }
  name <- vapply(resources, field, character(1), name = "name", empty = "")
  resources <- resources[grepl("^EPD_SNOMED_[0-9]{6}$", name)]
  name <- name[grepl("^EPD_SNOMED_[0-9]{6}$", name)]
  out <- data.frame(
    year_month = as.integer(substring(name, 12L)),
    name = name,
    url = vapply(resources, field, character(1), name = "url", empty = NA_character_),
    zip_url = vapply(resources, field, character(1), name = "zip_url", empty = NA_character_),
    size = vapply(resources, function(r) as.numeric(field(r, "size")), numeric(1)),
    sha256 = vapply(resources, field, character(1), name = "sha256", empty = NA_character_),
    created = as.POSIXct(
      vapply(resources, field, character(1), name = "created", empty = NA_character_),
      format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"
    )
  )
  out <- out[order(out$year_month, out$created, decreasing = c(FALSE, TRUE), method = "radix"), ]
  out <- out[!duplicated(out$year_month), ]
  rownames(out) <- NULL
  out
}

# The portal's current resource for one month; stops when it is not published.
month_resource <- function(year_month) {
  resources <- epd_resources()
  res <- resources[resources$year_month == year_month, ]
  if (nrow(res) == 0L) {
    stop(
      "EPD_SNOMED_", year_month, " is not published on the portal. The latest month is ",
      max(resources$year_month), ".",
      call. = FALSE
    )
  }
  as.list(res)
}

#' Download one month's file from the portal
#'
#' Downloads the month's ZIP, or its CSV when the portal offers no ZIP, into
#' `dir`. The file is written as `<file>.part` and renamed only when complete,
#' so an interrupted download never leaves a complete-looking file. An existing
#' complete file is kept (for the CSV, only if its size matches the portal's).
#'
#' Each attempt fetches the month's metadata again, because the ZIP's link is
#' signed for one hour. Network errors and server errors (5xx, 429) are retried
#' with growing pauses; other errors stop at once. The file's content is checked
#' against the portal's SHA-256 when it is staged.
#'
#' @param year_month The month, as `YYYYMM`.
#' @param dir Folder for downloads. Defaults to `PREXP_DOWNLOAD_DIR`, or
#'   `/data/epd`.
#' @param attempts Number of attempts.
#' @param backoff Seconds to wait after a failed attempt, as a function of the
#'   attempt number.
#' @return The path of the downloaded file, invisibly.
#' @export
download_month <- function(year_month, dir = Sys.getenv("PREXP_DOWNLOAD_DIR", "/data/epd"),
                           attempts = 4L, backoff = function(attempt) min(300, 15 * 2^attempt)) {
  ym <- check_year_month(year_month)
  name <- paste0("EPD_SNOMED_", ym)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  zip <- file.path(dir, paste0(name, ".zip"))
  if (file.exists(zip)) {
    message("Using ", zip, ", downloaded before")
    return(invisible(zip))
  }
  error <- NULL
  for (attempt in seq_len(attempts)) {
    if (attempt > 1L) {
      Sys.sleep(backoff(attempt - 1L))
    }
    outcome <- tryCatch(download_attempt(ym, dir), error = function(e) e)
    if (!inherits(outcome, "error")) {
      return(invisible(outcome))
    }
    error <- outcome
    if (!is_retryable(error)) {
      break
    }
    message("Download of ", name, " failed (attempt ", attempt, " of ", attempts, "): ",
            conditionMessage(error))
  }
  stop("Could not download ", name, ": ", conditionMessage(error), call. = FALSE)
}

# One attempt: fresh metadata, then the ZIP, or the CSV, into <file>.part.
download_attempt <- function(year_month, dir) {
  res <- month_resource(year_month)
  use_zip <- !is.na(res$zip_url)
  file <- file.path(dir, paste0(res$name, if (use_zip) ".zip" else ".csv"))
  if (!use_zip && file.exists(file) && isTRUE(file.size(file) == res$size)) {
    message("Using ", file, ", downloaded before")
    return(file)
  }
  part <- paste0(file, ".part")
  unlink(part)
  started <- Sys.time()
  fetch_file(if (use_zip) res$zip_url else res$url, part)
  if (!use_zip && !is.na(res$size) && file.size(part) != res$size) {
    stop(
      "The download of ", basename(file), " has ", file.size(part), " bytes, not ",
      format(res$size, scientific = FALSE), ".",
      call. = FALSE
    )
  }
  if (!file.rename(part, file)) {
    stop("Could not rename ", part, " to ", basename(file), ".", call. = FALSE)
  }
  seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  message(sprintf(
    "Downloaded %s: %.1f MB in %.0f s", basename(file), file.size(file) / 1e6, seconds
  ))
  file
}

# Streams the response body to `path`. Hours of total time are allowed for a
# multi-GB file; a transfer slower than 10 kB/s for two minutes is abandoned.
fetch_file <- function(url, path) {
  resp <- httr2::request(url) |>
    httr2::req_user_agent(user_agent) |>
    httr2::req_timeout(4 * 3600) |>
    httr2::req_options(low_speed_limit = 10240L, low_speed_time = 120L) |>
    httr2::req_perform(path = path)
  # A mocked response (in tests) keeps its body in memory instead of writing it
  if (is.raw(resp$body) && !file.exists(path)) {
    writeBin(resp$body, path)
  }
  invisible(path)
}

# Network failures, server errors and rate limits are worth another attempt;
# other HTTP errors (a missing file) and our own checks are not, except a
# truncated download.
is_retryable <- function(error) {
  if (inherits(error, "httr2_failure")) {
    return(TRUE)
  }
  if (inherits(error, "httr2_http")) {
    return(httr2::resp_status(error$resp) %in% c(429L, 500L, 502L, 503L, 504L))
  }
  grepl("^The download of .* bytes, not", conditionMessage(error))
}
