# The PowerPoint export (P5-05; spec section 5.5), on report.pptx, 13.333 by
# 7.5 inches (data-raw/make_templates.R): a title slide with the maker's
# wordmark; one slide per item with its title, its view and subject, its
# native chart and its note; its table beside the chart when it is short and
# narrow, or else on slides of its own after it; a note too long for the room
# under the chart on slides of its own too; then the methods, a slide per
# section, or more for a long one. A slide does not grow to fit its text, so
# the text is measured (text_lines(), table_layout()) in both the fonts Office
# may draw it in, and the slide laid out to hold it. The text takes the
# theme's font, IBM Plex Sans, and the exports' colours (export_palette()).

#' Writes a report as a PowerPoint file
#'
#' @param spec A report ([new_report()]).
#' @param con A pool or connection that can read the app's views.
#' @param path Where to write the file.
#' @param exported When the export was made.
#' @return Invisibly, `path`.
#' @noRd
export_pptx <- function(spec, con, path, exported = Sys.time()) {
  use_export_font()
  fetches <- plain_fetches(con)
  window <- fetches$window()
  items <- export_items(spec, fetches)
  tidy <- tempdir_tidier()
  on.exit(tidy(path), add = TRUE)
  deck <- officer::read_pptx(template_file("report.pptx"))
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
  finish_charts(file.path(deck$package_dir, "ppt", "charts"))
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
pptx_line <- 12 * export_line / 72
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
  sum(text_lines(lines, size, pptx_width - 2 * pptx_inset)) * size * export_line / 72 + pptx_inset
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
  # The data period, the export's time and the items, in the secondary text's
  # colour, at a size whose three lines the box holds in either font
  prop <- officer::fp_text_lite(font.size = 20, color = export_palette()[["secondary"]])
  lines <- c(
    window_period(window), paste("Exported on", export_time(exported)),
    paste(n, if (n == 1L) "item" else "items")
  )
  deck <- officer::ph_with(
    deck, do.call(officer::block_list, lapply(lines, function(line) {
      officer::fpar(officer::ftext(line, prop))
    })),
    location = officer::ph_location_type("subTitle")
  )
  # Last, so that screen readers read the title first
  pptx_wordmark(deck)
}

# The maker's wordmark at the top of the cover, as on its site: its name in
# IBM Plex Mono, its letters spaced, in the text colour, as the site and the
# app draw it, the text box a link to its site. PowerPoint draws a link on
# text in the theme's link colour, underlined; on a box, the text keeps its
# own.
pptx_wordmark <- function(deck) {
  mono <- export_fonts()$mono
  size <- 12
  prop <- officer::fp_text(
    font.size = size, color = export_palette()[["text"]], font.family = mono$typeface
  )
  deck <- officer::ph_with(
    deck, officer::fpar(officer::ftext(export_wordmark$text, prop)),
    location = officer::ph_location(
      left = pptx_left, top = 0.5, width = 4, height = 0.4, newlabel = export_wordmark$text
    )
  )
  deck <- officer::ph_hyperlink(deck, ph_label = export_wordmark$text, href = export_wordmark$url)
  # Its font declared as the theme declares IBM Plex Sans, so that PowerPoint
  # draws a font of fixed pitch where it is not installed, and its letters
  # spaced, in hundredths of a point
  slide <- slide_xml(deck)
  ns <- xml2::xml_ns(slide)
  shape <- xml2::xml_find_first(
    slide, sprintf("//p:sp[p:nvSpPr/p:cNvPr/@name = '%s']", export_wordmark$text), ns
  )
  run <- xml2::xml_find_first(shape, ".//a:r/a:rPr", ns)
  xml2::xml_set_attr(run, "spc", round(100 * export_wordmark$spacing * size))
  for (font in xml2::xml_find_all(run, "a:latin | a:ea | a:cs | a:sym", ns)) {
    xml2::xml_set_attrs(font, c(
      typeface = mono$typeface, panose = mono$panose, pitchFamily = mono$pitch_family,
      charset = "0"
    ))
  }
  top_anchor(deck)
}

# The months loaded, for the title page
window_period <- function(window) {
  if (is.null(window) || nrow(window) == 0L || is.na(window$first_month[1])) {
    return("No months of data loaded")
  }
  paste("Data:", format_month(window$first_month[1]), "to", format_month(window$last_month[1]))
}

pptx_item <- function(deck, item, frame) {
  secondary <- export_palette()[["secondary"]]
  deck <- officer::add_slide(deck, layout = "Title Only", master = "Office Theme")
  deck <- pptx_slide_title(deck, item$title)
  deck <- pptx_text(deck, c(item$summary, item$profile), top = frame$summary$top,
                    height = frame$summary$height, size = 12, colour = secondary)
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
                      colour = secondary, left = left, width = beside$width)
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
                      height = frame$footnote$height, size = 10, colour = secondary)
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
                    colour = export_palette()[["secondary"]])
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
  colours <- export_palette()
  # In the theme's font, which the text box takes
  text <- function(...) officer::fp_text_lite(font.size = 12, ...)
  body <- text(color = colours[["text"]])
  bold <- text(color = colours[["text"]], bold = TRUE)
  link <- text(color = colours[["link"]], underlined = TRUE)
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
  deck <- officer::ph_with(
    deck, do.call(officer::block_list, paragraphs),
    location = officer::ph_location(
      left = pptx_left, top = text_box$top, width = pptx_width, height = text_box$height
    )
  )
  top_anchor(deck)
}

# A slide's title, in the theme's font for titles, IBM Plex Sans too
pptx_slide_title <- function(deck, title) {
  prop <- officer::fp_text_lite(font.size = 24, color = export_palette()[["text"]])
  officer::ph_with(
    deck, officer::fpar(officer::ftext(title, prop)), location = officer::ph_location_type("title")
  )
}

# Lines of text in a box of their own, a paragraph each, in the theme's font
pptx_text <- function(deck, lines, top, height, size, colour = export_palette()[["text"]],
                      left = pptx_left, width = pptx_width) {
  prop <- officer::fp_text_lite(font.size = size, color = colour)
  paragraphs <- lapply(lines, function(line) officer::fpar(officer::ftext(line, prop)))
  deck <- officer::ph_with(
    deck, do.call(officer::block_list, paragraphs),
    location = officer::ph_location(left = left, top = top, width = width, height = height)
  )
  top_anchor(deck)
}

# The current slide's XML, which officer keeps as the deck is built
slide_xml <- function(deck) {
  deck$slide$get_slide(deck$cursor)$get()
}

# officer writes a box placed with ph_location() as a placeholder of no
# type, which PowerPoint draws as the layout's title, its text centred in
# its height: a methods slide's text would start halfway down its box. The
# current slide's boxes of no type start their text at their top.
top_anchor <- function(deck) {
  slide <- slide_xml(deck)
  ns <- xml2::xml_ns(slide)
  boxes <- xml2::xml_find_all(
    slide, "//p:sp[p:nvSpPr/p:nvPr/p:ph[not(@type)]]/p:txBody/a:bodyPr", ns
  )
  xml2::xml_set_attr(boxes, "anchor", "t")
  deck
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
# French, and with no line of its own around it, so that Word draws its grey
# frame: the charts of a deck or a document, written into its folder as they
# were placed, say British English instead, with english_chart(), and have no
# frame, with flat_chart_space()
finish_charts <- function(dir) {
  for (file in list.files(dir, "[.]xml$", full.names = TRUE)) {
    xml <- paste(readLines(file, encoding = "UTF-8", warn = FALSE), collapse = "\n")
    writeLines(flat_chart_space(english_chart(xml)), file, useBytes = TRUE)
  }
  invisible(dir)
}
