# Prescription Explorer images (docs/spec.md §1, §2.1). Build from the repository root:
#   docker build -f docker/Dockerfile --target <stage> -t prexp-<stage>:local .
#
#   base  R 4.6.1, system libraries, psql 18 and every package in renv.lock
#   ci    base; Google Chrome is added in phase 6 (P6-01)  -> ghcr.io/katonometrica/prexp-ci
#   dev   base, RStudio Server, git and development tools   -> Compose service rstudio
#   app   base and the installed prexp package, non-root    -> ghcr.io/katonometrica/prexp-app

# ------------------------------------------------------------------- base
# rocker/r-ver:4.6.1 is Ubuntu 24.04 (noble). It is frozen: R 4.6.2 replaced it on
# 2026-10-29 and rocker does not rebuild older R versions. Its default R repository is
# the Posit Package Manager (P3M) snapshot of 2026-10-28. Pulled from GHCR, where rocker
# publishes the same image as on Docker Hub (same index digest), to avoid Docker Hub's
# rate limits in CI. linux/amd64 manifest:
# sha256:5fd51e501b827a421b2135980cadd83da1724de37b1be7237e3adf790f990138
FROM ghcr.io/rocker-org/r-ver:4.6.1@sha256:780bc87219250a6dfffef6c812999731986fd94d8d5f7e572d1157c923d1b4bb AS base

ARG PG_MAJOR=18
LABEL org.opencontainers.image.source="https://github.com/katonometrica/prexp" \
      org.opencontainers.image.description="Prescription Explorer: R 4.6.1, psql 18 and the locked R packages" \
      org.opencontainers.image.licenses="MIT"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

# Operating system packages
# - apt-get upgrade: the frozen rocker image receives no more Ubuntu security fixes.
# - psql comes from the PostgreSQL apt repository (PGDG) for this image's own Ubuntu
#   codename, read at build time. PGDG "main" now ships libpq 19, so component 18 is
#   added and libpq is pinned to the server's major version. r-ver has no curl.
# - System libraries for the packages in renv.lock, with Ubuntu 24.04 names
#   (libfreetype6-dev and libfontconfig1-dev are only aliases on noble):
#     libpq-dev             RPostgres
#     libxml2-dev           xml2 (lintr, officer)
#     libuv1-dev            fs (testthat > pkgload > fs links libuv.so.1)
#     libcurl4-openssl-dev, libssl-dev                      curl, openssl
#     libfontconfig-dev, libfreetype-dev, libharfbuzz-dev, libfribidi-dev, libpng-dev
#                           systemfonts, textshaping, ggiraph
#     libjpeg-dev, libtiff-dev, libwebp-dev                 ragg (officer)
#   The -dev packages pull in the runtime libraries the P3M binaries link to, and let a
#   package compile from source when no binary exists. Check them whenever renv.lock
#   changes (renv::sysreqs()).
# - Fonts metric-compatible with Arial, Times New Roman and Courier New for charts and
#   Office exports, DejaVu for wide Unicode coverage. unzip as a general tool (the
#   loader reads the monthly archives with bsdtar, added in P1-05). tini runs as
#   process 1 in the app image.
# OS_REFRESH: CI passes the month (for example 2026-11). A new value changes this
# layer's cache key, so the upgrade and everything after it run again once a month;
# otherwise the build cache would keep the first build's OS packages forever. Local
# builds leave it empty and keep their cache.
# UBUNTU_MIRROR: CI passes the runner's own Ubuntu mirror, because archive.ubuntu.com
# can be very slow from GitHub's runners (62 kB/s once). It is used for this layer only:
# the original sources are put back at the end, so the image's apt setup is standard.
ARG OS_REFRESH=
ARG UBUNTU_MIRROR=
RUN <<'EOF'
set -eux
echo "OS packages refreshed for: ${OS_REFRESH:-a local build}"
. /etc/os-release
if [ -n "${UBUNTU_MIRROR}" ]; then
  cp /etc/apt/sources.list.d/ubuntu.sources /tmp/ubuntu.sources.orig
  sed -E -i "s#https?://(archive|security)\.ubuntu\.com/ubuntu/?#${UBUNTU_MIRROR}#g" /etc/apt/sources.list.d/ubuntu.sources
fi
apt-get update
apt-get -y upgrade
apt-get install -y --no-install-recommends ca-certificates curl
install -d /usr/share/postgresql-common/pgdg
curl -fsSL --retry 3 -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc
{
  echo 'Types: deb'
  echo 'URIs: https://apt.postgresql.org/pub/repos/apt'
  echo "Suites: ${VERSION_CODENAME}-pgdg"
  echo "Components: main ${PG_MAJOR}"
  echo 'Signed-By: /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc'
} > /etc/apt/sources.list.d/pgdg.sources
{
  echo 'Package: libpq5 libpq-dev'
  echo "Pin: version ${PG_MAJOR}.*"
  echo 'Pin-Priority: 1001'
} > /etc/apt/preferences.d/pgdg-libpq
apt-get update
apt-get install -y --no-install-recommends "postgresql-client-${PG_MAJOR}" \
  libpq-dev libxml2-dev libuv1-dev libcurl4-openssl-dev libssl-dev \
  libfontconfig-dev libfreetype-dev libharfbuzz-dev libfribidi-dev libpng-dev \
  libjpeg-dev libtiff-dev libwebp-dev fonts-liberation fonts-dejavu-core unzip tini
if [ -f /tmp/ubuntu.sources.orig ]; then
  mv /tmp/ubuntu.sources.orig /etc/apt/sources.list.d/ubuntu.sources
fi
rm -rf /var/lib/apt/lists/*
EOF

# R packages. renv.lock is the only list of package versions. Every stage uses R's site
# library, where the locked packages are installed below, and renv's autoloader is off,
# so renv never switches libraries inside a container (spec §2.1, "Packages").
ENV RENV_CONFIG_AUTOLOADER_ENABLED=FALSE

# Only renv.lock is copied before the restore, so code changes never invalidate the
# package layers. renv is bootstrapped into a throwaway library; restore() then installs
# the locked renv with everything else. Binaries come from the dated P3M snapshot
# recorded in renv.lock (https://p3m.dev/cran/<date>, which renv rewrites to
# .../__linux__/noble/<date>). The cache mount keeps renv's cache between local builds;
# packages are copied, not linked, into the image, and renv's downloads stay on the
# mount. Loading every locked package turns a missing system library into a build error.
COPY renv.lock /opt/prexp/renv.lock
RUN --mount=type=cache,id=prexp-renv-cache,target=/var/cache/renv,sharing=locked <<'EOF'
set -eux
cd /opt/prexp
mkdir -p /tmp/renv-bootstrap
Rscript -e 'install.packages("renv", lib = "/tmp/renv-bootstrap", quiet = TRUE)'
RENV_PATHS_ROOT=/var/cache/renv/root RENV_PATHS_CACHE=/var/cache/renv/cache RENV_CONFIG_CACHE_SYMLINKS=FALSE \
  Rscript -e '.libPaths(c("/tmp/renv-bootstrap", .libPaths())); renv::restore(lockfile = "renv.lock", library = .Library.site[1], prompt = FALSE)'
Rscript -e 'pkgs <- names(renv::lockfile_read("/opt/prexp/renv.lock")[["Packages"]]); for (p in pkgs) loadNamespace(p); message(length(pkgs), " locked packages load")'
rm -rf /tmp/renv-bootstrap /root/.cache/R
EOF

# ------------------------------------------------------------------- ci
FROM base AS ci
# Google Chrome for shinytest2 is added here in phase 6 (P6-01), after the package layer.
# No USER: GitHub Actions job containers must run as root to use the workspace.

# ------------------------------------------------------------------- dev
FROM base AS dev
ARG DEBIAN_FRONTEND=noninteractive

# RStudio Server through rocker's script, pinned to the version rocker ships with R 4.6.1
# (rocker/rstudio:4.6.1); unpinned, the script installs the newest stable. On noble it
# installs the jammy build. The script also installs s6-overlay, git, sudo and wget,
# creates user rstudio (UID 1000, group staff, which can write to the site library), and
# adds the start-up scripts that copy the container environment into Renviron.site, which
# is how PREXP_* variables reach RStudio sessions. install_pandoc.sh links RStudio's
# bundled pandoc. libgit2-dev: gert, loaded by usethis, links libgit2.
# safe.directory: on a Windows bind mount every file appears owned by root, so git run by
# rstudio would refuse the repository as "dubious ownership".
ENV S6_VERSION=v2.1.0.2 RSTUDIO_VERSION=2026.10.1+239 DEFAULT_USER=rstudio
RUN <<'EOF'
set -eux
apt-get update
apt-get install -y --no-install-recommends git libgit2-dev
/rocker_scripts/install_rstudio.sh
/rocker_scripts/install_pandoc.sh
rm -rf /var/lib/apt/lists/*
git config --system --add safe.directory /home/rstudio/prexp
EOF

# Development-only R packages, deliberately not in renv.lock (snapshots are explicit:
# only DESCRIPTION's dependencies are recorded). Installed into the site library from
# the same P3M snapshot as renv.lock, so they never change a locked package's version.
ARG PPM_DATE=2026-10-28
RUN <<'EOF'
set -eux
. /etc/os-release
export DEV_REPO="https://p3m.dev/cran/__linux__/${VERSION_CODENAME}/${PPM_DATE}"
Rscript -e 'install.packages(c("devtools", "usethis", "roxygen2"), repos = c(CRAN = Sys.getenv("DEV_REPO")), Ncpus = 4, quiet = TRUE)'
Rscript -e 'for (p in c("devtools", "usethis", "roxygen2")) loadNamespace(p); message("dev tools load")'
install -d -o rstudio -g rstudio /home/rstudio/prexp
# Group staff, setgid: still writable when compose.yaml remaps rstudio to the host's
# UID and GID (USERID, GROUPID), because rocker keeps rstudio in staff.
install -d -o rstudio -g staff -m 2775 /data/epd
rm -rf /root/.cache/R
EOF
ENV PREXP_DOWNLOAD_DIR=/data/epd

EXPOSE 8787
CMD ["/init"]

# ------------------------------------------------------------------- app
FROM base AS app

# Non-root runtime user. /data/epd is the download directory of the jobs container
# (spec §7, P1-08); a new named volume mounted there takes this owner.
# tini (installed in base) runs as process 1: R installs no SIGTERM handler, and the
# kernel drops unhandled signals for process 1, so without it every stop waits for
# SIGKILL, and child processes (mirai daemons, the loader's pipes) are never reaped.
RUN <<'EOF'
set -eux
useradd --create-home --home-dir /home/prexp --shell /bin/bash --uid 10001 --user-group prexp
install -d -o prexp -g prexp /data/epd
EOF
ENV PREXP_DOWNLOAD_DIR=/data/epd

# The package, installed from source into the site library next to its locked
# dependencies. The build context is bind-mounted rather than copied, so no source layer
# stays in the image; .dockerignore keeps secrets, renv/, tests and docs out.
RUN --mount=type=bind,target=/mnt/src <<'EOF'
set -eux
cp -a /mnt/src /tmp/prexp
cd /tmp
R CMD INSTALL --no-test-load prexp
Rscript -e 'library(prexp); message("prexp ", packageVersion("prexp"), " loads")'
rm -rf /tmp/prexp
EOF

USER prexp
WORKDIR /home/prexp
EXPOSE 3838
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["Rscript", "-e", "prexp::run_app(host = '0.0.0.0', port = 3838)"]
