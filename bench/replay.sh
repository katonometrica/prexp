#!/usr/bin/env bash
# Replays a recorded session (P4-08) against the app: 5 simulated users for 5
# minutes of steady load, with shinycannon, from the rstudio container
# (bench/setup.sh installs it). Its arguments: the run's folder in bench/
# (run-<name>), the app's address (http://app:3838 by default) and the
# recording (recording.log by default):
#
#   docker compose exec -T -u rstudio rstudio bash /home/rstudio/prexp/bench/replay.sh run-1
#
# The app is the app container on the full database, and the machine quiet.
# Build its image from the commit to measure, from a clean working tree (the
# build copies it, and nothing in a run's output says which build answered),
# and note the commit. Restart it before the replay, so that its cache does
# not start with the recording's lookups (record.R goes through it), and note
# the time: bench/report.R reads the app's log from then on.
#
#   docker compose --profile app up -d --build app
#   git rev-parse --short HEAD
#   docker compose --profile app restart app
#   date -u +%Y-%m-%dT%H:%M:%SZ
#
# Every replayed session asks the same things, so after the first one the
# app's cache answers them. To send every lookup to the database instead, as
# when each user asks for something not yet in the cache, start the app image
# without its cache (app_server() takes NULL as no cache), wait until its log
# says it is listening, and name it as the second argument:
#
#   docker compose --profile app run --rm -d --name prexp-app-uncached app \
#     Rscript -e 'utils::assignInNamespace("app_cache", function(...) NULL, "prexp")
#                 prexp::run_app(host = "0.0.0.0", port = 3838)'
#   docker logs prexp-app-uncached
#   docker compose exec -T -u rstudio rstudio bash /home/rstudio/prexp/bench/replay.sh \
#     run-2 http://prexp-app-uncached:3838
#
# Then save that container's log, and only then stop it, as bench/report.R
# says. Another recording is named third, as for the largest chemical:
#
#   docker compose exec -T -u rstudio rstudio bash /home/rstudio/prexp/bench/replay.sh \
#     run-3 http://app:3838 recording-largest.log
#
# In Git Bash, put MSYS_NO_PATHCONV=1 before these commands, or it turns their
# container paths into Windows paths.
set -euo pipefail
cd "$(dirname "$0")"
out="${1:?name the run run-<name>, a folder in bench/, for example run-1}"
# shinycannon empties the run's folder first: only ever a run-<name> folder here
if [[ ! $out =~ ^run-[A-Za-z0-9_-]+$ ]]; then
  echo "name the run run-<name>, a folder in bench/, for example run-1" >&2
  exit 2
fi
url="${2:-http://app:3838}"
recording="${3:-recording.log}"
shinycannon "$recording" "$url" \
  --workers 5 --loaded-duration-minutes 5 \
  --output-dir "$out" --overwrite-output
