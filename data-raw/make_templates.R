# Writes the exports' templates in inst/templates/ (spec section 5.5; tickets
# P5-05 and P5-06) from the templates officer ships, so that they hold only
# what this script puts in them. Run from the repository root in the rstudio
# container:
#
#   Rscript data-raw/make_templates.R
#
# report.pptx is officer's template.pptx:
# - widened to 16:9, 13.333 by 7.5 inches, with every shape of its master and
#   layouts widened in proportion, so that the layouts keep their margins;
# - in Arial, the font of the app's charts, rather than Calibri;
# - with neutral document properties in English, rather than officer's
#   author's name and French ones, with no revision number or counts that
#   officer would not update, and without its 4:3 thumbnail and its printer
#   settings;
# - with the editor's vertical guide at the wide slide's centre.

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

  # The theme's fonts
  edit_part(part("ppt", "theme", "theme1.xml"), function(doc, ns) {
    fonts <- xml2::xml_find_all(doc, "//a:majorFont/a:latin | //a:minorFont/a:latin", ns)
    xml2::xml_set_attr(fonts, "typeface", "Arial")
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

# Zips a folder into an Office file, [Content_Types].xml first
pack <- function(dir, target) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  files <- c("[Content_Types].xml", setdiff(files, "[Content_Types].xml"))
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

dir.create("inst/templates", showWarnings = FALSE)
make_pptx_template("inst/templates/report.pptx")
size <- officer::slide_size(officer::read_pptx("inst/templates/report.pptx"))
message("inst/templates/report.pptx: ", round(size$width, 3), " by ", size$height, " inches")
