# The methods text (spec sections 5.3 and 5.5): what the data is, what each
# measure means, its limitations, and the source and licence. The About tab
# shows it, and the exports (P5-04) add it as their methods section, so it is
# written once, here, as plain sections that each format renders its own way.

#' The attribution the data's licence requires
#'
#' The Open Government Licence asks every reuse to include "NHSBSA Copyright"
#' with the years the portal gives (docs/dataset.md). The years are the
#' portal's page text and will change: the app keeps them here, the README in
#' its own place.
#'
#' @return A list with `statement`, `licence` and `licence_url`, and the
#'   source's `source` and `source_url`.
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
#'   `unit` (how a value is counted: `"items"`, `"units"`, `"ADQs"`, or the pound
#'   sign for the costs)
#'   and `definition`.
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
        "The basic price of the drug or appliance, from the Drug Tariff or the manufacturer's",
        "list price, before discounts, dispensing fees and other payments."
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
#' @return A list of sections, each a list with `title`, `text` (paragraphs)
#'   and `points` (a list, each point a named pair of `term` and `text`, the
#'   term `NA` for a plain point).
#' @noRd
methods_sections <- function() {
  measures <- measure_info()
  attribution <- data_attribution()
  list(
    list(
      title = "The data",
      text = c(
        paste(
          "Prescription Explorer shows NHS England's English Prescribing Dataset: the",
          "prescriptions written in England and dispensed in the community, month by month, as",
          "the NHS Business Services Authority publishes them. It holds the most recent twelve",
          "months; each new month replaces the oldest."
        ),
        paste(
          "Prescriptions are counted by the month they were dispensed in and by the practice or",
          "other prescriber that wrote them. Each prescriber's region and integrated care board",
          "(ICB) are those of the latest month, so every month is shown in today's geography."
        )
      ),
      points = list()
    ),
    list(
      title = "Measures",
      text = character(),
      points = Map(
        function(term, text) list(term = term, text = text),
        measures$label, measures$definition,
        USE.NAMES = FALSE
      )
    ),
    list(
      title = "Limitations",
      text = character(),
      points = lapply(
        c(
          paste(
            "Community dispensing only. Items dispensed in hospitals, dental prescribing,",
            "supplies under Patient Group Directions (such as Pharmacy First) and private",
            "prescriptions are not included."
          ),
          paste(
            "No patient detail. The data says what was prescribed and dispensed, and by whom,",
            "but not to whom or why."
          ),
          paste(
            "Costs are list prices before discounts, not what the NHS paid in the end."
          ),
          paste(
            "Quantities are not comparable across forms: a tablet, a millilitre and a gram are",
            "different units."
          ),
          paste(
            "Regions and ICBs follow the commissioner, not the address: a service can carry the",
            "ICB that commissions it, far from where it is. ICBs were reorganised in April 2026."
          ),
          paste(
            "Prescriptions not linked to a practice, from unidentified prescribers, count in",
            "national and regional totals but cannot be searched as practices."
          )
        ),
        function(text) list(term = NA_character_, text = text)
      )
    ),
    list(
      title = "Source and licence",
      text = c(
        paste0("Source: ", attribution$source, "."),
        paste(attribution$statement, "\u00b7", attribution$licence)
      ),
      points = list()
    )
  )
}
