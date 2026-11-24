# The chart builders (spec section 5.1; P4-02). Each takes the tibble a fetch
# returns, or one shaped like it, and returns a ggplot with interactive
# layers; render_girafe() turns it into the widget the views show. A builder
# stops on input with nothing to draw: the views check first and show their
# empty state instead.

#' @importFrom ggplot2 .data
NULL

#' A monthly series
#'
#' A line through the months with an interactive point for each, whose tooltip
#' shows the month and the value.
#'
#' @param data A tibble with `year_month`, `measure` and `value`, as
#'   [fetch_drug_series()] returns: one measure, one row per month.
#' @param months Optional: the first and last month asked for. A month in that
#'   range with no row had no prescribing, and is drawn at 0.
#' @return A ggplot.
#' @noRd
chart_series <- function(data, months = NULL) {
  check_chart_data(data, c("year_month", "measure", "value"))
  measure <- data$measure[1]
  if (!is.null(months)) {
    data <- fill_months(data, months)
  }
  data <- data[!is.na(data$value), ]
  if (nrow(data) == 0L) {
    no_chart(paste("no values of", measure, "to chart"))
  }
  data <- data[order(data$year_month), ]
  plot_data <- data.frame(
    month = as.Date(sprintf("%d01", data$year_month), "%Y%m%d"),
    value = data$value,
    tooltip = paste0(
      "<b>", format_month(data$year_month), "</b><br/>", value_words(data$value, measure)
    ),
    data_id = as.character(data$year_month)
  )
  colour <- prexp_palette()[["blue"]]
  # A line needs two months; one month is a point
  line <- if (nrow(plot_data) > 1L) ggplot2::geom_line(colour = colour, linewidth = 0.8)
  ggplot2::ggplot(plot_data, ggplot2::aes(x = .data$month, y = .data$value)) +
    line +
    ggiraph::geom_point_interactive(
      ggplot2::aes(tooltip = .data$tooltip, data_id = .data$data_id),
      colour = colour, size = 2.5
    ) +
    ggplot2::scale_x_date(
      breaks = plot_data$month, labels = format_month(data$year_month),
      guide = ggplot2::guide_axis(check.overlap = TRUE)
    ) +
    ggplot2::scale_y_continuous(
      labels = axis_labels(measure), limits = c(0, NA),
      expand = ggplot2::expansion(mult = c(0, 0.08))
    ) +
    ggplot2::labs(x = NULL, y = measure_title(measure)) +
    theme_prexp()
}

#' Horizontal bars, largest at the top
#'
#' One bar per row, with a tooltip and a `data_id` for click selection.
#'
#' @param data A tibble with `measure`, `value` and the label and id columns,
#'   as [fetch_region_comparison()] returns.
#' @param label,id The names of the columns that label each bar and identify
#'   it. A missing label shows the id.
#' @param width The most characters of a label on the axis; the tooltip has it
#'   whole.
#' @return A ggplot.
#' @noRd
chart_bars <- function(data, label = "region_name", id = "region_code", width = 40L) {
  check_chart_data(data, c(label, id, "measure", "value"))
  measure <- data$measure[1]
  data <- data[!is.na(data$value), ]
  if (nrow(data) == 0L) {
    no_chart(paste("no values of", measure, "to chart"))
  }
  ids <- as.character(data[[id]])
  labels <- ifelse(is.na(data[[label]]), ids, as.character(data[[label]]))
  plot_data <- data.frame(
    id = factor(ids, levels = ids[order(data$value, decreasing = FALSE)]),
    value = data$value,
    tooltip = paste0(
      "<b>", escape_html(labels), "</b><br/>", value_words(data$value, measure)
    ),
    data_id = ids
  )
  ggplot2::ggplot(plot_data, ggplot2::aes(x = .data$value, y = .data$id)) +
    ggiraph::geom_col_interactive(
      ggplot2::aes(tooltip = .data$tooltip, data_id = .data$data_id),
      fill = prexp_palette()[["blue"]], width = 0.7
    ) +
    ggplot2::scale_y_discrete(labels = structure(shorten(labels, width), names = ids)) +
    ggplot2::scale_x_continuous(
      labels = axis_labels(measure), expand = ggplot2::expansion(mult = c(0, 0.05))
    ) +
    ggplot2::labs(x = measure_title(measure), y = NULL) +
    theme_prexp() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
}

#' A practice's top drugs, as bars
#'
#' @param data A page of [fetch_practice_top_drugs()]: `presentation_id`,
#'   `bnf_description` and `total`.
#' @param by The measure the page is ranked by: `"items"`, `"nic"` or
#'   `"actual_cost"`.
#' @return A ggplot.
#' @noRd
chart_top_drugs <- function(data, by) {
  check_chart_data(data, c("presentation_id", "bnf_description", "total"))
  bars <- data.frame(
    label = data$bnf_description,
    id = data$presentation_id,
    measure = rep(by, nrow(data)),
    value = data$total
  )
  chart_bars(bars, label = "label", id = "id", width = 45L)
}

#' A chart as an interactive widget
#'
#' The one place for the girafe() options: hover, single selection, no
#' toolbar (so no save button), and a width that follows its container.
#'
#' @param p A ggplot from a chart builder.
#' @param height The chart's height in inches; the width follows the page.
#' @return A girafe htmlwidget.
#' @noRd
render_girafe <- function(p, height = 4) {
  use_chart_font()
  highlight <- prexp_palette()[["vermillion"]]
  ggiraph::girafe(
    ggobj = p,
    width_svg = 8,
    height_svg = height,
    fonts = list(sans = chart_font),
    options = list(
      ggiraph::opts_hover(css = "opacity:0.75;cursor:pointer;"),
      ggiraph::opts_selection(
        type = "single", only_shiny = TRUE,
        css = paste0("fill:", highlight, ";stroke:", highlight, ";")
      ),
      ggiraph::opts_toolbar(saveaspng = FALSE, hidden = c("selection", "zoom", "misc")),
      ggiraph::opts_sizing(rescale = TRUE, width = 1),
      ggiraph::opts_tooltip(
        use_fill = FALSE,
        css = paste(
          "background:#ffffff;color:#222222;border:1px solid #c8ccd0;padding:4px 8px;",
          "border-radius:4px;font-family:Arial,sans-serif;font-size:13px;"
        )
      )
    )
  )
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

# Every month from the first to the last, those without a row at 0
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

# A measure's axis title: its label, with its unit where it has one
measure_title <- function(measure) {
  info <- measure_info()
  row <- match(measure, info$measure)
  unit <- info$unit[row]
  paste0(info$label[row], if (unit %in% c("items", "")) "" else paste0(" (", unit, ")"))
}

# A value with its unit, for a tooltip: "1,234 items", "GBP 567.89"
value_words <- function(value, measure) {
  info <- measure_info()
  unit <- info$unit[match(measure, info$measure)]
  formatted <- format_measure(value, measure)
  if (measure %in% c("nic", "actual_cost")) formatted else paste(formatted, unit)
}

# Axis labels: whole pounds for the costs, whole numbers otherwise
axis_labels <- function(measure) {
  if (measure %in% c("nic", "actual_cost")) {
    function(x) format_pounds(x, digits = 0L, na = "")
  } else {
    function(x) format_number(x, digits = 0L, na = "")
  }
}

# Labels cut to `width` characters, with an ellipsis
shorten <- function(x, width) {
  long <- !is.na(x) & nchar(x) > width
  x[long] <- paste0(substr(x[long], 1L, width - 1L), "\u2026")
  x
}

# Text for HTML: drug and practice names can hold <, > and &
escape_html <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}
