# WCAG 2's contrast ratio between two colours, hex or R colour names: from 1
# (the same) to 21 (black on white). AA asks 4.5 for text, 3 for large text and
# for the marks of a chart.
contrast_ratio <- function(a, b) {
  luminance <- function(colour) {
    rgb <- grDevices::col2rgb(colour)[, 1L] / 255
    linear <- ifelse(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055)^2.4)
    sum(c(0.2126, 0.7152, 0.0722) * linear)
  }
  ends <- range(luminance(a), luminance(b))
  (ends[[2L]] + 0.05) / (ends[[1L]] + 0.05)
}
