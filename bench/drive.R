# Goes through one of the load test's sessions (P4-08) in a headless Chrome,
# at the times of the first recordings, so that a recording can be made again
# the same way: run it against shinyloadtest's proxy (bench/record.R), from
# the rstudio container, which has Chrome:
#
#   Rscript bench/drive.R ordinary http://127.0.0.1:8600/
#
# ordinary (bench/recording-p602.log): Drug: search "atorva", pick
# Atorvastatin; From Jan 2026. Practice: search "N81655", pick it; Next, then
# Previous. Region: search "metformin hydro", pick Metformin hydrochloride.
# largest (bench/recording-largest-p602.log): Drug: search "2003", pick Wound
# Management & Other Dressings; From Jan 2026; the measure Actual cost.
# Each action waits for its time in the session (seconds from the page's
# connection, as in bench/recording.log) and for the app to be idle. A search
# is put in at once, as a paste is, so the browser sends the server one query
# and gets one answer. Typed, the browser sends the first letter and then the
# whole text, and on a busy server the 300 ms wait for typing to stop can
# pass between the two: the first is answered too (an empty list), and a
# replay, which expects the recording's messages in order, fails.
# Each run is a new Chrome, so a first visit: the page asks for all its files.
suppressPackageStartupMessages(library(chromote))
argv <- commandArgs(trailingOnly = TRUE)
scenario <- argv[[1L]]
url <- argv[[2L]]

b <- ChromoteSession$new(width = 1920, height = 1080)
b$default_timeout <- 60
js <- function(x) b$Runtime$evaluate(x, returnByValue = TRUE)$result$value
run <- function(x) invisible(b$Runtime$evaluate(paste0("void (", x, ")")))
pump <- function(secs) {
  end <- Sys.time() + secs
  while (Sys.time() < end) later::run_now(0.02)
}
wait <- function(cond, timeout = 60) {
  started <- Sys.time()
  repeat {
    if (isTRUE(js(cond))) return(invisible(TRUE))
    if (difftime(Sys.time(), started, units = "secs") > timeout) stop("timed out: ", cond)
    pump(0.05)
  }
}
idle <- function(secs = 1) {
  wait("!document.documentElement.classList.contains('shiny-busy')")
  pump(secs)
  wait("!document.documentElement.classList.contains('shiny-busy')")
}
started <- NULL
at <- function(second, what) {
  left <- second - as.numeric(difftime(Sys.time(), started, units = "secs"))
  if (left > 0) pump(left)
  cat(sprintf("%6.1f s  %s\n", as.numeric(difftime(Sys.time(), started, units = "secs")), what))
}
box <- function(view) sprintf("document.getElementById('%s-search-pick').selectize", view)
# An option by its name, or for a practice by its code, which starts the
# option's second line
option <- function(view, kind, text) {
  test <- if (kind == "practice") {
    sprintf("var p = o.querySelector('.prexp-option-meta'); return p && p.innerText.indexOf('%s') === 0;", text)
  } else {
    sprintf("var p = o.firstElementChild; return p && p.innerText === '%s';", text)
  }
  sprintf(paste0(
    "Array.from(%s.$dropdown[0].querySelectorAll(\"[data-value^='%s:']\"))",
    ".find(function (o) { %s })"
  ), box(view), kind, test)
}
search <- function(second, view, text) {
  at(second, paste(view, "search", text))
  run(paste0(box(view), ".focus()"))
  b$Input$insertText(text = text)
}
pick <- function(second, view, kind, text) {
  find <- option(view, kind, text)
  wait(paste0("(", find, ") !== undefined"))
  at(second, paste(view, "pick", text))
  run(paste0("(", find, ").click()"))
  idle()
  run("document.activeElement.blur()")
}
from_month <- function(second, view, month) {
  at(second, paste(view, "from", month))
  run(sprintf("document.getElementById('%s-from').selectize.setValue('%s')", view, month))
  idle()
}
set_measure <- function(second, view, measure) {
  at(second, paste(view, "measure", measure))
  run(sprintf("document.querySelector(\"input[name='%s-measure'][value='%s']\").click()",
              view, measure))
  idle()
}
tab <- function(second, name) {
  at(second, paste("tab", name))
  run(sprintf("document.querySelector(\".navbar a[data-value='%s']\").click()", name))
  idle()
}
button <- function(second, id) {
  wait(sprintf("document.getElementById('%s') && !document.getElementById('%s').disabled", id, id))
  at(second, id)
  run(sprintf("document.getElementById('%s').click()", id))
  idle()
}

b$Page$navigate(url, wait_ = FALSE)
wait(paste(
  "!!(window.Shiny && Shiny.shinyapp && Shiny.shinyapp.isConnected() &&",
  "document.getElementById('drug-from') && document.getElementById('drug-from').selectize)"
))
started <- Sys.time()
idle(2)
if (scenario == "ordinary") {
  search(19.8, "drug", "atorva")
  pick(22.0, "drug", "chemical", "Atorvastatin")
  from_month(43.6, "drug", "202601")
  tab(47.7, "practice")
  search(49.9, "practice", "N81655")
  pick(52.0, "practice", "practice", "N81655")
  button(68.3, "practice-next_page")
  button(81.3, "practice-previous_page")
  tab(87.4, "region")
  search(89.6, "region", "metformin hydro")
  pick(97.8, "region", "chemical", "Metformin hydrochloride")
  at(103, "leave")
} else if (scenario == "largest") {
  search(14.5, "drug", "2003")
  pick(22.0, "drug", "chemical", "Wound Management & Other Dressings")
  from_month(45.1, "drug", "202601")
  set_measure(51.2, "drug", "actual_cost")
  at(56, "leave")
} else {
  stop("no such scenario: ", scenario)
}
b$Page$navigate("about:blank")
pump(3)
b$close()
cat("done\n")
