#!/usr/bin/env bash
# The load test's tools (P4-08), installed into the running rstudio container:
# a Java runtime, shinycannon (which replays a recorded session) and the R
# package shinyloadtest (which records one and reports on the replay). They
# are not in the images: only the load test needs them.
#
#   docker compose exec -T -u root rstudio bash /home/rstudio/prexp/bench/setup.sh
#
# shinycannon comes from Posit's release on GitHub, checked against the
# SHA-256 it had when first installed (24 November 2026); shinyloadtest from
# the same package snapshot as the rest of the project.
set -euo pipefail

SHINYCANNON_VERSION="1.1.3-dd43f6b"
SHINYCANNON_URL="https://github.com/rstudio/shinycannon/releases/download/v1.1.3/shinycannon_${SHINYCANNON_VERSION}_amd64.deb"
SHINYCANNON_SHA256="fa213265cb153ce28f6bb00772d706f964229988e4bd4a069d8f40aab66117e8"

if ! command -v java >/dev/null; then
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends default-jre-headless
fi

if ! command -v shinycannon >/dev/null; then
  deb="$(mktemp --suffix=.deb)"
  curl -fsSL -o "$deb" "$SHINYCANNON_URL"
  actual="$(sha256sum "$deb" | cut -d' ' -f1)"
  echo "shinycannon .deb SHA-256: $actual"
  if [ "$actual" != "$SHINYCANNON_SHA256" ]; then
    echo "SHA-256 mismatch: expected $SHINYCANNON_SHA256" >&2
    exit 1
  fi
  dpkg -i "$deb"
  rm -f "$deb"
fi

Rscript -e 'if (!requireNamespace("shinyloadtest", quietly = TRUE)) install.packages("shinyloadtest", quiet = TRUE)'
Rscript -e 'cat("shinyloadtest", as.character(packageVersion("shinyloadtest")), "\n")'
java -version 2>&1 | head -1
dpkg-query -W -f='shinycannon ${Version}\n' shinycannon
