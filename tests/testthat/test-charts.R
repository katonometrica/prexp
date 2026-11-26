# The chart builders (P4-02): a ggplot with interactive layers from the tibble
# a fetch returns; render_girafe() turns it into the widget.

series <- function(values = c(10, 30, 20), months = c(202607L, 202608L, 202609L),
                   measure = "items") {
  tibble::tibble(
    year_month = months, measure = rep(measure, length(months)), value = values,
    practices = rep(3L, length(months))
  )
}

regions <- function(measure = "nic") {
  tibble::tibble(
    region_code = c("Y56", "Y58", "-"),
    region_name = c("LONDON", "SOUTH WEST", NA),
    measure = rep(measure, 3L),
    value = c(1234.5, 5000, 12)
  )
}

# The geoms of a plot's layers
geoms <- function(p) unname(vapply(p$layers, function(l) class(l$geom)[1], character(1)))

# The labels an axis shows
axis_text <- function(axis) {
  labels <- axis$get_labels(axis$get_breaks())
  labels[!is.na(labels)]
}

test_that("chart_series() draws a line and a point for each month, with tooltips", {
  p <- chart_series(series())
  expect_true(ggplot2::is_ggplot(p))
  expect_identical(geoms(p), c("GeomLine", "GeomInteractivePoint"))
  points <- ggplot2::ggplot_build(p)$data[[2]]
  expect_identical(points$y, c(10, 30, 20))
  expect_identical(
    as.Date(points$x), as.Date(c("2026-07-01", "2026-08-01", "2026-09-01"))
  )
  expect_identical(points$data_id, c("202607", "202608", "202609"))
  # Plain text, which a screen reader reads as the point's name
  expect_identical(points$tooltip[2], "Aug 2026: 30 items")
  expect_identical(p$labels$y, "Items")
  expect_null(p$labels$x)
  # Unordered rows are drawn in month order
  shuffled <- chart_series(series()[c(3, 1, 2), ])
  expect_identical(ggplot2::ggplot_build(shuffled)$data[[2]]$y, c(10, 30, 20))
})

test_that("a series shows each measure in its unit, on its axis and in its tooltips", {
  cost <- chart_series(series(c(1234.5, 99, 0.5), measure = "actual_cost"))
  expect_identical(cost$labels$y, "Actual cost (\u00a3)")
  expect_identical(ggplot2::ggplot_build(cost)$data[[2]]$tooltip[1], "Jul 2026: \u00a31,234.50")
  axis <- ggplot2::layer_scales(cost)$y
  expect_identical(axis$get_labels(c(0, 1500)), c("\u00a30", "\u00a31,500"))
  quantity <- chart_series(series(measure = "total_quantity"))
  expect_identical(quantity$labels$y, "Quantity (units)")
  expect_match(ggplot2::ggplot_build(quantity)$data[[2]]$tooltip[1], "10 units", fixed = TRUE)
  adq <- chart_series(series(measure = "adq_usage"))
  expect_identical(adq$labels$y, "ADQ usage (ADQs)")
})

test_that("tooltips write fractions of an ADQ, and one of a unit in the singular", {
  adq <- chart_series(series(c(0.496, 0.008, 1, 1.624, 1234.4), 202605:202609, "adq_usage"))
  expect_identical(
    ggplot2::ggplot_build(adq)$data[[2]]$tooltip,
    paste0(
      c("May", "Jun", "Jul", "Aug", "Sep"), " 2026: ",
      c("0.496 ADQs", "0.008 ADQs", "1 ADQ", "1.62 ADQs", "1,234 ADQs")
    )
  )
  expect_identical(value_words(c(1, 2), "items"), c("1 item", "2 items"))
  expect_identical(value_words(1, "total_quantity"), "1 unit")
  expect_identical(value_words(1, "nic"), "\u00a31.00")
})

test_that("axis labels tell a small range's breaks apart, and items break at whole numbers", {
  labels <- function(p) axis_text(ggplot2::layer_scales(p)$y)
  adq <- chart_series(series(c(0.4, 1.2, 2), measure = "adq_usage"))
  expect_identical(labels(adq), c("0.0", "0.5", "1.0", "1.5", "2.0"))
  nic <- chart_series(series(c(0.4, 1.2, 2), measure = "nic"))
  expect_identical(
    labels(nic), c("\u00a30.00", "\u00a30.50", "\u00a31.00", "\u00a31.50", "\u00a32.00")
  )
  expect_identical(labels(chart_series(series(c(1, 2, 2)))), c("0", "1", "2"))
  big <- chart_series(series(c(2.1e6, 4e6, 3e6)))
  expect_identical(labels(big), c("0", "1,000,000", "2,000,000", "3,000,000", "4,000,000"))
  # Bars write millions short, and never repeat a label
  millions <- transform(regions("items"), value = c(15.77e6, 9e6, 1))
  bars <- ggplot2::layer_scales(chart_bars(millions))$x
  expect_identical(axis_text(bars), c("0", "4M", "8M", "12M", "16M"))
  small <- ggplot2::layer_scales(chart_bars(regions("items")))$x
  expect_false(anyDuplicated(axis_text(small)) > 0L)
})

test_that("month labels name each month, with the year under the first and each January", {
  labels <- ggplot2::layer_scales(chart_series(series()[c(3, 1, 2), ]))$x$get_labels()
  expect_identical(labels, c("Jul\n2026", "Aug", "Sep"))
  twelve <- month_axis(c(202510:202512, 202601:202609))
  expect_identical(
    twelve$labels,
    c("Oct\n2025", "Nov", "Dec", "Jan\n2026", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug",
      "Sep")
  )
  # More months than fit: every second, every third...
  twentyfour <- month_axis(c(202410:202412, 202501:202512, 202601:202609))
  expect_identical(twentyfour$labels[1:3], c("Oct\n2024", "Dec", "Feb\n2025"))
  expect_length(twentyfour$labels, 12L)
  # A narrow chart labels fewer months
  narrow <- chart_series(series(seq_len(12), c(202510:202512, 202601:202609)), width = 360)
  expect_identical(
    ggplot2::layer_scales(narrow)$x$get_labels(), c("Oct\n2025", "Jan\n2026", "Apr", "Jul")
  )
})

test_that("chart marks are drawn in the marks' colour, which keeps 3:1 in both themes", {
  marks <- c(
    unique(ggplot2::ggplot_build(chart_series(series()))$data[[1]]$colour),
    unique(ggplot2::ggplot_build(chart_series(series()))$data[[2]]$colour),
    unique(ggplot2::ggplot_build(chart_bars(regions()))$data[[1]]$fill)
  )
  expect_identical(unique(toupper(marks)), chart_colours()$mark)
  # The page shows them in each theme's own colour, a selected one in its gold
  # (test-theme.R checks those on every surface)
  for (mode in c("light", "dark")) {
    t <- brand_tokens()[[mode]]
    for (colour in c(t$chart_mark, t$chart_selected)) {
      expect_gte(contrast_ratio(colour, t$bg), 3, label = paste(mode, colour))
    }
  }
})

test_that("a series fills the months without prescribing with 0, and breaks at missing values", {
  p <- chart_series(series(c(10, 20), months = c(202607L, 202609L)), months = c(202606L, 202609L))
  points <- ggplot2::ggplot_build(p)$data[[2]]
  expect_identical(points$data_id, c("202606", "202607", "202608", "202609"))
  expect_identical(points$y, c(0, 10, 0, 20))
  # Neither end has a row
  ends <- ggplot2::ggplot_build(chart_series(series(10, 202607L), months = c(202606L, 202609L)))
  expect_identical(ends$data[[2]]$data_id, c("202606", "202607", "202608", "202609"))
  expect_identical(ends$data[[2]]$y, c(0, 10, 0, 0))
  # A month with prescribing but no value (no ADQ) breaks the line, and has no
  # point, while the months without prescribing are at 0
  partial <- ggplot2::ggplot_build(chart_series(
    series(c(10, NA, 20), months = c(202606L, 202607L, 202609L), measure = "adq_usage"),
    months = c(202605L, 202609L)
  ))
  expect_identical(partial$data[[1]]$y, c(0, 10, NA, 0, 20))
  expect_identical(partial$data[[2]]$data_id, c("202605", "202606", "202608", "202609"))
  # Every month asked for is on the axis, even with a missing value at the end
  last <- chart_series(series(c(10, NA), c(202608L, 202609L), "adq_usage"))
  expect_identical(ggplot2::layer_scales(last)$x$get_labels(), c("Aug\n2026", "Sep"))
})

test_that("chart_bars() draws sorted bars, largest at the top, with ids for selection", {
  p <- chart_bars(regions())
  expect_identical(geoms(p), "GeomInteractiveCol")
  bars <- ggplot2::ggplot_build(p)$data[[1]]
  expect_setequal(bars$x, c(1234.5, 5000, 12))
  # The y order: bottom to top, so the largest is last
  expect_identical(bars$data_id[order(bars$y)], c("-", "Y56", "Y58"))
  expect_identical(bars$tooltip[bars$data_id == "Y56"], "LONDON: \u00a31,234.50")
  # A region without a name shows its code
  axis <- ggplot2::layer_scales(p)$y
  expect_identical(unname(axis$get_labels(c("Y56", "-"))), c("LONDON", "-"))
  expect_identical(p$labels$x, "Net ingredient cost (\u00a3)")
  expect_null(p$labels$y)
  # Missing values are left out
  partial <- regions("adq_usage")
  partial$value[2] <- NA
  expect_setequal(ggplot2::ggplot_build(chart_bars(partial))$data[[1]]$data_id, c("Y56", "-"))
  expect_error(chart_bars(rbind(regions(), regions())), "one row per id")
})

test_that("tied bars keep the input's order, top down", {
  tied <- tibble::tibble(
    region_code = c("A", "B", "C", "D", "E"), region_name = NA_character_, measure = "items",
    value = c(1, 5, 1, 7, 1)
  )
  bars <- ggplot2::ggplot_build(chart_bars(tied))$data[[1]]
  expect_identical(bars$data_id[order(bars$y, decreasing = TRUE)], c("D", "B", "A", "C", "E"))
})

test_that("chart_top_drugs() draws a page of top drugs, long names cut on the axis only", {
  long <- paste(rep("Very long presentation name", 3), collapse = " ")
  page <- tibble::tibble(
    presentation_id = c(7L, 9L), bnf_description = c("Atorvastatin 20mg tablets", long),
    total = c(120, 80)
  )
  p <- chart_top_drugs(page, by = "items")
  expect_identical(geoms(p), "GeomInteractiveCol")
  bars <- ggplot2::ggplot_build(p)$data[[1]]
  expect_identical(bars$data_id[order(bars$y)], c("9", "7"))
  expect_identical(bars$x[order(bars$y)], c(80, 120))
  axis <- unname(ggplot2::layer_scales(p)$y$get_labels(c("7", "9")))
  expect_identical(axis[1], "Atorvastatin 20mg tablets")
  expect_identical(nchar(axis[2]), 45L)
  expect_true(endsWith(axis[2], "\u2026"))
  expect_match(bars$tooltip[bars$data_id == "9"], long, fixed = TRUE)
  expect_identical(p$labels$x, "Items")
  # Ranked by a cost: pounds on the axis and in the tooltips
  page$total <- c(1234.5, 80)
  for (by in c("nic", "actual_cost")) {
    cost <- chart_top_drugs(page, by)
    expect_identical(cost$labels$x, measure_title(by))
    built <- ggplot2::ggplot_build(cost)$data[[1]]
    expect_identical(
      built$tooltip[built$data_id == "7"], "Atorvastatin 20mg tablets: \u00a31,234.50"
    )
    expect_true(all(startsWith(axis_text(ggplot2::layer_scales(cost)$x), "\u00a3")))
  }
  # A narrow chart cuts names shorter
  narrow <- chart_top_drugs(page, "items", width = 360)
  expect_identical(nchar(unname(ggplot2::layer_scales(narrow)$y$get_labels("9"))), 21L)
})

test_that("names that would cut to the same label are cut in the middle", {
  names <- c(
    "Salbutamol 2.5mg/2.5ml nebuliser liquid unit dose ampoules",
    "Salbutamol 2.5mg/2.5ml nebuliser liquid unit dose vials",
    "Atorvastatin 20mg tablets"
  )
  cut <- shorten(names, 30L)
  expect_false(anyDuplicated(cut) > 0L)
  expect_identical(nchar(cut[1:2]), c(30L, 30L))
  expect_true(endsWith(cut[1], "ampoules"))
  expect_true(endsWith(cut[2], "vials"))
  expect_identical(cut[3], names[3])
})

test_that("names are escaped in tooltips", {
  p <- chart_bars(tibble::tibble(
    region_code = "X", region_name = "A <b>bold</b> & \"quoted\" name", measure = "items",
    value = 1
  ))
  expect_identical(
    ggplot2::ggplot_build(p)$data[[1]]$tooltip,
    "A &lt;b&gt;bold&lt;/b&gt; &amp; &quot;quoted&quot; name: 1 item"
  )
})

test_that("a series of one month is one point", {
  p <- chart_series(series(5, 202609L))
  expect_identical(geoms(p), "GeomInteractivePoint")
  expect_identical(ggplot2::ggplot_build(p)$data[[1]]$y, 5)
})

test_that("a builder stops on input with nothing to draw", {
  expect_error(chart_series(series()[0, ]), class = "prexp_empty_chart")
  expect_error(chart_series(series(NA_real_, 202609L)), class = "prexp_empty_chart")
  # A drug with no ADQ: the months without prescribing are no values either
  expect_error(
    chart_series(series(c(NA, NA), c(202608L, 202609L), "adq_usage"), months = c(202606L, 202609L)),
    class = "prexp_empty_chart"
  )
  expect_error(chart_bars(regions()[0, ]), class = "prexp_empty_chart")
  expect_error(
    chart_top_drugs(tibble::tibble(presentation_id = integer(), bnf_description = character(),
                                   total = numeric()), "nic"),
    class = "prexp_empty_chart"
  )
  expect_error(chart_series(series()[c("year_month", "value")]), "columns measure")
  expect_error(chart_series(list(1)), "data frame")
})

test_that("each chart says in words what it shows", {
  expect_identical(
    ggplot2::get_alt_text(chart_series(series())),
    paste(
      "Items by month, Jul \u2013 Sep 2026: 10 items in Jul 2026 first and 20 items in",
      "Sep 2026 last; highest 30 items in Aug 2026, lowest 10 items in Jul 2026."
    )
  )
  expect_identical(
    ggplot2::get_alt_text(chart_bars(regions())),
    paste(
      "Net ingredient cost, 3 bars: largest SOUTH WEST, \u00a35,000.00; smallest -,",
      "\u00a312.00."
    )
  )
})

test_that("render_girafe() makes the widget: hover, one selection, no toolbar, full width", {
  widget <- render_girafe(chart_series(series()), height = 300, title = "Atorvastatin")
  expect_s3_class(widget, "girafe")
  settings <- widget$x$settings
  expect_setequal(settings$toolbar$hidden, c("selection", "zoom", "misc", "saveaspng"))
  expect_identical(settings$select$type, "single")
  # A selected mark in the theme's gold, with an outline in its text colour;
  # the light theme's where the page has none
  light <- brand_tokens()$light
  expect_match(
    settings$select$css,
    paste0(
      "fill:var(--prexp-chart-selected,", light$accent, ");",
      "stroke:var(--prexp-chart-outline,", light$text, ");stroke-width:2px;"
    ),
    fixed = TRUE
  )
  # The tooltip in the theme's colours and the page's font, square
  tooltip <- settings$tooltip$css
  expect_match(tooltip, paste0("background:var(--prexp-chart-tip-bg,", light$bg, ")"), fixed = TRUE)
  expect_match(tooltip, "color:var(--prexp-chart-tip-text,", fixed = TRUE)
  expect_match(tooltip, "border-radius:0;", fixed = TRUE)
  expect_match(tooltip, "font-family:'IBM Plex Sans'", fixed = TRUE)
  expect_true(settings$sizing$rescale)
  expect_identical(settings$sizing$width, 1)
  # The SVG names the page's font, measured with the page's own copy of it,
  # and brings no font files of its own: the page's @font-face is their source
  expect_match(widget$x$html, "font-family='IBM Plex Sans'", fixed = TRUE)
  expect_no_match(widget$x$html, "font-family='(Arial|Liberation)")
  expect_identical(theme_prexp()$text$family, "IBM Plex Sans")
  deps <- vapply(widget$dependencies, function(dep) dep$name, "")
  expect_false(any(grepl("font|liberation|plex", deps, ignore.case = TRUE)), label = toString(deps))
  # No background of its own: the card shows through
  expect_no_match(widget$x$html, "<rect[^>]*fill='#FFFFFF' fill-opacity='1'")
  # The chart's name and description, for screen readers
  expect_match(widget$x$html, "<title[^>]*>Atorvastatin</title>")
  expect_match(widget$x$html, "<desc[^>]*>Items by month, Jul", perl = TRUE)
})

test_that("the charts' theme and fonts are made once and kept", {
  kept <- c("theme_12", "theme_bars", "font_set")
  saved <- mget(kept, envir = chart_state, ifnotfound = list(NULL))
  withr::defer(for (name in kept) assign(name, saved[[name]], envir = chart_state))
  for (name in kept) {
    assign(name, structure(list(), class = paste0("kept_", name)), envir = chart_state)
  }
  expect_s3_class(theme_prexp(), "kept_theme_12")
  expect_s3_class(theme_bars(), "kept_theme_bars")
  expect_s3_class(chart_font_set(), "kept_font_set")
})

test_that("the charts' kept theme and fonts draw as made afresh", {
  p <- chart_series(series())
  kept <- render_girafe(p, title = "Atorvastatin")
  # As before they were kept: a theme built for this chart, a font set made
  # for it
  colours <- chart_colours()
  fresh <- ggiraph::girafe(
    ggobj = p + ggplot2::theme_minimal(base_size = 12, base_family = "IBM Plex Sans") +
      ggplot2::theme(
        plot.background = ggplot2::element_blank(),
        panel.grid.major = ggplot2::element_line(
          colour = colours$grid, linewidth = 1 / ggplot2::.pt
        ),
        panel.grid.minor = ggplot2::element_blank(),
        axis.title = ggplot2::element_text(colour = colours$title),
        axis.text = ggplot2::element_text(colour = colours$tick),
        plot.title.position = "plot", legend.position = "none"
      ),
    width_svg = 8, height_svg = 4, bg = "transparent",
    font_set = gdtools::font_set(sans = "IBM Plex Sans"),
    title = "Atorvastatin", desc = ggplot2::get_alt_text(p)
  )
  svg <- function(widget) gsub("svg_[0-9a-f_]+", "svg_ID", widget$x$html)
  expect_identical(svg(kept), svg(fresh))
})

test_that("the charts' text is measured in the page's own IBM Plex Sans", {
  use_chart_font()
  found <- systemfonts::match_fonts("IBM Plex Sans")
  expect_match(found$path, "ibm-plex-sans-var-latin[.]woff2$")
  # The font's own widths, not a fallback's: its digits are 0.6 em wide
  # (Arial's 0.556, DejaVu Sans's 0.636), at the tick labels' 9.6 pt, measured
  # at a high resolution, as ggiraph measures, which hinting does not round
  width <- systemfonts::string_width(
    "0123456789", family = "IBM Plex Sans", size = 9.6, res = 7200
  ) / 100
  expect_equal(width, 57.5, tolerance = 0.005)
})

test_that("render_girafe() draws the chart at the size it is shown at", {
  view_box <- function(widget) {
    regmatches(widget$x$html, regexpr("viewBox='[^']*'", widget$x$html))
  }
  p <- chart_series(series())
  expect_identical(view_box(render_girafe(p)), "viewBox='0 0 576 288'")
  expect_identical(view_box(render_girafe(p, width = 600, height = 300)), "viewBox='0 0 450 225'")
})
