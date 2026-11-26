# The app's look (spec section 5.3): KATONOMETRICA's, as its site
# katonometrica.com draws it. The site's styles.css gives the colours and
# fonts/fonts.css the type: IBM Plex Sans and Mono, served with the app
# (inst/app/www/fonts) and never fetched from elsewhere. Dark by default, with
# a light theme; corners square, surfaces flat, gold for what is active.
#
# One source for the colours: the token lists here. brand_css() writes them
# as the page's CSS custom properties, Bootstrap's colour modes and the
# charts' colours, and the tests check every pair's contrast against them.
# Where a site value falls short of WCAG AA the app uses a stronger one
# (brand_tokens()). The charts are drawn once, in the light theme's colours,
# which the page recolours for the dark theme (chart_css()). The Office
# exports take the light theme's colours and IBM Plex Sans too, at the end of
# this file: their palette, their templates' colour scheme and fonts, and the
# fonts their text is measured in.

#' The brand's colours, for the dark theme and the light one
#'
#' The site's tokens (styles.css), under the names the page's custom
#' properties take (`--prexp-` and the name, `_` as `-`), with the colours of
#' the charts' roles. Where the site's value fails WCAG AA the app departs
#' from it: borders of form controls at 3:1 or more against what they sit on
#' (the site's are 1.3 to 1.8:1); errors and successes at 4.5:1 or more on
#' every surface they sit on; and in light, a darker gold for the hover of
#' gold buttons (the site's #c9a84c is 2.2:1 under their text). Placeholders
#' take the secondary text colour, and `muted` marks disabled controls only:
#' #5a5650 in dark (2.6:1 on the page) and #9e9a94 in light (2.7:1). The
#' site's light `muted` is its secondary text colour, which makes a disabled
#' button look live.
#'
#' The charts (chart_colours()) mark their values in the brand's navy blue,
#' lighter in dark, and a selected mark in the gold, outlined in the text
#' colour; tick labels in the secondary text colour, axis titles in the text
#' colour, gridlines as faint as the borders.
#'
#' @return A list of two named lists of colours, `light` and `dark`: hex or
#'   `rgba()` strings.
#' @noRd
brand_tokens <- function() {
  light <- list(
    bg = "#FDFCFB", bg_alt = "#F7F5F2",
    surface = "rgba(0,0,0,0.05)", border = "rgba(0,0,0,0.12)",
    border_strong = "rgba(0,0,0,0.25)", control_border = "#858280",
    text = "#0b1222", text_secondary = "#5a5650", muted = "#9e9a94",
    accent = "#7d6523", accent_hover = "#5e4c1a", accent_subtle = "rgba(125,101,35,0.1)",
    on_accent = "#FDFCFB",
    success = "#166534", success_bg = "#dcfce7", error = "#b91c1c", error_bg = "#fee2e2",
    chart_mark = "#355695", chart_grid = "rgba(0,0,0,0.12)",
    chart_tip_bg = "#FDFCFB", chart_tip_border = "rgba(0,0,0,0.25)"
  )
  dark <- list(
    bg = "#0b1222", bg_alt = "#0f1730",
    surface = "rgba(200,195,185,0.04)", border = "rgba(200,195,185,0.08)",
    border_strong = "rgba(200,195,185,0.14)", control_border = "#706b63",
    text = "#e2dfd8", text_secondary = "#8b8579", muted = "#5a5650",
    accent = "#c9a84c", accent_hover = "#d4b65e", accent_subtle = "rgba(201,168,76,0.06)",
    on_accent = "#0b1222",
    success = "#4ade80", success_bg = "#2d6a4f", error = "#f87171", error_bg = "#9b2226",
    chart_mark = "#678ccf", chart_grid = "rgba(200,195,185,0.14)",
    chart_tip_bg = "#0f1730", chart_tip_border = "rgba(200,195,185,0.14)"
  )
  # The roles that take a colour the theme has already
  roles <- function(t) {
    c(t, list(
      chart_selected = t$accent, chart_outline = t$text, chart_tick = t$text_secondary,
      chart_title = t$text, chart_tip_text = t$text
    ))
  }
  list(light = roles(light), dark = roles(dark))
}

#' The colours the charts are drawn in
#'
#' Each role in a colour of its own, the light theme's, which the SVG keeps
#' and the page's CSS maps to the role's colour in the theme shown
#' (chart_css()): so no two roles may share one, and each must read on its
#' own where that CSS is missing. The gridlines' is the light border over the
#' light page, as the colour has to be opaque.
#'
#' @return A named list of hex colours: `mark`, `grid`, `tick` and `title`.
#' @noRd
chart_colours <- function() {
  light <- brand_tokens()$light
  list(
    mark = toupper(light$chart_mark),
    grid = toupper(blend(light$chart_grid, light$bg)),
    tick = toupper(light$chart_tick),
    title = toupper(light$chart_title)
  )
}

# A colour, hex or rgba(), laid over an opaque background, as a browser
# composites it: the hex of the result
blend <- function(colour, background) {
  under <- grDevices::col2rgb(background)[, 1L]
  parts <- regmatches(colour, regexec("^rgba\\(([^)]*)\\)$", colour))[[1L]]
  if (length(parts) == 0L) {
    return(colour)
  }
  values <- as.numeric(strsplit(parts[[2L]], ",", fixed = TRUE)[[1L]])
  alpha <- values[[4L]]
  mixed <- round(values[1:3] * alpha + under * (1 - alpha))
  grDevices::rgb(mixed[[1L]], mixed[[2L]], mixed[[3L]], maxColorValue = 255)
}

#' The brand's CSS: the themes' custom properties and the charts' colours
#'
#' For each theme, the tokens as custom properties (`--prexp-bg` and so on),
#' and Bootstrap's own properties set from them, which its colour modes
#' switch with `data-bs-theme` on the page's root: the light theme is the
#' root's, the dark one the attribute's, which the page's head sets before it
#' is drawn (theme_script()). Generated from brand_tokens(), so the page, the
#' charts and the tests read the same colours.
#'
#' @return One string of CSS.
#' @noRd
brand_css <- function() {
  tokens <- brand_tokens()
  paste(
    "/* Generated by brand_css() in R/theme.R from brand_tokens(): edit it there. */",
    theme_block(":root,\n[data-bs-theme=\"light\"]", "light", tokens$light),
    theme_block("[data-bs-theme=\"dark\"]", "dark", tokens$dark),
    chart_css(),
    sep = "\n"
  )
}

# One theme's custom properties
theme_block <- function(selector, scheme, t) {
  tokens <- vapply(names(t), function(name) {
    paste0("  --prexp-", gsub("_", "-", name, fixed = TRUE), ": ", t[[name]], ";")
  }, "")
  # Bootstrap's own, with their r, g, b where it has them
  bs <- c(
    "body-bg" = t$bg, "body-color" = t$text, "emphasis-color" = t$text,
    "secondary-color" = t$text_secondary, "tertiary-color" = t$text_secondary,
    "secondary-bg" = t$bg_alt, "tertiary-bg" = t$bg_alt, "heading-color" = t$text,
    "border-color" = t$border, "border-color-translucent" = t$border,
    "link-color" = t$accent, "link-hover-color" = t$accent_hover,
    "primary" = t$accent, "secondary" = t$text_secondary,
    "success" = t$success, "danger" = t$error, "code-color" = t$text,
    "highlight-color" = t$text, "highlight-bg" = t$accent_subtle
  )
  rgb <- c(
    "body-bg", "body-color", "emphasis-color", "secondary-color", "tertiary-color",
    "secondary-bg", "tertiary-bg", "link-color", "link-hover-color", "primary", "secondary",
    "success", "danger"
  )
  triples <- vapply(bs[rgb], function(colour) {
    paste(grDevices::col2rgb(colour)[, 1L], collapse = ", ")
  }, "")
  # Images in the theme's colours: a checked radio's dot, in the colour of
  # text on the gold, and a select's chevron, the site's filled one
  svg <- function(...) {
    paste0(
      "url(\"data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' ", ...,
      "%3c/svg%3e\")"
    )
  }
  colour <- function(x) sub("#", "%23", x, fixed = TRUE)
  dot <- svg("viewBox='-4 -4 8 8'%3e%3ccircle r='2' fill='", colour(t$on_accent), "'/%3e")
  chevron <- svg(
    "width='12' height='8' viewBox='0 0 12 8'%3e%3cpath fill='",
    colour(t$text_secondary), "' d='M1 1l5 5 5-5'/%3e"
  )
  paste0(
    selector, " {\n",
    "  color-scheme: ", scheme, ";\n",
    paste(tokens, collapse = "\n"), "\n",
    paste0("  --bs-", names(bs), ": ", bs, ";", collapse = "\n"), "\n",
    paste0("  --bs-", names(triples), "-rgb: ", triples, ";", collapse = "\n"), "\n",
    "  --prexp-radio-dot: ", dot, ";\n",
    "  --prexp-chevron: ", chevron, ";\n",
    "}"
  )
}

#' The charts' colours in the theme shown
#'
#' ggiraph writes each colour as an SVG attribute, which any CSS rule
#' overrides: one rule per role and attribute maps the role's drawn colour
#' (chart_colours()) to its custom property. The rules weigh nothing
#' (`:where()`), so ggiraph's own rules for a hovered or selected mark still
#' win.
#'
#' @return One string of CSS.
#' @noRd
chart_css <- function() {
  colours <- chart_colours()
  rule <- function(element, attribute, colour, role) {
    sprintf(
      ":where(.ggiraph-svg) :where(%s[%s=\"%s\" i]) { %s: var(--prexp-chart-%s); }",
      element, attribute, colour, attribute, role
    )
  }
  paste(
    "/* The charts: each role's drawn colour (chart_colours()) as the theme's */",
    rule("", "fill", colours$mark, "mark"),
    rule("", "stroke", colours$mark, "mark"),
    rule("", "stroke", colours$grid, "grid"),
    rule("text", "fill", colours$tick, "tick"),
    rule("text", "fill", colours$title, "title"),
    sep = "\n"
  )
}

#' The script that sets the theme before the page is drawn
#'
#' Dark, unless the visitor chose light before: the theme button
#' (inst/app/www/theme.js) keeps the choice in the browser's storage, under
#' `theme`, as katonometrica.com does. Storage can be blocked: the page is
#' then dark. Inline in the head, so the page never shows in the other theme
#' first.
#'
#' @return One string of JavaScript.
#' @noRd
theme_script <- function() {
  paste(
    "(function () {",
    "  var theme = 'dark';",
    "  try {",
    "    var saved = window.localStorage.getItem('theme');",
    "    if (saved === 'light' || saved === 'dark') { theme = saved; }",
    "  } catch (e) {}",
    "  document.documentElement.setAttribute('data-bs-theme', theme);",
    "})();",
    sep = "\n"
  )
}

#' The ggplot2 theme of the app's charts
#'
#' A light theme in the charts' font, on no background of its own, so the
#' card shows through, with no minor grid and no legend: each chart shows one
#' measure. Each role in its colour (chart_colours()). Built once for each
#' size and kept: building a ggplot2 theme takes about a fifth of a chart's
#' time, and it never changes.
#'
#' @param base_size The base font size, in points.
#' @return A ggplot2 theme.
#' @noRd
theme_prexp <- function(base_size = 12) {
  key <- paste0("theme_", base_size)
  if (is.null(chart_state[[key]])) {
    colours <- chart_colours()
    chart_state[[key]] <- ggplot2::theme_minimal(base_size = base_size, base_family = chart_font) +
      ggplot2::theme(
        plot.background = ggplot2::element_blank(),
        # One CSS pixel: 1 lwd at the size the chart is shown
        panel.grid.major = ggplot2::element_line(
          colour = colours$grid, linewidth = 1 / ggplot2::.pt
        ),
        panel.grid.minor = ggplot2::element_blank(),
        axis.title = ggplot2::element_text(colour = colours$title),
        axis.text = ggplot2::element_text(colour = colours$tick),
        plot.title.position = "plot",
        legend.position = "none"
      )
  }
  chart_state[[key]]
}

# The charts' font: the page's, IBM Plex Sans. ggiraph measures the text with
# a font R can find and names it in the SVG, which the browser draws with the
# page's own copy (inst/app/www/fonts). use_chart_font() registers that copy
# with systemfonts, so the text is measured with the very font it is drawn in,
# unless IBM Plex Sans is installed: then the installed font, with the same
# metrics, measures it.
chart_font <- "IBM Plex Sans"

use_chart_font <- function() {
  if (isTRUE(chart_state$font)) {
    return(invisible(chart_font))
  }
  path <- system.file("app", "www", "fonts", "ibm-plex-sans-var-latin.woff2", package = "prexp")
  if (!nzchar(path)) {
    stop("The charts' font, IBM Plex Sans, is missing from the package.", call. = FALSE)
  }
  # systemfonts will not register a name an installed font has
  if (!chart_font %in% systemfonts::system_fonts()$family) {
    systemfonts::register_font(chart_font, plain = path)
  }
  chart_state$font <- TRUE
  invisible(chart_font)
}

# The fonts ggiraph gives its SVG device: IBM Plex Sans for the text, made
# once and kept. girafe() reads a font set's fonts and its dependencies only.
# Given a font's name, gdtools::font_set() would copy its files to the user's
# cache and add them to the page with every chart; the page's own @font-face
# rules are their source, so the set starts empty and is given the name.
chart_font_set <- function() {
  if (is.null(chart_state$font_set)) {
    use_chart_font()
    set <- gdtools::font_set()
    set$sans <- chart_font
    set$dsvg_fonts <- list(sans = chart_font)
    chart_state$font_set <- set
  }
  chart_state$font_set
}

# What the charts make once and keep, for the process: the fonts registered,
# the themes and the font set; and the advances of the glyphs the exports'
# text is measured with (glyph_advances())
chart_state <- new.env(parent = emptyenv())

#' The app's Bootstrap theme
#'
#' Bootstrap 5 with bslib's "shiny" preset, in the brand's fonts, weights
#' and shapes: IBM Plex Sans and Mono (the page loads them, so the theme
#' fetches no web font), weights up to 600, the font's heaviest, corners
#' square and no shadows. Its colours are the light theme's; brand_css() sets
#' both themes' over them, and prexp.css styles the components from those.
#'
#' @return A [bslib::bs_theme()].
#' @noRd
prexp_theme <- function() {
  light <- brand_tokens()$light
  radius <- c(
    "border-radius", "border-radius-sm", "border-radius-lg", "border-radius-xl",
    "border-radius-xxl", "border-radius-pill", "card-border-radius",
    "form-check-input-border-radius"
  )
  do.call(bslib::bs_theme, c(
    list(
      version = 5,
      primary = light$accent,
      secondary = light$text_secondary,
      success = light$success,
      danger = light$error,
      info = light$text_secondary,
      warning = light$text_secondary,
      "link-color" = light$accent,
      "font-family-sans-serif" = "'IBM Plex Sans', 'Segoe UI', system-ui, sans-serif",
      "font-family-monospace" = "'IBM Plex Mono', Consolas, monospace",
      "font-family-base" = "var(--bs-font-sans-serif)",
      "web-font-path" = FALSE,
      "headings-font-weight" = 600,
      "font-weight-bold" = 600,
      "font-weight-bolder" = 600,
      "bslib-enable-shadows" = FALSE,
      "input-btn-focus-width" = 0
    ),
    stats::setNames(as.list(rep(0, length(radius))), radius)
  ))
}

#' The tables' look
#'
#' One reactable theme for every table, from the page's custom properties,
#' so it follows the theme shown: no background of its own, a rule between
#' rows, a stronger one under the header and over the footer, the row under
#' the pointer on the brand's surface, no stripes. A page button under the
#' pointer or the keyboard's focus takes the page's colour: on the surface
#' over a card, its secondary text and its gold would fall under 4.5:1.
#'
#' @return A [reactable::reactableTheme()].
#' @noRd
table_theme <- function() {
  reactable::reactableTheme(
    color = "var(--prexp-text)",
    backgroundColor = "transparent",
    borderColor = "var(--prexp-border)",
    highlightColor = "var(--prexp-surface)",
    cellPadding = "6px 10px",
    style = list(fontVariantNumeric = "tabular-nums", fontSize = "14px"),
    headerStyle = list(
      fontWeight = 600, color = "var(--prexp-text)",
      borderBottom = "1px solid var(--prexp-border-strong)"
    ),
    footerStyle = list(fontWeight = 600, borderTop = "1px solid var(--prexp-border-strong)"),
    paginationStyle = list(color = "var(--prexp-text-secondary)"),
    pageButtonStyle = list(borderRadius = 0),
    pageButtonHoverStyle = list(backgroundColor = "var(--prexp-bg)"),
    pageButtonActiveStyle = list(backgroundColor = "var(--prexp-bg)"),
    # The page shown, in the gold of what is active, and heavier
    pageButtonCurrentStyle = list(color = "var(--prexp-accent)", fontWeight = 600),
    selectStyle = list(
      backgroundColor = "var(--prexp-bg)", color = "var(--prexp-text)",
      border = "1px solid var(--prexp-control-border)", borderRadius = 0
    )
  )
}

# The Office exports' look (P5-05 to P5-07): the brand's light theme, which
# it keeps for print and daytime presentations, in IBM Plex Sans. An Office
# file cannot carry the font. The templates and the workbook name it as their
# theme's font, with IBM's classification of it, and the text takes the
# theme's font, so Office draws it in a sans of its own where Plex is not
# installed, most often Arial. The text is measured in both fonts, so that it
# fits in either (export_text_width()).

#' The exports' colours
#'
#' The light theme's (brand_tokens()), by role: the text; the secondary text
#' of summaries, captions, footnotes, the charts' tick labels and the maker's
#' wordmark; the charts' mark, the app's charts' own, so that an export shows
#' what the screen shows; links, which are underlined as well; the tables'
#' rules, in the text colour under a header and over a total, and the light
#' theme's strong border between rows; the charts' gridlines, the app's
#' charts' own. On the white of a slide or a page, text reads at
#' 4.5:1 or more and the mark at 3:1 (test-theme.R); the rules and gridlines
#' only separate what the text says. The tables have no bands and the charts
#' no axis lines or ticks, as the app's have none.
#'
#' @return A named character vector of hex colours.
#' @noRd
export_palette <- function() {
  light <- brand_tokens()$light
  chart <- chart_colours()
  c(
    text = toupper(light$text), secondary = toupper(light$text_secondary), mark = chart$mark,
    link = toupper(light$accent), rule = toupper(light$text),
    row_rule = toupper(blend(light$border_strong, light$bg)), grid = chart$grid
  )
}

#' The exports' Office colour scheme
#'
#' The theme colours of the templates and of the workbook, which Office
#' offers for anything a reader adds, so that a chart, a table or a shape
#' added in Office takes the brand's colours too. Dark 1 and light 1 are the
#' text and white; dark 2 and light 2 the dark theme's panel and the light
#' theme's alternate page; the accents the light and dark charts' marks, the
#' gold of links, the secondary text, the rules between rows and the dark
#' theme's gold; links are in the gold, and followed links in the secondary
#' text's colour.
#'
#' @return A named character vector of six-digit hex colours with no "#", in
#'   the scheme's order.
#' @noRd
export_scheme <- function() {
  light <- brand_tokens()$light
  dark <- brand_tokens()$dark
  colours <- export_palette()
  scheme <- c(
    dk1 = colours[["text"]], lt1 = "#FFFFFF", dk2 = dark$bg_alt, lt2 = light$bg_alt,
    accent1 = colours[["mark"]], accent2 = colours[["link"]], accent3 = colours[["secondary"]],
    accent4 = dark$chart_mark, accent5 = colours[["row_rule"]], accent6 = dark$accent,
    hlink = colours[["link"]], folHlink = colours[["secondary"]]
  )
  toupper(sub("#", "", scheme, fixed = TRUE))
}

# The font the exports name, the app's
export_font <- "IBM Plex Sans"

#' The exports' fonts, as Office files declare them
#'
#' IBM Plex Sans for the text and IBM Plex Mono for the maker's wordmark,
#' each with what Office picks a substitute by where it is not installed:
#' IBM's PANOSE classification of its Regular, as IBM's own files give it,
#' and its pitch and family, a sans of variable pitch and a font of fixed
#' pitch, both as OOXML's `pitchFamily` and as Word's font table writes them.
#'
#' @return A list of two fonts, `sans` and `mono`, each a list of `typeface`,
#'   `panose`, `pitch_family`, `family` and `pitch`.
#' @noRd
export_fonts <- function() {
  list(
    sans = list(
      typeface = export_font, panose = "020B0503050203000203", pitch_family = "34",
      family = "swiss", pitch = "variable"
    ),
    mono = list(
      typeface = "IBM Plex Mono", panose = "020B0509050203000203", pitch_family = "49",
      family = "modern", pitch = "fixed"
    )
  )
}

# The maker's name, as it writes it: the name of the colour, font and shape
# schemes of the exports' themes, and of the Word template's and the
# workbook's themes
brand_name <- "Katonom\u00e9trica"

#' An Office theme in the exports' colours and font
#'
#' Changes a theme part (`a:theme`) of a template or of the workbook: its
#' colour scheme to export_scheme(); its fonts, major and minor, to IBM Plex
#' Sans, declared as export_fonts() declares it; and its styles for shapes to
#' the brand's flat ones, solid fills with no gradient, shadow or bevel. Its
#' three schemes take the brand's name.
#'
#' @param doc The theme, an xml2 document, changed in place.
#' @param name The theme's new name, or `NULL` to keep its own: officer names
#'   a PowerPoint's master after its theme, and the exports choose layouts on
#'   the master "Office Theme".
#' @return `doc`, invisibly.
#' @noRd
brand_office_theme <- function(doc, name = NULL) {
  ns <- c(a = "http://schemas.openxmlformats.org/drawingml/2006/main")
  if (!is.null(name)) {
    xml2::xml_set_attr(xml2::xml_root(doc), "name", name)
  }
  elements <- xml2::xml_find_first(doc, "/a:theme/a:themeElements", ns)
  colours <- export_scheme()
  scheme <- xml2::xml_find_first(elements, "a:clrScheme", ns)
  xml2::xml_set_attr(scheme, "name", brand_name)
  for (slot in names(colours)) {
    node <- xml2::xml_find_first(scheme, paste0("a:", slot), ns)
    xml2::xml_remove(xml2::xml_children(node))
    xml2::xml_add_child(node, "a:srgbClr", val = colours[[slot]])
  }
  fonts <- xml2::xml_find_first(elements, "a:fontScheme", ns)
  xml2::xml_set_attr(fonts, "name", brand_name)
  sans <- export_fonts()$sans
  for (latin in xml2::xml_find_all(fonts, "a:majorFont/a:latin | a:minorFont/a:latin", ns)) {
    xml2::xml_set_attrs(latin, c(
      typeface = sans$typeface, panose = sans$panose, pitchFamily = sans$pitch_family,
      charset = "0"
    ))
  }
  shapes <- xml2::xml_find_first(elements, "a:fmtScheme", ns)
  xml2::xml_set_attr(shapes, "name", brand_name)
  for (fill in xml2::xml_find_all(shapes, "a:fillStyleLst/* | a:bgFillStyleLst/*", ns)) {
    if (xml2::xml_name(fill) != "solidFill") {
      solid <- xml2::xml_add_sibling(fill, "a:solidFill", .where = "before")
      xml2::xml_add_child(solid, "a:schemeClr", val = "phClr")
      xml2::xml_remove(fill)
    }
  }
  for (effect in xml2::xml_find_all(shapes, "a:effectStyleLst/a:effectStyle", ns)) {
    xml2::xml_remove(xml2::xml_children(effect))
    xml2::xml_add_child(effect, "a:effectLst")
  }
  invisible(doc)
}

# The fonts the exports' text is measured in: IBM Plex Sans, which they name,
# and Arial, which Office most often draws in its place
export_measure_fonts <- c(export_font, "Arial")

# Registers both for measuring: IBM Plex Sans as the charts do, from the app's
# own copy (use_chart_font()); and where Arial is not installed, as in the
# containers, Liberation Sans, which has Arial's metrics, under Arial's name
use_export_font <- function() {
  if (isTRUE(chart_state$export_font)) {
    return(invisible(export_measure_fonts))
  }
  use_chart_font()
  installed <- systemfonts::system_fonts()
  known <- c(installed$family, systemfonts::registry_fonts()$family)
  liberation <- installed[installed$family == "Liberation Sans", c("path", "style")]
  if (!"Arial" %in% known && nrow(liberation) > 0L) {
    path <- function(style) {
      found <- liberation$path[liberation$style == style]
      if (length(found) > 0L) found[1] else liberation$path[1]
    }
    systemfonts::register_font(
      "Arial",
      plain = path("Regular"), bold = path("Bold"), italic = path("Italic"),
      bolditalic = path("Bold Italic")
    )
  }
  chart_state$export_font <- TRUE
  invisible(export_measure_fonts)
}

# The theme's body font, IBM Plex Sans, by reference, as Office's own charts
# and tables name it, for text that sets its font: the font Office then draws
# and substitutes is the theme's, as it declares it
theme_text <- function(...) {
  officer::fp_text(
    ..., font.family = "+mn-lt", cs.family = "+mn-cs", eastasia.family = "+mn-ea",
    hansi.family = "+mn-lt"
  )
}

#' The theme of the exports' charts
#'
#' The native Office charts that mschart draws in the PowerPoint, Word and
#' Excel exports (P5-05 to P5-07), as the app draws its charts: in the
#' theme's font, tick labels in the secondary text colour and axis titles in
#' the text colour, gridlines as faint as the app's on the values' axis only,
#' no axis lines or ticks, no borders and no legend, as each chart shows one
#' measure. The series takes the mark's colour (export_chart()).
#'
#' @return An mschart theme.
#' @noRd
prexp_mschart_theme <- function() {
  colours <- export_palette()
  text <- function(size, colour) theme_text(color = colour, font.size = size)
  none <- officer::fp_border(style = "none")
  mschart::mschart_theme(
    main_title = text(14, colours[["text"]]),
    axis_title = text(11, colours[["text"]]),
    axis_text = text(10, colours[["secondary"]]),
    legend_text = text(10, colours[["text"]]),
    grid_major_line_x = none,
    grid_major_line_y = officer::fp_border(color = colours[["grid"]], width = 0.75),
    grid_minor_line = none,
    axis_ticks = none,
    chart_border = none,
    plot_border = none,
    legend_position = "n"
  )
}
