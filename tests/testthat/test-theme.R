# The brand (spec section 5.3): the token lists of both themes, the CSS
# generated from them, the contrast of every pair the page draws, the head's
# theme script and the theme button, and the fonts served with the app.

# The surfaces of a theme that text and marks sit on: the page, the
# alternate panel (lists, notifications, the dark tooltip), a card on the
# page, and a table's row under the pointer in a card
surfaces <- function(t) {
  card <- blend(t$surface, t$bg)
  list(bg = t$bg, bg_alt = t$bg_alt, card = card, hover = blend(t$surface, card))
}

# The contrast of a colour, hex or rgba(), on an opaque background
contrast_on <- function(colour, ground) {
  contrast_ratio(blend(colour, ground), ground)
}

test_that("both themes have the same tokens, each a colour", {
  tokens <- brand_tokens()
  expect_named(tokens, c("light", "dark"))
  expect_identical(names(tokens$dark), names(tokens$light))
  for (mode in names(tokens)) {
    for (name in names(tokens[[mode]])) {
      value <- tokens[[mode]][[name]]
      expect_match(value, "^(#[0-9A-Fa-f]{6}|rgba\\([0-9., ]+\\))$", label = paste(mode, name))
    }
  }
  # The site's values (katonometrica.com's styles.css), where the app keeps
  # them: the pages, the text, the gold
  expect_identical(tokens$dark$bg, "#0b1222")
  expect_identical(tokens$dark$text, "#e2dfd8")
  expect_identical(tokens$dark$accent, "#c9a84c")
  expect_identical(tokens$light$bg, "#FDFCFB")
  expect_identical(tokens$light$text, "#0b1222")
  expect_identical(tokens$light$accent, "#7d6523")
})

test_that("every text the page draws reads in both themes (WCAG AA, 4.5:1)", {
  for (mode in c("light", "dark")) {
    t <- brand_tokens()[[mode]]
    grounds <- surfaces(t)
    # Text in each of its colours, on every surface it sits on: body text,
    # in a table's row under the pointer too; labels and secondary text; links,
    # the outline buttons' text and its hover, an option chosen in a list;
    # errors and successes; the charts' tick labels and axis titles, in cards
    on <- list(
      text = names(grounds), text_secondary = c("bg", "bg_alt", "card"),
      accent = c("bg", "bg_alt", "card"), accent_hover = c("bg", "bg_alt", "card"),
      error = c("bg", "bg_alt", "card"), success = c("bg", "bg_alt", "card"),
      chart_tick = c("bg", "card"), chart_title = c("bg", "card")
    )
    for (colour in names(on)) {
      for (ground in on[[colour]]) {
        expect_gte(
          contrast_on(t[[colour]], grounds[[ground]]), 4.5,
          label = paste(mode, colour, "on", ground)
        )
      }
    }
    # The gold buttons' text, at rest and under the pointer
    expect_gte(contrast_on(t$on_accent, t$accent), 4.5, label = paste(mode, "on_accent"))
    expect_gte(contrast_on(t$on_accent, t$accent_hover), 4.5, label = paste(mode, "hover"))
    # An outline button under the pointer: its gold text on its gold tint
    tint <- blend(t$accent_subtle, grounds$card)
    expect_gte(contrast_on(t$accent_hover, tint), 4.5, label = paste(mode, "outline hover"))
    # Notifications
    expect_gte(contrast_on(t$text, t$error_bg), 4.5, label = paste(mode, "error toast"))
    expect_gte(contrast_on(t$text, t$success_bg), 4.5, label = paste(mode, "success toast"))
    # The charts' tooltip, its secondary text too
    for (colour in c("chart_tip_text", "text_secondary")) {
      expect_gte(
        contrast_on(t[[colour]], t$chart_tip_bg), 4.5, label = paste(mode, colour, "on tooltip")
      )
    }
  }
})

test_that("every mark and control edge reads in both themes (WCAG AA, 3:1)", {
  for (mode in c("light", "dark")) {
    t <- brand_tokens()[[mode]]
    grounds <- surfaces(t)
    # The charts' marks, a selected one and its outline; the edges of the
    # fields, radios and lists; the focus outline and the open tab's rule;
    # an error's rule
    for (colour in c("chart_mark", "chart_selected", "chart_outline", "control_border",
                     "accent", "error")) {
      for (ground in c("bg", "bg_alt", "card")) {
        expect_gte(
          contrast_on(t[[colour]], grounds[[ground]]), 3,
          label = paste(mode, colour, "on", ground)
        )
      }
    }
    # A field's edge against the field, which is a well of the page's colour
    expect_gte(contrast_on(t$control_border, t$bg), 3, label = paste(mode, "field"))
  }
  # The colours the SVG is drawn in read on their own, where the page's CSS
  # is missing: on the light page, and on white
  colours <- chart_colours()
  for (ground in c(brand_tokens()$light$bg, "#FFFFFF")) {
    expect_gte(contrast_ratio(colours$mark, ground), 3, label = paste("mark on", ground))
    expect_gte(contrast_ratio(colours$tick, ground), 4.5, label = paste("tick on", ground))
    expect_gte(contrast_ratio(colours$title, ground), 4.5, label = paste("title on", ground))
  }
})

test_that("the navbar's title and tabs read on the page in both themes", {
  for (mode in c("light", "dark")) {
    t <- brand_tokens()[[mode]]
    # The title and the open tab in the text colour, the others in the
    # secondary one, on the page's colour
    expect_gte(contrast_on(t$text, t$bg), 4.5, label = paste(mode, "open tab"))
    expect_gte(contrast_on(t$text_secondary, t$bg), 4.5, label = paste(mode, "other tabs"))
    # The open tab is marked by more than its colour: a gold rule under it
    expect_gte(contrast_on(t$accent, t$bg), 3, label = paste(mode, "rule"))
  }
})

test_that("brand_css() sets every token in both themes, dark on the attribute", {
  css <- brand_css()
  blocks <- strsplit(css, "}", fixed = TRUE)[[1L]]
  light <- blocks[grepl(":root,\n[data-bs-theme=\"light\"] {", blocks, fixed = TRUE)]
  dark <- blocks[grepl("[data-bs-theme=\"dark\"] {", blocks, fixed = TRUE)]
  expect_length(light, 1L)
  expect_length(dark, 1L)
  # The light theme first: the dark one, later, wins where both apply
  expect_lt(regexpr("[data-bs-theme=\"light\"]", css, fixed = TRUE),
            regexpr("[data-bs-theme=\"dark\"]", css, fixed = TRUE))
  tokens <- brand_tokens()
  for (mode in c("light", "dark")) {
    block <- if (mode == "light") light else dark
    expect_match(block, paste0("color-scheme: ", mode, ";"), fixed = TRUE)
    for (name in names(tokens[[mode]])) {
      property <- paste0(
        "--prexp-", gsub("_", "-", name, fixed = TRUE), ": ", tokens[[mode]][[name]], ";"
      )
      expect_match(block, property, fixed = TRUE, label = paste(mode, name))
    }
    # Bootstrap's own, from the same tokens
    t <- tokens[[mode]]
    expect_match(block, paste0("--bs-body-bg: ", t$bg, ";"), fixed = TRUE)
    expect_match(block, paste0("--bs-body-color: ", t$text, ";"), fixed = TRUE)
    expect_match(block, paste0("--bs-secondary-color: ", t$text_secondary, ";"), fixed = TRUE)
    expect_match(block, paste0("--bs-link-color: ", t$accent, ";"), fixed = TRUE)
    danger <- paste(grDevices::col2rgb(t$error)[, 1L], collapse = ", ")
    expect_match(block, paste0("--bs-danger-rgb: ", danger, ";"), fixed = TRUE)
  }
})

test_that("the generated CSS recolours every role the charts draw", {
  css <- brand_css()
  colours <- chart_colours()
  # Each role in a colour of its own
  expect_identical(anyDuplicated(toupper(unlist(colours))), 0L)
  rule <- function(element, attribute, role) {
    sprintf(
      ":where(.ggiraph-svg) :where(%s[%s=\"%s\" i]) { %s: var(--prexp-chart-%s); }",
      element, attribute, colours[[role]], attribute, role
    )
  }
  expect_match(css, rule("", "fill", "mark"), fixed = TRUE)
  expect_match(css, rule("", "stroke", "mark"), fixed = TRUE)
  expect_match(css, rule("", "stroke", "grid"), fixed = TRUE)
  expect_match(css, rule("text", "fill", "tick"), fixed = TRUE)
  expect_match(css, rule("text", "fill", "title"), fixed = TRUE)
  # Every colour a chart's SVG holds is one of the roles', or the background,
  # which is all but transparent: none stays light in the dark theme
  drawn <- function(widget) {
    html <- widget$x$html
    found <- regmatches(html, gregexpr("(fill|stroke)='#[0-9A-Fa-f]{6}'", html))[[1L]]
    unique(toupper(sub(".*'(#[0-9A-Fa-f]{6})'", "\\1", found)))
  }
  series <- tibble::tibble(year_month = c(202607L, 202608L, 202609L), measure = "items",
                           value = c(10, 30, 20))
  regions <- tibble::tibble(
    region_code = c("Y56", "Y58"), region_name = c("LONDON", "SOUTH WEST"),
    measure = "nic", value = c(12, 5000)
  )
  for (widget in list(render_girafe(chart_series(series)), render_girafe(chart_bars(regions)))) {
    expect_setequal(setdiff(drawn(widget), "#FFFFFF"), intersect(drawn(widget), unlist(colours)))
    expect_true(colours$mark %in% drawn(widget))
    # Each role drawn in the form its rule matches: the colour as an
    # attribute, the tick labels' and the axis titles' on text
    html <- widget$x$html
    expect_match(html, paste0(" stroke='", colours$grid, "'"), fixed = TRUE)
    expect_match(html, paste0("<text[^>]*fill='", colours$tick, "'"), ignore.case = TRUE)
    expect_match(html, paste0("<text[^>]*fill='", colours$title, "'"), ignore.case = TRUE)
  }
})

test_that("a paged table's controls read on a card in both themes", {
  theme <- table_theme()
  # A page button under the pointer or the keyboard's focus on the page's
  # colour, where the secondary text and the gold read (the checks above):
  # on the surface over a card they would not
  expect_identical(theme$pageButtonHoverStyle$backgroundColor, "var(--prexp-bg)")
  expect_identical(theme$pageButtonActiveStyle$backgroundColor, "var(--prexp-bg)")
  # The count of rows opaque, not reactable's 0.9, and a focused page button
  # outlined, as reactable's stylesheet would leave it without
  css <- paste(
    readLines(system.file("app", "www", "prexp.css", package = "prexp")), collapse = "\n"
  )
  expect_match(css, ".Reactable .rt-page-info {\n  opacity: 1;\n}", fixed = TRUE)
  expect_match(css, ".Reactable .rt-page-button:focus-visible", fixed = TRUE)
})

test_that("a disabled control looks disabled in both themes", {
  for (mode in c("light", "dark")) {
    t <- brand_tokens()[[mode]]
    # Its text fainter than any text that can be used, which reads at 4.5:1,
    # but still seen
    muted <- contrast_on(t$muted, t$bg)
    expect_lt(muted, 3, label = paste(mode, "muted"))
    expect_gt(muted, 2, label = paste(mode, "muted"))
  }
})

test_that("the head sets the theme before the page is drawn, dark unless chosen", {
  script <- theme_script()
  # Dark by default; light or dark as stored under "theme"; storage that
  # throws leaves it dark
  expect_match(script, "var theme = 'dark';", fixed = TRUE)
  expect_match(script, "localStorage.getItem('theme')", fixed = TRUE)
  expect_match(script, "saved === 'light' || saved === 'dark'", fixed = TRUE)
  expect_match(script, "} catch (e) {}", fixed = TRUE)
  expect_match(script, "setAttribute('data-bs-theme', theme)", fixed = TRUE)
  expect_no_match(script, "cookie", fixed = TRUE)
  # In the head, before any stylesheet
  head <- htmltools::renderTags(app_ui(NULL))$head
  at <- function(pattern) regexpr(pattern, head, fixed = TRUE)[[1L]]
  expect_gt(at("var theme = 'dark';"), 0L)
  expect_lt(at("var theme = 'dark';"), at("prexp/fonts/fonts.css"))
  expect_lt(at("var theme = 'dark';"), at("prexp/prexp.css"))
  # The brand's CSS, then the components' that read it
  expect_lt(at("--prexp-bg:"), at("prexp/prexp.css"))
  expect_match(head, "<script src=\"prexp/theme.js\"></script>", fixed = TRUE)
})

test_that("the theme button says what it does, and theme.js keeps the choice", {
  page <- htmltools::renderTags(app_ui(NULL))$html
  pattern <- "<button[^>]*id=\"prexp-theme-toggle\"[^>]*>[^<]*</button>"
  button <- regmatches(page, regexpr(pattern, page))
  expect_length(button, 1L)
  expect_match(button, "type=\"button\"", fixed = TRUE)
  expect_match(button, "aria-label=\"Switch to light theme\"", fixed = TRUE)
  expect_match(button, paste0(">", intToUtf8(0x25D0L), "</button>"), fixed = TRUE)
  # In the navbar, after the tabs
  expect_gt(regexpr("prexp-theme-toggle", page), regexpr("data-value=\"about\"", page))
  expect_lt(regexpr("prexp-theme-toggle", page), regexpr("role=\"main\"", page))
  js <- paste(readLines(system.file("app", "www", "theme.js", package = "prexp")), collapse = "\n")
  expect_match(js, "localStorage.setItem('theme', next)", fixed = TRUE)
  expect_match(js, "setAttribute('data-bs-theme', next)", fixed = TRUE)
  expect_match(js, "'Switch to dark theme' : 'Switch to light theme'", fixed = TRUE)
  expect_match(js, "light ? '\\u25D1' : '\\u25D0'", fixed = TRUE)
  expect_match(js, "try {", fixed = TRUE)
})

test_that("the fonts are IBM Plex, served with the app, with their licence", {
  fonts <- system.file("app", "www", "fonts", package = "prexp")
  css <- paste(readLines(file.path(fonts, "fonts.css")), collapse = "\n")
  files <- regmatches(css, gregexpr("url\\('[^']+'\\)", css))[[1L]]
  files <- unique(sub("url\\('([^']+)'\\)", "\\1", files))
  expect_length(files, 6L)
  expect_true(all(file.exists(file.path(fonts, files))))
  expect_true(all(grepl("^ibm-plex-(sans-var|mono-[45]00)-latin(-ext)?[.]woff2$", files)))
  # Weights 400 to 600 only, the font's
  weights <- regmatches(css, gregexpr("font-weight: [0-9 ]+;", css))[[1L]]
  expect_setequal(weights, c("font-weight: 400;", "font-weight: 500;", "font-weight: 400 600;"))
  # The SIL Open Font License beside them
  ofl <- readLines(file.path(fonts, "OFL.txt"), warn = FALSE)
  expect_match(ofl[[1L]], "IBM Corp.", fixed = TRUE)
  expect_true(any(grepl("SIL Open Font License, Version 1.1", ofl, fixed = TRUE)))
  # The head links them and preloads the latin Sans; nothing comes from Google
  head <- htmltools::renderTags(app_ui(NULL))$head
  expect_match(head, "<link rel=\"stylesheet\" href=\"prexp/fonts/fonts.css\"/>", fixed = TRUE)
  expect_match(
    head,
    paste0(
      "<link rel=\"preload\" href=\"prexp/fonts/ibm-plex-sans-var-latin.woff2\" as=\"font\"",
      " type=\"font/woff2\" crossorigin/>"
    ),
    fixed = TRUE
  )
  expect_match(head, "<link rel=\"icon\" type=\"image/svg+xml\" href=\"prexp/favicon.svg\"/>",
               fixed = TRUE)
  expect_true(file.exists(system.file("app", "www", "favicon.svg", package = "prexp")))
  expect_no_match(head, "googleapis", fixed = TRUE)
})

test_that("the exports' colours are the light theme's, and read on white", {
  colours <- export_palette()
  light <- brand_tokens()$light
  # The light theme's text, secondary text and gold, the app's charts' mark
  # and gridlines, and its strong border on its page between rows
  expect_identical(colours, c(
    text = "#0B1222", secondary = "#5A5650", mark = "#355695", link = "#7D6523",
    rule = "#0B1222", row_rule = "#BEBDBC", grid = "#DFDEDD"
  ))
  expect_identical(colours[["text"]], toupper(light$text))
  expect_identical(colours[["secondary"]], toupper(light$text_secondary))
  expect_identical(colours[["link"]], toupper(light$accent))
  expect_identical(colours[["mark"]], chart_colours()$mark)
  expect_identical(colours[["grid"]], chart_colours()$grid)
  # On the white of a slide or a page: text at 4.5:1, the chart's mark and
  # the header's rule at 3:1. The rules between rows and the gridlines only
  # separate what the text says.
  for (colour in c("text", "secondary", "link")) {
    expect_gte(contrast_ratio(colours[[colour]], "#FFFFFF"), 4.5, label = colour)
  }
  for (colour in c("mark", "rule")) {
    expect_gte(contrast_ratio(colours[[colour]], "#FFFFFF"), 3, label = colour)
  }
})

test_that("the exports' Office theme is the brand's colours and IBM Plex", {
  expect_identical(export_scheme(), c(
    dk1 = "0B1222", lt1 = "FFFFFF", dk2 = "0F1730", lt2 = "F7F5F2", accent1 = "355695",
    accent2 = "7D6523", accent3 = "5A5650", accent4 = "678CCF", accent5 = "BEBDBC",
    accent6 = "C9A84C", hlink = "7D6523", folHlink = "5A5650"
  ))
  # Text a reader adds in dark 1, links and followed links, on light 1
  scheme <- stats::setNames(paste0("#", export_scheme()), names(export_scheme()))
  for (slot in c("dk1", "accent3", "hlink", "folHlink")) {
    expect_gte(contrast_ratio(scheme[[slot]], scheme[["lt1"]]), 4.5, label = slot)
  }
  # IBM's classifications of the Regulars, by which Office substitutes
  fonts <- export_fonts()
  expect_identical(
    vapply(fonts, `[[`, "", "typeface"), c(sans = "IBM Plex Sans", mono = "IBM Plex Mono")
  )
  expect_identical(
    vapply(fonts, `[[`, "", "panose"),
    c(sans = "020B0503050203000203", mono = "020B0509050203000203")
  )
  expect_identical(vapply(fonts, `[[`, "", "pitch_family"), c(sans = "34", mono = "49"))
  # The charts: the theme's font, by reference; tick labels in the secondary
  # text's colour, axis titles in the text's, as the app draws them
  theme <- prexp_mschart_theme()
  expect_identical(theme$axis_text_x$font.family, "+mn-lt")
  expect_identical(theme$axis_text_x$color, export_palette()[["secondary"]])
  expect_identical(theme$axis_title_y$color, export_palette()[["text"]])
  expect_identical(theme$grid_major_line_y$color, export_palette()[["grid"]])
})

test_that("brand_office_theme() puts the brand in an Office theme", {
  theme <- xml2::read_xml(unz(
    system.file("template", "template.pptx", package = "officer"), "ppt/theme/theme1.xml"
  ))
  brand_office_theme(theme)
  a <- c(a = "http://schemas.openxmlformats.org/drawingml/2006/main")
  # Its name kept, unless another is given
  expect_identical(xml2::xml_attr(xml2::xml_root(theme), "name"), "Office Theme")
  colours <- vapply(names(export_scheme()), function(slot) {
    colour <- xml2::xml_find_first(theme, sprintf("//a:clrScheme/a:%s/a:srgbClr", slot), a)
    xml2::xml_attr(colour, "val")
  }, "")
  expect_identical(colours, export_scheme())
  latin <- xml2::xml_find_all(theme, "//a:majorFont/a:latin | //a:minorFont/a:latin", a)
  expect_identical(xml2::xml_attr(latin, "typeface"), rep("IBM Plex Sans", 2L))
  expect_identical(xml2::xml_attr(latin, "panose"), rep("020B0503050203000203", 2L))
  expect_identical(xml2::xml_attr(latin, "pitchFamily"), rep("34", 2L))
  # Flat: no gradient, shadow or bevel, as many styles as before
  expect_length(xml2::xml_find_all(theme, "//a:gradFill | //a:outerShdw | //a:sp3d", a), 0L)
  expect_length(xml2::xml_find_all(theme, "//a:fillStyleLst/a:solidFill", a), 3L)
  expect_length(xml2::xml_find_all(theme, "//a:effectStyle/a:effectLst", a), 3L)
  schemes <- xml2::xml_find_all(theme, "//a:clrScheme | //a:fontScheme | //a:fmtScheme", a)
  expect_identical(unique(xml2::xml_attr(schemes, "name")), brand_name)
  renamed <- xml2::read_xml(as.character(theme))
  brand_office_theme(renamed, name = brand_name)
  expect_identical(xml2::xml_attr(xml2::xml_root(renamed), "name"), brand_name)
})
