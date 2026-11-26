# Writes the exports' templates in inst/templates/ (spec section 5.5; tickets
# P5-05, P5-06 and P7-03) from the templates officer ships, so that they hold
# only what this script puts in them. Run from the repository root in the
# rstudio container:
#
#   Rscript data-raw/make_templates.R
#
# The brand's colours and fonts come from the package (R/theme.R), which the
# script loads, so that the templates and the exports cannot drift apart:
# export_scheme(), export_fonts() and export_palette().
#
# report.pptx is officer's template.pptx:
# - widened to 16:9, 13.333 by 7.5 inches, with every shape of its master and
#   layouts widened in proportion, so that the layouts keep their margins;
# - in the brand's theme (brand_office_theme()): its colour scheme, IBM Plex
#   Sans as its fonts, declared with IBM's classification so that Office
#   substitutes a sans where Plex is not installed, and flat shapes, with no
#   gradients, shadows or bevels. The theme keeps its name, Office Theme:
#   officer names the master after it, and the exports choose layouts on it;
# - with titles left-aligned, as the slides' own are, and the title slide's
#   title and subtitle at the content's left margin, across the master's
#   title box, the subtitle in the secondary text's colour;
# - with neutral document properties in English, rather than officer's
#   author's name and French ones, with no revision number or counts that
#   officer would not update, and without its 4:3 thumbnail and its printer
#   settings;
# - with the editor's vertical guide at the wide slide's centre.
#
# report.docx is officer's template.docx, A4 with 2.5 cm margins, cleaned the
# same way, in the brand's theme, renamed, with a Title style and its styles
# named in English (make_docx_template() below).

make_pptx_template <- function(target) {
  dir <- tempfile("pptx-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  utils::unzip(system.file("template", "template.pptx", package = "officer"), exdir = dir)
  part <- function(...) file.path(dir, ...)

  # The slide size: 16:9 at the same height
  wide <- 12192000
  doc <- xml2::read_xml(part("ppt", "presentation.xml"))
  size <- xml2::xml_find_first(doc, "/p:presentation/p:sldSz", xml2::xml_ns(doc))
  scale <- wide / as.numeric(xml2::xml_attr(size, "cx"))
  xml2::xml_set_attr(size, "cx", format(wide, scientific = FALSE))
  xml2::xml_set_attr(size, "type", NULL)
  xml2::write_xml(doc, part("ppt", "presentation.xml"))

  # Every shape of the master and the layouts, widened in proportion. The
  # a:ext elements of extension lists have no cx, and are left as they are.
  shapes <- c(
    list.files(part("ppt", "slideMasters"), "[.]xml$", full.names = TRUE),
    list.files(part("ppt", "slideLayouts"), "[.]xml$", full.names = TRUE)
  )
  for (file in shapes) {
    edit_part(file, function(doc, ns) {
      widen(xml2::xml_find_all(doc, "//a:off | //a:chOff", ns), "x", scale)
      widen(xml2::xml_find_all(doc, "//a:ext[@cx] | //a:chExt", ns), "cx", scale)
    })
  }

  # The brand's theme, under its own name
  edit_part(part("ppt", "theme", "theme1.xml"), function(doc, ns) brand_office_theme(doc))

  # Titles left-aligned, as the slides' own titles and their text are
  master <- part("ppt", "slideMasters", "slideMaster1.xml")
  edit_part(master, function(doc, ns) {
    level <- xml2::xml_find_first(doc, "/p:sldMaster/p:txStyles/p:titleStyle/a:lvl1pPr", ns)
    xml2::xml_set_attr(level, "algn", "l")
  })

  # The title slide's title and subtitle at the content's left margin, across
  # the master's title box, both left-aligned; the subtitle in the secondary
  # text's colour
  doc <- xml2::read_xml(master)
  box <- xml2::xml_find_first(
    doc, "//p:sp[p:nvSpPr/p:nvPr/p:ph/@type = 'title']/p:spPr/a:xfrm", xml2::xml_ns(doc)
  )
  left <- xml2::xml_attr(xml2::xml_child(box, "a:off"), "x")
  width <- xml2::xml_attr(xml2::xml_child(box, "a:ext"), "cx")
  secondary <- sub("#", "", export_palette()[["secondary"]], fixed = TRUE)
  edit_part(part("ppt", "slideLayouts", "slideLayout1.xml"), function(doc, ns) {
    placeholder <- function(type) {
      xml2::xml_find_first(doc, sprintf("//p:sp[p:nvSpPr/p:nvPr/p:ph/@type = '%s']", type), ns)
    }
    for (type in c("ctrTitle", "subTitle")) {
      xfrm <- xml2::xml_find_first(placeholder(type), "p:spPr/a:xfrm", ns)
      xml2::xml_set_attr(xml2::xml_child(xfrm, "a:off"), "x", left)
      xml2::xml_set_attr(xml2::xml_child(xfrm, "a:ext"), "cx", width)
    }
    levels <- xml2::xml_find_all(placeholder("subTitle"), "p:txBody/a:lstStyle/*", ns)
    xml2::xml_set_attr(levels, "algn", "l")
    for (fill in xml2::xml_find_all(levels, "a:defRPr/a:solidFill", ns)) {
      xml2::xml_remove(xml2::xml_children(fill))
      xml2::xml_add_child(fill, "a:srgbClr", val = secondary)
    }
  })

  # The document's properties
  edit_part(part("docProps", "core.xml"), function(doc, ns) {
    for (name in c("dc:title", "dc:creator", "cp:lastModifiedBy")) {
      node <- xml2::xml_find_first(doc, paste0("//", name), ns)
      xml2::xml_text(node) <- ""
    }
    xml2::xml_remove(xml2::xml_find_first(doc, "//cp:revision", ns))
  })
  writeLines(app_properties, part("docProps", "app.xml"), useBytes = TRUE)

  # The vertical guide, at the 4:3 slide's centre, at the wide one's
  edit_part(part("ppt", "viewProps.xml"), function(doc, ns) {
    widen(xml2::xml_find_all(doc, "//p:guide[not(@orient) or @orient = 'vert']", ns), "pos", scale)
  })

  # The thumbnail and the printer settings, and the relationships to them
  unlink(c(part("docProps", "thumbnail.jpeg"), part("ppt", "printerSettings")), recursive = TRUE)
  drop_relationships(part("_rels", ".rels"), "docProps/thumbnail.jpeg")
  drop_relationships(
    part("ppt", "_rels", "presentation.xml.rels"), "printerSettings/printerSettings1.bin"
  )

  pack(dir, target)
}

# Reads a part, lets `change` change it, and writes it back
edit_part <- function(file, change) {
  doc <- xml2::read_xml(file)
  change(doc, xml2::xml_ns(doc))
  xml2::write_xml(doc, file)
}

# Multiplies an attribute of each node by `scale`, in whole EMUs
widen <- function(nodes, attr, scale) {
  for (node in nodes) {
    value <- round(as.numeric(xml2::xml_attr(node, attr)) * scale)
    xml2::xml_set_attr(node, attr, format(value, scientific = FALSE))
  }
}

# Removes the relationships to a target from a relationships part
drop_relationships <- function(file, target) {
  edit_part(file, function(doc, ns) {
    xml2::xml_remove(xml2::xml_find_all(doc, sprintf("//*[@Target = '%s']", target)))
  })
}

# Zips a folder into an Office file, [Content_Types].xml first, with fixed
# times, so that the same parts always make the same file
pack <- function(dir, target) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  files <- c("[Content_Types].xml", setdiff(files, "[Content_Types].xml"))
  Sys.setFileTime(file.path(dir, files), as.POSIXct("2026-01-01 00:00:00", tz = "UTC"))
  # zip() works from `root`, so the target's path must not be relative
  target <- file.path(normalizePath(dirname(target)), basename(target))
  unlink(target)
  zip::zip(target, files, root = dir, mode = "mirror")
}

app_properties <- paste0(
  '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n',
  '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" ',
  'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">',
  "<Application>Prescription Explorer</Application>",
  "<PresentationFormat>Widescreen</PresentationFormat>",
  '<ScaleCrop>false</ScaleCrop><HeadingPairs><vt:vector size="2" baseType="variant">',
  "<vt:variant><vt:lpstr>Theme</vt:lpstr></vt:variant><vt:variant><vt:i4>1</vt:i4></vt:variant>",
  '</vt:vector></HeadingPairs><TitlesOfParts><vt:vector size="1" baseType="lpstr">',
  "<vt:lpstr>Office Theme</vt:lpstr></vt:vector></TitlesOfParts><LinksUpToDate>false",
  "</LinksUpToDate><SharedDoc>false</SharedDoc><HyperlinksChanged>false</HyperlinksChanged>",
  "<AppVersion>16.0000</AppVersion></Properties>"
)

# report.docx is officer's template.docx, A4 with 2.5 cm margins:
# - in the brand's theme (brand_office_theme()), renamed from officer's
#   French one, with IBM Plex Sans as its fonts, and IBM Plex Sans and Mono
#   in the font table, with what Word picks a substitute by (export_fonts());
# - in the text's colour, its headings' rule too, with captions in the
#   secondary text's colour, upright and left-aligned, as the PowerPoint's;
# - with its styles' names and ids in English, as Word names them, rather
#   than in French, and headings that are not numbered;
# - with a Title style for the report's title, 6 points after a paragraph,
#   and a table style, Report Table, with its paragraph style, Table Text:
#   9 points, a bold header row over a rule in the text colour, a light rule
#   under each row, and a bold total row under a rule in the text colour, as
#   the PowerPoint's tables;
# - with a page started by each Heading 1, a table's caption kept with its
#   table, and a List Bullet style that is a list, which screen readers
#   announce as one;
# - in British English, for Word's proofing, as the charts are, opening at
#   100%, with English separators, rather than officer's 180% and French ones;
# - with neutral document properties in English, rather than officer's
#   author's name and French ones, and no revision number or counts that
#   officer would not update.
make_docx_template <- function(target) {
  dir <- tempfile("docx-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  utils::unzip(system.file("template", "template.docx", package = "officer"), exdir = dir)
  part <- function(...) file.path(dir, ...)

  # The brand's theme, under the brand's name
  edit_part(part("word", "theme", "theme1.xml"), function(doc, ns) {
    brand_office_theme(doc, name = brand_name)
  })
  # The exports' fonts in the font table
  edit_part(part("word", "fontTable.xml"), function(doc, ns) {
    for (font in export_fonts()) {
      xml2::xml_add_child(xml2::xml_root(doc), xml2::read_xml(font_entry(font)))
    }
  })

  # The styles' ids, wherever they are named
  for (file in c(part("word", "styles.xml"), part("word", "numbering.xml"))) {
    xml <- readLines(file, encoding = "UTF-8", warn = FALSE)
    for (id in names(english_ids)) {
      for (attr in c("w:styleId", "w:val")) {
        xml <- gsub(
          sprintf('%s="%s"', attr, id), sprintf('%s="%s"', attr, english_ids[[id]]), xml,
          fixed = TRUE
        )
      }
    }
    writeLines(xml, file, useBytes = TRUE)
  }
  # The styles: English names, headings not numbered, space after a
  # paragraph, the text's colour, and the report's own styles
  colours <- sub("#", "", export_palette(), fixed = TRUE)
  edit_part(part("word", "styles.xml"), function(doc, ns) {
    english <- c(
      "Titre 1 Car" = "Heading 1 Char", "Titre 2 Car" = "Heading 2 Char",
      "Titre 3 Car" = "Heading 3 Char", "Texte de bulles Car" = "Balloon Text Char"
    )
    for (name in names(english)) {
      node <- xml2::xml_find_first(doc, sprintf("//w:style/w:name[@w:val = '%s']", name), ns)
      xml2::xml_set_attr(node, "w:val", english[[name]])
    }
    xml2::xml_remove(xml2::xml_find_all(
      doc, "//w:style[starts-with(@w:styleId, 'Heading')]/w:pPr/w:numPr", ns
    ))
    normal <- xml2::xml_find_first(doc, "//w:style[@w:styleId = 'Normal']", ns)
    xml2::xml_add_child(normal, xml2::read_xml(normal_spacing))
    # British English, as the charts, for Word's proofing; every text in the
    # text's colour, after the fonts, as a run's properties order them
    defaults <- xml2::xml_find_first(doc, "/w:styles/w:docDefaults/w:rPrDefault/w:rPr", ns)
    xml2::xml_set_attr(xml2::xml_child(defaults, "w:lang"), "w:val", "en-GB")
    xml2::xml_add_sibling(
      xml2::xml_child(defaults, "w:rFonts"), "w:color", "w:val" = colours[["text"]],
      .where = "after"
    )
    # An item, and the methods, start a page: no break paragraph, which would
    # leave a blank page when a table ends at the foot of one. In the order
    # of a paragraph's properties: after keepLines, before the border.
    heading <- xml2::xml_find_first(doc, "//w:style[@w:styleId = 'Heading1']/w:pPr", ns)
    xml2::xml_add_sibling(xml2::xml_child(heading, "w:keepLines"), "w:pageBreakBefore",
                          .where = "after")
    # Its rule in the text's colour, not Word's automatic black
    rule <- xml2::xml_find_first(heading, "w:pBdr/w:bottom", ns)
    xml2::xml_set_attr(rule, "w:color", colours[["text"]])
    # A table's caption on the page of its table's first row, as the
    # PowerPoint's: upright, left-aligned, in the secondary text's colour
    caption <- xml2::xml_find_first(doc, "//w:style[@w:styleId = 'TableCaption']", ns)
    xml2::xml_add_child(caption, xml2::read_xml(caption_paragraph))
    xml2::xml_add_child(caption, xml2::read_xml(caption_text(colours[["secondary"]])))
    styles <- c(title_style, table_text_style, report_table_style(colours), list_bullet_style)
    for (style in styles) {
      xml2::xml_add_child(xml2::xml_root(doc), xml2::read_xml(style))
    }
  })

  # The numbering's levels, unlinked from the headings, which are not
  # numbered; and the bullets of List Bullet, the abstract definitions before
  # the numbers, as the numbering's schema orders them
  edit_part(part("word", "numbering.xml"), function(doc, ns) {
    xml2::xml_remove(xml2::xml_find_all(
      doc, "//w:lvl/w:pStyle[starts-with(@w:val, 'Heading')]", ns
    ))
    abstracts <- xml2::xml_find_all(doc, "/w:numbering/w:abstractNum", ns)
    stopifnot(!bullet_ids[["abstract"]] %in% xml2::xml_attr(abstracts, "abstractNumId"))
    xml2::xml_add_sibling(
      abstracts[[length(abstracts)]], xml2::read_xml(bullet_abstract), .where = "after"
    )
    nums <- xml2::xml_find_all(doc, "/w:numbering/w:num", ns)
    stopifnot(!bullet_ids[["num"]] %in% xml2::xml_attr(nums, "numId"))
    xml2::xml_add_child(xml2::xml_root(doc), xml2::read_xml(bullet_num))
  })

  # The settings officer copies into every document: 100% zoom, English
  # separators for fields, British English
  edit_part(part("word", "settings.xml"), function(doc, ns) {
    set <- function(name, attr, value) {
      node <- xml2::xml_find_first(doc, paste0("/w:settings/w:", name), ns)
      xml2::xml_set_attr(node, paste0("w:", attr), value)
    }
    set("zoom", "percent", "100")
    set("decimalSymbol", "val", ".")
    set("listSeparator", "val", ",")
    set("themeFontLang", "val", "en-GB")
  })

  # The document's properties
  edit_part(part("docProps", "core.xml"), function(doc, ns) {
    for (name in c("dc:title", "dc:creator", "cp:lastModifiedBy")) {
      node <- xml2::xml_find_first(doc, paste0("//", name), ns)
      xml2::xml_text(node) <- ""
    }
    xml2::xml_remove(xml2::xml_find_first(doc, "//cp:revision", ns))
  })
  writeLines(docx_app_properties, part("docProps", "app.xml"), useBytes = TRUE)

  pack(dir, target)
}

# The ids of officer's styles, French, as Word names them in English
english_ids <- c(
  Titre1 = "Heading1", Titre2 = "Heading2", Titre3 = "Heading3",
  Titre1Car = "Heading1Char", Titre2Car = "Heading2Char", Titre3Car = "Heading3Char",
  Policepardfaut = "DefaultParagraphFont", TableauNormal = "TableNormal",
  Aucuneliste = "NoList", "Listeclaire-Accent2" = "LightList-Accent2",
  Tableauprofessionnel = "TableProfessional", TM1 = "TOC1", TM2 = "TOC2",
  Textedebulles = "BalloonText", TextedebullesCar = "BalloonTextChar"
)

w_ns <- "xmlns:w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'"

# A font of the font table: its classification, its character set, and its
# family and pitch, in the order of the table's schema
font_entry <- function(font) {
  paste0(
    "<w:font ", w_ns, " w:name='", font$typeface, "'>",
    "<w:panose1 w:val='", font$panose, "'/><w:charset w:val='00'/>",
    "<w:family w:val='", font$family, "'/><w:pitch w:val='", font$pitch, "'/></w:font>"
  )
}

# 6 points after a paragraph of the body
normal_spacing <- paste0("<w:pPr ", w_ns, "><w:spacing w:after='120'/></w:pPr>")

# A caption: kept on the page of the next paragraph, its table's, left-aligned
# rather than centred as officer's Image Caption, which it is based on; and
# 10 points, upright and of normal weight, rather than bold and italic, in a
# colour
caption_paragraph <- paste0(
  "<w:pPr ", w_ns, "><w:keepNext/><w:jc w:val='left'/></w:pPr>"
)
caption_text <- function(colour) {
  paste0(
    "<w:rPr ", w_ns, "><w:b w:val='0'/><w:bCs w:val='0'/><w:i w:val='0'/><w:iCs w:val='0'/>",
    "<w:color w:val='", colour, "'/><w:sz w:val='20'/><w:szCs w:val='20'/></w:rPr>"
  )
}

# List Bullet: a list of one level, a bullet hanging to the left of the text.
# Its numbering's ids, which officer's template does not use.
bullet_ids <- c(abstract = "3", num = "4")
list_bullet_style <- paste0(
  "<w:style ", w_ns, " w:type='paragraph' w:styleId='ListBullet'>",
  "<w:name w:val='List Bullet'/><w:basedOn w:val='Normal'/><w:uiPriority w:val='99'/>",
  "<w:unhideWhenUsed/><w:qFormat/>",
  "<w:pPr><w:numPr><w:numId w:val='", bullet_ids[["num"]], "'/></w:numPr>",
  "<w:ind w:left='360' w:hanging='360'/></w:pPr></w:style>"
)
bullet_abstract <- paste0(
  "<w:abstractNum ", w_ns, " w:abstractNumId='", bullet_ids[["abstract"]], "'>",
  "<w:multiLevelType w:val='singleLevel'/><w:lvl w:ilvl='0'><w:start w:val='1'/>",
  "<w:numFmt w:val='bullet'/><w:pStyle w:val='ListBullet'/>",
  "<w:lvlText w:val='", intToUtf8(0x2022), "'/><w:lvlJc w:val='left'/>",
  "<w:pPr><w:ind w:left='360' w:hanging='360'/></w:pPr></w:lvl></w:abstractNum>"
)
bullet_num <- paste0(
  "<w:num ", w_ns, " w:numId='", bullet_ids[["num"]], "'><w:abstractNumId w:val='",
  bullet_ids[["abstract"]], "'/></w:num>"
)

# A table's paragraphs: 9 points, no space around
table_text_style <- paste0(
  "<w:style ", w_ns, " w:type='paragraph' w:customStyle='1' w:styleId='TableText'>",
  "<w:name w:val='Table Text'/><w:basedOn w:val='Normal'/><w:qFormat/>",
  "<w:pPr><w:spacing w:before='0' w:after='0'/></w:pPr>",
  "<w:rPr><w:sz w:val='18'/><w:szCs w:val='18'/></w:rPr></w:style>"
)

# The report's tables, as the PowerPoint's: a bold header row over a 1 pt
# rule in the text colour, a light half-point rule under each row, a bold
# total row under a 1 pt rule in the text colour, no bands, narrow cell
# margins. Rules in eighths of a point.
report_table_style <- function(colours) {
  rule <- function(side, size, colour) {
    sprintf("<w:%s w:val='single' w:sz='%d' w:space='0' w:color='%s'/>", side, size, colour)
  }
  paste0(
    "<w:style ", w_ns, " w:type='table' w:customStyle='1' w:styleId='ReportTable'>",
    "<w:name w:val='Report Table'/><w:basedOn w:val='TableNormal'/>",
    "<w:uiPriority w:val='59'/><w:qFormat/>",
    "<w:pPr><w:spacing w:before='0' w:after='0'/></w:pPr>",
    "<w:rPr><w:sz w:val='18'/><w:szCs w:val='18'/></w:rPr>",
    "<w:tblPr><w:tblStyleRowBandSize w:val='1'/><w:tblBorders>",
    rule("bottom", 4L, colours[["row_rule"]]), rule("insideH", 4L, colours[["row_rule"]]),
    "</w:tblBorders><w:tblCellMar><w:top w:w='20' w:type='dxa'/>",
    "<w:left w:w='80' w:type='dxa'/><w:bottom w:w='20' w:type='dxa'/>",
    "<w:right w:w='80' w:type='dxa'/></w:tblCellMar></w:tblPr>",
    "<w:tblStylePr w:type='firstRow'><w:rPr><w:b/><w:bCs/></w:rPr><w:tcPr><w:tcBorders>",
    rule("bottom", 8L, colours[["rule"]]),
    "</w:tcBorders></w:tcPr></w:tblStylePr>",
    "<w:tblStylePr w:type='lastRow'><w:rPr><w:b/><w:bCs/></w:rPr><w:tcPr><w:tcBorders>",
    rule("top", 8L, colours[["rule"]]),
    "</w:tcBorders></w:tcPr></w:tblStylePr>",
    "</w:style>"
  )
}

# A Title paragraph style: 26 points, as the first line of the report
title_style <- paste0(
  "<w:style ", w_ns, " w:type='paragraph' w:styleId='Title'>",
  "<w:name w:val='Title'/><w:basedOn w:val='Normal'/><w:next w:val='Normal'/><w:qFormat/>",
  "<w:pPr><w:spacing w:after='240'/><w:outlineLvl w:val='9'/></w:pPr>",
  "<w:rPr><w:rFonts w:asciiTheme='majorHAnsi' w:hAnsiTheme='majorHAnsi'/>",
  "<w:sz w:val='52'/><w:szCs w:val='52'/></w:rPr></w:style>"
)

docx_app_properties <- paste0(
  '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n',
  '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" ',
  'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">',
  "<Application>Prescription Explorer</Application><DocSecurity>0</DocSecurity>",
  "<ScaleCrop>false</ScaleCrop><LinksUpToDate>false</LinksUpToDate>",
  "<SharedDoc>false</SharedDoc><HyperlinksChanged>false</HyperlinksChanged>",
  "<AppVersion>16.0000</AppVersion></Properties>"
)

# The brand's colours and fonts, from the package
pkgload::load_all(".", quiet = TRUE)
dir.create("inst/templates", showWarnings = FALSE)
make_pptx_template("inst/templates/report.pptx")
size <- officer::slide_size(officer::read_pptx("inst/templates/report.pptx"))
message("inst/templates/report.pptx: ", round(size$width, 3), " by ", size$height, " inches")
make_docx_template("inst/templates/report.docx")
styles <- officer::styles_info(officer::read_docx("inst/templates/report.docx"))
message("inst/templates/report.docx: ", nrow(styles), " styles, Title among them: ",
        "Title" %in% styles$style_name)
