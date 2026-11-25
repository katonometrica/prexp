# The PowerPoint export (P5-05; spec section 5.5), on report.pptx, 13.333 by
# 7.5 inches (data-raw/make_templates.R): a title slide; one slide per item
# with its title, its view and subject, its native chart and its note; its
# table beside the chart when it is short and narrow, or else on slides of its
# own after it; a note too long for the room under the chart on slides of its
# own too; then the methods, a slide per section, or more for a long one. A
# slide does not grow to fit its text, so the text is measured (text_lines(),
# table_layout()) and the slide laid out to hold it.

#' Writes a report as a PowerPoint file
#'
#' @param spec A report ([new_report()]).
#' @param con A pool or connection that can read the app's views.
#' @param path Where to write the file.
#' @param exported When the export was made.
#' @return Invisibly, `path`.
#' @noRd
export_pptx <- function(spec, con, path, exported = Sys.time()) {
  use_chart_font()
  fetches <- plain_fetches(con)
  window <- fetches$window()
  items <- export_items(spec, fetches)
  deck <- officer::read_pptx(template_file("report.pptx"))
  # officer unpacks the template into a folder of tempdir() that print() zips
  # but does not delete, and a worker lives as long as the app: the folder
  # goes when the export ends, written or not
  on.exit(unlink(deck$package_dir, recursive = TRUE), add = TRUE)
  deck <- officer::set_doc_properties(
    deck, title = "Prescription Explorer report", creator = "Prescription Explorer",
    created = exported
  )
  deck <- pptx_title(deck, window, exported, length(items))
  for (item in items) {
    frame <- pptx_frame(item)
    deck <- pptx_item(deck, item, frame)
    pages <- pptx_note_pages(item, frame)
    for (k in seq_along(pages)) {
      deck <- pptx_note(deck, item, item_note_lines(item)[pages[[k]]], k)
    }
    if (!is.null(item$table) && !pptx_beside(item$table, frame)) {
      pages <- pptx_table_pages(item$table)
      for (k in seq_along(pages)) {
        deck <- pptx_table(deck, item, pages[[k]], k)
      }
    }
  }
  for (page in methods_pages(methods_content(spec, window, exported))) {
    deck <- pptx_methods(deck, page)
  }
  english_charts(deck)
  print(deck, target = path)
  invisible(path)
}

# The path of one of the exports' templates
template_file <- function(name) {
  system.file("templates", name, package = "prexp", mustWork = TRUE)
}

# Where things go on a slide, in inches: the layouts' margins, the bottom of
# the text, the line of a 12-point paragraph and the text boxes' side insets;
# a table beside a chart, at 10 points, and on a slide of its own, at 9; the
# box of a slide of text (the methods, a note).
pptx_left <- 0.667
pptx_width <- 12
pptx_bottom <- 7.4
pptx_line <- 12 * 1.2 / 72
pptx_inset <- 0.1
beside <- list(left = 8.3, width = 4.35, size = 10)
alone <- list(top = 2, height = 5.4, size = 9)
text_box <- list(top = 1.7, height = 5.5)

#' Where an item's slide puts things
#'
#' From the measured height of its text: the summary under the title, the
#' note at the bottom with a footnote above it, and the chart between them.
#' A note that would leave the chart under three inches goes on slides of its
#' own, and one line says where it is.
#'
#' @param item An item, from [export_items()].
#' @return A list of the boxes' `top` and `height`, in inches: `summary`,
#'   `chart`, `footnote` and `note`; and `apart`, whether the note goes on
#'   slides of its own.
#' @noRd
pptx_frame <- function(item) {
  summary <- list(top = 1.55, height = text_height(c(item$summary, item$profile), 12))
  footnote <- text_height(item$footnote, 10)
  layout <- function(note) {
    note_top <- pptx_bottom - note
    foot_top <- note_top - footnote - if (footnote > 0) 0.05 else 0
    chart_top <- summary$top + summary$height + 0.05
    list(
      summary = summary,
      chart = list(top = chart_top, height = foot_top - 0.05 - chart_top),
      footnote = list(top = foot_top, height = footnote),
      note = list(top = note_top, height = note)
    )
  }
  note <- text_height(item_note_lines(item), 12)
  frame <- layout(note)
  frame$apart <- note > 0 && frame$chart$height < 3
  if (frame$apart) {
    frame <- c(layout(text_height(pptx_note_moved, 12)), apart = TRUE)
  }
  frame
}

pptx_note_moved <- "The note is on the next slide."

# The height of paragraphs in a text box the width of the slide's text, its
# insets included; none for no text
text_height <- function(lines, size) {
  if (length(lines) == 0L) {
    return(0)
  }
  sum(text_lines(lines, size, pptx_width - 2 * pptx_inset)) * size * 1.2 / 72 + pptx_inset
}

# The note's paragraphs on each slide of its own, when it has them
pptx_note_pages <- function(item, frame) {
  if (!isTRUE(frame$apart)) {
    return(list())
  }
  lines <- item_note_lines(item)
  heights <- text_lines(lines, 12, pptx_width - 2 * pptx_inset) * pptx_line
  table_pages(list(header = pptx_inset, heights = heights), text_box$height)
}

# Whether a table goes beside its chart: a few rows of a few columns, as an
# item's months or its regions, that fit the chart's height under a caption
pptx_beside <- function(table, frame) {
  if (nrow(table$data) > 12L || ncol(table$data) > 3L) {
    return(FALSE)
  }
  layout <- table_layout(table, beside$size, beside$width)
  layout$header + sum(layout$heights) <= frame$chart$height - 0.4
}

# The rows of each slide of a table on slides of its own
pptx_table_pages <- function(table) {
  table_pages(table_layout(table, alone$size, pptx_width), alone$height)
}

pptx_title <- function(deck, window, exported, n) {
  deck <- officer::add_slide(deck, layout = "Title Slide", master = "Office Theme")
  deck <- officer::ph_with(
    deck, "Prescription Explorer report", location = officer::ph_location_type("ctrTitle")
  )
  officer::ph_with(deck, c(
    window_period(window),
    paste("Exported on", export_time(exported)),
    paste(n, if (n == 1L) "item" else "items")
  ), location = officer::ph_location_type("subTitle"))
}

# The months loaded, for the title page
window_period <- function(window) {
  if (is.null(window) || nrow(window) == 0L || is.na(window$first_month[1])) {
    return("No months of data loaded")
  }
  paste("Data:", format_month(window$first_month[1]), "to", format_month(window$last_month[1]))
}

pptx_item <- function(deck, item, frame) {
  deck <- officer::add_slide(deck, layout = "Title Only", master = "Office Theme")
  deck <- pptx_slide_title(deck, item$title)
  deck <- pptx_text(deck, c(item$summary, item$profile), top = frame$summary$top,
                    height = frame$summary$height, size = 12, colour = "#5A6470")
  chart <- frame$chart
  by_chart <- !is.null(item$table) && pptx_beside(item$table, frame)
  if (!is.null(item$chart)) {
    deck <- officer::ph_with(
      deck, export_chart(item$chart, item$measure),
      location = officer::ph_location(
        left = pptx_left, top = chart$top, width = if (by_chart) 7.4 else pptx_width,
        height = chart$height
      )
    )
    deck <- chart_alt_text(deck, item$chart$alt)
  } else if (!is.null(item$message)) {
    deck <- pptx_text(deck, item$message, top = chart$top, height = 0.8, size = 16)
  }
  if (by_chart) {
    # A drug that only unidentified prescribers prescribed has no chart, as in
    # the Region view: its table takes the chart's place
    left <- if (is.null(item$chart)) pptx_left else beside$left
    deck <- pptx_text(deck, item$table$caption, top = chart$top, height = 0.35, size = 11,
                      colour = "#5A6470", left = left, width = beside$width)
    layout <- table_layout(item$table, beside$size, beside$width)
    deck <- officer::ph_with(
      deck, export_flextable(item$table, beside$size, layout),
      location = officer::ph_location(
        left = left, top = chart$top + 0.4, width = beside$width, height = chart$height - 0.4
      )
    )
    deck <- table_header_row(deck)
  }
  if (frame$footnote$height > 0) {
    deck <- pptx_text(deck, item$footnote, top = frame$footnote$top,
                      height = frame$footnote$height, size = 10, colour = "#5A6470")
  }
  note <- if (isTRUE(frame$apart)) pptx_note_moved else item_note_lines(item)
  if (length(note) > 0L) {
    deck <- pptx_text(deck, note, top = frame$note$top, height = frame$note$height, size = 12)
  }
  deck
}

# A page of an item's note on a slide of its own, after the item's
pptx_note <- function(deck, item, lines, page) {
  deck <- officer::add_slide(deck, layout = "Title Only", master = "Office Theme")
  deck <- pptx_slide_title(deck, paste0("Note: ", item$title, if (page > 1L) " (continued)"))
  pptx_text(deck, lines, top = text_box$top, height = text_box$height, size = 12)
}

# A page of an item's table on a slide of its own, after the item's
pptx_table <- function(deck, item, rows, page) {
  deck <- officer::add_slide(deck, layout = "Title Only", master = "Office Theme")
  deck <- pptx_slide_title(
    deck, paste0("Table: ", item$title, if (page > 1L) " (continued)")
  )
  deck <- pptx_text(deck, item$table$caption, top = 1.55, height = 0.4, size = 12,
                    colour = "#5A6470")
  layout <- table_layout(item$table, alone$size, pptx_width)
  deck <- officer::ph_with(
    deck, export_flextable(item$table, alone$size, layout, rows),
    location = officer::ph_location(
      left = pptx_left, top = alone$top, width = pptx_width, height = alone$height
    )
  )
  table_header_row(deck)
}

pptx_methods <- function(deck, page) {
  deck <- officer::add_slide(deck, layout = "Title Only", master = "Office Theme")
  deck <- pptx_slide_title(deck, page$title)
  text <- function(...) officer::fp_text(font.size = 12, font.family = chart_font, ...)
  body <- text(color = "#333333")
  bold <- text(color = "#333333", bold = TRUE)
  link <- text(color = prexp_palette()[["blue"]], underlined = TRUE)
  spaced <- officer::fp_par(padding.bottom = 6)
  paragraphs <- lapply(page$blocks, function(block) {
    switch(block$kind,
      text = officer::fpar(officer::ftext(block$text, body), fp_p = spaced),
      point = do.call(officer::fpar, c(
        list(officer::ftext("\u2022 ", body)),
        if (!is.null(block$term)) list(officer::ftext(paste0(block$term, ". "), bold)),
        list(officer::ftext(block$text, body), fp_p = spaced)
      )),
      link = officer::fpar(
        officer::hyperlink_ftext(block$text, prop = link, href = block$url), fp_p = spaced
      )
    )
  })
  officer::ph_with(
    deck, do.call(officer::block_list, paragraphs),
    location = officer::ph_location(
      left = pptx_left, top = text_box$top, width = pptx_width, height = text_box$height
    )
  )
}

pptx_slide_title <- function(deck, title) {
  prop <- officer::fp_text(font.size = 24, color = "#222222", font.family = chart_font)
  officer::ph_with(
    deck, officer::fpar(officer::ftext(title, prop)), location = officer::ph_location_type("title")
  )
}

# Lines of text in a box of their own, a paragraph each
pptx_text <- function(deck, lines, top, height, size, colour = "#333333", left = pptx_left,
                      width = pptx_width) {
  prop <- officer::fp_text(font.size = size, color = colour, font.family = chart_font)
  paragraphs <- lapply(lines, function(line) officer::fpar(officer::ftext(line, prop)))
  officer::ph_with(
    deck, do.call(officer::block_list, paragraphs),
    location = officer::ph_location(left = left, top = top, width = width, height = height)
  )
}

# The current slide's XML, which officer keeps as the deck is built
slide_xml <- function(deck) {
  deck$slide$get_slide(deck$cursor)$get()
}

# officer places a chart without alt text: the slide's last chart gets the
# chart in words, which screen readers read
chart_alt_text <- function(deck, alt) {
  slide <- slide_xml(deck)
  frames <- xml2::xml_find_all(
    slide, "//p:graphicFrame/p:nvGraphicFramePr/p:cNvPr", xml2::xml_ns(slide)
  )
  if (length(frames) > 0L && length(alt) == 1L && !is.na(alt)) {
    xml2::xml_set_attr(frames[[length(frames)]], "descr", alt)
  }
  deck
}

# flextable writes a table with an empty a:tblPr, so nothing marks its first
# row as the header: the slide's tables get PowerPoint's Header Row, by which
# screen readers announce each cell's column
table_header_row <- function(deck) {
  slide <- slide_xml(deck)
  props <- xml2::xml_find_all(slide, "//a:tbl/a:tblPr", xml2::xml_ns(slide))
  xml2::xml_set_attr(props, "firstRow", "1")
  deck
}

# mschart writes each chart from its template, which says the chart's text is
# French: the deck's charts, written into its folder as they were placed, say
# British English instead, for Office's proofing
english_charts <- function(deck) {
  dir <- file.path(deck$package_dir, "ppt", "charts")
  for (file in list.files(dir, "[.]xml$", full.names = TRUE)) {
    xml <- readLines(file, encoding = "UTF-8", warn = FALSE)
    writeLines(gsub("\"fr-FR\"", "\"en-GB\"", xml, fixed = TRUE), file, useBytes = TRUE)
  }
  invisible(deck)
}
