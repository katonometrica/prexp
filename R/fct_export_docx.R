# The Word export (P5-06; spec section 5.5), on report.docx, A4 with 2.5 cm
# margins (data-raw/make_templates.R): a title page with the maker's wordmark,
# the data period and the export time; then a page per item with its heading,
# its view and subject, a native chart, its note and its table; and the
# methods as an appendix. Each Heading 1 starts a page (the template's
# style). Word lays the text out and breaks a long table across pages itself,
# repeating its header row; a table of more than three columns, whose BNF
# codes and national totals do not wrap, is wider than a portrait page's
# text, so it goes on landscape pages of its own after its item's. The text
# takes the template's font, IBM Plex Sans, and colour, the exports' text
# colour; secondary text and links take theirs (export_palette()).

#' Writes a report as a Word file
#'
#' @inheritParams export_pptx
#' @return Invisibly, `path`.
#' @noRd
export_docx <- function(spec, con, path, exported = Sys.time()) {
  use_export_font()
  fetches <- plain_fetches(con)
  window <- fetches$window()
  items <- export_items(spec, fetches)
  tidy <- tempdir_tidier()
  on.exit(tidy(path), add = TRUE)
  doc <- officer::read_docx(template_file("report.docx"))
  doc <- officer::set_doc_properties(
    doc, title = "Prescription Explorer report", creator = "Prescription Explorer",
    created = exported
  )
  doc <- docx_wordmark(doc)
  doc <- officer::body_add_par(doc, "Prescription Explorer report", style = "Title")
  n <- length(items)
  for (line in c(
    window_period(window), paste("Exported on", export_time(exported)),
    paste(n, if (n == 1L) "item" else "items")
  )) {
    doc <- docx_secondary(doc, line)
  }
  for (item in items) {
    doc <- docx_item(doc, item)
  }
  doc <- officer::body_add_par(doc, "Methods", style = "heading 1")
  for (section in methods_content(spec, window, exported)) {
    doc <- docx_section(doc, section)
  }
  # The last section, which the template's makes continuous: portrait, on a
  # page of its own
  doc <- officer::body_set_default_section(doc, docx_page("portrait"))
  finish_charts(file.path(doc$package_dir, "word", "charts"))
  print(doc, target = path)
  invisible(path)
}

# The width of the text on an A4 page with 2.5 cm margins, in inches
docx_width <- 6.3

# Whether a table goes on landscape pages of its own, 9.7 inches of text
# wide: the tables of more than three columns, a chemical substance's
# presentations and a practice's top drugs
docx_wide <- function(table) {
  !is.null(table) && ncol(table$data) > 3L
}

# A section of the template's A4 page and 2.5 cm margins, in twips, that
# starts a page
docx_page <- function(orient) {
  inch <- function(twips) twips / 1440
  officer::prop_section(
    page_size = officer::page_size(width = inch(11900), height = inch(16840), orient = orient),
    page_margins = officer::page_mar(
      bottom = inch(1417), top = inch(1417), right = inch(1417), left = inch(1417),
      header = inch(708), footer = inch(708), gutter = 0
    ),
    type = "nextPage"
  )
}

# Ends the section of what was added since the last, in an orientation
docx_end_section <- function(doc, orient) {
  officer::body_end_block_section(doc, officer::block_section(docx_page(orient)))
}

docx_item <- function(doc, item) {
  doc <- officer::body_add_par(doc, item$title, style = "heading 1")
  for (line in c(item$summary, item$profile)) {
    doc <- docx_secondary(doc, line)
  }
  if (!is.null(item$chart)) {
    doc <- mschart::body_add_chart(
      doc, export_chart(item$chart, item$measure), style = "centered", width = docx_width,
      height = 3.4
    )
    doc <- docx_alt_text(doc, item$chart$alt)
  } else if (!is.null(item$message)) {
    doc <- officer::body_add_par(doc, item$message, style = "Normal")
  }
  if (!is.null(item$footnote)) {
    doc <- docx_secondary(doc, item$footnote)
  }
  for (line in item_note_lines(item)) {
    doc <- officer::body_add_par(doc, line, style = "Normal")
  }
  if (!is.null(item$table)) {
    wide <- docx_wide(item$table)
    if (wide) {
      doc <- docx_end_section(doc, "portrait")
    }
    doc <- officer::body_add_par(doc, item$table$caption, style = "Table Caption")
    doc <- docx_table(doc, item$table)
    if (wide) {
      doc <- docx_end_section(doc, "landscape")
    }
  }
  doc
}

# An item's table in the template's Report Table style: the values as the app
# writes them, numbers to the right, its header row repeated on a page it
# runs onto, a total in the style's last row. A plain Word table, which the
# style formats, rather than a flextable, whose formatting of every cell
# makes a document of fifteen tables six times larger, and its writing
# several times slower.
docx_table <- function(doc, table) {
  text <- table_text(table)
  names(text) <- table$labels
  officer::body_add_table(
    doc, text, style = "Report Table", header = TRUE,
    alignment = ifelse(table$kinds == "text", "l", "r"),
    stylenames = officer::table_stylenames(list(`Table Text` = names(text))),
    first_row = TRUE, last_row = isTRUE(table$total), no_hband = FALSE
  )
}

docx_section <- function(doc, section) {
  doc <- officer::body_add_par(doc, section$title, style = "heading 2")
  for (text in section$text) {
    doc <- officer::body_add_par(doc, text, style = "Normal")
  }
  # The style's font and colour, but for a point's term, in bold, and links
  text <- officer::fp_text_lite
  # A list Word and screen readers know as one, its bullets from the style
  for (point in section$points) {
    runs <- c(
      if (!is.na(point$term)) list(officer::ftext(paste0(point$term, ". "), text(bold = TRUE))),
      list(officer::ftext(point$text, text()))
    )
    doc <- officer::body_add_fpar(doc, do.call(officer::fpar, runs), style = "List Bullet")
  }
  link <- text(color = export_palette()[["link"]], underlined = TRUE)
  for (target in section$links) {
    doc <- officer::body_add_fpar(
      doc, officer::fpar(officer::hyperlink_ftext(target$text, prop = link, href = target$url)),
      style = "Normal"
    )
  }
  doc
}

# A paragraph of secondary text: in the Normal style, in the secondary text's
# colour
docx_secondary <- function(doc, text) {
  prop <- officer::fp_text_lite(color = export_palette()[["secondary"]])
  officer::body_add_fpar(doc, officer::fpar(officer::ftext(text, prop)), style = "Normal")
}

# The maker's wordmark at the top of the title page, as on the PowerPoint's
# cover: its name in IBM Plex Mono, which the template's font table declares,
# its letters spaced, in the secondary text's colour, linked to its site. Word
# draws a link's text in the link's own colour.
docx_wordmark <- function(doc) {
  mono <- export_fonts()$mono$typeface
  size <- 10
  prop <- officer::fp_text_lite(
    font.size = size, color = export_palette()[["secondary"]], font.family = mono,
    hansi.family = mono, cs.family = mono, eastasia.family = mono
  )
  doc <- officer::body_add_fpar(doc, officer::fpar(
    officer::hyperlink_ftext(export_wordmark$text, prop = prop, href = export_wordmark$url)
  ), style = "Normal")
  # Its letters spaced, in twentieths of a point
  body <- doc$doc_obj$get()
  run <- xml2::xml_find_first(body, sprintf(
    "//w:hyperlink/w:r[w:t = '%s']/w:rPr", export_wordmark$text
  ), xml2::xml_ns(body))
  xml2::xml_add_child(run, "w:spacing", "w:val" = round(20 * export_wordmark$spacing * size))
  doc
}

# officer places a chart without alt text: the document's last drawing gets
# the chart in words, which screen readers read
docx_alt_text <- function(doc, alt) {
  body <- doc$doc_obj$get()
  drawings <- xml2::xml_find_all(body, "//wp:docPr", xml2::xml_ns(body))
  if (length(drawings) > 0L && length(alt) == 1L && !is.na(alt)) {
    xml2::xml_set_attr(drawings[[length(drawings)]], "descr", alt)
  }
  doc
}
