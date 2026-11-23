#!/usr/bin/env bash
# Prints the fastest Ubuntu mirror for this runner as a plain http(s) URL, or nothing,
# which means the default mirrors. The CI image builds pass it to docker/Dockerfile as
# the build secret ubuntu_mirror (base stage).
#
# The candidates are the mirrors in the runner's own list (its apt sources point at
# mirror+file:/etc/apt/apt-mirrors.txt), Azure's mirror and the main archive. Each is
# timed on the same index file, about 1.5 MB, for at most 10 seconds. The runner's
# first mirror is not always fast: us-east-2.ec2.archive.ubuntu.com delivered packages
# at 100 to 270 kB/s to the runners that listed it, against 20 MB/s and more from
# azure.archive.ubuntu.com on Azure runners. The timings go to standard error.
set -euo pipefail

candidates=()
uri="$(awk '/^URIs:/ {print $2; exit}' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true)"
case "$uri" in
  mirror+file:*)
    while IFS= read -r listed; do
      candidates+=("$listed")
    done < <(grep -oE 'https?://[^[:space:]]+' "${uri#mirror+file:}" 2>/dev/null || true)
    ;;
  ?*) candidates+=("$uri") ;;
esac
candidates+=("http://azure.archive.ubuntu.com/ubuntu/" "http://archive.ubuntu.com/ubuntu/")

codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-noble}")"
best=""
best_speed=0
seen=" "
for mirror in "${candidates[@]}"; do
  [[ "$mirror" =~ ^https?://[A-Za-z0-9.-]+(/[A-Za-z0-9._/-]*)?$ ]] || continue
  mirror="${mirror%/}/"
  case "$seen" in *" $mirror "*) continue ;; esac
  seen="$seen$mirror "
  speed="$(curl -fsS -o /dev/null --connect-timeout 5 --max-time 10 -w '%{speed_download}' \
    "${mirror}dists/${codename}/main/binary-amd64/Packages.gz" 2>/dev/null)" || speed=0
  speed="${speed%%.*}"
  echo "Ubuntu mirror ${mirror}: ${speed:-0} bytes/s" >&2
  if [ "${speed:-0}" -gt "$best_speed" ]; then
    best="$mirror"
    best_speed="$speed"
  fi
done
if [ -n "$best" ]; then
  printf '%s' "$best"
fi
