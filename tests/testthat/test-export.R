# The exports (P5-05 to P5-07; spec section 5.5): each item fetched again and shaped as
# its view shapes it, its table laid out to fit its slides, and the report
# written to PowerPoint with native charts, tables, notes and the methods
# last; the runner that sends an export to a worker; and the Report tab's
# Prepare and Download. The fixture database holds the data
# (helper-fixture-db.R).

export_months <- c(202601L, 202609L)

# The shapes of each slide of a PowerPoint file, in inches: where each
# starts and ends, and for a table the bottom of the rows PowerPoint draws
pptx_shapes <- function(path) {
  dir <- withr::local_tempdir()
  utils::unzip(path, exdir = dir)
  files <- list.files(file.path(dir, "ppt", "slides"), "[.]xml$", full.names = TRUE)
  do.call(rbind, lapply(files, function(file) {
    doc <- xml2::read_xml(file)
    ns <- xml2::xml_ns(doc)
    shapes <- xml2::xml_find_all(doc, "//p:spTree/p:sp | //p:spTree/p:graphicFrame", ns)
    if (length(shapes) == 0L) {
      return(NULL)
    }
    inch <- function(node, xpath, attr) {
      as.numeric(xml2::xml_attr(xml2::xml_find_first(node, xpath, ns), attr)) / 914400
    }
    data.frame(
      slide = basename(file),
      left = vapply(shapes, inch, 1, ".//a:off", "x"),
      top = vapply(shapes, inch, 1, ".//a:off", "y"),
      width = vapply(shapes, inch, 1, ".//a:ext", "cx"),
      height = vapply(shapes, inch, 1, ".//a:ext", "cy"),
      rows = vapply(shapes, function(node) {
        sum(as.numeric(xml2::xml_attr(xml2::xml_find_all(node, ".//a:tr", ns), "h"))) / 914400
      }, 1),
      table = vapply(shapes, function(node) {
        length(xml2::xml_find_all(node, ".//a:tbl", ns)) > 0L
      }, TRUE)
    )
  }))
}

# That every shape is on its slide, and every table's rows within its frame
expect_on_slides <- function(path) {
  shapes <- pptx_shapes(path)
  expect_true(all(shapes$top + shapes$height <= 7.5 + 1e-6), label = "every shape on its slide")
  expect_true(all(shapes$left + shapes$width <= 13.334), label = "every shape within the width")
  tables <- shapes[shapes$table, ]
  expect_true(
    all(tables$top + tables$rows <= tables$top + tables$height + 1e-6),
    label = "every table's rows within its frame"
  )
  invisible(shapes)
}
# A part of an unpacked workbook, without its namespaces, so that paths into
# a sheet, its .rels or styles.xml need no prefix
xlsx_part <- function(dir, ...) {
  xml2::xml_ns_strip(xml2::read_xml(file.path(dir, "xl", ...)))
}

# The number format of each cell of a sheet, by its address: its code, or
# "General" for none
xlsx_cell_formats <- function(dir, sheet) {
  styles <- xlsx_part(dir, "styles.xml")
  numfmts <- xml2::xml_find_all(styles, "//numFmts/numFmt")
  codes <- c("0" = "General", structure(
    xml2::xml_attr(numfmts, "formatCode"), names = xml2::xml_attr(numfmts, "numFmtId")
  ))
  ids <- xml2::xml_attr(xml2::xml_find_all(styles, "//cellXfs/xf"), "numFmtId")
  cells <- xml2::xml_find_all(sheet, "//sheetData/row/c")
  style <- as.integer(xml2::xml_attr(cells, "s"))
  structure(
    unname(codes[ids[ifelse(is.na(style), 0L, style) + 1L]]), names = xml2::xml_attr(cells, "r")
  )
}

# The fonts the parts of an unpacked Office file name, the parts whose names
# match `pattern`: each typeface of a drawing's runs (slides, charts), each
# font of a Word run, each font of a workbook's styles
named_fonts <- function(dir, pattern) {
  files <- list.files(dir, pattern, recursive = TRUE, full.names = TRUE)
  unlist(lapply(files, function(file) {
    xml <- paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = " ")
    tags <- unlist(regmatches(
      xml, gregexpr("<a:(latin|ea|cs|sym) [^>]*>|<w:rFonts[^>]*>|<name [^>]*>", xml)
    ))
    values <- regmatches(
      tags, gregexpr("(typeface|w:ascii|w:hAnsi|w:eastAsia|w:cs|val)=\"[^\"]*\"", tags)
    )
    sub("^[^\"]*\"([^\"]*)\"$", "\\1", unlist(values))
  }))
}

# The theme's fonts, by reference: IBM Plex Sans in the exports' themes
theme_fonts <- c("+mn-lt", "+mn-ea", "+mn-cs", "+mj-lt", "+mj-ea", "+mj-cs")

# The colours the parts of an unpacked Office file draw in, six hex digits
drawn_colours <- function(dir, pattern) {
  files <- list.files(dir, pattern, recursive = TRUE, full.names = TRUE)
  xml <- vapply(files, function(file) paste(readLines(file, warn = FALSE), collapse = " "), "")
  found <- unlist(regmatches(
    xml, gregexpr("(srgbClr val|w:color w:val|w:fill|rgb)=\"[0-9A-Fa-f]{6,8}\"", xml)
  ))
  hex <- toupper(sub("^.*=\"([0-9A-Fa-f]+)\"$", "\\1", found))
  substr(hex, nchar(hex) - 5L, nchar(hex))
}

# The exports' colours as six hex digits, and white, the page's
export_colours <- function() c(sub("#", "", export_palette(), fixed = TRUE), "FFFFFF")

# That chart parts draw no frame around the chart: the chart space's one
# shape property straight after the chart, as the schema orders it, with no
# line, and none after its text properties, where mschart writes one
expect_flat_charts <- function(files) {
  expect_gt(length(files), 0L)
  for (file in files) {
    doc <- xml2::read_xml(file)
    ns <- xml2::xml_ns(doc)
    found <- function(xpath) length(xml2::xml_find_all(doc, xpath, ns))
    expect_identical(found(
      "/c:chartSpace/c:chart/following-sibling::*[1][self::c:spPr]/a:ln/a:noFill"
    ), 1L, label = basename(file))
    expect_identical(found("/c:chartSpace/c:spPr"), 1L, label = basename(file))
    expect_identical(found("/c:chartSpace/c:txPr/following-sibling::c:spPr"), 0L)
  }
}

# The anchors of the text boxes of no type on a deck's slides, those officer
# places with ph_location()
untyped_anchors <- function(path) {
  dir <- withr::local_tempdir()
  utils::unzip(path, exdir = dir)
  files <- list.files(file.path(dir, "ppt", "slides"), "[.]xml$", full.names = TRUE)
  unlist(lapply(files, function(file) {
    doc <- xml2::read_xml(file)
    boxes <- xml2::xml_find_all(
      doc, "//p:sp[p:nvSpPr/p:nvPr/p:ph[not(@type)]]/p:txBody/a:bodyPr", xml2::xml_ns(doc)
    )
    xml2::xml_attr(boxes, "anchor")
  }))
}

export_time_fixed <- as.POSIXct("2026-11-25 14:05", tz = "UTC")

# A report with an item of each kind, two with notes
export_spec <- function(con) {
  subject <- function(kind, code) fetch_subject(con, kind, code)
  chemical <- subject("chemical", "0212000B0")
  presentation <- subject("presentation", "0212000B0AAABAB")
  practice <- subject("practice", "N81655")
  drug <- function(found, level, measure) {
    list(
      level = level, id = found$id, code = found$code, label = found$name,
      months = export_months, measure = measure
    )
  }
  spec <- report_add(new_report(), "drug", drug(chemical, "chemical", "nic"))
  spec <- report_set_note(spec, 1L, "Costs rose after March.\nSee the presentations.")
  spec <- report_add(spec, "drug", drug(presentation, "presentation", "total_quantity"))
  spec <- report_add(spec, "practice", list(
    id = practice$id, code = practice$code, label = practice$name, months = export_months,
    measure = "items"
  ))
  spec <- report_add(spec, "region", drug(chemical, "chemical", "adq_usage"))
  report_set_note(spec, 4L, "The regions differ.")
}

test_that("each item is fetched again and shaped as its view shapes it", {
  con <- fixture_app()
  spec <- export_spec(con)
  items <- export_items(spec, plain_fetches(con))
  expect_identical(vapply(items, `[[`, "", "title"), vapply(spec$items, report_item_title, ""))
  months <- format_month(index_month(seq(month_index(202601L), month_index(202609L))))
  # A chemical substance: its months, and its presentations, most items first
  chemical <- spec$items[[1]]$params
  series <- fetch_drug_series(con, "chemical", chemical$id, export_months, "nic")
  expect_identical(items[[1]]$chart$type, "line")
  expect_identical(items[[1]]$chart$labels, months)
  expect_equal(items[[1]]$chart$values[match(series$year_month, index_month(
    seq(month_index(202601L), month_index(202609L))
  ))], series$value)
  presentations <- fetch_drug_presentations(con, chemical$id, export_months)
  expect_identical(items[[1]]$table$data$code, utils::head(presentations$bnf_code, 25L))
  expect_equal(items[[1]]$table$data$nic, utils::head(presentations$nic, 25L))
  expect_identical(items[[1]]$note, "Costs rose after March.\nSee the presentations.")
  expect_match(items[[1]]$chart$alt, "^Net ingredient cost by month, Jan . Sep 2026: ")
  # A presentation: its months, as a table too
  expect_identical(items[[2]]$table$labels, c("Month", "Quantity", "Prescribers"))
  expect_equal(items[[2]]$table$data$value, items[[2]]$chart$values)
  # A practice: its months of the measure, its top drugs by it, and where it is
  practice <- spec$items[[3]]$params
  top <- fetch_practice_top_drugs(con, practice$id, export_months, "items", 26L)
  expect_identical(items[[3]]$table$data$code, utils::head(top$bnf_code, 25L))
  expect_identical(items[[3]]$table$data$rank, seq_len(min(25L, nrow(top))))
  profile <- fetch_practice_profile(con, practice$id)
  expect_match(items[[3]]$profile, profile$region_name, fixed = TRUE)
  # A drug by region: the largest region at the top of the chart, which
  # Office draws from the bottom, and England's total under the regions
  region <- spec$items[[4]]$params
  rows <- fetch_region_comparison(con, "chemical", region$id, export_months, "adq_usage")
  expect_identical(items[[4]]$chart$type, "bar")
  expect_identical(items[[4]]$chart$values, sort(items[[4]]$chart$values))
  table <- items[[4]]$table
  expect_identical(utils::tail(table$data$region, 1L), "England")
  expect_equal(utils::tail(table$data$value, 1L), sum(rows$value, na.rm = TRUE))
  expect_true(table$total)
  # What it says where there is nothing to show
  gone <- report_add(new_report(), "drug", modifyList(chemical, list(id = 2147483647L)))
  gone <- report_add(gone, "practice", modifyList(practice, list(id = 2147483647L)))
  empty <- export_items(gone, plain_fetches(con))
  expect_null(empty[[1]]$chart)
  expect_match(empty[[1]]$message, "was not prescribed in Jan . Sep 2026.")
  expect_identical(empty[[2]]$message, paste(practice$label, "is not in the data."))
})

test_that("a table's values are written as the app writes them", {
  table <- export_table(
    "A table",
    data.frame(name = c("A", NA), n = c(1234, NA), cost = c(1234.5, 0), share = c(0.1234, NA)),
    c("Name", "Items", "Net ingredient cost", "Share"),
    c("text", "items", "nic", "share")
  )
  expect_identical(table_text(table), data.frame(
    name = c("A", ""), n = c("1,234", "\u2013"), cost = c("\u00a31,234.50", "\u00a30.00"),
    share = c("12.3%", "\u2013")
  ))
})

test_that("a table is laid out to fit its width, and cut into pages that fit their height", {
  long <- paste("A presentation with a long name", seq_len(30))
  table <- export_table(
    "Presentations",
    data.frame(name = long, items = seq(1000, by = 1000, length.out = 30)),
    c("Presentation", "Items"), c("text", "items")
  )
  use_export_font()
  wide <- table_layout(table, size = 9, width = 12)
  expect_lte(sum(wide$widths), 12)
  expect_true(all(wide$heights == wide$heights[[1]]))
  # Narrow: the names wrap, so the rows are higher
  narrow <- table_layout(table, size = 9, width = 2.5)
  expect_lte(sum(narrow$widths), 2.5 + 1e-9)
  expect_true(all(narrow$heights > wide$heights))
  # Pages that each fit, every row on one of them, in order
  pages <- table_pages(narrow, height = 2)
  expect_gt(length(pages), 1L)
  expect_identical(unlist(pages), seq_len(30L))
  for (rows in pages) {
    expect_lte(narrow$header + sum(narrow$heights[rows]), 2)
  }
  expect_identical(table_pages(wide, height = 100), list(seq_len(30L)))
  # A table with no rows has no pages
  none <- table
  none$data <- none$data[0, ]
  expect_identical(table_pages(table_layout(none, 9, 12), 5), list())
})

test_that("the methods are cut into pages, a section each, a long one over more", {
  sections <- methods_content(new_report(), NULL, export_time_fixed)
  pages <- methods_pages(sections)
  titles <- vapply(pages, `[[`, "", "title")
  for (section in sections) {
    expect_true(paste("Methods:", section$title) %in% titles)
  }
  expect_identical(titles[[1]], "Methods: This report")
  # Every block once, in order
  blocks <- unlist(lapply(pages, function(page) vapply(page$blocks, `[[`, "", "text")))
  expected <- unlist(lapply(sections, function(section) {
    c(
      section$text, vapply(section$points, `[[`, "", "text"),
      vapply(section$links, `[[`, "", "text")
    )
  }))
  expect_identical(blocks, expected)
  use_export_font()
  expect_false("Methods: Limitations (continued)" %in% titles)
  # A small box: the long sections go on, and say so
  small <- methods_pages(sections, height = 1.5)
  expect_gt(length(small), length(pages))
  expect_true("Methods: Limitations (continued)" %in% vapply(small, `[[`, "", "title"))
})

test_that("the exports' text is measured in the wider of IBM Plex Sans and Arial", {
  # Each string takes the wider font's width, in either weight: capitals are
  # wider in Arial, a drug's name in IBM Plex Sans
  strings <- c("NORTH EAST AND YORKSHIRE", "Levothyroxine sodium 100microgram tablets")
  for (weight in c("normal", "bold")) {
    each <- font_widths(strings, 10, weight)
    expect_named(each, c("IBM Plex Sans", "Arial"))
    expect_identical(
      export_text_width(strings, 10, weight), pmax(each[["IBM Plex Sans"]], each[["Arial"]])
    )
  }
  each <- font_widths(strings, 10)
  expect_gt(each[["Arial"]][[1]], each[["IBM Plex Sans"]][[1]])
  expect_gt(each[["IBM Plex Sans"]][[2]], each[["Arial"]][[2]])
  # Each font's own design widths: digits of 0.556 em in Arial (Liberation
  # Sans has its metrics) and of 0.6 em in IBM Plex Sans
  digits <- font_widths("0123456789", 10)
  expect_equal(digits[["Arial"]] * 72, 55.6, tolerance = 1e-3)
  expect_equal(digits[["IBM Plex Sans"]] * 72, 60, tolerance = 1e-3)
  # Bold IBM Plex Sans is the variable font at its bold weight; measuring it
  # leaves the font at its regular weight, which the charts measure with.
  # The regular widths first, so that they are kept, and only the reset
  # after the bold ones can set the face back
  saved <- chart_state$advances
  withr::defer(chart_state$advances <- saved)
  chart_state$advances <- NULL
  plex <- function(weight) font_widths("Prescribers", 10, weight)[["IBM Plex Sans"]]
  regular <- plex("normal")
  bold <- plex("bold")
  charts <- systemfonts::string_width(
    "Prescribers", family = "IBM Plex Sans", size = 10, res = 7200
  )
  expect_gt(bold, regular * 1.03)
  expect_equal(charts / 7200, regular, tolerance = 1e-3)
  # A line is 1.2 em, as PowerPoint lays out a single-spaced line in any
  # font, IBM Plex Sans included, whose own ascent and descent make 1.3 em
  expect_identical(export_line, 1.2)
  # A paragraph takes as many lines as it wraps to in the font it needs
  # more in
  para <- "levothyroxine sodium tablets for the thyroid"
  each <- font_widths(para, 12)
  between <- mean(c(each[["Arial"]], each[["IBM Plex Sans"]])) + export_room
  expect_identical(text_lines(para, 12, between), 2L)
  expect_identical(text_lines(para, 12, max(unlist(each)) + export_room), 1L)
  # A table's column: its widest value in the wider font, the cell's margins
  # and a point of room; its rows a line of 1.2 em each
  table <- export_table(
    "By region", data.frame(region = c("NORTH EAST AND YORKSHIRE", "LONDON")), "Region", "text"
  )
  layout <- table_layout(table, 10, 12)
  expect_equal(
    layout$widths, max(export_text_width(table$data$region, 10)) + 8 / 72 + export_room
  )
  expect_equal(layout$heights, rep(10 * export_line / 72 + 4 / 72, 2L))
  expect_equal(text_height(c("One line", "Another"), 12), 2 * 12 * export_line / 72 + pptx_inset)
})

test_that("a glyph neither font has is an em wide, and one only Arial has is Arial's width", {
  use_export_font()
  # Chinese, which notes may be written in (report_limits()): Office draws it
  # from a font of its own, an em a character, so that 70 characters at 12
  # points fill a line of a slide's text box, and 71 take two
  han <- intToUtf8(0x4e2d)
  expect_identical(text_lines(strrep(han, 70), 12, pptx_width - 2 * pptx_inset), 1L)
  expect_identical(text_lines(strrep(han, 71), 12, pptx_width - 2 * pptx_inset), 2L)
  # A letter that the app's IBM Plex Sans, a Latin subset, lacks: Arial's
  # width in both, not an em
  barred <- font_widths(intToUtf8(0x142), 10)
  expect_equal(barred[["IBM Plex Sans"]], barred[["Arial"]])
  expect_lt(barred[["Arial"]] * 72, 3)
})

test_that("a table's total is measured in bold, as it is drawn", {
  use_export_font()
  # England's total, the widest value, with three commas, which are wider in
  # bold IBM Plex Sans than in its regular weight
  regions <- c(
    "EAST OF ENGLAND", "LONDON", "MIDLANDS", "NORTH EAST AND YORKSHIRE", "NORTH WEST",
    "SOUTH EAST", "SOUTH WEST"
  )
  values <- c(301234578, 4e8, 3.5e8, 4.5e8, 3e8, 3.5e8, 2.5e8)
  table <- export_table(
    "By region",
    data.frame(
      region = c(regions, "England"), value = c(values, sum(values)),
      share = c(values / sum(values), 1)
    ),
    c("Region", "Quantity", "Share of England"), c("text", "total_quantity", "share")
  )
  table$total <- TRUE
  expect_identical(utils::tail(table_text(table)$value, 1L), "2,401,234,578")
  layout <- table_layout(table, 10, beside$width)
  expect_lte(sum(layout$widths), beside$width + 1e-9)
  expect_gte(
    layout$widths[[2]] - 8 / 72,
    export_text_width("2,401,234,578", 10, "bold") + export_room - 1e-9
  )
  # Its row on one line
  expect_equal(utils::tail(layout$heights, 1L), 10 * export_line / 72 + 4 / 72)
  # A total alone is measured in bold too
  england <- table
  england$data <- england$data[8L, ]
  expect_equal(table_layout(england, 10, beside$width)$heights, 10 * export_line / 72 + 4 / 72)
})

test_that("a table's pages are filled evenly, as few as hold its rows", {
  layout <- list(header = 0.3, heights = rep(0.21, 25L))
  pages <- table_pages(layout, 5.4)
  # 24 rows fit a page: two pages, of 13 and 12 rows rather than 24 and 1
  expect_identical(lengths(pages), c(13L, 12L))
  expect_identical(unlist(pages), seq_len(25L))
  expect_identical(table_pages(layout, 10), list(seq_len(25L)))
  # A row too high for any page still goes on one
  tall <- list(header = 0.3, heights = c(0.2, 6, 0.2))
  expect_identical(table_pages(tall, 5.4), list(1L, 2L, 3L))
})

test_that("a table of 25 rows of a line each fits a slide of its own", {
  use_export_font()
  n <- export_rows
  table <- export_table(
    "Top 25 drugs by items",
    data.frame(
      rank = seq_len(n), presentation = "Atorvastatin 20mg tablets", code = "0212000B0AAABAB",
      kind = "Generic", items = seq(1000, by = 37, length.out = n),
      adq_usage = seq(10.5, by = 1.25, length.out = n),
      nic = seq(1234.5, by = 11.1, length.out = n),
      actual_cost = seq(1100.25, by = 9.9, length.out = n)
    ),
    c(
      "#", "Presentation", "BNF code", "Brand or generic", "Items", "ADQ usage",
      "Net ingredient cost", "Actual cost"
    ),
    c("count", "text", "text", "text", "items", "adq_usage", "nic", "actual_cost")
  )
  # The header and 25 rows of 9-point text, each a line of 1.2 em and its
  # margins: 5.34 inches, within the 5.4 of a slide's table
  layout <- table_layout(table, alone$size, pptx_width)
  expect_equal(layout$heights, rep(9 * export_line / 72 + 4 / 72, n))
  expect_identical(pptx_table_pages(table), list(seq_len(n)))
})

test_that("the PowerPoint file reads back: a title, each item, its tables and the methods", {
  con <- fixture_app()
  spec <- export_spec(con)
  path <- withr::local_tempfile(fileext = ".pptx")
  before <- list.files(tempdir(), all.files = TRUE, no.. = TRUE)
  expect_identical(export_report("pptx", spec, con, path, export_time_fixed), path)
  # Nothing left in tempdir() but the file: officer's unpacked deck goes
  expect_setequal(
    list.files(tempdir(), all.files = TRUE, no.. = TRUE), c(before, basename(path))
  )
  deck <- officer::read_pptx(path)
  expect_equal(officer::slide_size(deck), list(width = 13.333333, height = 7.5), tolerance = 1e-6)
  # One slide for the title, one per item, one per page of a note or a table
  # that has slides of its own, and one per page of the methods
  items <- export_items(spec, plain_fetches(con))
  own <- sum(vapply(items, function(item) {
    frame <- pptx_frame(item)
    tables <- if (is.null(item$table) || pptx_beside(item$table, frame)) {
      0L
    } else {
      length(pptx_table_pages(item$table))
    }
    tables + length(pptx_note_pages(item, frame))
  }, 1L))
  expect_gt(own, 0L)
  methods <- length(methods_pages(methods_content(spec, fetch_window(con), export_time_fixed)))
  expect_identical(length(deck), 1L + length(items) + own + methods)
  expect_on_slides(path)
  texts <- officer::pptx_summary(deck)$text
  expect_true(all(c(
    "Prescription Explorer report", window_period(fetch_window(con)),
    "Exported on 25 November 2026 at 14:05 GMT", "4 items"
  ) %in% texts))
  for (item in items) {
    expect_true(item$title %in% texts, label = item$title)
  }
  # Notes, a paragraph per line
  expect_true(all(c(
    "Note: Costs rose after March.", "See the presentations.", "Note: The regions differ."
  ) %in% texts))
  # The tables' values as the app writes them
  expect_true(all(table_text(items[[1]]$table)$nic %in% texts))
  expect_true("England" %in% texts)
  # The methods, with the attribution exact
  expect_true(paste(
    "NHSBSA Copyright 2021-2026 \u00b7 Contains public sector information licensed under the",
    "Open Government Licence v3.0."
  ) %in% texts)
  expect_true("Methods: Filters" %in% texts)
  # A native chart for each item, each with its words for screen readers
  dir <- withr::local_tempdir()
  utils::unzip(path, exdir = dir)
  charts <- list.files(file.path(dir, "ppt", "charts"), pattern = "[.]xml$")
  expect_length(charts, length(items))
  slides <- unlist(lapply(list.files(file.path(dir, "ppt", "slides"), "[.]xml$", full.names = TRUE),
                          function(file) paste(readLines(file, warn = FALSE), collapse = "")))
  alts <- unlist(regmatches(slides, gregexpr("descr=\"[^\"]*\"", slides)))
  expect_length(alts, length(items))
  expect_true(any(grepl("Net ingredient cost by month", alts, fixed = TRUE)))
  # Straight lines between the months, and charts in English
  chart_xml <- unlist(lapply(file.path(dir, "ppt", "charts", charts), readLines, warn = FALSE))
  expect_true(any(grepl("<c:smooth val=\"0\"/>", chart_xml, fixed = TRUE)))
  expect_false(any(grepl("<c:smooth val=\"1\"/>", chart_xml, fixed = TRUE)))
  expect_false(any(grepl("fr-FR", chart_xml, fixed = TRUE)))
  expect_true(any(grepl("en-GB", chart_xml, fixed = TRUE)))
  # No frame around a chart, and the region's bars with no outline: one of
  # no opacity, as the app draws them
  expect_flat_charts(file.path(dir, "ppt", "charts", charts))
  outline <- unlist(lapply(file.path(dir, "ppt", "charts", charts), function(file) {
    doc <- xml2::read_xml(file)
    alpha <- xml2::xml_find_all(
      doc, "//c:barChart/c:ser/c:spPr/a:ln/a:solidFill/a:srgbClr/a:alpha", xml2::xml_ns(doc)
    )
    xml2::xml_attr(alpha, "val")
  }))
  expect_identical(outline, "0")
  # Every box officer places starts its text at its top, not halfway down
  anchors <- untyped_anchors(path)
  expect_gt(length(anchors), length(items))
  expect_true(all(anchors %in% "t"))
  # Each table's first row marked as its header, for screen readers
  props <- unlist(regmatches(slides, gregexpr("<a:tblPr[^>]*>", slides)))
  expect_gt(length(props), 0L)
  expect_identical(length(props), sum(lengths(regmatches(slides, gregexpr("<a:tbl>", slides)))))
  expect_true(all(grepl("firstRow=\"1\"", props, fixed = TRUE)))
  # Every run in IBM Plex Sans, the theme's font, which the text takes and
  # the tables and charts name by reference; IBM Plex Mono only in the maker's
  # wordmark, for its four scripts
  drawn <- "^(slide[0-9]+|chart[^/]*)[.]xml$"
  fonts <- named_fonts(dir, drawn)
  expect_true(all(fonts %in% c(theme_fonts, "IBM Plex Mono")), label = toString(unique(fonts)))
  expect_identical(sum(fonts == "IBM Plex Mono"), 4L)
  # The exports' colours only, the charts' series in the mark's
  used <- drawn_colours(dir, drawn)
  expect_true(all(used %in% export_colours()), label = toString(setdiff(used, export_colours())))
  marks <- drawn_colours(file.path(dir, "ppt", "charts"), "[.]xml$")
  expect_true(sub("#", "", export_palette()[["mark"]]) %in% marks)
  properties <- officer::doc_properties(deck)
  expect_identical(properties$value[properties$tag == "title"], "Prescription Explorer report")
  expect_identical(properties$value[properties$tag == "creator"], "Prescription Explorer")
  # A format the app does not have
  expect_error(export_report("odt", spec, con, path), class = "prexp_invalid_argument")
})

test_that("the Word file reads back: a title, a heading per item, its chart, note and table", {
  con <- fixture_app()
  spec <- export_spec(con)
  path <- withr::local_tempfile(fileext = ".docx")
  before <- list.files(tempdir(), all.files = TRUE, no.. = TRUE)
  expect_identical(export_report("docx", spec, con, path, export_time_fixed), path)
  # Nothing left in tempdir() but the file
  expect_setequal(
    list.files(tempdir(), all.files = TRUE, no.. = TRUE), c(before, basename(path))
  )
  doc <- officer::read_docx(path)
  parts <- officer::docx_summary(doc)
  style <- function(name) {
    parts$text[which(parts$content_type == "paragraph" & parts$style_name == name)]
  }
  items <- export_items(spec, plain_fetches(con))
  # The title, a heading per item, then the methods as an appendix
  expect_identical(style("Title"), "Prescription Explorer report")
  expect_identical(style("heading 1"), c(vapply(items, `[[`, "", "title"), "Methods"))
  sections <- methods_content(spec, fetch_window(con), export_time_fixed)
  expect_identical(style("heading 2"), vapply(sections, `[[`, "", "title"))
  texts <- parts$text
  expect_true(all(c(
    window_period(fetch_window(con)), "Exported on 25 November 2026 at 14:05 GMT", "4 items"
  ) %in% texts))
  # Notes, a paragraph per line, and each table's values as the app writes them
  expect_true(all(c(
    "Note: Costs rose after March.", "See the presentations.", "Note: The regions differ."
  ) %in% texts))
  expect_true(all(table_text(items[[1]]$table)$nic %in% texts))
  expect_identical(style("Table Caption"), vapply(items, function(item) item$table$caption, ""))
  # The methods, with the attribution exact
  expect_true(paste(
    "NHSBSA Copyright 2021-2026 \u00b7 Contains public sector information licensed under the",
    "Open Government Licence v3.0."
  ) %in% texts)
  # Native charts that can be edited: each with its workbook, its words for
  # screen readers, in English
  dir <- withr::local_tempdir()
  utils::unzip(path, exdir = dir)
  charts <- list.files(file.path(dir, "word", "charts"), pattern = "[.]xml$", full.names = TRUE)
  expect_length(charts, length(items))
  workbooks <- list.files(file.path(dir, "word", "embeddings"), pattern = "[.]xlsx$")
  expect_length(workbooks, length(items))
  chart_xml <- unlist(lapply(charts, readLines, warn = FALSE))
  expect_false(any(grepl("fr-FR", chart_xml, fixed = TRUE)))
  expect_true(any(grepl("<c:smooth val=\"0\"/>", chart_xml, fixed = TRUE)))
  # No frame around a chart, which Word would draw grey
  expect_flat_charts(charts)
  body <- paste(readLines(file.path(dir, "word", "document.xml"), warn = FALSE), collapse = "")
  xml <- xml2::read_xml(file.path(dir, "word", "document.xml"))
  ns <- xml2::xml_ns(xml)
  # Each chart its own words for screen readers, in order
  drawings <- xml2::xml_find_all(xml, "//wp:docPr", ns)
  expect_identical(
    xml2::xml_attr(drawings, "descr"), vapply(items, function(item) item$chart$alt, "")
  )
  # Each table's header row its labels, marked and repeated on a page it runs
  # onto; numbers to the right; a total in the style's last row
  expect_identical(
    length(regmatches(body, gregexpr("<w:tblHeader/>", body))[[1]]), length(items)
  )
  tables <- xml2::xml_find_all(xml, "//w:tbl", ns)
  expect_length(tables, length(items))
  cells <- function(row) xml2::xml_find_all(row, "w:tc", ns)
  for (k in seq_along(items)) {
    table <- items[[k]]$table
    rows <- xml2::xml_find_all(tables[[k]], "w:tr", ns)
    expect_identical(xml2::xml_text(cells(rows[[1]])), table$labels)
    align <- vapply(cells(rows[[2]]), function(cell) {
      xml2::xml_attr(xml2::xml_find_first(cell, ".//w:jc", ns), "val")
    }, "")
    expect_identical(align, ifelse(table$kinds == "text", "left", "right"))
    look <- xml2::xml_find_first(tables[[k]], "w:tblPr/w:tblLook", ns)
    expect_identical(xml2::xml_attr(look, "lastRow"), if (isTRUE(table$total)) "1" else "0")
    # A wide table on landscape pages of its own, a narrow one in its item's
    # portrait page: the next section's properties say which
    section <- xml2::xml_find_first(tables[[k]], paste(
      "following-sibling::w:p[w:pPr/w:sectPr][1]/w:pPr/w:sectPr",
      "| /w:document/w:body/w:sectPr"
    ), ns)
    size <- xml2::xml_find_first(section, "w:pgSz", ns)
    expect_identical(
      xml2::xml_attr(size, "orient"), if (docx_wide(table)) "landscape" else "portrait"
    )
  }
  last <- xml2::xml_find_all(tables[[4]], "w:tr", ns)
  expect_identical(xml2::xml_text(cells(last[[length(last)]])[[1]]), "England")
  # Pages start at each item's heading and the methods', not at break
  # paragraphs; every section starts a page, in the template's margins
  expect_false(grepl("w:type=\"page\"", body, fixed = TRUE))
  types <- xml2::xml_attr(xml2::xml_find_all(xml, "//w:sectPr/w:type", ns), "val")
  expect_true(length(types) > 1L && all(types == "nextPage"))
  margins <- xml2::xml_find_all(xml, "//w:sectPr/w:pgMar", ns)
  expect_true(all(xml2::xml_attr(margins, "left") == "1417"))
  # The methods' points a list, its bullets the style's
  expect_identical(
    sum(parts$style_name == "List Bullet", na.rm = TRUE),
    sum(lengths(lapply(sections, `[[`, "points")))
  )
  # Every run in IBM Plex Sans, the template's font, which the text takes
  # from its styles and the charts name by reference; IBM Plex Mono only in
  # the maker's wordmark, for its four scripts
  drawn <- "^(document|chart[^/]*)[.]xml$"
  fonts <- named_fonts(dir, drawn)
  expect_true(all(fonts %in% c(theme_fonts, "IBM Plex Mono")), label = toString(unique(fonts)))
  expect_identical(sum(fonts == "IBM Plex Mono"), 4L)
  # The exports' colours only: the secondary text's, links' and the mark's
  # among them; the rest of the text the template's
  used <- drawn_colours(dir, drawn)
  expect_true(all(used %in% export_colours()), label = toString(setdiff(used, export_colours())))
  colours <- sub("#", "", export_palette()[c("secondary", "link", "mark")], fixed = TRUE)
  expect_true(all(colours %in% used))
  properties <- officer::doc_properties(doc)
  expect_identical(properties$value[properties$tag == "title"], "Prescription Explorer report")
})

test_that("an item with nothing to show says so, in PowerPoint and Word", {
  con <- fixture_app()
  spec <- export_spec(con)
  away <- list(id = 2147483647L)
  gone <- report_add(new_report(), "drug", utils::modifyList(spec$items[[1]]$params, away))
  gone <- report_add(gone, "practice", utils::modifyList(spec$items[[3]]$params, away))
  messages <- vapply(export_items(gone, plain_fetches(con)), `[[`, "", "message")
  for (format in c("pptx", "docx")) {
    path <- withr::local_tempfile(fileext = paste0(".", format))
    export_report(format, gone, con, path, export_time_fixed)
    texts <- if (format == "pptx") {
      officer::pptx_summary(officer::read_pptx(path))$text
    } else {
      officer::docx_summary(officer::read_docx(path))$text
    }
    expect_true(all(messages %in% texts), label = format)
  }
})

test_that("the templates' themes are the brand's colours and IBM Plex Sans", {
  a <- c(a = "http://schemas.openxmlformats.org/drawingml/2006/main")
  part <- function(file, name) xml2::read_xml(unz(template_file(file), name))
  for (case in list(
    list(file = "report.pptx", theme = "ppt/theme/theme1.xml", name = "Office Theme"),
    list(file = "report.docx", theme = "word/theme/theme1.xml", name = brand_name)
  )) {
    theme <- part(case$file, case$theme)
    # The PowerPoint's keeps its name, which officer names the master after
    expect_identical(xml2::xml_attr(xml2::xml_root(theme), "name"), case$name)
    colours <- vapply(names(export_scheme()), function(slot) {
      node <- xml2::xml_find_first(theme, sprintf("//a:clrScheme/a:%s/a:srgbClr", slot), a)
      xml2::xml_attr(node, "val")
    }, "")
    expect_identical(colours, export_scheme(), label = case$file)
    # IBM Plex Sans, major and minor, with what Office substitutes by
    latin <- xml2::xml_find_all(theme, "//a:majorFont/a:latin | //a:minorFont/a:latin", a)
    expect_identical(xml2::xml_attr(latin, "typeface"), rep("IBM Plex Sans", 2L))
    expect_identical(xml2::xml_attr(latin, "panose"), rep("020B0503050203000203", 2L))
    expect_identical(xml2::xml_attr(latin, "pitchFamily"), rep("34", 2L))
    expect_length(xml2::xml_find_all(theme, "//a:gradFill | //a:outerShdw | //a:sp3d", a), 0L)
  }
  # The layouts the exports choose, on the master named after the theme
  layouts <- officer::layout_summary(officer::read_pptx(template_file("report.pptx")))
  expect_true(all(
    c("Title Slide", "Title Only") %in% layouts$layout[layouts$master == "Office Theme"]
  ))
  # Word's font table declares both fonts, for Word to substitute by
  fonts <- part("report.docx", "word/fontTable.xml")
  w <- xml2::xml_ns(fonts)
  for (font in export_fonts()) {
    entry <- xml2::xml_find_first(fonts, sprintf("//w:font[@w:name = '%s']", font$typeface), w)
    value <- function(name) xml2::xml_attr(xml2::xml_child(entry, name, w), "w:val", w)
    expect_identical(value("w:panose1"), font$panose)
    expect_identical(value("w:family"), font$family)
    expect_identical(value("w:pitch"), font$pitch)
  }
  # Word's text in the text's colour; its tables' rules in the exports', with
  # no bands
  styles <- part("report.docx", "word/styles.xml")
  w <- xml2::xml_ns(styles)
  text <- xml2::xml_find_first(styles, "/w:styles/w:docDefaults/w:rPrDefault/w:rPr/w:color", w)
  expect_identical(xml2::xml_attr(text, "w:val", w), "0B1222")
  table <- xml2::xml_find_first(styles, "//w:style[@w:styleId = 'ReportTable']", w)
  rules <- xml2::xml_find_all(table, ".//w:tblBorders/* | .//w:tcBorders/*", w)
  expect_setequal(xml2::xml_attr(rules, "w:color", w), c("BEBDBC", "0B1222"))
  expect_length(xml2::xml_find_all(table, ".//w:shd", w), 0L)
})

test_that("the cover and the title page carry the maker's wordmark, linked to its site", {
  dir <- withr::local_tempdir()
  # PowerPoint: a text box on the cover, which is the link, so that its text
  # keeps its own colour
  deck <- officer::read_pptx(template_file("report.pptx"))
  deck <- pptx_title(deck, NULL, export_time_fixed, 1L)
  path <- file.path(dir, "cover.pptx")
  print(deck, target = path)
  utils::unzip(path, exdir = file.path(dir, "pptx"))
  slides <- file.path(dir, "pptx", "ppt", "slides")
  slide <- xml2::read_xml(file.path(slides, "slide1.xml"))
  ns <- xml2::xml_ns(slide)
  shape <- xml2::xml_find_first(slide, "//p:sp[p:nvSpPr/p:cNvPr/@name = 'KATONOMETRICA']", ns)
  expect_identical(xml2::xml_text(shape), "KATONOMETRICA")
  link <- xml2::xml_find_first(shape, "p:nvSpPr/p:cNvPr/a:hlinkClick", ns)
  rels <- xml2::xml_ns_strip(xml2::read_xml(file.path(slides, "_rels", "slide1.xml.rels")))
  target <- xml2::xml_find_first(
    rels, sprintf("//Relationship[@Id = '%s']", xml2::xml_attr(link, "r:id", ns))
  )
  expect_identical(xml2::xml_attr(target, "Target"), "https://katonometrica.com")
  # In IBM Plex Mono, declared so that PowerPoint substitutes a font of fixed
  # pitch; in the secondary text's colour, its letters spaced 0.18 em
  run <- xml2::xml_find_first(shape, ".//a:r/a:rPr", ns)
  expect_identical(xml2::xml_attr(run, "spc"), "216")
  colour <- xml2::xml_find_first(run, "a:solidFill/a:srgbClr", ns)
  expect_identical(xml2::xml_attr(colour, "val"), sub("#", "", export_palette()[["secondary"]]))
  latin <- xml2::xml_attrs(xml2::xml_find_first(run, "a:latin", ns))
  expect_identical(
    latin[c("typeface", "panose", "pitchFamily")],
    c(typeface = "IBM Plex Mono", panose = "020B0509050203000203", pitchFamily = "49")
  )
  texts <- officer::pptx_summary(officer::read_pptx(path))$text
  expect_true(all(c("KATONOMETRICA", "Prescription Explorer report", "1 item") %in% texts))
  # Word: a paragraph that is a link, in IBM Plex Mono, which the template's
  # font table declares
  doc <- docx_wordmark(officer::read_docx(template_file("report.docx")))
  path <- file.path(dir, "title.docx")
  print(doc, target = path)
  utils::unzip(path, exdir = file.path(dir, "docx"))
  body <- xml2::read_xml(file.path(dir, "docx", "word", "document.xml"))
  w <- xml2::xml_ns(body)
  link <- xml2::xml_find_first(body, "//w:hyperlink[w:r/w:t = 'KATONOMETRICA']", w)
  rels <- xml2::xml_ns_strip(
    xml2::read_xml(file.path(dir, "docx", "word", "_rels", "document.xml.rels"))
  )
  target <- xml2::xml_find_first(
    rels, sprintf("//Relationship[@Id = '%s']", xml2::xml_attr(link, "r:id", w))
  )
  expect_identical(xml2::xml_attr(target, "Target"), "https://katonometrica.com")
  run <- xml2::xml_find_first(link, "w:r/w:rPr", w)
  property <- function(name, attr) xml2::xml_attr(xml2::xml_child(run, name, w), attr, w)
  expect_identical(property("w:rFonts", "w:ascii"), "IBM Plex Mono")
  expect_identical(property("w:color", "w:val"), sub("#", "", export_palette()[["secondary"]]))
  expect_identical(property("w:spacing", "w:val"), "36")
})

test_that("a Word export that fails leaves nothing in tempdir()", {
  con <- fixture_app()
  spec <- export_spec(con)
  path <- withr::local_tempfile(fileext = ".docx")
  local_mocked_bindings(finish_charts = function(dir) stop("injected failure"))
  before <- list.files(tempdir(), all.files = TRUE, no.. = TRUE)
  expect_error(export_report("docx", spec, con, path, export_time_fixed), "injected failure")
  expect_setequal(list.files(tempdir(), all.files = TRUE, no.. = TRUE), before)
})

test_that("the Excel workbook reads back: a sheet per item with its tables and chart", {
  con <- fixture_app()
  spec <- export_spec(con)
  path <- withr::local_tempfile(fileext = ".xlsx")
  before <- list.files(tempdir(), all.files = TRUE, no.. = TRUE)
  expect_identical(export_report("xlsx", spec, con, path, export_time_fixed), path)
  expect_setequal(
    list.files(tempdir(), all.files = TRUE, no.. = TRUE), c(before, basename(path))
  )
  items <- export_items(spec, plain_fetches(con))
  sheets <- openxlsx2::wb_get_sheet_names(openxlsx2::wb_load(path))
  # A first sheet, a sheet per item, and the methods last
  expect_identical(unname(sheets), c("Report", xlsx_sheet_names(items), "Methods"))
  cover <- openxlsx2::wb_to_df(path, sheet = "Report", col_names = FALSE)
  expect_identical(cover[[1]][1:4], c(
    "Prescription Explorer report", window_period(fetch_window(con)),
    "Exported on 25 November 2026 at 14:05 GMT", "4 items"
  ))
  expect_true(all(vapply(items, `[[`, "", "title") %in% cover[[2]]))
  # Each item's sheet: its title and note on top, its table's values as
  # numbers equal to the fetch, and the chart's data
  first <- openxlsx2::wb_to_df(path, sheet = 2, col_names = FALSE)
  expect_identical(first[[1]][1], items[[1]]$title)
  expect_true(all(c("Note: Costs rose after March.", "See the presentations.") %in% first[[1]]))
  table <- items[[1]]$table
  header <- which(first[[1]] == "Presentation")
  all <- openxlsx2::wb_to_df(path, sheet = 2, start_row = header)
  got <- all[seq_len(nrow(table$data)), ]
  expect_identical(got[["BNF code"]], table$data$code)
  expect_equal(got[["Net ingredient cost"]], table$data$nic)
  expect_equal(got[["Items"]], table$data$items)
  # The chart's data beside the table, read by position: its value column has
  # the table's own name for the measure
  month <- which(names(all) == "Month")
  n <- length(items[[1]]$chart$labels)
  expect_identical(all[[month]][seq_len(n)], items[[1]]$chart$labels)
  expect_equal(all[[month + 1L]][seq_len(n)], items[[1]]$chart$values)
  # The methods, with the attribution exact
  methods <- openxlsx2::wb_to_df(path, sheet = "Methods", col_names = FALSE)[[1]]
  expect_true(paste(
    "NHSBSA Copyright 2021-2026 \u00b7 Contains public sector information licensed under the",
    "Open Government Licence v3.0."
  ) %in% methods)
  # The file: a native chart for each item; no macros, pivots or formulas
  dir <- withr::local_tempdir()
  utils::unzip(path, exdir = dir)
  parts <- list.files(dir, recursive = TRUE)
  expect_length(grep("^xl/charts/chart[0-9]+[.]xml$", parts), length(items))
  read_parts <- function(pattern) {
    unlist(lapply(file.path(dir, grep(pattern, parts, value = TRUE)), readLines, warn = FALSE))
  }
  expect_false(any(grepl("vbaProject|pivot", parts)))
  sheet_xml <- read_parts("^xl/worksheets/sheet[0-9]+[.]xml$")
  expect_false(any(grepl("<f>", sheet_xml, fixed = TRUE)))
  # The charts in British English, without PowerPoint's link to a workbook;
  # every reference to a sheet quoted as Excel quotes it, and to a sheet there
  chart_xml <- read_parts("^xl/charts/chart[0-9]+[.]xml$")
  expect_false(any(grepl("fr-FR", chart_xml, fixed = TRUE)))
  expect_true(any(grepl("en-GB", chart_xml, fixed = TRUE)))
  expect_false(any(grepl("c:externalData", chart_xml, fixed = TRUE)))
  # Prefixed parts: their own namespaces, which xml_ns_strip() keeps
  prefixed <- function(file, xpath) {
    doc <- xml2::read_xml(file)
    xml2::xml_find_all(doc, xpath, xml2::xml_ns(doc))
  }
  charts <- file.path(dir, grep("^xl/charts/chart[0-9]+[.]xml$", parts, value = TRUE))
  # No frame around a chart, which Excel would draw grey
  expect_flat_charts(charts)
  refs <- unlist(lapply(charts, function(file) xml2::xml_text(prefixed(file, "//c:f"))))
  expect_gt(length(refs), 0L)
  quoted <- "^'((?:[^']|'')+)'![$][A-Z]+[$][0-9]+(:[$][A-Z]+[$][0-9]+)?$"
  expect_true(all(grepl(quoted, refs, perl = TRUE)))
  named <- gsub("''", "'", sub(quoted, "\\1", refs, perl = TRUE), fixed = TRUE)
  expect_true(all(named %in% sheets))
  # Every relationship a part names is in its .rels, or Excel repairs the file
  for (part in grep("[.]xml$", parts, value = TRUE)) {
    xml <- paste(readLines(file.path(dir, part), warn = FALSE), collapse = "")
    ids <- gsub("^r:id=\"|\"$", "", unlist(regmatches(xml, gregexpr("r:id=\"[^\"]+\"", xml))))
    rels <- file.path(dir, dirname(part), "_rels", paste0(basename(part), ".rels"))
    known <- if (file.exists(rels)) {
      rel <- paste(readLines(rels, warn = FALSE), collapse = "")
      gsub("^Id=\"|\"$", "", unlist(regmatches(rel, gregexpr("Id=\"[^\"]+\"", rel))))
    }
    expect_identical(setdiff(ids, known), character(), label = paste(part, "names unknown rels"))
  }
  # Each item's sheet: its title in A1; its tables' header row frozen; each
  # value in the format the app writes it in, text in none; its chart's own
  # words for screen readers
  for (i in seq_along(items)) {
    item <- items[[i]]
    sheet <- xlsx_part(dir, "worksheets", paste0("sheet", i + 1L, ".xml"))
    cells <- openxlsx2::wb_to_df(path, sheet = i + 1L, col_names = FALSE)
    expect_identical(cells[[1]][1], item$title)
    header <- which(cells[[1]] == item$table$labels[[1]])[1]
    pane <- xml2::xml_find_first(sheet, "//sheetView/pane")
    expect_identical(xml2::xml_attr(pane, "state"), "frozen")
    expect_identical(xml2::xml_attr(pane, "topLeftCell"), paste0("A", header + 1L))
    formats <- xlsx_cell_formats(dir, sheet)
    rows <- header + seq_len(nrow(item$table$data))
    for (j in seq_along(item$table$kinds)) {
      col <- openxlsx2::int2col(j)
      want <- xlsx_numfmt(item$table$kinds[[j]], item$table$data[[j]])
      want[is.na(want)] <- "General"
      got <- unname(formats[paste0(col, rows)])
      # A blank cell has no format to check
      blank <- is.na(item$table$data[[j]])
      expect_identical(got[!blank], want[!blank], label = paste("sheet", i + 1L, "column", col))
    }
    rels <- xlsx_part(dir, "worksheets", "_rels", paste0("sheet", i + 1L, ".xml.rels"))
    drawing <- xml2::xml_attr(
      xml2::xml_find_first(rels, "//Relationship[contains(@Type, '/drawing')]"), "Target"
    )
    frame <- prefixed(
      file.path(dir, "xl", "drawings", basename(drawing)),
      "//xdr:graphicFrame/xdr:nvGraphicFramePr/xdr:cNvPr"
    )
    expect_identical(xml2::xml_attr(frame, "descr"), item$chart$alt)
  }
  # The methods' links, hyperlinks to their pages
  methods_rels <- paste(readLines(file.path(
    dir, "xl", "worksheets", "_rels", paste0("sheet", length(sheets), ".xml.rels")
  ), warn = FALSE), collapse = "")
  for (url in c(data_attribution()$source_url, data_attribution()$licence_url)) {
    expect_true(grepl(url, methods_rels, fixed = TRUE), label = url)
  }
  # IBM Plex Sans throughout: every font of the styles, the base font of the
  # Swiss family, by which Excel substitutes; the theme's, declared as the
  # templates'; the charts' by reference
  styles <- xlsx_part(dir, "styles.xml")
  fonts <- xml2::xml_attr(xml2::xml_find_all(styles, "//fonts/font/name"), "val")
  expect_identical(unique(fonts), export_font)
  base <- xml2::xml_find_first(styles, "//fonts/font/family")
  expect_identical(xml2::xml_attr(base, "val"), "2")
  theme <- xml2::read_xml(file.path(dir, "xl", "theme", "theme1.xml"))
  a <- c(a = "http://schemas.openxmlformats.org/drawingml/2006/main")
  latin <- xml2::xml_find_all(theme, "//a:majorFont/a:latin | //a:minorFont/a:latin", a)
  expect_identical(xml2::xml_attr(latin, "typeface"), rep(export_font, 2L))
  expect_identical(xml2::xml_attr(latin, "panose"), rep(export_fonts()$sans$panose, 2L))
  colours <- vapply(names(export_scheme()), function(slot) {
    xml2::xml_attr(xml2::xml_find_first(theme, sprintf("//a:%s/a:srgbClr", slot), a), "val")
  }, "")
  expect_identical(colours, export_scheme())
  expect_true(all(named_fonts(dir, "^chart[0-9]+[.]xml$") %in% theme_fonts))
  # Its tables in Excel's Light 1, whose rules take the theme's text colour,
  # with no bands, as the other formats' tables
  tables <- list.files(file.path(dir, "xl", "tables"), "[.]xml$", full.names = TRUE)
  styles_used <- vapply(tables, function(file) {
    info <- xml2::xml_find_first(xml2::xml_ns_strip(xml2::read_xml(file)), "//tableStyleInfo")
    paste(xml2::xml_attr(info, "name"), xml2::xml_attr(info, "showRowStripes"))
  }, "")
  expect_identical(unique(unname(styles_used)), "TableStyleLight1 0")
  # The exports' colours only, the links' among them
  used <- drawn_colours(dir, "^(styles|chart[0-9]+)[.]xml$")
  expect_true(all(used %in% export_colours()), label = toString(setdiff(used, export_colours())))
  expect_true(sub("#", "", export_palette()[["link"]]) %in% used)
})

test_that("Excel shows quantity and ADQ usage as the app writes them", {
  x <- c(0.536, 0.008, 0, NA, 25936, 1.624, 97.72)
  expect_identical(
    xlsx_numfmt("adq_usage", x),
    c("#,##0.000", "#,##0.000", "#,##0", NA, "#,##0", "#,##0.00", "#,##0.0")
  )
  expect_identical(xlsx_numfmt("total_quantity", c(28, 2.5)), c("#,##0", "#,##0.0"))
  expect_identical(xlsx_numfmt("nic", c(1, NA)), rep("\u00a3#,##0.00", 2L))
  expect_identical(xlsx_numfmt("text", c("a", "b")), rep(NA_character_, 2L))
})

test_that("a long note goes under the tables, so that the frozen rows leave room", {
  con <- fixture_app()
  spec <- export_spec(con)
  lines <- paste("Point", seq_len(14))
  long <- report_set_note(spec, 1L, paste(lines, collapse = "\n"))
  short <- report_set_note(spec, 1L, "_x0041_ here")
  for (case in list(list(spec = long, moved = TRUE), list(spec = short, moved = FALSE))) {
    path <- withr::local_tempfile(fileext = ".xlsx")
    export_report("xlsx", case$spec, con, path, export_time_fixed)
    cells <- openxlsx2::wb_to_df(path, sheet = 2, col_names = FALSE)[[1]]
    dir <- withr::local_tempdir()
    utils::unzip(path, exdir = dir)
    pane <- xml2::xml_find_first(xlsx_part(dir, "worksheets", "sheet2.xml"), "//sheetView/pane")
    frozen <- as.integer(sub("^[A-Z]+", "", xml2::xml_attr(pane, "topLeftCell"))) - 1L
    expect_lte(frozen, xlsx_frozen_rows)
    if (case$moved) {
      expect_identical(cells[[3]], "The note is under the table and chart.")
      expect_gt(which(cells == "Point 14"), frozen)
    } else {
      # Excel reads "_xHHHH_" as a character: the note's underscore is kept
      xml <- paste(readLines(file.path(dir, "xl", "worksheets", "sheet2.xml"), warn = FALSE),
                   collapse = "")
      expect_true(grepl("Note: _x005F_x0041_ here", xml, fixed = TRUE))
    }
  }
})

test_that("an item's sheet name is short, unique and one Excel takes", {
  items <- list(
    list(title = "Atorvastatin \u00b7 items \u00b7 Jan 2026 to Sep 2026"),
    list(title = paste(
      "'A/B: very [long] name? with * marks and more words than fit", "\u00b7 items"
    )),
    list(title = "Atorvastatin \u00b7 items \u00b7 Jan 2026 to Sep 2026"),
    list(title = "ST JAMES' SURGERY \u00b7 items \u00b7 Jan 2026 to Sep 2026")
  )
  names <- xlsx_sheet_names(items)
  # A straight apostrophe as a typographic one, which a chart's reference
  # to the sheet needs no doubling for
  expect_identical(names[[4]], "4 ST JAMES\u2019 SURGERY")
  expect_false(any(grepl("'", names, fixed = TRUE)))
  expect_identical(names[[1]], "1 Atorvastatin")
  expect_identical(names[[3]], "3 Atorvastatin")
  expect_lte(nchar(names[[2]]), 31L)
  expect_false(grepl("[\\[\\]:*?/\\\\]", names[[2]], perl = TRUE))
  expect_false(any(duplicated(names)))
  expect_identical(xml_escape("a < b & \"c\" > d"), "a &lt; b &amp; &quot;c&quot; &gt; d")
})

test_that("a long table goes on slides of its own, continued as needed", {
  con <- fixture_app()
  practice <- fetch_subject(con, "practice", "N81655")
  spec <- report_add(new_report(), "practice", list(
    id = practice$id, code = practice$code, label = practice$name, months = export_months,
    measure = "nic"
  ))
  items <- export_items(spec, plain_fetches(con))
  table <- items[[1]]$table
  expect_false(pptx_beside(table, pptx_frame(items[[1]])))
  # Narrow pages: more than one
  local_mocked_bindings(pptx_table_pages = function(table) {
    table_pages(table_layout(table, 9, 12), 1.2)
  })
  pages <- pptx_table_pages(table)
  expect_gt(length(pages), 1L)
  path <- withr::local_tempfile(fileext = ".pptx")
  export_pptx(spec, con, path, export_time_fixed)
  texts <- officer::pptx_summary(officer::read_pptx(path))$text
  title <- paste("Table:", items[[1]]$title)
  expect_true(title %in% texts)
  expect_true(paste(title, "(continued)") %in% texts)
  expect_on_slides(path)
})

# An item as export_items() gives it, made here
made_item <- function(...) {
  item <- list(
    title = "Atorvastatin \u00b7 items \u00b7 Jan 2026 to Sep 2026",
    summary = "Drug view \u00b7 chemical substance 0212000B0", profile = NULL, note = "",
    clamped = FALSE, measure = "items", footnote = NULL, message = NULL, table = NULL,
    chart = list(
      type = "line", labels = c("Jan 2026", "Feb 2026", "Mar 2026"), values = c(3, 5, 4),
      alt = "Items by month"
    )
  )
  utils::modifyList(item, list(...))
}

# A deck of these items' slides, as export_pptx() writes them
made_deck <- function(items) {
  deck <- officer::read_pptx(template_file("report.pptx"))
  for (item in items) {
    frame <- pptx_frame(item)
    deck <- pptx_item(deck, item, frame)
    pages <- pptx_note_pages(item, frame)
    for (k in seq_along(pages)) {
      deck <- pptx_note(deck, item, item_note_lines(item)[pages[[k]]], k)
    }
  }
  path <- withr::local_tempfile(fileext = ".pptx", .local_envir = parent.frame())
  print(deck, target = path)
  path
}

test_that("a slide holds its text: a long note goes on, a long address moves the chart", {
  use_export_font()
  points <- paste(sprintf("- point %d: costs rose", 1:15), collapse = "\n")
  short <- made_item(note = "Costs rose.", clamped = TRUE)
  long <- made_item(note = points, clamped = TRUE)
  many <- made_item(note = paste(rep("a", 200), collapse = "\n"))
  where <- made_item(profile = paste(rep("A very long address, Somewhere", 8), collapse = ", "))
  # A short note stays under the chart; a long one goes on slides of its own
  expect_false(pptx_frame(short)$apart)
  expect_true(pptx_frame(long)$apart)
  expect_length(pptx_note_pages(long, pptx_frame(long)), 1L)
  expect_gt(length(pptx_note_pages(many, pptx_frame(many))), 1L)
  # A long address takes more lines, and the chart starts below them
  expect_gt(pptx_frame(where)$chart$top, pptx_frame(short)$chart$top)
  frame <- pptx_frame(where)
  expect_gte(frame$chart$top, frame$summary$top + frame$summary$height)
  path <- made_deck(list(short, long, many, where))
  expect_on_slides(path)
  # The items' text and the notes' slides start at their boxes' top
  anchors <- untyped_anchors(path)
  expect_gt(length(anchors), 0L)
  expect_true(all(anchors %in% "t"))
  texts <- officer::pptx_summary(officer::read_pptx(path))$text
  expect_true(all(item_note_lines(long) %in% texts))
  expect_true(paste("Note:", long$title) %in% texts)
  expect_true(paste("Note:", many$title, "(continued)") %in% texts)
  expect_true("The note is on the next slide." %in% texts)
  # Each box holds its text as measured
  for (item in list(short, long, where)) {
    frame <- pptx_frame(item)
    expect_gte(frame$chart$height, 3)
  }
})

test_that("a short table with no chart takes the chart's place", {
  use_export_font()
  table <- export_table(
    "By region",
    data.frame(
      region = c("LONDON", "No region: unidentified prescribers", "England"),
      value = c(0, 4, 4), share = c(0, 1, 1)
    ),
    c("Region", "Items", "Share of England"), c("text", "items", "share")
  )
  table$total <- TRUE
  item <- made_item(chart = NULL, table = table)
  expect_true(pptx_beside(table, pptx_frame(item)))
  shapes <- expect_on_slides(made_deck(list(item)))
  expect_equal(shapes$left[shapes$table], pptx_left, tolerance = 1e-3)
})

test_that("an export's chart has the view's axis: whole items, labels that differ", {
  expect_identical(export_axis(c(0, 1, 1, 0), "items"), list(unit = "1", format = "#,##0"))
  expect_identical(
    export_axis(c(0, 2, 1.5), "nic"), list(unit = "0.5", format = "\u00a3#,##0.00")
  )
  expect_identical(
    export_axis(c(0.6, NA), "adq_usage"), list(unit = "0.1", format = "#,##0.0")
  )
  expect_identical(export_axis(c(1234567, 2), "items")$unit, "300000")
  expect_null(export_axis(c(NA, NA), "adq_usage")$unit)
  # Bars across: the values' axis title reads across; a line's stays upright
  bars <- list(type = "bar", labels = c("A", "B"), values = c(1, 2))
  expect_identical(export_chart(bars, "items")$theme$title_y_rot, 0)
  line <- list(type = "line", labels = c("A", "B"), values = c(1, 2))
  expect_false(identical(export_chart(line, "items")$theme$title_y_rot, 0))
  # Bars filled in the mark's colour with no outline, as the app's; the line
  # in the mark's colour
  mark <- export_palette()[["mark"]]
  settings <- export_chart(bars, "items")$series_settings
  expect_identical(unname(settings$fill), mark)
  expect_identical(unname(settings$colour), "transparent")
  expect_identical(unname(export_chart(line, "items")$series_settings$colour), mark)
})

test_that("a drug's regions are charted in the view's order and said as the view says them", {
  con <- fixture_app()
  regions <- fetch_regions(con)
  # Two regions that prescribed it, the others at 0, tied
  rows <- tibble::tibble(
    region_code = regions$region_code[c(2, 5)], region_name = regions$region_name[c(2, 5)],
    measure = "items", value = c(5, 1)
  )
  fetches <- list(region_comparison = function(...) rows, regions = function() regions)
  params <- list(
    level = "chemical", id = 1L, code = "0212000B0", label = "Atorvastatin",
    months = export_months, measure = "items"
  )
  item <- region_export(params, fetches)
  filled <- fill_regions(rows, regions)
  screen <- chart_bars(filled[in_region(filled), ])
  # The view's bars, from the bottom up
  codes <- filled$region_code[match(item$chart$labels, filled$region_name)]
  expect_identical(codes, levels(screen$data$id))
  # The table beside it, from the top down
  shown <- item$table$data$region[item$table$data$region != "England"]
  expect_identical(rev(item$chart$labels), shown)
  expect_identical(item$chart$alt, ggplot2::get_alt_text(screen))
})

test_that("the runner exports here without workers, and on a worker with them", {
  con <- fixture_app()
  spec <- export_spec(con)
  run <- export_runner(con)
  # No workers: here, as a promise of the file's path
  path <- withr::local_tempfile(fileext = ".pptx")
  got <- NULL
  promises::then(run("pptx", spec, path, export_time_fixed), function(value) got <<- value)
  for (i in 1:50) {
    if (!is.null(got)) break
    later::run_now(0.05)
  }
  expect_identical(got, path)
  expect_true(file.exists(path))
  # A failure rejects the promise
  failure <- NULL
  promises::catch(run("odt", spec, path, export_time_fixed), function(e) failure <<- e)
  for (i in 1:50) {
    if (!is.null(failure)) break
    later::run_now(0.05)
  }
  expect_s3_class(failure, "prexp_invalid_argument")
  # With a worker: a mirai, on the worker's own connection, to a file here
  start_workers(1L, setup = worker_setup(), dbname = local_fixture_db())
  withr::defer(stop_workers())
  path <- withr::local_tempfile(fileext = ".pptx")
  promise <- run("pptx", spec, path, export_time_fixed)
  expect_s3_class(promise, "mirai")
  got <- NULL
  promises::then(promise, function(value) got <<- value)
  deadline <- Sys.time() + 60
  while (is.null(got) && Sys.time() < deadline) {
    later::run_now(0.05)
  }
  expect_identical(got, path)
  expect_gt(length(officer::read_pptx(path)), 5L)
})

test_that("an export that no worker takes ends as an error, not a wait", {
  # Daemons asked for, but none connected
  mirai::daemons(url = mirai::local_url())
  withr::defer(mirai::daemons(0L))
  failure <- NULL
  promises::catch(
    export_runner(NULL, timeout = 0.5)("pptx", new_report(), tempfile(), Sys.time()),
    function(e) failure <<- e
  )
  deadline <- Sys.time() + 10
  while (is.null(failure) && Sys.time() < deadline) {
    later::run_now(0.05)
  }
  expect_match(conditionMessage(failure), "Timed out", fixed = TRUE)
})

test_that("a worker exports on its own connection", {
  dbname <- local_fixture_db()
  app <- local_test_db("app", dbname = dbname)
  spec <- export_spec(app)
  worker_connect(dbname)
  withr::defer({
    DBI::dbDisconnect(worker$con)
    worker$con <- NULL
  })
  path <- withr::local_tempfile(fileext = ".pptx")
  expect_identical(worker_export("pptx", spec, path, export_time_fixed), path)
  expect_gt(length(officer::read_pptx(path)), 5L)
})

test_that("a prepared file is named after the app and the day in the UK", {
  expect_identical(
    export_filename("pptx", as.POSIXct("2026-06-30 23:30", tz = "UTC")),
    "prescription-explorer-report-2026-07-01.pptx"
  )
  expect_identical(export_formats()$format, c("pptx", "docx", "xlsx"))
  expect_identical(
    export_filename("docx", as.POSIXct("2026-01-15 12:00", tz = "UTC")),
    "prescription-explorer-report-2026-01-15.docx"
  )
})

# The Report tab with a runner, and what it says
export_item_params <- list(
  level = "chemical", id = 57L, code = "0212000B0", label = "Atorvastatin",
  months = export_months, measure = "nic"
)

wait_status <- function(session, output, while_text) {
  for (i in 1:100) {
    later::run_now(0.02)
    session$flushReact()
    if (!identical(output$export_status, while_text)) break
  }
  output$export_status
}

test_that("Prepare runs the export as a task, and Download serves its file", {
  said <- character()
  local_mocked_bindings(announce = function(session, text) said <<- c(said, text))
  asked <- list()
  run <- function(format, spec, path, exported) {
    asked[[length(asked) + 1L]] <<- list(format = format, spec = spec, path = path)
    writeLines("the file", path)
    promises::promise_resolve(path)
  }
  report <- shiny::reactiveVal(new_report())
  shiny::testServer(mod_report_server, args = list(report = report, run = run), {
    session$flushReact()
    expect_identical(output$export_status, "Pin a view to export the report.")
    # A click with nothing pinned does nothing
    session$setInputs(prepare = 1L)
    expect_length(asked, 0L)
    report(report_add(new_report(), "drug", export_item_params))
    session$setInputs(format = "pptx", prepare = 2L)
    expect_length(asked, 1L)
    expect_identical(asked[[1]]$format, "pptx")
    expect_identical(asked[[1]]$spec, report())
    expect_identical(said[[1]], "Preparing the PowerPoint file of the report's 1 item.")
    expect_match(
      wait_status(session, output, "Preparing the PowerPoint file\u2026"),
      "^Ready: prepared at [0-9]{2}:[0-9]{2} (GMT|BST)[.]$"
    )
    expect_identical(
      said[[2]], "The PowerPoint file is ready: the Download button is next to Prepare."
    )
    expect_match(output$download_ui$html, "Download PowerPoint", fixed = TRUE)
    expect_identical(readLines(output$download), "the file")
    # A note added since: that file is not the report's any more
    report(report_set_note(report(), 1L, "Added later."))
    session$flushReact()
    expect_null(output$download_ui)
    expect_match(output$export_status, "has changed since it was prepared", fixed = TRUE)
    # Prepared again: the earlier file goes
    first <- asked[[1]]$path
    session$setInputs(prepare = 3L)
    expect_match(wait_status(session, output, "Preparing the PowerPoint file\u2026"), "^Ready: ")
    expect_false(file.exists(first))
    expect_true(file.exists(asked[[2]]$path))
    # Another format: the PowerPoint file is not offered for it, and is said
    # to be still the report's; Word is made
    session$setInputs(format = "docx")
    expect_null(output$download_ui)
    expect_identical(output$export_status, paste(
      "The PowerPoint file is prepared: choose PowerPoint to download it, or Prepare to make",
      "the Word file."
    ))
    session$setInputs(prepare = 4L)
    expect_identical(asked[[3]]$format, "docx")
    expect_match(asked[[3]]$path, "[.]docx$")
    expect_match(wait_status(session, output, "Preparing the Word file\u2026"), "^Ready: ")
    expect_match(output$download_ui$html, "Download Word", fixed = TRUE)
  })
})

test_that("a file prepared for a report changed since is not said to be ready", {
  said <- character()
  local_mocked_bindings(announce = function(session, text) said <<- c(said, text))
  finish <- NULL
  run <- function(format, spec, path, exported) {
    writeLines("the file", path)
    promises::promise(function(resolve, reject) finish <<- function() resolve(path))
  }
  report <- shiny::reactiveVal(report_add(new_report(), "drug", export_item_params))
  shiny::testServer(mod_report_server, args = list(report = report, run = run), {
    session$flushReact()
    session$setInputs(prepare = 1L)
    # A note saved while the file is prepared
    session$setInputs(note = list(id = 1L, note = "Added while preparing."))
    finish()
    expect_match(
      wait_status(session, output, "Preparing the PowerPoint file\u2026"),
      "has changed since it was prepared", fixed = TRUE
    )
    expect_null(output$download_ui)
    expect_identical(said[[2]], paste(
      "The PowerPoint file was prepared, but the report has changed since: prepare it",
      "again to download it."
    ))
  })
  # Only the status region says what Prepare did
  ui <- htmltools::tagQuery(mod_report_ui("report"))
  for (id in c("report-prepare", "report-download_ui")) {
    expect_identical(ui$find(paste0("#", id))$selectedTags()[[1]]$attribs[["aria-live"]], "off")
  }
})

test_that("a file an export finishes after its session ended goes too", {
  local_mocked_bindings(announce = function(session, text) NULL)
  written <- NULL
  run <- function(format, spec, path, exported) {
    promises::promise(function(resolve, reject) {
      later::later(function() {
        writeLines("the file", path)
        written <<- path
        resolve(path)
      }, 0.2)
    })
  }
  report <- shiny::reactiveVal(report_add(new_report(), "drug", export_item_params))
  shiny::testServer(mod_report_server, args = list(report = report, run = run), {
    session$flushReact()
    session$setInputs(prepare = 1L)
  })
  # testServer ended the session as it returned, while the export ran
  for (i in 1:100) {
    later::run_now(0.02)
    if (!is.null(written) && !file.exists(written)) break
  }
  for (i in 1:10) {
    later::run_now(0.02)
  }
  expect_false(is.null(written))
  expect_false(file.exists(written))
})

test_that("a link's value for the export's format cannot stop the page from opening", {
  # Shiny restores a value the app never writes, as radioButtons() would take it
  for (value in c("[\"pptx\",\"docx\"]", "{\"a\":1}", "\"odt\"", "null")) {
    search <- paste0("?_inputs_&report-format=", utils::URLencode(value, reserved = TRUE))
    page <- NULL
    expect_no_error(
      page <- shiny:::withRestoreContext(shiny:::RestoreContext$new(search), app_ui(NULL))
    )
    html <- htmltools::renderTags(page)$html
    expect_match(html, "value=\"pptx\" checked=\"checked\"", fixed = TRUE)
  }
  # The markup is radioButtons()', which the browser's binding reads
  choices <- c(`PowerPoint (.pptx)` = "pptx", `Word (.docx)` = "docx")
  expect_identical(
    as.character(format_radio("report-format", "Export as", choices)),
    as.character(shiny::radioButtons("report-format", "Export as", choices, inline = TRUE))
  )
})

test_that("a file prepared in a format no longer chosen is said to be ready in it", {
  said <- character()
  local_mocked_bindings(announce = function(session, text) said <<- c(said, text))
  finish <- NULL
  run <- function(format, spec, path, exported) {
    writeLines("the file", path)
    promises::promise(function(resolve, reject) finish <<- function() resolve(path))
  }
  report <- shiny::reactiveVal(report_add(new_report(), "drug", export_item_params))
  shiny::testServer(mod_report_server, args = list(report = report, run = run), {
    session$flushReact()
    session$setInputs(format = "docx", prepare = 1L)
    # PowerPoint chosen while the Word file is prepared
    session$setInputs(format = "pptx")
    finish()
    expect_identical(wait_status(session, output, "Preparing the Word file\u2026"), paste(
      "The Word file is prepared: choose Word to download it, or Prepare to make the",
      "PowerPoint file."
    ))
    expect_null(output$download_ui)
    expect_identical(said[[2]], "The Word file is ready: choose Word to download it.")
    session$setInputs(format = "docx")
    expect_match(output$export_status, "^Ready: ")
    expect_match(output$download_ui$html, "Download Word", fixed = TRUE)
  })
})

test_that("an export that fails is said and logged, not swallowed", {
  said <- character()
  local_mocked_bindings(announce = function(session, text) said <<- c(said, text))
  toasts <- character()
  local_mocked_bindings(
    showNotification = function(ui, ...) toasts <<- c(toasts, list(...)$type),
    .package = "shiny"
  )
  run <- function(format, spec, path, exported) {
    promises::promise_reject(simpleError("the disk is full"))
  }
  report <- shiny::reactiveVal(report_add(new_report(), "drug", export_item_params))
  shiny::testServer(mod_report_server, args = list(report = report, run = run), {
    session$flushReact()
    # Shiny's ExtendedTask warns as well when its task fails
    expect_warning(
      expect_message(
        {
          session$setInputs(prepare = 1L)
          status <- wait_status(session, output, "Preparing the PowerPoint file\u2026")
        },
        "An export failed: the disk is full"
      ),
      "invoking the ExtendedTask"
    )
    expect_identical(status, "The report could not be exported. Try again.")
    expect_identical(toasts, "error")
    expect_match(said[[2]], "could not be exported", fixed = TRUE)
    expect_null(output$download_ui)
  })
})

test_that("Prepare is off with nothing pinned or no runner, and answers clicks only", {
  states <- list()
  local_mocked_bindings(
    updateActionButton = function(session, ...) {
      args <- list(...)
      states[[length(states) + 1L]] <<- args$disabled
    },
    .package = "shiny"
  )
  asked <- 0L
  run <- function(...) {
    asked <<- asked + 1L
    promises::promise_resolve(NULL)
  }
  report <- shiny::reactiveVal(report_add(new_report(), "drug", export_item_params))
  shiny::testServer(mod_report_server, args = list(report = report, run = run), {
    # The value a link's `_inputs_` gives the button, sent as the page opens
    session$setInputs(prepare = 1L)
    expect_identical(asked, 0L)
    expect_false(utils::tail(states, 1L)[[1]])
    report(new_report())
    session$flushReact()
    expect_true(utils::tail(states, 1L)[[1]])
  })
  states <- list()
  shiny::testServer(mod_report_server, args = list(report = report), {
    session$flushReact()
    expect_true(utils::tail(states, 1L)[[1]])
  })
  ui <- htmltools::renderTags(mod_report_ui("report"))$html
  expect_match(ui, "id=\"report-prepare\"", fixed = TRUE)
  expect_match(ui, "PowerPoint (.pptx)", fixed = TRUE)
})
