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
#'   palette's blue, with the measure's label as the series' name and its
#'   title on the values' axis.
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
  blue <- named(prexp_palette()[["blue"]])
  graph <- mschart::chart_data_fill(graph, values = blue)
  graph <- mschart::chart_data_stroke(graph, values = blue)
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
#' Each column is as wide as its widest value or name, measured in the
#' charts' font. When that is wider than `width`, the widest column of text,
#' such as the presentations' names, is narrowed to fit, down to an inch and
#' a half, and its values wrap; each row is then as high as its lines.
#'
#' @param table An item's `table`, from [export_items()].
#' @param size The font size, in points.
#' @param width The most the table may be wide, in inches.
#' @return A list: `widths`, the columns', and `heights`, the body rows', and
#'   `header`, the header row's, in inches.
#' @noRd
table_layout <- function(table, size, width) {
  text <- table_text(table)
  pad <- 8 / 72
  measure <- function(strings, weight = "normal") {
    if (length(strings) == 0L) {
      return(numeric())
    }
    systemfonts::string_width(strings, family = chart_font, size = size, weight = weight) / 72
  }
  cells <- lapply(text, measure)
  names <- measure(table$labels, weight = "bold")
  widths <- vapply(seq_along(text), function(j) max(c(cells[[j]], names[[j]])) + pad, 1)
  over <- sum(widths) - width
  if (over > 0) {
    texts <- which(table$kinds == "text")
    if (length(texts) > 0L) {
      wide <- texts[which.max(widths[texts])]
      widths[wide] <- max(widths[wide] - over, 1.5)
    }
    widths <- widths * min(1, width / sum(widths))
  }
  line <- size * 1.2 / 72
  # The widest value of a column fills it: a little room for rounding, so it
  # is not counted as wrapping
  lines <- function(measured) pmax(1, ceiling(measured / (widths - pad) - 1e-6))
  rows <- if (nrow(text) == 0L) {
    numeric()
  } else {
    apply(do.call(cbind, cells), 1L, function(row) max(lines(row)))
  }
  # flextable writes the 1 pt top and bottom padding twice: as the cell's
  # margins and as the paragraph's space before and after
  list(
    widths = widths, heights = rows * line + 4 / 72, header = max(lines(names)) * line + 4 / 72
  )
}

#' An item's table cut into pages that each fit a height
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

#' Rows of an item's table as a flextable
#'
#' @param table An item's `table`, from [export_items()].
#' @param size The font size, in points.
#' @param layout The table's layout at that size, from [table_layout()].
#' @param rows The rows to show.
#' @return A flextable: the values written as the app writes them, numbers
#'   right-aligned, every other row shaded, a total in bold.
#' @noRd
export_flextable <- function(table, size, layout, rows = seq_len(nrow(table$data))) {
  data <- table_text(table)[rows, , drop = FALSE]
  line <- officer::fp_border(color = "#5A6470", width = 1)
  ft <- flextable::flextable(data)
  ft <- flextable::set_header_labels(
    ft, values = structure(as.list(table$labels), names = names(data))
  )
  ft <- flextable::border_remove(ft)
  ft <- flextable::font(ft, fontname = chart_font, part = "all")
  ft <- flextable::fontsize(ft, size = size, part = "all")
  ft <- flextable::color(ft, color = "#222222", part = "all")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::hline_top(ft, border = line, part = "header")
  ft <- flextable::hline_bottom(ft, border = line, part = "header")
  numbers <- which(table$kinds != "text")
  if (length(numbers) > 0L) {
    ft <- flextable::align(ft, j = numbers, align = "right", part = "all")
  }
  if (nrow(data) >= 2L) {
    ft <- flextable::bg(ft, i = seq(2L, nrow(data), by = 2L), bg = "#F2F4F6", part = "body")
  }
  if (isTRUE(table$total) && max(rows) == nrow(table$data)) {
    ft <- flextable::bold(ft, i = nrow(data), part = "body")
    ft <- flextable::hline_bottom(ft, border = line, part = "body")
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

#' How many lines paragraphs take, wrapped at spaces as Office wraps them
#'
#' Each word is measured in the charts' font; a word wider than the box
#' breaks across lines.
#'
#' @param lines The paragraphs.
#' @param size The font size, in points.
#' @param width The width the text has, in inches.
#' @return The lines each paragraph takes.
#' @noRd
text_lines <- function(lines, size, width) {
  space <- systemfonts::string_width(" ", family = chart_font, size = size) / 72
  vapply(lines, function(line) {
    words <- strsplit(line, " ", fixed = TRUE)[[1]]
    words <- words[nzchar(words)]
    if (length(words) == 0L) {
      return(1L)
    }
    widths <- systemfonts::string_width(words, family = chart_font, size = size) / 72
    count <- 1L
    used <- 0
    for (w in widths) {
      gap <- if (used > 0) space else 0
      if (used > 0 && used + gap + w > width) {
        count <- count + 1L
        used <- 0
        gap <- 0
      }
      if (w > width) {
        more <- ceiling(w / width) - 1L
        count <- count + as.integer(more)
        used <- w - more * width
      } else {
        used <- used + gap + w
      }
    }
    count
  }, 1L, USE.NAMES = FALSE)
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
      text_lines(text, size, width) * size * 1.2 / 72 + 6 / 72
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
