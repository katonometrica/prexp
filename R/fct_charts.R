# The chart builders (spec section 5.1; P4-02). Each takes the tibble a fetch
# returns, or one shaped like it, and returns a ggplot with interactive
# layers; render_girafe() turns it into the widget the views show. A builder
# stops on input with nothing to draw, with an error of class
# prexp_empty_chart: the views check first and show their empty state instead.
#
# Each builder takes the width its chart is drawn at, in CSS pixels, and fits
# its axes to it: fewer month labels and shorter names on a phone. Each gives
# its chart a text alternative (labs(alt = ...)), which render_girafe() writes
# into the SVG for screen readers.

#' @importFrom ggplot2 .data
NULL

#' A monthly series
#'
#' A line through the months, with an interactive point for each month that
#' has a value; its tooltip gives the month and the value.
#'
#' @param data A tibble with `year_month`, `measure` and `value`, as
#'   [fetch_drug_series()] returns: one measure, one row per month.
#' @param months Optional: the first and last month asked for. A month in that
#'   range with no row had no prescribing, and is drawn at 0. A month with a
#'   row but no value (a presentation without an ADQ) breaks the line.
#' @param width The width the chart is drawn at, in CSS pixels.
#' @return A ggplot.
#' @noRd
chart_series <- function(data, months = NULL, width = 768) {
  check_chart_data(data, c("year_month", "measure", "value"))
  measure <- data$measure[1]
  # Before the fill: zeros for the months without prescribing would be no
  # values of a measure the drug does not have
  if (all(is.na(data$value))) {
    no_chart(paste("no values of", measure, "to chart"))
  }
  if (!is.null(months)) {
    data <- fill_months(data, months)
  }
  data <- data[order(data$year_month), ]
  plot_data <- data.frame(
    month = month_date(data$year_month),
    value = data$value,
    tooltip = paste0(format_month(data$year_month), ": ", value_words(data$value, measure)),
    data_id = as.character(data$year_month)
  )
  known <- plot_data[!is.na(plot_data$value), ]
  axis <- month_axis(data$year_month, most = max(3L, width %/% 64L))
  colour <- chart_colours()$mark
  # A line needs two months with values; it breaks at a month without one
  line <- if (nrow(known) > 1L) {
    ggplot2::geom_line(colour = colour, linewidth = 0.8, na.rm = TRUE)
  }
  ggplot2::ggplot(plot_data, ggplot2::aes(x = .data$month, y = .data$value)) +
    line +
    ggiraph::geom_point_interactive(
      ggplot2::aes(tooltip = .data$tooltip, data_id = .data$data_id),
      data = known, colour = colour, size = 2.5
    ) +
    ggplot2::scale_x_date(
      breaks = axis$breaks, labels = axis$labels, limits = range(plot_data$month)
    ) +
    ggplot2::scale_y_continuous(
      breaks = axis_breaks(measure), labels = axis_labels(measure), limits = c(0, NA),
      expand = ggplot2::expansion(mult = c(0, 0.08))
    ) +
    ggplot2::labs(x = NULL, y = measure_title(measure), alt = series_alt(data, measure)) +
    theme_prexp()
}

#' Horizontal bars, largest at the top
#'
#' One bar per row, with a tooltip and a `data_id` for click selection. Ties
#' keep the input's order, top down, as a table of the same rows shows them.
#'
#' @param data A tibble with `measure`, `value` and the label and id columns,
#'   as [fetch_region_comparison()] returns.
#' @param label,id The names of the columns that label each bar and identify
#'   it, one row per id. A missing label shows the id.
#' @param chars The most characters of a label on the axis, fewer on a narrow
#'   chart; the tooltip has it whole.
#' @param width The width the chart is drawn at, in CSS pixels.
#' @return A ggplot.
#' @noRd
chart_bars <- function(data, label = "region_name", id = "region_code", chars = 40L,
                       width = 768) {
  check_chart_data(data, c(label, id, "measure", "value"))
  if (anyDuplicated(data[[id]]) > 0L) {
    stop("A chart of bars needs one row per id.", call. = FALSE)
  }
  measure <- data$measure[1]
  data <- data[!is.na(data$value), ]
  if (nrow(data) == 0L) {
    no_chart(paste("no values of", measure, "to chart"))
  }
  ids <- as.character(data[[id]])
  labels <- ifelse(is.na(data[[label]]), ids, as.character(data[[label]]))
  plot_data <- data.frame(
    # The first level is drawn at the bottom
    id = factor(ids, levels = rev(ids[order(-data$value)])),
    value = data$value,
    tooltip = paste0(escape_html(labels), ": ", value_words(data$value, measure)),
    data_id = ids
  )
  # About 6.8 px a character, the names taking at most 40% of the width. In
  # IBM Plex Sans at the tick labels' 9.6 pt, drug names take 5.8 to 6.3 px a
  # character and names in capitals 7.2 to 7.5.
  fit <- max(12L, min(as.integer(chars), as.integer(width * 0.4 / 6.8)))
  ggplot2::ggplot(plot_data, ggplot2::aes(x = .data$value, y = .data$id)) +
    ggiraph::geom_col_interactive(
      ggplot2::aes(tooltip = .data$tooltip, data_id = .data$data_id),
      fill = chart_colours()$mark, width = 0.7
    ) +
    ggplot2::scale_y_discrete(labels = structure(shorten(labels, fit), names = ids)) +
    ggplot2::scale_x_continuous(
      breaks = axis_breaks(measure, n = if (width < 500) 3L else 5L),
      labels = axis_labels(measure, short = TRUE),
      expand = ggplot2::expansion(mult = c(0, 0.05))
    ) +
    ggplot2::labs(
      x = measure_title(measure), y = NULL, alt = bars_alt(labels, data$value, measure)
    ) +
    theme_bars()
}

# The bars' theme: theme_prexp() with no grid lines along the bars, built once
# and kept as theme_prexp() is
theme_bars <- function() {
  if (is.null(chart_state$theme_bars)) {
    chart_state$theme_bars <- theme_prexp() +
      ggplot2::theme(
        panel.grid.major.y = ggplot2::element_blank(),
        # Room on the right for half the last tick label, centred on a break
        # that can fall at the panel's edge: the canvas would cut the rest. The
        # labels are short ("16M", "GBP 12.5M"): in IBM Plex Sans, half the
        # widest a view's breaks give is 16.7 pt.
        plot.margin = ggplot2::margin(5.5, 18, 5.5, 5.5)
      )
  }
  chart_state$theme_bars
}

#' A practice's top drugs, as bars
#'
#' @param data A page of [fetch_practice_top_drugs()]: `presentation_id`,
#'   `bnf_description` and `total`.
#' @param by The measure the page is ranked by: `"items"`, `"nic"` or
#'   `"actual_cost"`.
#' @param width The width the chart is drawn at, in CSS pixels.
#' @return A ggplot.
#' @noRd
chart_top_drugs <- function(data, by, width = 768) {
  check_chart_data(data, c("presentation_id", "bnf_description", "total"))
  bars <- data.frame(
    label = data$bnf_description,
    id = data$presentation_id,
    measure = rep(by, nrow(data)),
    value = data$total
  )
  chart_bars(bars, label = "label", id = "id", chars = 45L, width = width)
}

#' A chart as an interactive widget
#'
#' The one place for the girafe() options: hover, single selection marked by
#' an outline as well as its colour (a selected point drawn larger, too), no
#' toolbar (so no save button). The chart is drawn at the size it is shown
#' at, so its text is the page's size on any screen, and shrinks to fit until
#' it is drawn again. The chart's text alternative becomes the SVG's
#' description, and `title` its name.
#'
#' The SVG has no background, so the card shows through, and is drawn in the
#' light theme's colours, which the page recolours for the theme shown
#' (chart_css()). The selection and the tooltip take the theme's colours from
#' the page's custom properties, the light theme's where those are missing.
#'
#' @param p A ggplot from a chart builder.
#' @param width,height The chart's size in CSS pixels: the width of the
#'   output it is shown in.
#' @param title The chart's name for screen readers, such as the view's title;
#'   `NULL` for none.
#' @return A girafe htmlwidget.
#' @noRd
render_girafe <- function(p, width = 768, height = 384, title = NULL) {
  use_chart_font()
  alt <- ggplot2::get_alt_text(p)
  ggiraph::girafe(
    ggobj = p,
    width_svg = width / 96,
    height_svg = height / 96,
    bg = "transparent",
    font_set = chart_font_set(),
    title = title,
    desc = if (nzchar(alt)) alt,
    options = list(
      ggiraph::opts_hover(css = "opacity:0.75;cursor:pointer;"),
      ggiraph::opts_selection(
        type = "single", only_shiny = TRUE,
        css = ggiraph::girafe_css(css = selection_css(), point = selected_point_css())
      ),
      ggiraph::opts_toolbar(saveaspng = FALSE, hidden = c("selection", "zoom", "misc")),
      ggiraph::opts_sizing(rescale = TRUE, width = 1),
      ggiraph::opts_tooltip(use_fill = FALSE, opacity = 1, css = tooltip_css())
    )
  )
}

# A selected mark: the gold, outlined in the text colour, as gold and the
# marks' blue are only 1.3 to 1.5:1 apart. A selected bar keeps the 2 px
# outline.
selection_css <- function() {
  light <- brand_tokens()$light
  paste0(
    "fill:", theme_var("chart-selected", light$chart_selected), ";",
    "stroke:", theme_var("chart-outline", light$chart_outline), ";stroke-width:2px;"
  )
}

# A selected point: a dot about 6 px wide would be mostly outline, and read
# as a dot of the text colour, so it is drawn 1.8 times larger, with the
# outline painted under the gold, which leaves a 1 px ring
selected_point_css <- function() {
  paste0(
    selection_css(),
    "paint-order:stroke;vector-effect:non-scaling-stroke;",
    "transform-box:fill-box;transform-origin:center;transform:scale(1.8);"
  )
}

# The tooltip: square and flat, in the page's font
tooltip_css <- function() {
  light <- brand_tokens()$light
  paste0(
    "background:", theme_var("chart-tip-bg", light$chart_tip_bg), ";",
    "color:", theme_var("chart-tip-text", light$chart_tip_text), ";",
    "border:1px solid ", theme_var("chart-tip-border", light$chart_tip_border), ";",
    "border-radius:0;box-shadow:none;padding:4px 8px;",
    "font-family:'IBM Plex Sans','Segoe UI',system-ui,sans-serif;font-size:13px;line-height:1.4;"
  )
}

# A custom property of the page's theme, with the light theme's value where
# the page has none
theme_var <- function(name, fallback) {
  paste0("var(--prexp-", name, ",", fallback, ")")
}

# The input has the columns the chart needs, and rows
check_chart_data <- function(data, columns) {
  if (!is.data.frame(data)) {
    stop("A chart needs a data frame.", call. = FALSE)
  }
  missing <- setdiff(columns, names(data))
  if (length(missing) > 0L) {
    stop("A chart needs the columns ", toString(missing), ".", call. = FALSE)
  }
  if (nrow(data) == 0L) {
    no_chart("no rows to chart")
  }
}

# Nothing to draw: an error of its own class, which the views never let reach
# the page, since they check for rows first
no_chart <- function(why) {
  stop(structure(
    class = c("prexp_empty_chart", "error", "condition"),
    list(message = paste0("Nothing to chart: ", why, "."), call = NULL)
  ))
}

# Every month from the first to the last: those without a row at 0, those with
# a row as they are
fill_months <- function(data, months) {
  all <- index_month(seq(month_index(as.integer(months[1])), month_index(as.integer(months[2]))))
  missing <- setdiff(all, data$year_month)
  if (length(missing) == 0L) {
    return(data)
  }
  zeros <- data[rep(1L, length(missing)), ]
  zeros$year_month <- missing
  zeros$value <- 0
  rbind(data, zeros)
}

# A month YYYYMM as the date of its first day
month_date <- function(ym) {
  as.Date(sprintf("%d01", as.integer(ym)), "%Y%m%d")
}

# The months an axis labels: every month, or every second (third, ...) month
# when there are more than `most`. Each is its abbreviation, with the year on
# a second line under the first labelled month and the first of each year
month_axis <- function(ym, most = 12L) {
  ym <- sort(unique(as.integer(ym)))
  ym <- ym[seq(1L, length(ym), by = ceiling(length(ym) / most))]
  year <- ym %/% 100L
  new_year <- c(TRUE, year[-1L] != year[-length(year)])
  abb <- month.abb[ym %% 100L]
  list(breaks = month_date(ym), labels = ifelse(new_year, paste0(abb, "\n", year), abb))
}

# A measure's axis title: its label, with its unit where it has one
measure_title <- function(measure) {
  info <- measure_info()
  row <- match(measure, info$measure)
  unit <- info$unit[row]
  paste0(info$label[row], if (unit %in% c("items", "")) "" else paste0(" (", unit, ")"))
}

# A value with its unit, for a tooltip: "1,234 items", "1 item", "GBP 567.89"
value_words <- function(value, measure) {
  formatted <- format_measure(value, measure)
  if (measure %in% c("nic", "actual_cost")) {
    return(formatted)
  }
  info <- measure_info()
  unit <- info$unit[match(measure, info$measure)]
  one <- c(items = "item", units = "unit", ADQs = "ADQ")[[unit]]
  paste(formatted, ifelse(formatted == "1", one, unit))
}

# A series in words, for screen readers: its months, and its first, last,
# highest and lowest values
series_alt <- function(data, measure) {
  data <- data[!is.na(data$value), ]
  words <- function(row) {
    paste(value_words(row$value, measure), "in", format_month(row$year_month))
  }
  label <- measure_info()$label[match(measure, measure_info()$measure)]
  first <- data[1L, ]
  last <- data[nrow(data), ]
  paste0(
    label, " by month, ", format_month_range(first$year_month, last$year_month), ": ",
    words(first), " first and ", words(last), " last; highest ",
    words(data[which.max(data$value), ]), ", lowest ", words(data[which.min(data$value), ]), "."
  )
}

# Bars in words, for screen readers: how many, and the largest and smallest
bars_alt <- function(labels, values, measure) {
  words <- function(i) paste0(labels[i], ", ", value_words(values[i], measure))
  label <- measure_info()$label[match(measure, measure_info()$measure)]
  paste0(
    label, ", ", length(values), if (length(values) == 1L) " bar" else " bars",
    ": largest ", words(which.max(values)), "; smallest ", words(which.min(values)), "."
  )
}

# Axis labels with thousands separators, pounds for the costs, and as many
# decimals as the breaks need to differ (scales picks them): on a small range,
# labels rounded to whole numbers would repeat. `short` writes millions as
# "16M", for an axis across a narrow chart.
axis_labels <- function(measure, short = FALSE) {
  cut <- if (short) scales::cut_short_scale()
  if (measure %in% c("nic", "actual_cost")) {
    scales::label_currency(prefix = "\u00a3", big.mark = ",", scale_cut = cut)
  } else {
    scales::label_number(big.mark = ",", scale_cut = cut)
  }
}

# Axis breaks, about `n` of them: whole numbers only for items, which are
# counted whole
axis_breaks <- function(measure, n = 5L) {
  extended <- scales::breaks_extended(n = n)
  if (measure == "items") {
    function(limits) {
      breaks <- extended(limits)
      breaks[breaks == round(breaks)]
    }
  } else {
    extended
  }
}

# Labels cut to `width` characters with an ellipsis. Names that would cut to
# the same label are cut in the middle instead, keeping the endings that tell
# them apart.
shorten <- function(x, width) {
  long <- !is.na(x) & nchar(x) > width
  out <- x
  out[long] <- paste0(substr(x[long], 1L, width - 1L), "\u2026")
  same <- long & stats::ave(x, out, FUN = function(v) length(unique(v))) != "1"
  if (any(same)) {
    head <- (width - 1L) %/% 2L
    n <- nchar(x[same])
    out[same] <- paste0(
      substr(x[same], 1L, head), "\u2026", substr(x[same], n - (width - 1L - head) + 1L, n)
    )
  }
  out
}

# Text for HTML: drug and practice names can hold <, > and &
escape_html <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}
