# Writes the thirteen fixture months in tests/testthat/fixtures/ (spec section 6.1,
# ticket P1-02).
#
# Source: the September 2026 month of the English Prescribing Dataset (EPD) with
# SNOMED Code, NHSBSA Copyright 2021-2026, Open Government Licence 3.0
# (tests/testthat/fixtures/README.md). Run from the repository root in the
# rstudio container, with the month's ZIP downloaded:
#
#   Rscript data-raw/make_fixtures.R [/data/epd/EPD_SNOMED_202609.zip]
#
# The sample keeps every row of eight prescribers, chosen from the full month
# (docs/dataset.md) so that together they cover what the loader must handle, and
# a seeded sample of the national unidentified prescriber. The thirteen months,
# 202509 to 202609, repeat the same rows with YEAR_MONTH shifted and the
# measures scaled by a seeded factor per month, so series are not flat; 202609
# is the real rows, unscaled. The files keep the source's exact layout: the
# header line as published, every field quoted but ITEMS, numbers written as
# the publisher writes them ("60.", "0.75199"), CRLF line endings. They are
# zipped with bsdtar with fixed times and owners, so every run writes
# identical files.

source_zip <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(source_zip)) {
  source_zip <- "/data/epd/EPD_SNOMED_202609.zip"
}
out_dir <- "tests/testthat/fixtures"
stopifnot(file.exists(source_zip), dir.exists(out_dir))

# Every row of these prescribers is kept. Together they cover all seven v2
# groups, brands and generics of one substance, presentations with no ADQ,
# practice x presentation pairs with several rows (different SNOMED codes or
# quantities per item), empty SNOMED codes, and all seven regions.
prescribers <- c(
  F84737 = "London: an out-of-hours GP co-operative, with two rarely prescribed drugs",
  K84066 = "South East: a small practice",
  C82059 = "Midlands: a practice with a drug no other practice prescribed (0404000W0BBAAAA)",
  N81655 = "North West: a practice for homeless people",
  A82620 = "North East and Yorkshire: an appliance no other practice prescribed (23052400508)",
  Y06630 = "South West: a lymphoedema service, nearly all appliances (chapters 20 to 23)",
  Y03965 = "Midlands: a community service, not a GP practice",
  `07H998` = "East of England: the unidentified prescribers of one commissioner"
)
# The national unidentified prescriber '-' has 13,773 rows in 202609. The
# sample always includes its two pairs of rows that share the finest key
# (presentation, SNOMED code and quantity) and differ only in their measures.
national_rows <- 800L
# A real month can hold rows identical in all 27 columns (docs/dataset.md),
# though 202609 has none: one sampled national row is written twice.
months <- c(202509L:202512L, 202601L:202609L)
stamp <- as.POSIXct("2026-11-20 00:00:00", tz = "UTC")

columns <- utils::read.csv("inst/extdata/epd_columns.csv", colClasses = "character")
names <- columns$name
text_columns <- names[columns$source_type == "text"]

run <- function(script, ...) {
  res <- processx::run("bash", c("-c", script, "bash", ...), encoding = "UTF-8")
  sub("\r$", "", strsplit(res$stdout, "\n", fixed = TRUE)[[1]])
}

# The header as published, and the rows that mention a chosen code. The exact
# practice filter comes after parsing.
header <- run('bsdtar -xOf "$1" | head -n 1', source_zip)[1]
expected <- paste(ifelse(names %in% text_columns, paste0('"', names, '"'), names), collapse = ",")
stopifnot(identical(header, expected))
patterns <- tempfile(fileext = ".txt")
writeLines(sprintf(',"%s",', c(names(prescribers), "-")), patterns)
lines <- run('set -o pipefail; bsdtar -xOf "$1" | grep -F -f "$2"', source_zip, patterns)
rows <- utils::read.csv(
  text = paste(lines, collapse = "\n"), header = FALSE, col.names = names,
  colClasses = "character", na.strings = character(), check.names = FALSE
)
rows <- rows[rows$PRACTICE_CODE %in% c(names(prescribers), "-"), ]
stopifnot(all(rows$YEAR_MONTH == "2026-09"), all(names(prescribers) %in% rows$PRACTICE_CODE))

national <- which(rows$PRACTICE_CODE == "-")
finest <- paste(rows$BNF_PRESENTATION_CODE, rows$SNOMED_CODE, rows$QUANTITY)[national]
repeated <- national[finest %in% finest[duplicated(finest)]]
set.seed(20261123L)
others <- setdiff(national, repeated)
picked <- sort(sample.int(length(others), national_rows - length(repeated)))
sampled <- sort(c(repeated, others[picked]))
rows <- rows[sort(c(which(rows$PRACTICE_CODE != "-"), sampled)), ]
twice <- which(rows$PRACTICE_CODE == "-")[1]
rows <- rows[append(seq_len(nrow(rows)), twice, after = twice), ]
rownames(rows) <- NULL

# Month factors between 0.8 and 1.2, two decimals; 202609 keeps the real rows.
factors <- round(stats::runif(length(months), 0.8, 1.2), 2)
factors[months == 202609L] <- 1

# A number as the publisher writes it: up to `digits` decimals, no trailing
# zeros, and a trailing point for whole numbers.
source_number <- function(x, digits) {
  sub("0+$", "", sprintf(paste0("%.", digits, "f"), x))
}

scale_month <- function(rows, ym, factor) {
  rows$YEAR_MONTH <- sprintf("%d-%02d", ym %/% 100L, ym %% 100L)
  if (factor == 1) {
    return(rows)
  }
  items <- as.integer(rows$ITEMS)
  scaled <- pmax(1L, as.integer(round(items * factor)))
  ratio <- scaled / items
  rows$ITEMS <- as.character(scaled)
  # TOTAL_QUANTITY is always QUANTITY x ITEMS; the costs and ADQ follow the items
  rows$TOTAL_QUANTITY <- source_number(as.numeric(rows$QUANTITY) * scaled, 2)
  rows$ADQ_USAGE <- source_number(as.numeric(rows$ADQ_USAGE) * ratio, 5)
  rows$NIC <- source_number(as.numeric(rows$NIC) * ratio, 2)
  rows$ACTUAL_COST <- source_number(as.numeric(rows$ACTUAL_COST) * ratio, 5)
  rows
}

csv_lines <- function(rows) {
  fields <- lapply(names, function(col) {
    x <- rows[[col]]
    if (col == "ITEMS") x else paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
  })
  do.call(paste, c(fields, sep = ","))
}

work <- tempfile("fixtures-")
dir.create(work)
for (i in seq_along(months)) {
  name <- sprintf("EPD_SNOMED_%d", months[i])
  csv <- file.path(work, paste0(name, ".csv"))
  body <- c(header, csv_lines(scale_month(rows, months[i], factors[i])))
  writeBin(charToRaw(enc2utf8(paste0(body, "\r\n", collapse = ""))), csv)
  # The entry's owner, mode and time come from an mtree manifest rather than
  # the file system, which would add the file's own access and change times
  spec <- file.path(work, paste0(name, ".mtree"))
  writeLines(c("#mtree", sprintf(
    "%s type=file uid=0 gid=0 uname=root gname=root mode=0644 time=%d.0 contents=%s",
    basename(csv), as.integer(stamp), csv
  )), spec)
  zip <- file.path(normalizePath(out_dir), paste0(name, ".zip"))
  unlink(zip)
  processx::run("bsdtar", c(
    "--format", "zip", "--options", "zip:compression=deflate,zip:compression-level=9",
    "-cf", zip, paste0("@", spec)
  ))
  cat(sprintf(
    "%s  %d rows  factor %.2f  %s  %s\n", basename(zip), length(body) - 1L, factors[i],
    format(file.size(zip), big.mark = ","), tools::sha256sum(zip)
  ))
}
unlink(work, recursive = TRUE)
total <- sum(file.size(file.path(out_dir, sprintf("EPD_SNOMED_%d.zip", months))))
cat(sprintf(
  "%d fixture months, %s bytes in total\n", length(months), format(total, big.mark = ",")
))
