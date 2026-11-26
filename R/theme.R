# The app's look (spec section 5.3): one colour-blind-safe palette and the
# system font stack, for the page here, for the charts (theme_prexp(), P4-02)
# and for the Office exports (P5-05).

#' The app's colours
#'
#' Okabe and Ito's palette, whose colours stay apart for the common colour
#' vision deficiencies. Black is left out: it is the text colour.
#'
#' The charts draw their marks in blue (5.2 to 1 on white) and mark a
#' selection in vermillion (3.9 to 1), above the 3 to 1 that WCAG asks of a
#' chart's marks; a selected mark also has a dark outline, since vermillion and
#' blue are only 1.3 to 1 apart. Orange, sky and yellow are under 3 to 1 on
#' white (2.3, 2.3 and 1.3): a chart that draws marks in them needs a second
#' cue, such as a label or a darker outline.
#'
#' @return A named character vector of hex colours, in the order charts use
#'   them.
#' @noRd
prexp_palette <- function() {
  c(
    blue = "#0072B2", orange = "#E69F00", green = "#009E73", vermillion = "#D55E00",
    sky = "#56B4E9", purple = "#CC79A7", yellow = "#F0E442"
  )
}

#' The ggplot2 theme of the app's charts
#'
#' A light theme in the charts' font, with no minor grid and no legend: each
#' chart shows one measure. Built once for each size and kept: building a
#' ggplot2 theme takes about a fifth of a chart's time, and it never changes.
#'
#' @param base_size The base font size, in points.
#' @return A ggplot2 theme.
#' @noRd
theme_prexp <- function(base_size = 12) {
  key <- paste0("theme_", base_size)
  if (is.null(chart_state[[key]])) {
    chart_state[[key]] <- ggplot2::theme_minimal(base_size = base_size, base_family = chart_font) +
      ggplot2::theme(
        panel.grid.minor = ggplot2::element_blank(),
        axis.title = ggplot2::element_text(colour = "#5A6470"),
        axis.text = ggplot2::element_text(colour = "#333333"),
        plot.title.position = "plot",
        legend.position = "none"
      )
  }
  chart_state[[key]]
}

# The charts' font. Browsers on every platform have Arial or a font with its
# metrics; ggiraph measures the text with a font installed where R runs, and
# names that font in the SVG. Where Arial is not installed, as in the
# containers, use_chart_font() registers Liberation Sans, which has Arial's
# metrics, under Arial's name.
chart_font <- "Arial"

use_chart_font <- function() {
  if (isTRUE(chart_state$font)) {
    return(invisible(chart_font))
  }
  installed <- systemfonts::system_fonts()
  known <- c(installed$family, systemfonts::registry_fonts()$family)
  liberation <- installed[installed$family == "Liberation Sans", c("path", "style")]
  if (!chart_font %in% known && nrow(liberation) > 0L) {
    path <- function(style) {
      found <- liberation$path[liberation$style == style]
      if (length(found) > 0L) found[1] else liberation$path[1]
    }
    systemfonts::register_font(
      chart_font,
      plain = path("Regular"), bold = path("Bold"), italic = path("Italic"),
      bolditalic = path("Bold Italic")
    )
  }
  chart_state$font <- TRUE
  invisible(chart_font)
}

# The fonts ggiraph gives its SVG device: the Liberation fonts, as girafe()
# makes them when given none, made once and kept. Making them registers the
# fonts and looks them up again, about 5 ms a chart.
chart_font_set <- function() {
  if (is.null(chart_state$font_set)) {
    chart_state$font_set <- gdtools::font_set_liberation()
  }
  chart_state$font_set
}

# What the charts make once and keep, for the process: the font registered,
# the themes and the font set
chart_state <- new.env(parent = emptyenv())

#' The app's Bootstrap theme
#'
#' Bootstrap 5 with bslib's "shiny" preset, its web fonts (Open Sans and
#' Source Code Pro) swapped for Bootstrap's system font stacks: each
#' platform's own interface font, so no font is downloaded. The palette's blue
#' is the primary colour and the navbar's; the navbar's tab names are white,
#' for contrast enough on that blue (WCAG AA: 4.5 to 1), and the open tab is
#' marked by its underline and weight.
#'
#' @return A [bslib::bs_theme()].
#' @noRd
prexp_theme <- function() {
  palette <- prexp_palette()
  bslib::bs_theme(
    version = 5,
    primary = palette[["blue"]],
    secondary = "#5A6470",
    success = palette[["green"]],
    warning = palette[["orange"]],
    danger = palette[["vermillion"]],
    info = palette[["sky"]],
    "navbar-bg" = palette[["blue"]],
    "navbar-light-color" = "#FFFFFF",
    "navbar-light-hover-color" = "#FFFFFF",
    "link-color" = palette[["blue"]],
    "font-family-base" = "var(--bs-font-sans-serif)",
    "font-family-monospace" = paste(
      "SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\",",
      "monospace"
    ),
    "web-font-path" = FALSE
  )
}

#' The theme of the exports' charts
#'
#' The look of [theme_prexp()] for the native Office charts that mschart
#' draws in the PowerPoint, Word and Excel exports (P5-05 to P5-07): the
#' charts' font, dark text with grey axis titles, a light grid on the values'
#' axis only, no borders and no legend, as each chart shows one measure. The
#' series takes the palette's blue on each chart (export_chart()).
#'
#' @return An mschart theme.
#' @noRd
prexp_mschart_theme <- function() {
  text <- function(size, colour = "#333333") {
    officer::fp_text(color = colour, font.size = size, font.family = chart_font)
  }
  none <- officer::fp_border(style = "none")
  mschart::mschart_theme(
    main_title = text(14),
    axis_title = text(11, "#5A6470"),
    axis_text = text(10),
    legend_text = text(10),
    grid_major_line_x = none,
    grid_major_line_y = officer::fp_border(color = "#E3E6E8", width = 0.75),
    grid_minor_line = none,
    axis_ticks = officer::fp_border(color = "#C8CCD0", width = 0.75),
    chart_border = none,
    plot_border = none,
    legend_position = "n"
  )
}
