# The app's look (spec section 5.3): one colour-blind-safe palette and the
# system font stack, for the page here, for the charts (theme_prexp(), P4-02)
# and for the Office exports (P5-05).

#' The app's colours
#'
#' Okabe and Ito's palette, whose colours stay apart for the common colour
#' vision deficiencies. Black is left out: it is the text colour.
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

#' The app's Bootstrap theme
#'
#' Bootstrap 5, whose default font is the system font stack (each platform's
#' own interface font, so no web font is loaded), with the palette's blue as
#' the primary colour.
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
    "link-color" = palette[["blue"]]
  )
}
