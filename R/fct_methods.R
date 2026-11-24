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
          "integrated care board (ICB) of the last month it prescribed in. The seven NHS England",
          "regions did not change. ICBs were reorganised in April 2026: a prescriber still",
          "prescribing after that is shown in its new ICB for every month, while one that",
          "stopped before keeps the ICB it had, which no longer exists."
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
          "Quantities are not comparable across forms: a tablet, a millilitre and a gram are",
          "different units."
        )),
        plain(paste(
          "Regions and ICBs follow the commissioner, not the address: a service can carry the",
          "ICB that commissions it, far from where it is."
        )),
        plain(paste(
          "Prescriptions from unidentified prescribers, not linked to a practice, count in",
          "national totals but cannot be searched as practices. Those coded to a commissioner",
          "also count in its region. Those under the national unidentified code have no region,",
          "and comparisons by region show them apart from the seven regions."
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
