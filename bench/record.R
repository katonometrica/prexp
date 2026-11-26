# Records a session for the load test (P4-08) through shinyloadtest's proxy,
# in a container of its own on the Compose network, so that the host's browser
# can reach the proxy. The recording goes to bench/recording.log, or to the
# file in bench/ that its argument names:
#
#   docker compose run --rm -p 127.0.0.1:8600:8600 --entrypoint bash rstudio \
#     -c 'Rscript -e "install.packages(\"shinyloadtest\", quiet = TRUE)" &&
#         Rscript /home/rstudio/prexp/bench/record.R recording.log'
#
# then open http://127.0.0.1:8600. Wait until the page has connected: the From
# and To months show, styled like the search box; reload it if they do not.
# Then go through the session. bench/recording.log:
#
# 1. Drug: search "atorva", pick Atorvastatin; change From to Jan 2026.
# 2. Practice: search "N81655", pick the practice; Next, then Previous.
# 3. Region: search "metformin hydro", pick Metformin hydrochloride.
#
# bench/recording-largest.log, the chemical with the most presentations:
#
# 1. Drug: search "2003", pick Wound Management & Other Dressings; change From
#    to Jan 2026; change the measure to Actual cost.
#
# Leave the page (close the tab, or open another page) to end the session,
# and stop the container (Ctrl+C) if it does not stop by itself. Then tidy the
# recording for shinycannon with bench/tidy.R.
#
# The browser's cache decides which of the page's files it asks for, and so
# which shinycannon fetches. bench/recording.log was made with the cache on,
# after earlier visits: it asks for the page and 16 files, 10 of them only
# revalidated. bench/recording-largest.log is a first visit, the page and 32
# files: it was recorded through another host port (-p 127.0.0.1:8601:8600,
# then http://127.0.0.1:8601), an address the browser had not visited.
# Turning the cache off in the browser's developer tools also gives a first
# visit.
# The app must be the app container (docker compose --profile app up -d --build app).
#
# Since P6-02 a pick's view is one message, so the recordings made before
# (bench/recording.log, bench/recording-largest.log) no longer replay against
# the app: bench/recording-p602.log and bench/recording-largest-p602.log are
# the same sessions recorded again, by bench/drive.R in the rstudio container,
# which has shinyloadtest (bench/setup.sh) and Chrome. The second argument is
# the app (http://app:3838 by default), the third the proxy's port:
#
#   Rscript bench/record.R recording-p602.log http://app:3838 8600 &
#   Rscript bench/drive.R ordinary http://127.0.0.1:8600/
#   Rscript bench/tidy.R bench/recording-p602.log
#
# A recording against another app, such as the production server, names it
# in its "# target_url:" line: write <app-host> there before it is committed.

args <- commandArgs(trailingOnly = TRUE)
shinyloadtest::record_session(
  if (length(args) > 1L) args[[2L]] else "http://app:3838",
  host = "0.0.0.0",
  port = if (length(args) > 2L) as.integer(args[[3L]]) else 8600L,
  output_file = file.path(
    "/home/rstudio/prexp/bench", if (length(args) > 0L) args[[1L]] else "recording.log"
  ),
  open_browser = FALSE
)
