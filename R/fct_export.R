# The exports (spec section 5.5; P5-05 to P5-07). An export fetches each item
# again with the fetch functions the views call, so it shows what the screen
# shows for the database as it is now, and writes it with native Office
# charts and tables, its note under it, and the methods (fct_methods.R) last.
# export_items() shapes the items once for every format; export_pptx() writes
# the PowerPoint.

#' The formats a report exports to
#'
#' @return A data frame: `format`, the file's extension, and `label`, its
#'   name in the app.
#' @noRd
export_formats <- function() {
  data.frame(format = c("pptx", "docx", "xlsx"), label = c("PowerPoint", "Word", "Excel"))
}

#' Writes a report to a file
#'
#' @param format One of [export_formats()]' formats.
#' @param spec A report ([new_report()]).
#' @param con A pool or connection that can read the app's views.
#' @param path Where to write the file.
#' @param exported When the export was made.
#' @return Invisibly, `path`.
#' @noRd
export_report <- function(format, spec, con, path, exported = Sys.time()) {
  format <- validate_choice(format, export_formats()$format, "format")
  switch(format,
    pptx = export_pptx(spec, con, path, exported),
    docx = export_docx(spec, con, path, exported),
    xlsx = export_xlsx(spec, con, path, exported)
  )
  invisible(path)
}

# officer unpacks a template into a folder of tempdir(), and writes files of
# its own there as it prints a document, all named as tempfile() names them,
# and deletes none of them; a worker lives as long as the app. A tidier
# notes what is there before an export and, at its end, written or not,
# removes what it added but the file written.
tempdir_tidier <- function() {
  before <- list.files(tempdir(), pattern = "^file", all.files = TRUE)
  function(keep) {
    made <- setdiff(
      list.files(tempdir(), pattern = "^file", all.files = TRUE), c(before, basename(keep))
    )
    unlink(file.path(tempdir(), made), recursive = TRUE)
  }
}

# The most rows an item's table shows: a chemical substance can have
# thousands of presentations (dressings have 2,068), and a practice's top
# drugs are a ranking, as the view's first page
export_rows <- 25L

# The maker's wordmark on the PowerPoint's cover and the Word's title page,
# as the app's footer shows it: its name, a link to its site, its letters
# spaced by 0.18 em (inst/app/www/prexp.css)
export_wordmark <- list(text = "KATONOMETRICA", url = "https://katonometrica.com", spacing = 0.18)

#' What an export shows of each item
#'
#' Each item is fetched again with the fetch functions the views call, and
#' shaped as its view shapes it: a drug's monthly series, with, for a chemical
#' substance, its presentations, most items first; a practice's monthly series
#' and its top drugs by the item's measure; a drug's totals by NHS region,
#' with each one's share of England's.
#'
#' @param spec A report.
#' @param fetches The fetch functions, as [plain_fetches()] gives them.
#' @return A list, one element per item, each a list: `title`, `summary` (its
#'   view, subject and code), `profile` (a practice's address, ICB and region,
#'   or `NULL`), `note`, `clamped`, `measure`; `chart`, `NULL` or a list of
#'   `type` (`"line"` or `"bar"`), `labels`, `values` and `alt`, the chart in
#'   words; `table`, `NULL` or a list of `caption`, `data` (the values, as
#'   fetched), `labels` (the columns' names), `kinds` (how each column is
#'   written: `"text"`, `"count"`, `"share"` or a measure) and `total` (whether
#'   the last row is a total); `footnote`; and `message`, what to say in place
#'   of the chart when there is nothing to show.
#' @noRd
export_items <- function(spec, fetches) {
  lapply(spec$items, export_item, fetches = fetches)
}

export_item <- function(item, fetches) {
  params <- item$params
  shaped <- switch(item$view,
    drug = drug_export(params, fetches),
    practice = practice_export(params, fetches),
    region = region_export(params, fetches)
  )
  out <- list(
    title = report_item_title(item), summary = report_item_summary(item), profile = NULL,
    note = if (is.null(item$note)) "" else item$note, clamped = isTRUE(item$clamped),
    measure = params$measure, chart = NULL, table = NULL, footnote = NULL, message = NULL
  )
  out[names(shaped)] <- shaped
  out
}

# A drug's monthly series, as the Drug view draws it, and its table: a
# chemical substance's presentations, or a presentation's months
drug_export <- function(params, fetches) {
  rows <- fetches$drug_series(params$level, params$id, params$months, params$measure)
  if (nrow(rows) == 0L || all(is.na(rows$value))) {
    return(list(message = no_rows_text(params, params$measure, params$months)))
  }
  rows <- complete_months(
    rows, params$months, list(measure = params$measure, value = 0, practices = 0L)
  )
  table <- if (identical(params$level, "chemical")) {
    presentations_export(fetches$drug_presentations(params$id, params$months))
  } else {
    export_table(
      "By month",
      data.frame(month = format_month(rows$year_month), value = rows$value,
                 practices = rows$practices),
      c("Month", measure_label(params$measure), "Prescribers"),
      c("text", params$measure, "count")
    )
  }
  list(chart = series_chart(rows, params$measure), table = table)
}

# A practice's monthly series of the measure, and its top drugs by it
practice_export <- function(params, fetches) {
  profile <- fetches$practice_profile(params$id)
  if (nrow(profile) == 0L) {
    return(list(message = paste0(params$label, " is not in the data.")))
  }
  where <- profile_text(profile)
  rows <- fetches$practice_series(params$id, params$months)
  if (nrow(rows) == 0L) {
    return(list(profile = where, message = paste0(
      params$label, " did not prescribe in ",
      format_month_range(params$months[1], params$months[2]), "."
    )))
  }
  rows <- complete_months(
    rows, params$months, list(presentations = 0L, items = 0, nic = 0, actual_cost = 0)
  )
  series <- measure_series(rows, params$measure)
  top <- fetches$practice_top_drugs(params$id, params$months, params$measure, export_rows + 1L,
                                    NULL)
  list(
    profile = where, chart = series_chart(series, params$measure),
    table = top_drugs_export(top, params$measure)
  )
}

# A drug's totals by NHS region, as the Region view draws them, and their
# shares of England's total
region_export <- function(params, fetches) {
  rows <- fetches$region_comparison(params$level, params$id, params$months, params$measure)
  if (nrow(rows) == 0L || all(is.na(rows$value))) {
    return(list(message = no_rows_text(params, params$measure, params$months)))
  }
  rows <- fill_regions(rows, fetches$regions())
  shares <- region_shares(rows)
  total <- sum(rows$value, na.rm = TRUE)
  chart <- NULL
  if (has_regional(rows)) {
    regional <- rows[in_region(rows) & !is.na(rows$value), ]
    # In words as the view says it, the regions in its order
    alt <- bars_alt(regional$region_name, regional$value, params$measure)
    # Office draws the first category at the bottom: the largest goes on top,
    # and ties keep the view's order, as the table beside it shows them
    regional <- regional[rev(order(-regional$value)), ]
    chart <- list(
      type = "bar", labels = regional$region_name, values = regional$value, alt = alt
    )
  }
  table <- export_table(
    "By region",
    data.frame(
      region = c(shares$region, "England"), value = c(shares$value, total),
      share = c(shares$share, if (total > 0) 1 else NA_real_)
    ),
    c("Region", measure_label(params$measure), "Share of England"),
    c("text", params$measure, "share")
  )
  table$total <- TRUE
  list(
    chart = chart, table = table,
    footnote = if (any(!in_region(rows))) {
      paste(
        "Prescriptions under the national unidentified prescriber code have no NHS region:",
        "they count in England's total only."
      )
    }
  )
}

# A chemical substance's presentations, most items first as the view sorts
# them, at most export_rows of them
presentations_export <- function(rows) {
  shown <- utils::head(rows, export_rows)
  caption <- if (nrow(rows) > export_rows) {
    paste0(
      "Presentations: the ", export_rows, " with the most items, of ", format_number(nrow(rows))
    )
  } else {
    "Presentations"
  }
  export_table(
    caption,
    data.frame(
      presentation = shown$bnf_description, code = shown$bnf_code,
      kind = brand_or_generic(shown$is_generic), items = shown$items,
      total_quantity = shown$total_quantity, adq_usage = shown$adq_usage, nic = shown$nic,
      actual_cost = shown$actual_cost
    ),
    c(
      "Presentation", "BNF code", "Brand or generic", "Items", "Quantity", "ADQ usage",
      "Net ingredient cost", "Actual cost"
    ),
    c("text", "text", "text", "items", "total_quantity", "adq_usage", "nic", "actual_cost")
  )
}

# A practice's first export_rows drugs by the measure, as the view's first
# page, with whether there are more
top_drugs_export <- function(rows, by) {
  more <- nrow(rows) > export_rows
  shown <- utils::head(rows, export_rows)
  label <- tolower(measure_label(by))
  export_table(
    if (more) paste0("Top ", export_rows, " drugs by ", label) else paste("Top drugs by", label),
    data.frame(
      rank = seq_len(nrow(shown)), presentation = shown$bnf_description, code = shown$bnf_code,
      kind = brand_or_generic(shown$is_generic), items = shown$items,
      adq_usage = shown$adq_usage, nic = shown$nic, actual_cost = shown$actual_cost
    ),
    c(
      "#", "Presentation", "BNF code", "Brand or generic", "Items", "ADQ usage",
      "Net ingredient cost", "Actual cost"
    ),
    c("count", "text", "text", "text", "items", "adq_usage", "nic", "actual_cost")
  )
}

export_table <- function(caption, data, labels, kinds) {
  list(caption = caption, data = data, labels = labels, kinds = kinds, total = FALSE)
}

# A monthly series as a line chart
series_chart <- function(rows, measure) {
  list(
    type = "line", labels = format_month(rows$year_month), values = rows$value,
    alt = series_alt(rows, measure)
  )
}

# A measure's label, as the views name it
measure_label <- function(measure) {
  info <- measure_info()
  info$label[match(measure, info$measure)]
}

# A practice's address, ICB and region, and the months it prescribed in, as
# the Practice view shows them
profile_text <- function(profile) {
  practice <- profile[1L, ]
  address <- c(practice$address, practice$postcode)
  address <- address[!is.na(address) & nzchar(address)]
  paste(c(
    if (length(address) > 0L) paste(address, collapse = ", "),
    practice$icb_name, practice$region_name,
    paste("prescribing", format_month_range(practice$first_seen, practice$last_seen))
  ), collapse = " \u00b7 ")
}

# A table's values as text, as the app writes them
table_text <- function(table) {
  data <- table$data
  for (j in seq_along(data)) {
    kind <- table$kinds[[j]]
    x <- data[[j]]
    data[[j]] <- switch(kind,
      text = ifelse(is.na(x), "", as.character(x)),
      count = format_number(x),
      share = ifelse(is.na(x), "\u2013", paste0(format_number(100 * x, digits = 1L), "%")),
      format_measure(x, kind)
    )
  }
  data
}

#' An item's chart as a native Office chart
#'
#' @param chart An item's `chart`, from [export_items()].
#' @param measure The item's measure.
#' @param data The chart's data, or `NULL` to make it from `chart`: in Excel,
#'   the cells of the workbook that hold it, as [openxlsx2::wb_data()] gives
#'   them, with the columns "Month" or "Region" and the measure's label.
#' @return An mschart chart: a line by month, or bars by region, in the
#'   exports' mark colour, the app's charts' own, with the measure's label as
#'   the series' name and its title on the values' axis.
#' @noRd
export_chart <- function(chart, measure, data = NULL) {
  label <- measure_label(measure)
  line <- identical(chart$type, "line")
  category <- chart_category(chart)
  if (is.null(data)) {
    data <- data.frame(factor(chart$labels, levels = unique(chart$labels)), chart$values)
    names(data) <- c(category, label)
  }
  graph <- if (line) {
    mschart::ms_linechart(data, x = category, y = label)
  } else {
    mschart::ms_barchart(data, x = category, y = label)
  }
  named <- function(value) structure(value, names = label)
  colours <- export_palette()
  mark <- named(colours[["mark"]])
  graph <- mschart::chart_data_fill(graph, values = mark)
  graph <- mschart::chart_data_stroke(graph, values = mark)
  # Its data labels, which it does not show, in the theme's font too
  graph <- mschart::chart_labels_text(
    graph, values = theme_text(color = colours[["text"]], font.size = 10)
  )
  if (line) {
    graph <- mschart::chart_settings(graph, style = "lineMarker")
    graph <- mschart::chart_data_line_width(graph, values = named(2.25))
    graph <- mschart::chart_data_symbol(graph, values = named("circle"))
    graph <- mschart::chart_data_size(graph, values = named(7))
    # Straight lines between the months, as the view draws them: mschart
    # smooths a line by default, which overshoots its points
    graph <- mschart::chart_data_smooth(graph, values = named(0))
  } else {
    graph <- mschart::chart_settings(graph, dir = "horizontal", gap_width = 60)
  }
  axis <- export_axis(chart$values, measure)
  graph <- mschart::chart_ax_y(
    graph, num_fmt = axis$format, limit_min = 0, major_unit = axis$unit
  )
  graph <- mschart::chart_labels(graph, title = NULL, xlab = NULL, ylab = measure_title(measure))
  graph <- mschart::set_theme(graph, prexp_mschart_theme())
  # The values' axis of bars across runs along the bottom: its title reads
  # across too. After set_theme(), which replaces the whole theme.
  if (!line) {
    graph <- mschart::chart_theme(graph, title_y_rot = 0)
  }
  graph
}

# The name of a chart's categories, its data's first column
chart_category <- function(chart) {
  if (identical(chart$type, "line")) "Month" else "Region"
}

# The values' axis of an export's chart as the view draws it: the step of
# its breaks (axis_breaks()) as the major unit, so that items are counted in
# whole numbers, and the decimals that step needs, two for pounds, so that
# no two labels are the same. The unit is text: mschart writes 300000 as
# "3e+05". No unit leaves Office's own.
export_axis <- function(values, measure) {
  top <- max(c(0, values), na.rm = TRUE)
  breaks <- if (top > 0) axis_breaks(measure)(c(0, top)) else numeric()
  unit <- if (length(breaks) > 1L) breaks[[2]] - breaks[[1]]
  decimals <- 0L
  if (!is.null(unit)) {
    while (decimals < 6L && abs(unit * 10^decimals - round(unit * 10^decimals)) > 1e-9) {
      decimals <- decimals + 1L
    }
  }
  pounds <- measure %in% c("nic", "actual_cost")
  if (pounds && decimals > 0L) {
    decimals <- max(decimals, 2L)
  }
  list(
    unit = if (!is.null(unit)) format(unit, scientific = FALSE, trim = TRUE),
    format = paste0(
      if (pounds) "\u00a3", "#,##0", if (decimals > 0L) paste0(".", strrep("0", decimals))
    )
  )
}

#' How an item's table is laid out
#'
#' Each column is as wide as its widest value or name, measured as the
#' exports' text is (export_text_width()), with a point of room; the names
#' and a total are measured in bold, as export_flextable() draws them. When
#' that is wider than `width`, the widest column of text, such as the
#' presentations' names, is narrowed to fit, down to an inch and a half, and
#' its values wrap at their spaces (text_lines()); each row is then as high
#' as its most lines.
#'
#' @param table An item's `table`, from [export_items()].
#' @param size The font size, in points.
#' @param width The most the table may be wide, in inches.
#' @return A list: `widths`, the columns', and `heights`, the body rows', and
#'   `header`, the header row's, in inches.
#' @noRd
table_layout <- function(table, size, width) {
  text <- table_text(table)
  n <- nrow(text)
  # A cell's margins: 4 points each side
  pad <- 8 / 72
  # A total is drawn in bold (export_flextable()), whose commas and full
  # stops are wider than the regular weight's in IBM Plex Sans: measured in
  # the regular weight, a total of a billion could wrap
  bold <- isTRUE(table$total) && n > 0L
  measured <- export_text_width(unlist(text, use.names = FALSE), size)
  cells <- lapply(seq_along(text), function(j) measured[(j - 1L) * n + seq_len(n)])
  if (bold) {
    last <- export_text_width(unlist(text[n, ], use.names = FALSE), size, "bold")
    for (j in seq_along(cells)) {
      cells[[j]][[n]] <- last[[j]]
    }
  }
  names <- export_text_width(table$labels, size, "bold")
  widths <- vapply(seq_along(text), function(j) {
    max(c(cells[[j]], names[[j]])) + pad + export_room
  }, 1)
  over <- sum(widths) - width
  if (over > 0) {
    texts <- which(table$kinds == "text")
    if (length(texts) > 0L) {
      wide <- texts[which.max(widths[texts])]
      widths[wide] <- max(widths[wide] - over, 1.5)
    }
    widths <- widths * min(1, width / sum(widths))
  }
  line <- size * export_line / 72
  # The lines of a column's values, or of its name, in its width
  lines <- function(j, strings, weight = "normal") {
    text_lines(strings, size, widths[[j]] - pad, weight)
  }
  rows <- if (n == 0L) {
    numeric()
  } else {
    counts <- vapply(seq_along(text), function(j) {
      c(lines(j, text[[j]][seq_len(n - bold)]), if (bold) lines(j, text[[j]][[n]], "bold"))
    }, numeric(n))
    apply(matrix(counts, nrow = n), 1L, max)
  }
  header <- max(vapply(seq_along(text), function(j) lines(j, table$labels[[j]], "bold"), 1))
  # flextable writes the 1 pt top and bottom padding twice: as the cell's
  # margins and as the paragraph's space before and after
  list(widths = widths, heights = rows * line + 4 / 72, header = header * line + 4 / 72)
}

#' An item's table cut into pages that each fit a height
#'
#' As few pages as hold the rows, filled evenly: each as full as the least
#' height that needs no more pages, rather than all full but the last, which
#' could hold a row or two.
#'
#' @param layout The table's layout, from [table_layout()].
#' @param height The height a page holds, in inches, its header included.
#' @return A list of row numbers, one element per page.
#' @noRd
table_pages <- function(layout, height) {
  n <- length(layout$heights)
  if (n == 0L) {
    return(list())
  }
  # The rows in order, a page filled up to `height` before the next
  fill <- function(height) {
    pages <- list()
    first <- 1L
    used <- layout$header
    for (i in seq_len(n)) {
      if (i > first && used + layout$heights[[i]] > height) {
        pages <- c(pages, list(first:(i - 1L)))
        first <- i
        used <- layout$header
      }
      used <- used + layout$heights[[i]]
    }
    c(pages, list(first:n))
  }
  pages <- fill(height)
  # Filling in order makes the fewest pages; the least height that makes no
  # more, by bisection, fills them evenly
  if (length(pages) > 1L) {
    low <- min(height, layout$header + max(layout$heights))
    high <- height
    for (step in 1:30) {
      mid <- (low + high) / 2
      if (length(fill(mid)) > length(pages)) low <- mid else high <- mid
    }
    pages <- fill(high)
  }
  pages
}

#' Rows of an item's table as a flextable
#'
#' @param table An item's `table`, from [export_items()].
#' @param size The font size, in points.
#' @param layout The table's layout at that size, from [table_layout()].
#' @param rows The rows to show.
#' @return A flextable: the values written as the app writes them, in the
#'   theme's font and the text colour, numbers right-aligned; a rule in the
#'   text colour under the header and a light one under each row, and a
#'   total in bold over a rule in the text colour (export_palette()).
#' @noRd
export_flextable <- function(table, size, layout, rows = seq_len(nrow(table$data))) {
  data <- table_text(table)[rows, , drop = FALSE]
  colours <- export_palette()
  rule <- officer::fp_border(color = colours[["rule"]], width = 1)
  ft <- flextable::flextable(data)
  ft <- flextable::set_header_labels(
    ft, values = structure(as.list(table$labels), names = names(data))
  )
  ft <- flextable::border_remove(ft)
  # The theme's body font, by reference (theme_text()), which flextable
  # writes for every script
  ft <- flextable::font(ft, fontname = "+mn-lt", part = "all")
  ft <- flextable::fontsize(ft, size = size, part = "all")
  ft <- flextable::color(ft, color = colours[["text"]], part = "all")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::hline_bottom(ft, border = rule, part = "header")
  if (nrow(data) > 0L) {
    ft <- flextable::hline(
      ft, border = officer::fp_border(color = colours[["row_rule"]], width = 0.5), part = "body"
    )
  }
  numbers <- which(table$kinds != "text")
  if (length(numbers) > 0L) {
    ft <- flextable::align(ft, j = numbers, align = "right", part = "all")
  }
  if (isTRUE(table$total) && max(rows) == nrow(table$data)) {
    total <- nrow(data)
    ft <- flextable::bold(ft, i = total, part = "body")
    # Its rule: under the row above, or the header's when it is alone
    if (total > 1L) {
      ft <- flextable::hline(ft, i = total - 1L, border = rule, part = "body")
    }
  }
  ft <- flextable::padding(
    ft, padding.top = 1, padding.bottom = 1, padding.left = 4, padding.right = 4, part = "all"
  )
  # The layout's heights: else every row keeps flextable's 0.25 inch, which
  # PowerPoint draws as the least a row takes
  ft <- flextable::height(ft, height = layout$header, part = "header")
  ft <- flextable::height(ft, height = layout$heights[rows], part = "body")
  flextable::width(ft, width = layout$widths)
}

#' The widths of strings in the exports' text
#'
#' Each string's width in IBM Plex Sans, the font the exports name, which
#' Microsoft 365 draws from its cloud fonts, and in Arial, for an office
#' suite without Plex that draws a sans of its own in its place, and the
#' wider of the two, so that the text fits in either.
#'
#' @param strings The strings.
#' @param size The font size, in points.
#' @param weight `"normal"` or `"bold"`.
#' @return Their widths, in inches.
#' @noRd
export_text_width <- function(strings, size, weight = "normal") {
  do.call(pmax, unname(font_widths(strings, size, weight)))
}

# Each string's width in each font the exports' text is measured in
# (export_measure_fonts), in inches: the sum of its glyphs' advances at their
# design widths, as Office lays text out, without kerning, which Office
# applies only from 12 points and which only narrows text. IBM Plex Sans in
# bold is the app's variable font at its bold weight. A list of the fonts'.
font_widths <- function(strings, size, weight = "normal") {
  use_export_font()
  strings <- as.character(strings)
  strings[is.na(strings)] <- ""
  chars <- strsplit(strings, "", fixed = TRUE)
  glyphs <- unique(unlist(chars))
  fonts <- stats::setNames(nm = export_measure_fonts)
  if (length(glyphs) == 0L) {
    return(lapply(fonts, function(family) numeric(length(strings))))
  }
  advances <- lapply(fonts, function(family) glyph_advances(glyphs, family, size, weight))
  # A glyph one font lacks (the app's IBM Plex Sans is a Latin subset) takes
  # the other's width; one neither has (Chinese, emoji) takes an em, as
  # Office draws it from a font of its own that has it
  widest <- do.call(pmax, c(unname(advances), na.rm = TRUE))
  widest[is.na(widest)] <- size
  lapply(advances, function(advance) {
    advance[is.na(advance)] <- widest[is.na(advance)]
    vapply(chars, function(x) sum(advance[match(x, glyphs)]), 1, USE.NAMES = FALSE) / 72
  })
}

# Glyphs' advances in a font, in points, at a resolution at which hinting
# does not round them, kept for the process: a report measures the same
# glyphs many times. NA for a glyph the font does not have, for which
# glyph_info() gives its .notdef's advance, and which font_widths() measures
# otherwise. glyph_info() sets the weight on the face it keeps of a variable
# font, which the charts measure with too: a face set to another weight is
# set back to its regular one.
glyph_advances <- function(glyphs, family, size, weight) {
  if (is.null(chart_state$advances)) {
    chart_state$advances <- list()
  }
  key <- paste(family, weight, size)
  known <- chart_state$advances[[key]]
  missing <- setdiff(glyphs, names(known))
  if (length(missing) > 0L) {
    if (!identical(weight, "normal")) {
      on.exit(systemfonts::glyph_info(" ", family = family, size = size), add = TRUE)
    }
    info <- systemfonts::glyph_info(
      missing, family = family, weight = weight, size = size, res = 7200
    )
    # Index 0 is the font's .notdef: the glyph is not in the font
    advance <- ifelse(info$index == 0L, NA_real_, info$x_advance / 100)
    known <- c(known, stats::setNames(advance, missing))
    chart_state$advances[[key]] <- known
  }
  unname(known[glyphs])
}

# A point of room on each line of the exports' text: a line measured to fit
# its box exactly could wrap in Office, were its own rounding a hair wider
export_room <- 1 / 72

# The height of a line of the exports' text, in ems: PowerPoint lays out a
# single-spaced line at 1.2 times the font's size whatever the font, Arial,
# Calibri, Segoe UI and IBM Plex Sans alike, though Plex's own ascent and
# descent make 1.3 em. Here rather than in theme.R, as fct_export_pptx.R's
# constants need it first.
export_line <- 1.2

#' How many lines paragraphs take, wrapped at spaces as Office wraps them
#'
#' Each paragraph is wrapped in each font the exports' text is measured in
#' (font_widths()), and takes the more lines of the two, so that it fits in
#' either. A line holds what fits in its box with a point of room
#' (export_room); a word wider than that breaks across lines.
#'
#' @param lines The paragraphs.
#' @param size The font size, in points.
#' @param width The width the text has, in inches.
#' @param weight `"normal"` or `"bold"`.
#' @return The lines each paragraph takes.
#' @noRd
text_lines <- function(lines, size, width, weight = "normal") {
  words <- lapply(strsplit(as.character(lines), " ", fixed = TRUE), function(w) w[nzchar(w)])
  n <- lengths(words)
  before <- cumsum(n) - n
  spaces <- font_widths(" ", size, weight)
  measured <- font_widths(unlist(words), size, weight)
  counts <- lapply(names(measured), function(family) {
    vapply(seq_along(words), function(k) {
      wrapped_lines(
        measured[[family]][before[[k]] + seq_len(n[[k]])], spaces[[family]], width - export_room
      )
    }, 1L)
  })
  do.call(pmax, unname(counts))
}

# The lines words of these widths take, with spaces of this width between
# them, in a line this wide: a word goes on the next line when it does not
# fit, and one wider than a line breaks across lines. A little room for
# rounding: a value measured to fill the line fits it.
wrapped_lines <- function(widths, space, room) {
  count <- 1L
  used <- 0
  for (w in widths) {
    gap <- if (used > 0) space else 0
    if (used > 0 && used + gap + w > room + 1e-9) {
      count <- count + 1L
      used <- 0
      gap <- 0
    }
    if (w > room + 1e-9) {
      more <- ceiling(w / room - 1e-9) - 1L
      count <- count + as.integer(more)
      used <- w - more * room
    } else {
      used <- used + gap + w
    }
  }
  count
}

# What goes under an item: that a link moved its months into the window, and
# its note, a paragraph per line
item_note_lines <- function(item) {
  lines <- character()
  if (isTRUE(item$clamped)) {
    lines <- "Its months were moved into the data window when the report's link was opened."
  }
  if (nzchar(item$note)) {
    note <- strsplit(item$note, "\n", fixed = TRUE)[[1]]
    note[1] <- paste("Note:", note[1])
    lines <- c(lines, note)
  }
  lines
}

#' The methods, cut into pages
#'
#' Each section starts a page, and a long one goes on over more: each block
#' is measured as it wraps in the box at 12 points, with the space after it,
#' and a page holds what fits, as a slide does not grow to fit its text.
#'
#' @param sections The methods' sections, as [methods_content()] gives them.
#' @param height The box's height, in inches.
#' @return A list of pages, each a list of `title` ("Methods: " and the
#'   section's, "(continued)" after its first page) and `blocks`, each a list
#'   of `kind` (`"text"`, `"point"` or `"link"`), `text`, and `term` (a point's,
#'   or `NULL`) or `url` (a link's).
#' @noRd
methods_pages <- function(sections, height = 5.5) {
  size <- 12
  room <- height - 0.1
  pages <- list()
  for (section in sections) {
    blocks <- c(
      lapply(section$text, function(text) list(kind = "text", text = text)),
      lapply(section$points, function(point) {
        list(kind = "point", text = point$text, term = if (!is.na(point$term)) point$term)
      }),
      lapply(section$links, function(link) list(kind = "link", text = link$text, url = link$url))
    )
    # A point's bullet and bold term are a little wider than measured: a
    # narrower box for them
    heights <- vapply(blocks, function(block) {
      text <- if (identical(block$kind, "point")) {
        paste(c("\u2022", if (!is.null(block$term)) paste0(block$term, "."), block$text),
              collapse = " ")
      } else {
        block$text
      }
      width <- pptx_width - 0.2 - if (identical(block$kind, "point")) 0.4 else 0
      text_lines(text, size, width) * size * export_line / 72 + 6 / 72
    }, 1)
    page <- list()
    used <- 0
    part <- 1L
    for (i in seq_along(blocks)) {
      if (used + heights[[i]] > room && length(page) > 0L) {
        pages <- c(pages, list(list(title = methods_title(section$title, part), blocks = page)))
        page <- list()
        used <- 0
        part <- part + 1L
      }
      page <- c(page, list(blocks[[i]]))
      used <- used + heights[[i]]
    }
    pages <- c(pages, list(list(title = methods_title(section$title, part), blocks = page)))
  }
  pages
}

methods_title <- function(title, part) {
  paste0("Methods: ", title, if (part > 1L) " (continued)")
}
