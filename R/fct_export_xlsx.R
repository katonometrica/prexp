# The Excel export (P5-07; spec section 5.5), built in R with openxlsx2, with
# no template: a first sheet that says what the report is and lists its
# items; a sheet per item, with its title, its view and subject and its note
# in its first rows (a long note under its tables, as the frozen rows must
# leave the screen room), then its table as an Excel table under a frozen
# header row, and its months or regions beside it as a small table with a
# native chart under it; and a Methods sheet last. Numbers stay numbers, formatted
# as the app writes them. No macros, no pivots and no formulas, so that it
# opens without a security warning. Its base font is IBM Plex Sans, and its
# theme the templates', in the brand's colours (xlsx_brand()).
#
# The workbook is built with its own methods, which change it in place:
# openxlsx2's wb_*() functions copy the whole workbook at every call, which
# made a report of fifteen items take seconds.

#' Writes a report as an Excel workbook
#'
#' @inheritParams export_pptx
#' @return Invisibly, `path`.
#' @noRd
export_xlsx <- function(spec, con, path, exported = Sys.time()) {
  fetches <- plain_fetches(con)
  window <- fetches$window()
  items <- export_items(spec, fetches)
  tidy <- tempdir_tidier()
  on.exit(tidy(path), add = TRUE)
  wb <- openxlsx2::wb_workbook(
    creator = "Prescription Explorer", title = "Prescription Explorer report",
    datetime_created = exported
  )
  xlsx_brand(wb)
  sheets <- xlsx_sheet_names(items)
  xlsx_cover(wb, items, sheets, window, exported)
  for (i in seq_along(items)) {
    xlsx_item(wb, items[[i]], sheets[[i]], i)
  }
  xlsx_methods(wb, methods_content(spec, window, exported))
  wb$save(path, overwrite = TRUE)
  invisible(path)
}

# The workbook in the exports' font and colours: IBM Plex Sans as its base
# font, which its cells and links take, and the templates' theme, its colour
# scheme and IBM Plex Sans declared with IBM's classification
# (brand_office_theme()), which its tables' style, its charts and anything a
# reader adds take
xlsx_brand <- function(wb) {
  sans <- export_fonts()$sans
  wb$set_base_font(font_size = 11, font_name = sans$typeface, font_panose = sans$panose)
  theme <- xml2::read_xml(wb$theme)
  brand_office_theme(theme, name = brand_name)
  wb$theme <- as.character(theme, options = "no_declaration")
  invisible(wb)
}

# A cell's text in the exports' font, as a font of the Swiss family, which
# Excel substitutes by where it is not installed, and in the text's colour
# unless another is given
xlsx_font <- function(wb, sheet, dims, colour = export_palette()[["text"]], ...) {
  wb$add_font(
    sheet, dims, name = export_font, family = "2", color = openxlsx2::wb_color(hex = colour), ...
  )
}

#' Each item's sheet name
#'
#' Its number and its subject, as in "1 Atorvastatin": unique by the number,
#' at most 31 characters, without the characters Excel refuses in a name, and
#' with a straight apostrophe written as a typographic one: mschart quotes a
#' sheet's name in its charts' references without doubling an apostrophe in
#' it, as Excel's formulas need.
#'
#' @param items The items, from [export_items()].
#' @return A character vector, one name per item.
#' @noRd
xlsx_sheet_names <- function(items) {
  vapply(seq_along(items), function(i) {
    subject <- strsplit(items[[i]]$title, " \u00b7 ", fixed = TRUE)[[1]][1]
    name <- gsub("[\\[\\]:*?/\\\\]", " ", paste(i, subject), perl = TRUE)
    name <- gsub("'", "\u2019", name, fixed = TRUE)
    trimws(substr(trimws(gsub(" {2,}", " ", name)), 1L, 31L))
  }, "")
}

# A cell's or a range's address, from row and column numbers
xlsx_cells <- function(row, col, last_row = row, last_col = col) {
  openxlsx2::wb_dims(rows = row:last_row, cols = col:last_col)
}

# A sheet of the workbook, with its gridlines on the screen but not in print:
# openxlsx2 prints them too, which boxes every cell used in black, on paper
# or in a PDF, over the tables' own rules
xlsx_sheet <- function(wb, sheet) {
  wb$add_worksheet(sheet)
  wb$set_grid_lines(sheet, show = TRUE, print = FALSE)
  invisible(wb)
}

# Lines of text down column A from a row, one a row. Excel reads "_xHHHH_" in
# a string as the character HHHH, so an underscore before an x is written as
# "_x005F_", which Excel reads as the underscore: a note shows as typed.
xlsx_lines <- function(wb, sheet, lines, row) {
  if (length(lines) > 0L) {
    lines <- gsub("_x", "_x005F_x", lines, fixed = TRUE)
    wb$add_data(sheet, data.frame(lines), dims = xlsx_cells(row, 1L), col_names = FALSE)
  }
  invisible(wb)
}

# A number format for each value of a column, as the app writes them: whole
# items, pounds and pence, shares in percent; none for text. Quantity and ADQ
# usage keep three significant figures (format_significant()), which no one
# Excel format does: each value gets the decimals the app writes it with, so
# that 0.008 ADQs shows as 0.008, not 0.01, and 25,936 has no decimals.
xlsx_numfmt <- function(kind, x) {
  n <- length(x)
  switch(kind,
    text = rep(NA_character_, n),
    items = ,
    count = rep("#,##0", n),
    nic = ,
    actual_cost = rep("\u00a3#,##0.00", n),
    share = rep("0.0%", n),
    {
      decimals <- nchar(sub("^[^.]*[.]?", "", format_significant(x)))
      out <- paste0("#,##0", ifelse(decimals > 0L, ".", ""), strrep("0", decimals))
      out[!is.finite(x)] <- NA_character_
      out
    }
  )
}

xlsx_cover <- function(wb, items, sheets, window, exported) {
  sheet <- "Report"
  xlsx_sheet(wb, sheet)
  n <- length(items)
  xlsx_lines(wb, sheet, c(
    "Prescription Explorer report", window_period(window),
    paste("Exported on", export_time(exported)), paste(n, if (n == 1L) "item" else "items")
  ), row = 1L)
  xlsx_font(wb, sheet, xlsx_cells(1L, 1L), bold = TRUE, size = 16)
  # The period, the time and the items in the secondary text's colour, as on
  # the PowerPoint's cover and the Word's title page
  xlsx_font(wb, sheet, xlsx_cells(2L, 1L, 4L, 1L), colour = export_palette()[["secondary"]])
  if (n > 0L) {
    contents <- data.frame(Sheet = sheets, Item = vapply(items, `[[`, "", "title"))
    wb$add_data_table(
      sheet, contents, dims = xlsx_cells(6L, 1L), table_name = "Contents",
      table_style = xlsx_table_style, with_filter = FALSE, banded_rows = FALSE
    )
  }
  wb$set_col_widths(sheet, cols = 1:2, widths = c(36, 90))
  invisible(wb)
}

# The most rows an item's sheet freezes, down to its tables' header row:
# Excel does not scroll a frozen pane, so rows that fill a laptop's screen
# would hide the table and chart under them. A note that would push the
# header row further down goes under the table and chart, and one line on
# top says where it is, as PowerPoint puts a long note on slides of its own.
xlsx_frozen_rows <- 12L

xlsx_item <- function(wb, item, sheet, i) {
  xlsx_sheet(wb, sheet)
  head <- c(
    item$title, paste(c(item$summary, item$profile), collapse = " \u00b7 "), item$message,
    item$footnote
  )
  note <- item_note_lines(item)
  framed <- !is.null(item$table) || !is.null(item$chart)
  # The lines on top, a blank row, the tables' captions, then their header rows
  apart <- framed && length(head) + length(note) + 3L > xlsx_frozen_rows
  moved <- paste(
    "The note is under the", if (is.null(item$chart)) "table." else "table and chart."
  )
  top <- c(head, if (apart) moved else note)
  xlsx_lines(wb, sheet, top, row = 1L)
  xlsx_font(wb, sheet, xlsx_cells(1L, 1L), bold = TRUE, size = 14)
  # Its view and subject, and a footnote, in the secondary text's colour, as
  # the other formats write them
  secondary <- export_palette()[["secondary"]]
  xlsx_font(wb, sheet, xlsx_cells(2L, 1L), colour = secondary)
  if (!is.null(item$footnote)) {
    xlsx_font(wb, sheet, xlsx_cells(length(head), 1L), colour = secondary)
  }
  # The tables' captions, then their header rows, which stay in view
  caption <- length(top) + 2L
  header <- caption + 1L
  col <- 1L
  last <- header
  if (!is.null(item$table)) {
    xlsx_table(wb, sheet, item$table, caption, header, 1L, paste0("Table", i))
    col <- ncol(item$table$data) + 2L
    last <- header + nrow(item$table$data)
  }
  if (!is.null(item$chart)) {
    series <- data.frame(item$chart$labels, item$chart$values)
    names(series) <- c(chart_category(item$chart), measure_label(item$measure))
    table <- export_table("The chart's data", series, names(series), c("text", item$measure))
    xlsx_table(wb, sheet, table, caption, header, col, paste0("Chart", i))
    data <- openxlsx2::wb_data(
      wb, sheet, dims = xlsx_cells(header, col, header + nrow(series), col + 1L)
    )
    first <- header + nrow(series) + 2L
    wb$add_mschart(
      sheet, dims = xlsx_cells(first, col, first + 17L, col + 8L),
      graph = export_chart(item$chart, item$measure, data)
    )
    xlsx_alt_text(wb, sheet, item$chart$alt)
    xlsx_chart_clean(wb)
    last <- max(last, first + 17L)
  }
  if (apart) {
    xlsx_lines(wb, sheet, note, row = last + 2L)
  }
  if (framed) {
    wb$freeze_pane(sheet, first_active_row = header + 1L)
  }
  invisible(wb)
}

# The tables' style: Excel's Light 1, whose rules take the theme's dark 1, the
# text's colour, under the header and around the table; with no bands, as the
# other formats' tables, and the sheet's gridlines between rows
xlsx_table_style <- "TableStyleLight1"

# A table of values under its caption, which is in the secondary text's
# colour, as the other formats' captions, as an Excel table: numbers as
# numbers in their formats, blank where there is none, a total in bold over
# a rule; its columns as wide as their values, within reason
xlsx_table <- function(wb, sheet, table, caption, header, col, name) {
  wb$add_data(sheet, table$caption, dims = xlsx_cells(caption, col))
  xlsx_font(wb, sheet, xlsx_cells(caption, col), colour = export_palette()[["secondary"]])
  data <- table$data
  names(data) <- table$labels
  wb$add_data_table(
    sheet, data, dims = xlsx_cells(header, col), table_name = name,
    table_style = xlsx_table_style, with_filter = FALSE, banded_rows = FALSE,
    na = "_openxlsx_NULL"
  )
  n <- nrow(data)
  cols <- col + seq_along(table$kinds) - 1L
  rows <- header + seq_len(n)
  for (j in seq_along(table$kinds)) {
    if (n == 0L) {
      next
    }
    if (identical(table$kinds[[j]], "text")) {
      # Text of digits only, as an appliance's BNF code, stays text, which
      # Excel would otherwise mark on every cell as a number stored as text
      wb$add_ignore_error(
        sheet, xlsx_cells(min(rows), cols[[j]], max(rows), cols[[j]]),
        number_stored_as_text = TRUE
      )
      next
    }
    formats <- xlsx_numfmt(table$kinds[[j]], data[[j]])
    # One call per format: openxlsx2 adds a number format at every call
    for (format in unique(formats[!is.na(formats)])) {
      wb$add_numfmt(
        sheet, openxlsx2::wb_dims(rows = rows[formats %in% format], cols = cols[[j]]), format
      )
    }
  }
  text <- table_text(table)
  widths <- vapply(seq_along(table$kinds), function(j) {
    min(60, max(nchar(c(table$labels[[j]], text[[j]]))) + 3)
  }, 1)
  wb$set_col_widths(sheet, cols = cols, widths = widths)
  if (isTRUE(table$total) && n > 0L) {
    total <- xlsx_cells(header + n, col, header + n, max(cols))
    xlsx_font(wb, sheet, total, bold = TRUE)
    # Its rule over it, in the text colour, as the other formats and the app
    # draw it: Light 1 rules only an Excel table's own totals row, which
    # these tables do not have
    wb$add_border(
      sheet, dims = total, top_border = "thin",
      top_color = openxlsx2::wb_color(hex = export_palette()[["rule"]]),
      bottom_border = NULL, left_border = NULL, right_border = NULL
    )
  }
  invisible(wb)
}

# openxlsx2 draws a chart without alt text: the sheet's chart gets the chart
# in words, which screen readers read
xlsx_alt_text <- function(wb, sheet, alt) {
  if (length(alt) != 1L || is.na(alt)) {
    return(invisible(wb))
  }
  index <- match(sheet, wb$get_sheet_names())
  rels <- paste(wb$worksheets_rels[[index]], collapse = "")
  target <- regmatches(rels, regexpr("drawings/drawing[0-9]+[.]xml", rels))
  if (length(target) == 0L) {
    return(invisible(wb))
  }
  n <- as.integer(gsub("[^0-9]", "", target))
  # The words go into sub()'s replacement, where a backslash has a meaning
  words <- gsub("\\", "\\\\", xml_escape(alt), fixed = TRUE)
  wb$drawings[[n]] <- sub(
    "<xdr:cNvPr id=\"([0-9]+)\" name=\"([^\"]*)\"",
    paste0("<xdr:cNvPr id=\"\\1\" name=\"\\2\" descr=\"", words, "\""),
    wb$drawings[[n]]
  )
  invisible(wb)
}

# mschart writes a chart from its template for PowerPoint and Word: a link to
# the workbook those embed, which a workbook's chart does not have and whose
# relationship is not there, French as its text's language, and nothing to
# stop Excel's frame around it. The chart just added keeps none of them.
xlsx_chart_clean <- function(wb) {
  k <- nrow(wb$charts)
  chart <- sub(
    "(?s)<c:externalData[^>]*>.*?</c:externalData>", "", wb$charts$chart[k], perl = TRUE
  )
  wb$charts$chart[k] <- flat_chart_space(english_chart(chart))
  invisible(wb)
}

# Text as an XML attribute's value
xml_escape <- function(text) {
  text <- gsub("&", "&amp;", text, fixed = TRUE)
  text <- gsub("<", "&lt;", text, fixed = TRUE)
  text <- gsub(">", "&gt;", text, fixed = TRUE)
  gsub("\"", "&quot;", text, fixed = TRUE)
}

# The Methods sheet's column, 120 of the base font's digits wide, as Excel
# counts a column's width: about 10 inches where Excel draws Arial in IBM
# Plex Sans's place, and more in Plex, whose digits are wider. Its text has
# a little less, inside the cell's margins.
xlsx_methods_width <- list(digits = 120, text = 9.9)

xlsx_methods <- function(wb, sections) {
  sheet <- "Methods"
  xlsx_sheet(wb, sheet)
  row <- 1L
  for (section in sections) {
    xlsx_lines(wb, sheet, section$title, row)
    xlsx_font(wb, sheet, xlsx_cells(row, 1L), bold = TRUE, size = 12)
    lines <- c(
      section$text,
      vapply(section$points, function(point) {
        paste0("\u2022 ", if (!is.na(point$term)) paste0(point$term, ". "), point$text)
      }, ""),
      vapply(section$links, function(link) paste0(link$text, ": ", link$url), "")
    )
    xlsx_lines(wb, sheet, lines, row + 1L)
    if (length(lines) > 0L) {
      rows <- row + seq_along(lines)
      wb$add_cell_style(
        sheet, xlsx_cells(min(rows), 1L, max(rows), 1L), wrap_text = TRUE, vertical = "top"
      )
      # Excel does not grow a row to fit wrapped text it did not write: each
      # row as high as its lines at 11 points, measured as the exports' text
      # is, with Excel's margin of a point and a half above and below them.
      # Excel draws a line of 11-point IBM Plex Sans 15 points high (a row it
      # fits to its text is 15, 30, 45 points), more than a line of Arial
      # (13.5) and than PowerPoint's 1.2 em.
      wrapped <- text_lines(lines, 11, xlsx_methods_width$text)
      wb$set_row_heights(sheet, rows = rows, heights = wrapped * 15 + 3)
    }
    # The links last, each a hyperlink to its page, in the links' colour
    for (k in seq_along(section$links)) {
      cell <- xlsx_cells(row + length(lines) - length(section$links) + k, 1L)
      wb$add_hyperlink(sheet, cell, target = section$links[[k]]$url)
      xlsx_font(wb, sheet, cell, colour = export_palette()[["link"]], underline = "single")
    }
    row <- row + length(lines) + 2L
  }
  wb$set_col_widths(sheet, cols = 1L, widths = xlsx_methods_width$digits)
  invisible(wb)
}
