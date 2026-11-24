# The page (spec section 5.3): five tabs in a navbar, the data window and the
# attribution in a footer on every tab, and a head that asks search engines
# not to index the app.

#' The app's user interface
#'
#' @param request The request, for URL bookmarking: the UI is a function of it.
#' @return A Shiny UI.
#' @noRd
app_ui <- function(request) {
  bslib::page_navbar(
    title = "Prescription Explorer",
    id = "tab",
    theme = prexp_theme(),
    lang = "en",
    window_title = "Prescription Explorer",
    # Every tab flows as a page, so the footer follows its content; charts set
    # their own heights
    fillable = FALSE,
    header = shiny::tags$head(
      shiny::tags$meta(name = "robots", content = "noindex, nofollow"),
      shiny::tags$link(rel = "stylesheet", href = "prexp/prexp.css")
    ),
    bslib::nav_panel("Drug", value = "drug", coming_view("Drug", "P4-04")),
    bslib::nav_panel("Practice", value = "practice", coming_view("Practice", "P4-05")),
    bslib::nav_panel("Region", value = "region", coming_view("Region", "P4-06")),
    bslib::nav_panel("Report", value = "report", coming_view("Report", "P5-02")),
    bslib::nav_panel("About", value = "about", about_ui()),
    footer = footer_ui()
  )
}

# A tab whose view is still to come
coming_view <- function(name, ticket) {
  bslib::card(
    bslib::card_body(
      shiny::p(class = "text-muted", paste0("The ", name, " view comes next (", ticket, ")."))
    )
  )
}

#' The About tab: the methods text
#'
#' @return Shiny UI.
#' @noRd
about_ui <- function() {
  sections <- lapply(methods_sections(), function(section) {
    shiny::tags$section(
      class = "prexp-methods-section",
      shiny::tags$h2(section$title),
      lapply(section$text, shiny::tags$p),
      if (length(section$points) > 0L) {
        shiny::tags$ul(lapply(section$points, function(point) {
          if (is.na(point$term)) {
            shiny::tags$li(point$text)
          } else {
            shiny::tags$li(shiny::tags$strong(paste0(point$term, ".")), " ", point$text)
          }
        }))
      }
    )
  })
  attribution <- data_attribution()
  bslib::card(
    class = "prexp-about",
    bslib::card_body(
      sections,
      shiny::tags$p(
        shiny::tags$a(href = attribution$source_url, "The dataset on the NHSBSA portal"),
        " \u00b7 ",
        shiny::tags$a(href = attribution$licence_url, "Open Government Licence v3.0")
      )
    )
  )
}

#' The footer on every tab: the data window and the attribution
#'
#' @return Shiny UI; the window is the server's output `window`.
#' @noRd
footer_ui <- function() {
  attribution <- data_attribution()
  shiny::tags$footer(
    class = "prexp-footer",
    shiny::span(class = "prexp-window", shiny::textOutput("window", inline = TRUE)),
    " \u00b7 ",
    shiny::span(attribution$statement),
    " \u00b7 ",
    shiny::span(
      "Contains public sector information licensed under the ",
      shiny::tags$a(href = attribution$licence_url, "Open Government Licence v3.0"),
      "."
    )
  )
}
