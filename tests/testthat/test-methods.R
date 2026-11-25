# The methods section of an export (P5-04): the About tab's sections, so the
# app and the exports never disagree, after what only an export has: when it
# was made, by which version, on which months, and each item's filters.

methods_window <- tibble::tibble(
  first_month = 202510L, last_month = 202609L, months = 12L, loaded_at = Sys.time()
)

methods_report <- function() {
  spec <- report_add(new_report(), "drug", list(
    level = "chemical", id = 57L, code = "0212000B0", label = "Atorvastatin",
    months = c(202601L, 202609L), measure = "nic"
  ))
  spec <- report_add(spec, "practice", list(
    id = 12L, code = "N81655", label = "THE SURGERY", months = c(202510L, 202609L),
    measure = "items"
  ))
  report_add(spec, "region", list(
    level = "presentation", id = 300L, code = "0212000B0AAABAB",
    label = "Atorvastatin 20mg tablets", months = c(202609L, 202609L), measure = "adq_usage"
  ))
}

exported <- as.POSIXct("2026-11-25 14:05:00", tz = "UTC")

test_that("an export's methods say when, by which version and on which months it was made", {
  sections <- methods_content(methods_report(), methods_window, exported)
  titles <- vapply(sections, `[[`, "", "title")
  expect_identical(
    titles, c("This report", "Filters", vapply(methods_sections(), `[[`, "", "title"))
  )
  this <- sections[[1]]$text
  version <- as.character(utils::packageVersion("prexp"))
  expect_identical(this[[1]], paste0(
    "Exported from Prescription Explorer ", version, " on 25 November 2026 at 14:05 GMT."
  ))
  expect_identical(
    this[[2]], "Data period: Oct 2025 to Sep 2026, the months loaded when it was exported."
  )
  # In summer, the UK is an hour ahead of UTC
  july <- as.POSIXct("2026-07-01 09:30", tz = "UTC")
  summer <- methods_content(methods_report(), methods_window, july)
  expect_match(summer[[1]]$text[[1]], "on 1 July 2026 at 10:30 BST.", fixed = TRUE)
  # A POSIXlt in another zone is written in the UK's time too
  tokyo <- as.POSIXlt(july, tz = "Asia/Tokyo")
  expect_identical(export_time(tokyo), "1 July 2026 at 10:30 BST")
  # The date is the UK's, whatever the zone of the time or of the machine: at
  # 23:30 UTC on 30 June it is 1 July in the UK, but 30 June in UTC and in New
  # York. Sys.time(), the default, has no zone of its own, so the machine's
  # applies to it
  withr::local_timezone("America/New_York")
  late <- as.POSIXct("2026-06-30 23:30", tz = "UTC")
  expect_identical(export_time(late), "1 July 2026 at 00:30 BST")
  attr(late, "tzone") <- NULL
  expect_identical(export_time(late), "1 July 2026 at 00:30 BST")
  # The hour that comes twice when the clocks go back, told apart
  back <- as.POSIXct(c("2026-10-25 00:30", "2026-10-25 01:30"), tz = "UTC")
  expect_identical(export_time(back[1]), "25 October 2026 at 01:30 BST")
  expect_identical(export_time(back[2]), "25 October 2026 at 01:30 GMT")
  # The day without a leading zero, and the month in full
  march <- as.POSIXct("2026-03-02 12:00", tz = "UTC")
  expect_identical(export_time(march), "2 March 2026 at 12:00 GMT")
  # No window loaded
  none <- methods_content(methods_report(), methods_window[0, ], exported)
  expect_identical(none[[1]]$text[[2]], "No months of data were loaded when it was exported.")
  nothing <- methods_content(new_report(), NULL, exported)
  expect_identical(nothing[[1]]$text[[2]], none[[1]]$text[[2]])
})

test_that("every item's filters are listed under its title", {
  spec <- methods_report()
  filters <- methods_content(spec, methods_window, exported)[[2]]
  expect_identical(filters$title, "Filters")
  expect_identical(
    vapply(filters$points, `[[`, "", "term"), vapply(spec$items, report_item_title, "")
  )
  expect_identical(vapply(filters$points, `[[`, "", "text"), c(
    paste0(
      "Drug view \u00b7 chemical substance 0212000B0 (Atorvastatin); ",
      "months: Jan 2026 to Sep 2026; measure: Net ingredient cost."
    ),
    paste0(
      "Practice view \u00b7 practice N81655 (THE SURGERY); months: Oct 2025 to Sep 2026; ",
      "measure: Items."
    ),
    paste0(
      "Region view \u00b7 presentation 0212000B0AAABAB (Atorvastatin 20mg tablets); ",
      "months: Sep 2026; measure: ADQ usage."
    )
  ))
  # An item whose months a link moved says so
  clamped <- clamp_report(spec, tibble::tibble(first_month = 202602L, last_month = 202609L))
  text <- methods_content(clamped, methods_window, exported)[[2]]$points[[1]]$text
  expect_match(text, "months: Feb 2026 to Sep 2026", fixed = TRUE)
  expect_match(text, "moved into the data window when the report's link was opened", fixed = TRUE)
  # A report with no items says so
  empty <- methods_content(new_report(), methods_window, exported)[[2]]
  expect_identical(empty$text, "The report has no items.")
  expect_length(empty$points, 0L)
})

test_that("the rest is the About tab's text, the attribution exact, with every limitation", {
  sections <- methods_content(methods_report(), methods_window, exported)
  expect_identical(sections[-(1:2)], methods_sections())
  source <- sections[[length(sections)]]
  expect_identical(source$text[[2]], paste(
    "NHSBSA Copyright 2021-2026 \u00b7 Contains public sector information licensed under the",
    "Open Government Licence v3.0."
  ))
  limits <- vapply(sections[[5]]$points, `[[`, "", "text")
  for (limit in c(
    "(under 0.1% of items)", "follow the commissioner, not the address",
    "ICBs were reorganised in April 2026, from 42 to 36",
    "one that stopped before keeps its old ICB, which no longer exists",
    "dental prescribing", "Patient Group Directions", "hospital site codes",
    "private prescriptions", "about a third of items", "Actual cost changed method in April 2024"
  )) {
    expect_true(any(grepl(limit, limits, fixed = TRUE)), label = limit)
  }
})
