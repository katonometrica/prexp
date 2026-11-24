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
  expect_identical(points$tooltip[2], "<b>Aug 2026</b><br/>30 items")
  expect_identical(p$labels$y, "Items")
  expect_null(p$labels$x)
  # Unordered rows are drawn in month order
  shuffled <- chart_series(series()[c(3, 1, 2), ])
  expect_identical(ggplot2::ggplot_build(shuffled)$data[[2]]$y, c(10, 30, 20))
})

test_that("a series shows each measure in its unit, on its axis and in its tooltips", {
  cost <- chart_series(series(c(1234.5, 99, 0.5), measure = "actual_cost"))
  expect_identical(cost$labels$y, "Actual cost (\u00a3)")
  expect_identical(
    ggplot2::ggplot_build(cost)$data[[2]]$tooltip[1], "<b>Jul 2026</b><br/>\u00a31,234.50"
  )
  axis <- ggplot2::layer_scales(cost)$y
  expect_identical(axis$get_labels(c(0, 1500)), c("\u00a30", "\u00a31,500"))
  quantity <- chart_series(series(measure = "total_quantity"))
  expect_identical(quantity$labels$y, "Quantity (units)")
  expect_match(ggplot2::ggplot_build(quantity)$data[[2]]$tooltip[1], "10 units", fixed = TRUE)
  adq <- chart_series(series(measure = "adq_usage"))
  expect_identical(adq$labels$y, "ADQ usage (ADQs)")
})

test_that("a series fills the months without prescribing with 0, and skips missing values", {
  p <- chart_series(series(c(10, 20), months = c(202607L, 202609L)), months = c(202606L, 202609L))
  points <- ggplot2::ggplot_build(p)$data[[2]]
  expect_identical(points$data_id, c("202606", "202607", "202608", "202609"))
  expect_identical(points$y, c(0, 10, 0, 20))
  # A measure with no value (no ADQ) in some months: only the others are drawn
  partial <- chart_series(series(c(10, NA, 20), measure = "adq_usage"))
  expect_identical(ggplot2::ggplot_build(partial)$data[[2]]$y, c(10, 20))
})

test_that("chart_bars() draws sorted bars, largest at the top, with ids for selection", {
  p <- chart_bars(regions())
  expect_identical(geoms(p), "GeomInteractiveCol")
  bars <- ggplot2::ggplot_build(p)$data[[1]]
  expect_setequal(bars$x, c(1234.5, 5000, 12))
  # The y order: bottom to top, so the largest is last
  expect_identical(bars$data_id[order(bars$y)], c("-", "Y56", "Y58"))
  expect_identical(
    bars$tooltip[bars$data_id == "Y56"], "<b>LONDON</b><br/>\u00a31,234.50"
  )
  # A region without a name shows its code
  axis <- ggplot2::layer_scales(p)$y
  expect_identical(unname(axis$get_labels(c("Y56", "-"))), c("LONDON", "-"))
  expect_identical(p$labels$x, "Net ingredient cost (\u00a3)")
  expect_null(p$labels$y)
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
})

test_that("names are escaped in tooltips", {
  p <- chart_bars(tibble::tibble(
    region_code = "X", region_name = "A <b>bold</b> & \"quoted\" name", measure = "items",
    value = 1
  ))
  expect_identical(
    ggplot2::ggplot_build(p)$data[[1]]$tooltip,
    "<b>A &lt;b&gt;bold&lt;/b&gt; &amp; &quot;quoted&quot; name</b><br/>1 items"
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
  expect_error(chart_bars(regions()[0, ]), class = "prexp_empty_chart")
  expect_error(
    chart_top_drugs(tibble::tibble(presentation_id = integer(), bnf_description = character(),
                                   total = numeric()), "nic"),
    class = "prexp_empty_chart"
  )
  expect_error(chart_series(series()[c("year_month", "value")]), "columns measure")
  expect_error(chart_series(list(1)), "data frame")
})

test_that("render_girafe() makes the widget: hover, one selection, no toolbar, full width", {
  widget <- render_girafe(chart_series(series()), height = 3)
  expect_s3_class(widget, "girafe")
  settings <- widget$x$settings
  expect_setequal(settings$toolbar$hidden, c("selection", "zoom", "misc", "saveaspng"))
  expect_identical(settings$select$type, "single")
  expect_true(settings$sizing$rescale)
  expect_identical(settings$sizing$width, 1)
  # The SVG names the charts' font, measured with one that has its metrics
  expect_match(widget$x$html, "font-family='Arial'", fixed = TRUE)
  expect_identical(theme_prexp()$text$family, "Arial")
})
