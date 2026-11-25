# The methods text (spec sections 5.3 and 5.5): what the data is, what each
# measure means, its limitations, and the source and licence. The About tab
# shows it, and the exports (P5-04) add it as their methods section, so it is
# written once, here, as plain sections that each format renders its own way.
# docs/dataset.md has the facts it rests on.

#' The attribution the data's licence requires
#'
#' The Open Government Licence asks every reuse to include "NHSBSA Copyright"
#' with the years the portal gives (docs/dataset.md). The years are the
#' portal's page text and will change: the app keeps them here, the README in
#' its own place.
#'
#' @return A list with `statement`, `licence` and `licence_url`, and the
#'   source's name `source` and its page `source_url`.
#' @noRd
data_attribution <- function() {
  list(
    statement = "NHSBSA Copyright 2021-2026",
    licence = paste(
      "Contains public sector information licensed under the Open Government Licence v3.0."
    ),
    licence_url = "https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/",
    source = paste(
      "English Prescribing Dataset (EPD) with SNOMED Code, NHS Business Services Authority"
    ),
    source_url = paste0(
      "https://opendata.nhsbsa.net/dataset/english-prescribing-dataset-epd-with-snomed-code"
    )
  )
}

#' The measures, by the names the fetch functions use
#'
#' @return A data frame with `measure` (the fetch functions' name), `label`,
#'   `unit` (how a value is counted: `"items"`, `"units"`, `"ADQs"`, or the
#'   pound sign for the costs) and `definition`.
#' @noRd
measure_info <- function() {
  data.frame(
    measure = c("items", "total_quantity", "adq_usage", "nic", "actual_cost"),
    label = c("Items", "Quantity", "ADQ usage", "Net ingredient cost", "Actual cost"),
    unit = c("items", "units", "ADQs", "\u00a3", "\u00a3"),
    definition = c(
      paste(
        "Prescription items. Each drug or appliance written on a prescription form is one item,",
        "whatever quantity it is for."
      ),
      paste(
        "The total quantity supplied, in the presentation's own unit: tablets, capsules,",
        "millilitres, grams or doses. Units differ between presentations, so quantity is shown",
        "for a single presentation only."
      ),
      paste(
        "Average daily quantities: the quantity divided by the presentation's ADQ, the assumed",
        "average daily dose for an adult. An ADQ is defined for some presentations only. Where",
        "there is none the measure is blank, and a chemical substance's ADQ usage adds up only",
        "its presentations that have one."
      ),
      paste(
        "The cost of the quantity prescribed at its basic price, from the Drug Tariff or the",
        "manufacturer's, wholesaler's or supplier's list price, before any discount, dispensing",
        "fee or other payment."
      ),
      paste(
        "The net ingredient cost less the discount pharmacies are assumed to receive, plus",
        "payments for consumables, containers and some out-of-pocket expenses. It can be more",
        "than the net ingredient cost. Since April 2024 the discount is set for each product",
        "group rather than nationally, which changes the series at that point; the data window",
        "starts after it."
      )
    )
  )
}

#' The methods text, in sections
#'
#' @return A list of sections, each a list with `title`, `text` (paragraphs),
#'   `points` (a list, each point a named pair of `term` and `text`, the term
#'   `NA` for a plain point) and `links` (a list of `text` and `url` pairs).
#' @noRd
methods_sections <- function() {
  measures <- measure_info()
  attribution <- data_attribution()
  plain <- function(text) list(term = NA_character_, text = text)
  list(
    list(
      title = "The data",
      text = c(
        paste(
          "Prescription Explorer shows the English Prescribing Dataset (EPD) with SNOMED Code,",
          "which the NHS Business Services Authority (NHSBSA) publishes each month: the",
          "prescriptions written in England and dispensed in the community. It holds the most",
          "recent twelve months; each new month replaces the oldest."
        ),
        paste(
          "Prescriptions are counted by the month they were dispensed in and by the practice or",
          "other prescriber that wrote them. Each prescriber is shown with the region and",
          "integrated care board (ICB) of the last month it prescribed in: the seven NHS",
          "England regions have not changed, but the ICBs were reorganised in April 2026 (see",
          "Limitations)."
        )
      ),
      points = list(),
      links = list()
    ),
    list(
      title = "Measures",
      text = character(),
      points = Map(
        function(term, text) list(term = term, text = text),
        measures$label, measures$definition,
        USE.NAMES = FALSE
      ),
      links = list()
    ),
    list(
      title = "Limitations",
      text = character(),
      points = list(
        plain(paste(
          "Community dispensing only. Not included: medicines dispensed in hospitals;",
          "prescriptions written under hospital site codes, even when dispensed in the community",
          "(those under hospital cost-centre codes are included); dental prescribing; supplies",
          "under Patient Group Directions (such as Pharmacy First); private prescriptions; and",
          "items not dispensed or not submitted for payment."
        )),
        plain(paste(
          "No patient detail. The data says what was prescribed and dispensed, and by whom, but",
          "not to whom or why."
        )),
        plain(paste(
          "Costs are not what the NHS paid in the end. Net ingredient cost is at list price,",
          "before any discount. Actual cost takes off the discount pharmacies are assumed to",
          "receive and adds some payments to the dispenser, but not dispensing fees."
        )),
        plain(paste(
          "Actual cost changed method in April 2024: from then, the discount taken off is a",
          "rate for each product group, not one national rate. Every month shown comes after",
          "the change, but figures from before it are not comparable."
        )),
        plain(paste(
          "Quantities are not comparable across forms: a tablet, a millilitre and a gram are",
          "different units."
        )),
        plain(paste(
          "ADQ usage counts only what has an ADQ, which about a third of items do not: none",
          "is defined for dressings and appliances, oral anticoagulants or insulins, among",
          "others."
        )),
        plain(paste(
          "Regions and ICBs follow the commissioner, not the address: a service can carry the",
          "ICB that commissions it, far from where it is."
        )),
        plain(paste(
          "ICBs were reorganised in April 2026, from 42 to 36. A prescriber still prescribing",
          "after the change is shown in its new ICB, for its months before the change too; one",
          "that stopped before keeps its old ICB, which no longer exists."
        )),
        plain(paste(
          "Prescriptions from unidentified prescribers, not linked to a practice (under 0.1% of",
          "items), count in national totals but cannot be searched as practices. Those coded",
          "to a commissioner also count in its region. Those under the national unidentified",
          "code have no region, and comparisons by region show them apart from the seven",
          "regions."
        ))
      ),
      links = list()
    ),
    list(
      title = "Source and licence",
      text = c(
        paste0("Source: ", attribution$source, "."),
        paste(attribution$statement, "\u00b7", attribution$licence)
      ),
      points = list(),
      links = list(
        list(text = "The dataset on the NHSBSA portal", url = attribution$source_url),
        list(text = "Open Government Licence v3.0", url = attribution$licence_url)
      )
    )
  )
}

#' The methods section of an export
#'
#' The About tab's sections ([methods_sections()]), so that the app and its
#' exports never disagree, after two that only an export has: when it was
#' made, by which version of the app and on which months of data; and the
#' filters each item was pinned with.
#'
#' @param spec A report ([new_report()]).
#' @param window The data window, as [fetch_window()] gives it.
#' @param exported When the export was made.
#' @return A list of sections, as [methods_sections()] gives them: "This
#'   report", "Filters", then the About tab's.
#' @noRd
methods_content <- function(spec, window, exported = Sys.time()) {
  version <- as.character(utils::packageVersion("prexp"))
  period <- if (is.null(window) || nrow(window) == 0L || is.na(window$first_month[1])) {
    "No months of data were loaded when it was exported."
  } else {
    paste0(
      "Data period: ", format_month(window$first_month[1]), " to ",
      format_month(window$last_month[1]), ", the months loaded when it was exported."
    )
  }
  filters <- lapply(spec$items, function(item) {
    list(term = report_item_title(item), text = item_filters(item))
  })
  c(
    list(
      list(
        title = "This report",
        text = c(
          paste0(
            "Exported from Prescription Explorer ", version, " on ", export_time(exported), "."
          ),
          period
        ),
        points = list(),
        links = list()
      ),
      list(
        title = "Filters",
        text = if (length(filters) == 0L) "The report has no items." else character(),
        points = if (length(filters) == 0L) list() else filters,
        links = list()
      )
    ),
    methods_sections()
  )
}

# When an export was made, in the UK's time, as in "25 November 2026 at 14:05
# GMT". The month comes from month.name, as in format_month(), because
# format()'s %B follows the locale; a POSIXlt goes through POSIXct, because
# format() ignores tz for one; and the zone, GMT or BST, tells apart the hour
# that comes twice when the clocks go back.
export_time <- function(exported) {
  uk <- as.POSIXlt(as.POSIXct(exported), tz = "Europe/London")
  paste0(
    uk$mday, " ", month.name[uk$mon + 1L], " ", uk$year + 1900L, " at ",
    sprintf("%02d:%02d", uk$hour, uk$min), " ", format(uk, "%Z")
  )
}

# An item's filters, in words: its view, subject and code, months and measure,
# and whether a link moved its months into the data window
item_filters <- function(item) {
  params <- item$params
  info <- measure_info()
  measure <- info$label[match(params$measure, info$measure)]
  text <- paste0(
    report_item_summary(item), " (", params$label, "); months: ",
    format_month_span(params$months), "; measure: ",
    measure, "."
  )
  if (isTRUE(item$clamped)) {
    text <- paste(
      text, "Its months were moved into the data window when the report's link was opened."
    )
  }
  text
}
