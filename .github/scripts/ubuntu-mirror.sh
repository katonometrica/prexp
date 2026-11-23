#!/usr/bin/env bash
# Prints this runner's Ubuntu mirror as a plain http(s) URL, or nothing, which means the
# default mirrors. GitHub's runners list their mirrors in a file
# (URIs: mirror+file:/etc/apt/apt-mirrors.txt), and the first plain http(s) entry is
# taken. The CI image builds pass it to docker/Dockerfile as the build secret
# ubuntu_mirror (base stage).
set -euo pipefail

uri="$(awk '/^URIs:/ {print $2; exit}' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true)"
case "$uri" in
  mirror+file:*) mirror="$(grep -m1 -oE 'https?://[^[:space:]]+' "${uri#mirror+file:}" 2>/dev/null || true)" ;;
  *) mirror="$uri" ;;
esac
if [[ "$mirror" =~ ^https?://[A-Za-z0-9.-]+(/[A-Za-z0-9._/-]*)?$ ]]; then
  printf '%s' "$mirror"
fi
