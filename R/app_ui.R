# The page (spec section 5.3): five tabs in a navbar with the theme button,
# the data window and the attribution in a footer on every tab, and a head
# that sets the theme before the page is drawn, loads the brand's fonts and
# asks search engines not to index the app.

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
    header = shiny::tagList(
      shiny::tags$head(
        # First, so the page is never drawn in the other theme
        shiny::tags$script(shiny::HTML(theme_script())),
        shiny::tags$meta(name = "robots", content = "noindex, nofollow"),
        shiny::tags$link(rel = "icon", type = "image/svg+xml", href = "prexp/favicon.svg"),
        shiny::tags$link(
          rel = "preload", href = "prexp/fonts/ibm-plex-sans-var-latin.woff2", as = "font",
          type = "font/woff2", crossorigin = NA
        ),
        shiny::tags$link(rel = "stylesheet", href = "prexp/fonts/fonts.css"),
        shiny::tags$style(shiny::HTML(brand_css())),
        shiny::tags$link(rel = "stylesheet", href = "prexp/prexp.css"),
        shiny::tags$script(src = "prexp/theme.js"),
        shiny::tags$script(src = "prexp/search.js"),
        shiny::tags$script(src = "prexp/report.js")
      ),
      # The page's status region, there from the start on every tab, which
      # says what a pin or a change to the report did (report.js, announce())
      shiny::div(id = "prexp-status", class = "visually-hidden", role = "status")
    ),
    bslib::nav_panel("Drug", value = "drug", view_heading("Drug"), mod_drug_ui("drug")),
    bslib::nav_panel(
      "Practice", value = "practice", view_heading("Practice"), mod_practice_ui("practice")
    ),
    bslib::nav_panel(
      "Region", value = "region", view_heading("Region"), mod_region_ui("region")
    ),
    bslib::nav_panel(
      "Report", value = "report", view_heading("Report"), mod_report_ui("report")
    ),
    bslib::nav_panel("About", value = "about", view_heading("About the data"), about_ui()),
    bslib::nav_spacer(),
    bslib::nav_item(theme_button()),
    footer = footer_ui()
  )
  main_landmark(page)
}

# The theme button, at the navbar's right as on katonometrica.com: its glyph
# shows the theme, its label what a press does. The page opens dark
# (theme_script()), and theme.js sets both when the theme changes.
theme_button <- function() {
  shiny::tags$button(
    type = "button", id = "prexp-theme-toggle", class = "prexp-theme-toggle",
    `aria-label` = "Switch to light theme", "\u25d0"
  )
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
  # One column, as the brand's policy pages are
  shiny::div(class = "prexp-about", sections)
}

#' The footer on every tab: the data window, the attribution, the link to
#' the source, and KATONOMETRICA's wordmark, which links its site
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
    ),
    " \u00b7 ",
    shiny::tags$a(href = source_url(), "Source on GitHub"),
    shiny::tags$a(class = "prexp-wordmark", href = "https://katonometrica.com", "KATONOMETRICA")
  )
}

#' The app's source: the repository, from DESCRIPTION's URL field
#'
#' @return The address, as a string.
#' @noRd
source_url <- function() {
  url <- utils::packageDescription("prexp", fields = "URL")
  trimws(strsplit(url, ",", fixed = TRUE)[[1L]][[1L]])
}
