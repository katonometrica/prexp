# The load test's figures (P4-08), from a replay and the log of the app that
# answered it. First save that log as app.log in the run's folder. For the app
# container, from <start>, the time noted just before the replay (replay.sh):
#
#   docker compose --profile app logs app --no-log-prefix --since <start> > bench/run-1/app.log
#
# For the container without the cache, its whole log, before it stops:
# docker compose logs leaves out containers made by docker compose run, and
# --rm deletes the container with its log.
#
#   docker logs prexp-app-uncached > bench/run-2/app.log 2>&1
#   docker stop prexp-app-uncached
#
# Then, from the repository's root:
#
#   docker compose exec -T -u rstudio -w /home/rstudio/prexp rstudio \
#     Rscript bench/report.R bench/run-1
#
# End to end, from shinycannon's output, over the steady part of the run (the
# sessions run while all the workers were):
# - Per lookup: a user's action (a message the browser sends after a pause of
#   a second or more, or its first) and the app's messages that answer it, up
#   to the first that brings a table or chart (an htmlwidget), or all of them
#   if none does: the sum of their waits. A pick's view comes in two or three
#   messages (its frame; a drug's CSV link; its table and chart), each timed
#   from the event before it. The browser's own work between them (loading
#   libraries, drawing) is not counted, nor is a chart drawn again after the
#   view.
# - Per message (WS_RECV), and each message by its line in the recording.
# - A search's answer includes the 300 ms the server waits for typing to stop
#   (mod_search.R), a pause before the lookup rather than part of it: the
#   figures leave it out, and the searches are also shown with it.
# - The page's HTTP requests: the page itself, then its scripts and styles.
# In the database, from the app's timing log: timing_summary() per fetch, over
# the whole run. shinyloadtest's report goes into the run's folder as
# report.html.

args <- commandArgs(trailingOnly = TRUE)
run <- normalizePath(args[[1L]])
search_wait <- 0.3

# How each replayed session ended: shinycannon writes PLAYBACK_DONE, or
# PLAYBACK_FAIL if it failed, after the session's last event
sessions <- list.files(file.path(run, "sessions"), full.names = TRUE)
events <- lapply(sessions, function(f) utils::read.csv(f, comment.char = "#")$event)
ends <- vapply(events, function(e) e[[length(e)]], "")
closed <- vapply(events, function(e) "WS_CLOSE_END" %in% e, TRUE)
cat(sprintf(
  "Sessions: %d, %d of them replayed to the socket's close; %s\n",
  length(sessions), sum(closed),
  paste(names(table(ends)), table(ends), sep = " ", collapse = ", ")
))

runs <- shinyloadtest::load_runs(`5 workers` = run)
steady <- runs[runs$maintenance, ]
answers <- steady[steady$event == "WS_RECV", ]
search <- grepl("prexp-search-results", answers$label, fixed = TRUE)
waited <- answers$time - search_wait * search

# The lookups, from the recording the run replayed: each of its messages from
# the app is counted in the lookup of the latest action before it, up to the
# first that brings a table or chart
recording <- readLines(file.path(run, "recording.log"), encoding = "UTF-8", warn = FALSE)
at <- which(startsWith(recording, "{"))
event <- lapply(recording[at], jsonlite::fromJSON, simplifyVector = FALSE)
type <- vapply(event, `[[`, "", "type")
stamp <- function(x) as.numeric(as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"))
begin <- vapply(event, function(e) stamp(e$begin), 1)
finish <- vapply(event, function(e) stamp(if (is.null(e$end)) e$begin else e$end), 1)
sent <- type == "WS_SEND"
action <- sent & (cumsum(sent) == 1L | begin - c(-Inf, utils::head(finish, -1L)) >= 1)
received <- type == "WS_RECV"
widget <- received & vapply(event, function(e) {
  values <- if (e$type == "WS_RECV") jsonlite::fromJSON(e$message, simplifyVector = FALSE)$values
  any(vapply(values, function(v) is.list(v) && !is.null(v$x), TRUE))
}, TRUE)
group <- cummax(ifelse(action, seq_along(type), 0L))
upto <- tapply(which(widget), group[widget], min)[as.character(group)]
counted <- received & group > 0L & (is.na(upto) | seq_along(type) <= upto)
lookup_of <- stats::setNames(group[counted], at[counted])[as.character(answers$input_line_number)]
in_lookup <- !is.na(lookup_of)
per_lookup <- tapply(
  waited[in_lookup], paste(answers$session_id, lookup_of)[in_lookup], sum
)

p95 <- function(x) unname(stats::quantile(x, 0.95, type = 1))
figures <- function(x) {
  sprintf(
    "%4d  min %4.0f  p50 %4.0f  p95 %4.0f  max %4.0f ms",
    length(x), 1000 * min(x), 1000 * stats::median(x), 1000 * p95(x), 1000 * max(x)
  )
}
line <- function(what, x) cat(sprintf("  %-38s %s\n", what, figures(x)))

cat(sprintf("\nThe steady part: %d sessions\n", length(unique(steady$session_id))))
cat("Per lookup, the searches' wait aside:\n")
line("All", per_lookup)
cat("Per message (WS_RECV):\n")
line("All, the searches' wait aside", waited)
line("All, with it", answers$time)
line("The views' (not the searches')", answers$time[!search])
line("The searches', with the 300 ms wait", answers$time[search])
cat("Each message, by its line in the recording:\n")
for (n in sort(unique(answers$input_line_number))) {
  here <- answers$input_line_number == n
  cat(sprintf(
    "  Line %3d  %s  %s\n", n, figures(answers$time[here]),
    substr(sub("^Event [0-9]+\\) ", "", answers$label[here][[1L]]), 1L, 60L)
  ))
}
requests <- steady[startsWith(steady$event, "REQ"), ]
home <- requests$event == "REQ_HOME"
cat("The page's HTTP requests:\n")
line("The page itself", requests$time[home])
line("Its scripts and styles", requests$time[!home])

log <- file.path(run, "app.log")
if (file.exists(log)) {
  # The rstudio container has the package's source (run from its root), not
  # the package installed
  if (!requireNamespace("prexp", quietly = TRUE)) pkgload::load_all(quiet = TRUE)
  timing <- prexp::timing_summary(log)
  if (nrow(timing) == 0L) {
    warning(log, " has no timing lines: save the log of the app that answered the run",
      call. = FALSE
    )
  }
  cat("\nThe app's timing log, all the run's fetches:\n")
  print(timing, n = Inf)
} else {
  warning("No app.log in ", run, ": its timing log's figures are left out", call. = FALSE)
}

# Its plots go to a device of no file, not to Rplots.pdf where it runs
grDevices::pdf(NULL)
shinyloadtest::shinyloadtest_report(
  runs, file.path(run, "report.html"), self_contained = TRUE, open_browser = FALSE
)
invisible(grDevices::dev.off())
