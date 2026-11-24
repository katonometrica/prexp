# The page (spec section 5.3): five tabs in a navbar, the data window and the
# attribution in a footer on every tab, and a head that asks search engines
# not to index the app.

# The tabs' values, which URL bookmarks name
app_tabs <- c("drug", "practice", "region", "report", "about")

#' The app's user interface
#'
#' @param request The request, for URL bookmarking: the UI is a function of it.
#' @return A Shiny UI.
#' @noRd
app_ui <- function(request) {
  page <- bslib::page_navbar(
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
      shiny::tags$link(rel = "stylesheet", href = "prexp/prexp.css"),
      shiny::tags$script(src = "prexp/search.js")
    ),
    bslib::nav_panel(
      "Drug", value = "drug", view_heading("Drug"), search_view("drug", "P4-04")
    ),
    bslib::nav_panel(
      "Practice", value = "practice", view_heading("Practice"), search_view("practice", "P4-05")
    ),
    bslib::nav_panel(
      "Region", value = "region", view_heading("Region"), coming_view("Region", "P4-06")
    ),
    bslib::nav_panel(
      "Report", value = "report", view_heading("Report"), coming_view("Report", "P5-02")
    ),
    bslib::nav_panel("About", value = "about", view_heading("About the data"), about_ui()),
    footer = footer_ui()
  )
  main_landmark(page)
}

# A tab's heading: the page's h1 while the tab shows, for screen readers (the
# navbar shows the tab's name)
view_heading <- function(text) {
  shiny::tags$h1(class = "visually-hidden", text)
}

# The tabs as the page's main landmark, between the navbar and the footer, so
# a screen reader can skip to them. Only the first .tab-content is the tabs':
# a view's own tabs add another. tagQuery() returns a bare tag list, so the
# page's class, language and theme are put back.
main_landmark <- function(page) {
  tabs <- htmltools::tagQuery(page)$find(".tab-content")$filter(function(x, i) i == 1L)
  main <- tabs$addAttrs(role = "main")$allTags()
  structure(
    main,
    class = class(page), lang = attr(page, "lang"), bs_theme = attr(page, "bs_theme")
  )
}

# A tab with its search, whose view is still to come: it shows what was picked
search_view <- function(type, ticket) {
  bslib::card(
    bslib::card_body(
      mod_search_ui(paste0(type, "_search"), type),
      shiny::p(shiny::textOutput(paste0(type, "_picked"), inline = TRUE)),
      shiny::p(class = "text-muted", paste0("The view comes next (", ticket, ")."))
    )
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
      },
      if (length(section$links) > 0L) {
        shiny::tags$ul(lapply(section$links, function(link) {
          shiny::tags$li(shiny::tags$a(href = link$url, link$text))
        }))
      }
    )
  })
  bslib::card(class = "prexp-about", bslib::card_body(sections))
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
      # No space between the link and the full stop
      shiny::tags$a(
        href = attribution$licence_url, "Open Government Licence v3.0", .noWS = "after"
      ),
      "."
    )
  )
}
