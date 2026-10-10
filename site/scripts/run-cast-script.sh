#!/usr/bin/env bash
# Run one cast script in a throwaway world: empty cwd, fresh HOME and OCX_HOME, FIND_OCX_ROOT set.
# ctest and the recorder both go through here, so the test and the recording see the same world.
# PATH holds cmake, ninja and system tools, never ocx; the host ocx is $CAST_OCX.
#   run-cast-script.sh <file.sh>      knobs: site/casts/README.md
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
env -i ${pass[@]+"${pass[@]}"} PATH="$path" TERM=xterm-256color LANG=C.UTF-8 HOME="$tmp/home" \
  OCX_HOME="${CAST_OCX_HOME:-$tmp/home/.ocx}" OCX_NO_UPDATE_CHECK=1 \
  CAST_OCX="$(command -v ocx || true)" CAST_TMP="$tmp" CAST_WORK="$tmp/work" FIND_OCX_ROOT="$root" \
  bash "$file" || { rc=$?; echo "run-cast-script: $(basename "$file") exited $rc" >&2; exit "$rc"; }
