# The exports across formats (P5-08; spec section 6): one report on the fixture
# database, an item from each view with notes and one whose months a link
# moved, exported to PowerPoint, Word and Excel and read back from each file:
# every note, the methods with the exact attribution, the clamped months, and
# the tables' numbers as the fetch functions give them. Then the worst case,
# fifteen items with the longest notes, timed in each format.

formats_time <- as.POSIXct("2026-11-25 14:05", tz = "UTC")

# The report: a chemical substance and a presentation, a practice and a drug
# by region, with notes, and a drug whose months a link moved into the window
formats_report <- function(con) {
  subject <- function(kind, code) fetch_subject(con, kind, code)
  chemical <- subject("chemical", "0212000B0")
  presentation <- subject("presentation", "0212000B0AAABAB")
  practice <- subject("practice", "N81655")
  window <- fetch_window(con)
  drug <- function(found, level, months, measure) {
    list(
      level = level, id = found$id, code = found$code, label = found$name, months = months,
      measure = measure
    )
  }
  spec <- report_add(new_report(), "drug", drug(chemical, "chemical", c(202601L, 202609L), "nic"))
  spec <- report_set_note(spec, 1L, "Costs rose after March.\nSee the presentations.")
  spec <- report_add(
    spec, "drug", drug(presentation, "presentation", c(202510L, 202609L), "total_quantity")
  )
  spec <- report_add(spec, "practice", list(
    id = practice$id, code = practice$code, label = practice$name, months = c(202510L, 202609L),
    measure = "actual_cost"
  ))
  spec <- report_set_note(spec, 3L, "The practice's costs fell in the summer.")
  spec <- report_add(spec, "region", drug(chemical, "chemical", c(202601L, 202609L), "items"))
  spec <- report_set_note(spec, 4L, "The regions differ by a factor of two.")
  # Months from before the window, as an old link would give them
  spec <- report_add(spec, "drug", drug(chemical, "chemical", c(202401L, 202412L), "items"))
  spec <- report_set_note(spec, 5L, "Pinned a year ago.")
  clamp_report(spec, window)
}

# Every piece of text a file holds, as each format's reader gives it: the
# slides' and the document's paragraphs and table cells, the workbook's cells
# but the cover's, whose list of the items' titles would stand in for the
# items' own sheets
file_text <- function(format, path) {
  switch(format,
    pptx = officer::pptx_summary(officer::read_pptx(path))$text,
    docx = officer::docx_summary(officer::read_docx(path))$text,
    xlsx = {
      wb <- openxlsx2::wb_load(path)
      sheets <- setdiff(openxlsx2::wb_get_sheet_names(wb), "Report")
      unlist(lapply(sheets, function(sheet) {
        as.character(unlist(openxlsx2::wb_to_df(wb, sheet = sheet, col_names = FALSE)))
      }))
    }
  )
}

# The methods as each format writes them: each section's title (on a slide,
# after "Methods: "), its paragraphs, its points with their terms (a bullet
# typed on a slide and in a cell, the style's in Word), and its links (in a
# cell, with their address)
methods_lines <- function(format, sections) {
  unlist(lapply(sections, function(section) {
    c(
      if (identical(format, "pptx")) paste("Methods:", section$title) else section$title,
      section$text,
      vapply(section$points, function(point) {
        paste0(
          if (format != "docx") "\u2022 ",
          if (!is.na(point$term)) paste0(point$term, ". "), point$text
        )
      }, ""),
      vapply(section$links, function(link) {
        if (identical(format, "xlsx")) paste0(link$text, ": ", link$url) else link$text
      }, "")
    )
  }))
}

test_that("every format holds every note, the clamped months and the exact attribution", {
  con <- fixture_app()
  spec <- formats_report(con)
  items <- export_items(spec, plain_fetches(con))
  # The item whose months were all before the window has the window's, which
  # its title says, and its notice
  window <- fetch_window(con)
  expect_true(spec$items[[5]]$clamped)
  expect_identical(spec$items[[5]]$params$months, c(window$first_month, window$last_month))
  expect_match(items[[5]]$title, format_month_span(spec$items[[5]]$params$months), fixed = TRUE)
  attribution <- paste(
    "NHSBSA Copyright 2021-2026 \u00b7 Contains public sector information licensed under the",
    "Open Government Licence v3.0."
  )
  notes <- unlist(lapply(items, item_note_lines))
  expect_true(
    "Its months were moved into the data window when the report's link was opened." %in% notes
  )
  for (format in export_formats()$format) {
    path <- withr::local_tempfile(fileext = paste0(".", format))
    export_report(format, spec, con, path, formats_time)
    texts <- file_text(format, path)
    for (line in notes) {
      expect_true(line %in% texts, label = paste(format, "holds", line))
    }
    expect_true(attribution %in% texts, label = paste(format, "holds the attribution"))
    # The rest of the methods too: the data period, each item's filters, the
    # measures' definitions, the limitations
    sections <- methods_content(spec, window, formats_time)
    expect_identical(
      setdiff(methods_lines(format, sections), texts), character(),
      label = paste(format, "misses from the methods")
    )
    # Each item's title, with its months: the clamped item's, the window's
    for (item in items) {
      expect_true(item$title %in% texts, label = paste(format, "holds", item$title))
    }
  }
})

test_that("every format's tables hold the numbers the fetches give", {
  con <- fixture_app()
  spec <- formats_report(con)
  items <- export_items(spec, plain_fetches(con))
  # The numbers as the fetch functions give them, before any shaping: the
  # chemical's presentations, the practice's top drugs, the regions' totals
  chemical <- spec$items[[1]]$params
  presentations <- utils::head(fetch_drug_presentations(con, chemical$id, chemical$months), 25L)
  practice <- spec$items[[3]]$params
  top <- utils::head(
    fetch_practice_top_drugs(con, practice$id, practice$months, "actual_cost", 26L), 25L
  )
  region <- spec$items[[4]]$params
  regions <- fetch_region_comparison(con, "chemical", region$id, region$months, "items")
  written <- c(
    format_pounds(presentations$nic), format_number(presentations$items),
    format_pounds(top$actual_cost), format_number(regions$value),
    format_number(sum(regions$value))
  )
  for (format in c("pptx", "docx")) {
    path <- withr::local_tempfile(fileext = paste0(".", format))
    export_report(format, spec, con, path, formats_time)
    texts <- file_text(format, path)
    missing <- setdiff(written, texts)
    expect_identical(missing, character(), label = paste(format, "misses"))
  }
  # Excel keeps them as numbers
  path <- withr::local_tempfile(fileext = ".xlsx")
  export_report("xlsx", spec, con, path, formats_time)
  sheets <- c("Report", xlsx_sheet_names(items), "Methods")
  read_table <- function(item, sheet) {
    first <- openxlsx2::wb_to_df(path, sheet = sheet, col_names = FALSE)
    header <- which(first[[1]] == item$table$labels[[1]])[1]
    got <- openxlsx2::wb_to_df(path, sheet = sheet, start_row = header)
    got[seq_len(nrow(item$table$data)), seq_along(item$table$labels)]
  }
  chemical_sheet <- read_table(items[[1]], sheets[[2]])
  expect_equal(chemical_sheet[["Net ingredient cost"]], presentations$nic)
  expect_equal(chemical_sheet[["Items"]], presentations$items)
  practice_sheet <- read_table(items[[3]], sheets[[4]])
  expect_equal(practice_sheet[["Actual cost"]], top$actual_cost)
  region_sheet <- read_table(items[[4]], sheets[[5]])
  # Every region's total as fetched, and England's under them
  expect_true(all(regions$value %in% region_sheet[["Items"]]))
  expect_equal(utils::tail(region_sheet[["Items"]], 1L), sum(regions$value))
})

test_that("the worst case exports in under ten seconds in each format", {
  con <- fixture_app()
  window <- fetch_window(con)
  months <- c(window$first_month, window$last_month)
  codes <- function(sql) DBI::dbGetQuery(con, sql)[[1]]
  chemicals <- codes(paste(
    "SELECT c.chemical_code FROM app.v_chemical c",
    "JOIN app.v_presentation p ON p.chemical_id = c.chemical_id",
    "GROUP BY c.chemical_code ORDER BY count(*) DESC, c.chemical_code LIMIT 5"
  ))
  presentations <- codes("SELECT bnf_code FROM app.v_presentation ORDER BY bnf_code LIMIT 4")
  practices <- codes(paste(
    "SELECT practice_code FROM app.v_practice WHERE NOT is_unidentified",
    "ORDER BY practice_code LIMIT 3"
  ))
  note <- substr(
    paste(rep("Costs rose after March, and the region's share fell.", 10), collapse = " "), 1L, 500L
  )
  spec <- new_report()
  add <- function(spec, view, kind, code, measure) {
    found <- fetch_subject(con, kind, code)
    params <- list(id = found$id, code = found$code, label = found$name, months = months,
                   measure = measure)
    if (view != "practice") {
      params <- c(list(level = kind), params)
    }
    spec <- report_add(spec, view, params)
    report_set_note(spec, spec$next_id - 1L, note)
  }
  for (code in chemicals) spec <- add(spec, "drug", "chemical", code, "nic")
  for (code in presentations) spec <- add(spec, "drug", "presentation", code, "items")
  for (code in practices) spec <- add(spec, "practice", "practice", code, "actual_cost")
  for (code in chemicals[1:3]) spec <- add(spec, "region", "chemical", code, "items")
  expect_length(spec$items, report_limits()$items)
  for (format in export_formats()$format) {
    path <- withr::local_tempfile(fileext = paste0(".", format))
    took <- system.time(export_report(format, spec, con, path, formats_time))[["elapsed"]]
    expect_lt(took, 10, label = paste(format, "takes", round(took, 1), "s"))
  }
})
