#!/usr/bin/env bash
# Run one bash file in the cast-script environment. ctest runs a cast script through this file and
# scripts/record-casts.mjs runs its generated driver through it, so the test and the recording see
# the same world:
#
#   - cwd is an empty directory ($CAST_WORK); HOME and OCX_HOME are throwaway, so every run is cold;
#   - FIND_OCX_ROOT points at the repository, the module under test;
#   - PATH holds cmake, ctest and ninja and the system tools, never ocx: a host ocx would short-circuit
#     the bootstrap. The host ocx stays reachable as $CAST_OCX for the setup region, and a script that
#     wants it on PATH says so itself;
#   - nothing else leaks in but the locale and the proxy/CA variables.
#
#   run-cast-script.sh <file.sh>
#
# Needs cmake and ninja on PATH (`ocx exec --` provides both) and, unless the script bootstraps, ocx.
# Environment knobs:
#   CAST_TMP=<dir>               use (and keep) this directory instead of a mktemp one
#   CAST_OCX_HOME=<dir>          reuse a warm OCX_HOME (faster ctest runs); a recording always starts cold
#   CAST_OCX_EXECUTABLE=<path>   run the module through this ocx (becomes OCX_EXECUTABLE) instead of the
#                                pinned bootstrap; for proving a script while the pin lags the CLI
set -euo pipefail

file=$(realpath "$1")
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if [[ -n "${CAST_TMP:-}" ]]; then tmp=$CAST_TMP; else tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; fi
mkdir -p "$tmp/work" "$tmp/home"

tool_dirs=()
for t in cmake ninja; do
  p=$(command -v "$t") || { echo "run-cast-script: $t is not on PATH (run under 'ocx exec --')" >&2; exit 1; }
  tool_dirs+=("$(dirname "$p")")
done
path=$(IFS=:; echo "${tool_dirs[*]}"):/usr/local/bin:/usr/bin:/bin

pass=()
for v in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy SSL_CERT_FILE; do
  [[ -n "${!v:-}" ]] && pass+=("$v=${!v}")
done
[[ -n "${CAST_OCX_EXECUTABLE:-}" ]] && pass+=("OCX_EXECUTABLE=$CAST_OCX_EXECUTABLE")

cd "$tmp/work"
env -i "${pass[@]}" PATH="$path" TERM=xterm-256color LANG=C.UTF-8 HOME="$tmp/home" \
  OCX_HOME="${CAST_OCX_HOME:-$tmp/home/.ocx}" OCX_NO_UPDATE_CHECK=1 \
  CAST_OCX="$(command -v ocx || true)" CAST_TMP="$tmp" CAST_WORK="$tmp/work" FIND_OCX_ROOT="$root" \
  bash "$file" || { rc=$?; echo "run-cast-script: $(basename "$file") exited $rc" >&2; exit "$rc"; }
