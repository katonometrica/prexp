# Tidies a recorded session (P4-08) for shinycannon, and writes it over:
#
#   docker compose exec -T -u rstudio -w /home/rstudio/prexp rstudio \
#     Rscript bench/tidy.R bench/recording.log
#
# - The proxy records every page it serves, so a page that did not connect,
#   and was reloaded, leaves its requests in the file: only the last session
#   is kept, from its page request (REQ_HOME) on.
# - The proxy can stop before it writes the socket's close (WS_CLOSE), which
#   ends the session shinycannon replays: one is added, 5 seconds after the
#   last event.
#
# The events kept are written as they were recorded.

path <- commandArgs(trailingOnly = TRUE)[[1L]]
lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
header <- lines[startsWith(lines, "#")]
events <- lines[!startsWith(lines, "#") & nzchar(lines)]
parsed <- lapply(events, jsonlite::fromJSON)
type <- vapply(parsed, `[[`, "", "type")
home <- which(type == "REQ_HOME")
if (length(home) == 0L) stop("No page request (REQ_HOME) in ", path, call. = FALSE)
kept <- seq(max(home), length(events))
events <- events[kept]
added <- !"WS_CLOSE" %in% type[kept]
if (added) {
  times <- vapply(parsed[kept], function(e) if (is.null(e$end)) e$begin else e$end, "")
  last <- max(as.POSIXct(times, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"))
  # %OS3 cuts the milliseconds short; half of one more rounds them
  events <- c(events, sprintf(
    "{\"type\":\"WS_CLOSE\",\"begin\":\"%s\"}",
    format(last + 5.0005, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
  ))
}
# The proxy's container runs as root, so the recording can be root's to write
# while its folder is open to the user who tidies it: write beside it, then
# put that in its place
tmp <- tempfile("tidy-", tmpdir = dirname(path), fileext = ".log")
replaced <- FALSE
tryCatch(
  {
    writeLines(c(header, events), tmp, useBytes = TRUE)
    replaced <- file.rename(tmp, path)
  },
  finally = if (!replaced) unlink(tmp)
)
if (!replaced) stop("Could not replace ", path, call. = FALSE)
cat(sprintf(
  "%s: the last session's %d events of %d kept%s\n",
  path, length(kept), length(parsed), if (added) ", and its close added" else ""
))
