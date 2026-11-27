# The page (spec section 5.3): the site's skip link, then a header of two rows,
# katonometrica.com's bar over the app's own row with its name and five tabs;
# the data window and the attribution in a footer on every tab; and a head
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
    # The tabs as the site's links, on a row that never hides behind a menu
    # button: not Bootstrap's underlined tabs, and no collapsed menu
    navbar_options = bslib::navbar_options(collapsible = FALSE, underline = FALSE),
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
        shiny::tags$script(src = "prexp/navbar.js"),
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
    footer = footer_ui()
  )
  main_landmark(page_header(page))
}

# katonometrica.com's address, which its bar's links lead to, in the same tab
site_url <- "https://katonometrica.com/"

# The page's header, sticky at the top: katonometrica.com's bar (site_bar()),
# then bslib's navbar as the app's row, its name and the tabs. The two are
# navigation landmarks named apart. The site's drawer backdrop comes first,
# as the site's bar has it. Before the header, the site's skip link, the
# keyboard's first stop, which leads past both rows to the tabs' content
# (main_landmark()). prexp.css draws the header and navbar.js gives it the
# site's behaviour.
page_header <- function(page) {
  query <- htmltools::tagQuery(page)
  navbar <- query$find(".navbar")
  navbar$addClass("prexp-app-nav")$addAttrs(`aria-label` = "Prescription Explorer")
  navbar$find(".navbar-brand")$addClass("prexp-app-name")
  app_row <- navbar$selectedTags()
  navbar$replaceWith(
    shiny::tags$a(href = "#main-content", class = "kat-skip-link", "Skip to main content"),
    shiny::tags$header(
      class = "kat-navbar", id = "kat-navbar",
      shiny::div(
        class = "kat-nav-menu-backdrop", id = "kat-nav-menu-backdrop", `aria-hidden` = "true"
      ),
      site_bar(),
      app_row
    )
  )
  as_page(query$allTags(), page)
}

# katonometrica.com's bar as the site's pages draw it (its index.html), the
# classes under the prefix kat- (the site's .navbar and .nav-link are
# Bootstrap's too): the wordmark; the site's four sections; and its actions,
# the theme button and Book a call. No language menu: the app is in English.
# Below 900 px the links and the actions are a drawer, which the hamburger
# opens; its label names the bar it belongs to, as the page has two.
site_bar <- function() {
  sections <- c(
    "What we do" = "services", "Work" = "work", "How it works" = "how", "Contact" = "contact"
  )
  shiny::tags$nav(
    class = "kat-nav-row", `aria-label` = "katonometrica.com",
    shiny::div(
      class = "kat-nav-container",
      shiny::tags$a(href = site_url, class = "kat-nav-logo", "KATONOMETRICA"),
      shiny::tags$ul(
        class = "kat-nav-menu", id = "kat-nav-menu",
        lapply(names(sections), function(name) {
          shiny::tags$li(
            class = "kat-nav-item",
            shiny::tags$a(
              href = paste0(site_url, "#", sections[[name]]), class = "kat-nav-link", name
            )
          )
        })
      ),
      shiny::div(
        class = "kat-nav-actions", id = "kat-nav-actions",
        theme_button(),
        shiny::tags$a(
          href = paste0(site_url, "#contact"), class = "kat-btn kat-btn-primary kat-btn-nav",
          "Book a call"
        )
      ),
      shiny::tags$button(
        type = "button", class = "kat-nav-toggle", id = "kat-nav-toggle",
        `aria-label` = "katonometrica.com menu", `aria-expanded` = "false",
        `aria-controls` = "kat-nav-menu kat-nav-actions",
        lapply(1:3, function(i) shiny::span(class = "kat-hamburger-line"))
      )
    )
  )
}

# The theme button, among the site's actions as on katonometrica.com: its
# glyph shows the theme, its label what a press does. The page opens dark
# (theme_script()), and theme.js sets both when the theme changes.
theme_button <- function() {
  shiny::tags$button(
    type = "button", id = "prexp-theme-toggle", class = "kat-theme-toggle",
    `aria-label` = "Switch to light theme", "\u25d0"
  )
}

# A tab's heading: the page's h1 while the tab shows, for screen readers (the
# header shows the tab's name)
view_heading <- function(text) {
  shiny::tags$h1(class = "visually-hidden", text)
}

# The tabs as the page's main landmark, between the header and the footer, so
# a screen reader can skip to them, and the skip link's target. Only the first
# .tab-content is the tabs': a view's own tabs add another.
main_landmark <- function(page) {
  tabs <- htmltools::tagQuery(page)$find(".tab-content")$filter(function(x, i) i == 1L)
  as_page(tabs$addAttrs(role = "main", id = "main-content")$allTags(), page)
}

# tagQuery() returns a bare tag list: the page's class, language and theme
# put back
as_page <- function(tags, page) {
  structure(
    tags,
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
