# The search module (spec sections 5.3 and 5.4; P4-03): type-ahead over drugs
# or practices, queried from the database as the user types. A small script
# (inst/app/www/search.js) sends the text from the selectize input to the
# server, which ignores fewer than two characters, waits for 300 ms of quiet,
# runs the fetch and sends up to 20 matches back to the dropdown.

#' The search box
#'
#' @param id The module's id.
#' @param type `"drug"` (chemical substances and presentations) or
#'   `"practice"`.
#' @return Shiny UI: the selectize input and a line for messages.
#' @noRd
mod_search_ui <- function(id, type = c("drug", "practice")) {
  type <- match.arg(type)
  ns <- shiny::NS(id)
  label <- if (type == "drug") "Find a drug" else "Find a practice"
  placeholder <- if (type == "drug") {
    "A name, two letters or more, or a BNF code"
  } else {
    "A practice name or code"
  }
  shiny::tagList(
    shiny::selectizeInput(
      ns("pick"), label = label, choices = NULL, width = "100%",
      options = list(
        placeholder = placeholder,
        valueField = "value", labelField = "label", searchField = c("label", "meta"),
        maxOptions = 20L, loadThrottle = 50L,
        # On the page, not inside the card, which would clip it
        dropdownParent = "body",
        # The server ranks the matches: keep its order
        score = I("function() { return function() { return 1; }; }"),
        sortField = "$order",
        load = I(paste0(
          "function(query, callback) { prexpSearch.load(this, '", ns("query"),
          "', query, callback); }"
        )),
        render = I(paste0(
          "{ option: function(item, escape) { return '<div class=\"prexp-option\">' +",
          " '<div>' + escape(item.label) + '</div>' +",
          " '<div class=\"prexp-option-meta\">' + escape(item.meta) + '</div></div>'; } }"
        ))
      )
    ),
    shiny::div(
      class = "prexp-search-message", role = "status", `aria-live` = "polite",
      shiny::textOutput(ns("message"), inline = TRUE)
    )
  )
}

#' The search's server
#'
#' @param id The module's id.
#' @param fetch A function of the search text that returns the matches, as
#'   [fetch_search_drugs()] or [fetch_search_practices()] with their
#'   connection; the tests pass a fake.
#' @param type `"drug"` or `"practice"`.
#' @return A reactive: `NULL` until something is picked, then a list with
#'   `type`, `id` (integer), `label` and `level` (`"chemical"`,
#'   `"presentation"` or `"practice"`).
#' @noRd
mod_search_server <- function(id, fetch, type = c("drug", "practice")) {
  type <- match.arg(type)
  shiny::moduleServer(id, function(input, output, session) {
    message <- shiny::reactiveVal("")
    seen <- new.env(parent = emptyenv())
    query <- shiny::debounce(shiny::reactive(input$query), 300)

    shiny::observeEvent(query(), {
      text <- trimws(query())
      if (nchar(text) < 2L) {
        message("")
        send_search_results(session, list())
        return()
      }
      found <- tryCatch(fetch(text), error = function(e) e)
      if (inherits(found, "error")) {
        # The app's log gets the error's class only: its message can quote
        # the search text, which the log never holds (spec section 5.4)
        base::message("A search failed: ", class(found)[[1L]])
        message("The search failed. Please try again in a moment.")
        send_search_results(session, list())
        return()
      }
      options <- search_options(found, type)
      for (option in options) {
        seen[[option$value]] <- option
      }
      message(if (length(options) == 0L) "No matches." else "")
      send_search_results(session, options)
    })

    output$message <- shiny::renderText(message())

    shiny::reactive({
      value <- input$pick
      if (is.null(value) || !nzchar(value)) {
        return(NULL)
      }
      picked <- seen[[value]]
      parts <- strsplit(value, ":", fixed = TRUE)[[1]]
      list(
        type = type,
        id = as.integer(parts[2]),
        label = if (is.null(picked)) NA_character_ else picked$label,
        level = parts[1]
      )
    })
  })
}

# The matches as the dropdown's options, in the fetch's order. The value
# carries the level, since chemical and presentation ids are numbered apart.
search_options <- function(found, type) {
  if (nrow(found) == 0L) {
    return(list())
  }
  if (type == "drug") {
    level <- found$level
    value <- paste0(level, ":", found$id)
    label <- ifelse(is.na(found$name), found$code, found$name)
    meta <- paste(
      ifelse(level == "chemical", "Chemical substance", "Presentation"), "\u00b7", found$code
    )
  } else {
    value <- paste0("practice:", found$practice_id)
    label <- ifelse(is.na(found$practice_name), found$practice_code, found$practice_name)
    icb <- ifelse(is.na(found$icb_name), "", paste(" \u00b7", found$icb_name))
    meta <- paste0(found$practice_code, icb)
  }
  lapply(seq_along(value), function(i) {
    list(value = value[i], label = label[i], meta = meta[i])
  })
}

# The answer to the dropdown that asked: search.js hands the options to the
# selectize input whose query input is named in `id`
send_search_results <- function(session, options) {
  session$sendCustomMessage(
    "prexp-search-results", list(id = session$ns("query"), options = options)
  )
}
