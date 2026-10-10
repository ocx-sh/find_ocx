#!/usr/bin/env bash
# Run one bash file in the cast-script environment: an empty working directory, a throwaway HOME and
# OCX_HOME, FIND_OCX_ROOT pointing at the repository, and nothing else from the caller's environment but
# PATH (it must hold cmake, ocx, ninja), the locale and the proxy/CA variables.
# ctest runs a cast script through this file; scripts/record-casts.mjs runs its generated driver
# through it, so the test and the recording see the same world.
#   run-cast-script.sh <file.sh>        CAST_TMP=<dir> uses (and keeps) that directory instead of a mktemp one
set -euo pipefail

file=$(realpath "$1")
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if [[ -n "${CAST_TMP:-}" ]]; then tmp=$CAST_TMP; else tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; fi
mkdir -p "$tmp/work" "$tmp/home"

pass=()
for v in PATH HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy SSL_CERT_FILE; do
  [[ -n "${!v:-}" ]] && pass+=("$v=${!v}")
done
# CAST_OCX_HOME reuses a warm OCX_HOME (faster ctest runs); a recording always starts cold.
cd "$tmp/work"
env -i "${pass[@]}" TERM=xterm-256color LANG=C.UTF-8 HOME="$tmp/home" \
  OCX_HOME="${CAST_OCX_HOME:-$tmp/home/.ocx}" OCX_NO_UPDATE_CHECK=1 \
  FIND_OCX_ROOT="$root" CAST_WORK="$tmp/work" \
  bash "$file"
