#!/usr/bin/env bash
# cast: true
# doc: guides-add-a-tool/bins-typo
# title: A misspelled BINS name
# description: Name a binary the package does not provide, read the configure error that lists the real names, then fix the spelling.
#
# Harness contract: see site/scripts/run-cast-script.sh. Error cast: the region runs with errexit off
# because the first configure must fail; the verification repeats that configure and asserts status and message.
# Passes only with the BINS validation of ocx_project (ocx 0.6 family work, I3); before that the typo is silent.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cat > ocx.toml <<'TOML'
[tools]
jq = "ocx.sh/jqlang/jq:latest"
TOML
cat > CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.19)
project(bins_typo LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_project(NAME TOOLS BINS jqq)
CMAKE
cp CMakeLists.txt CMakeLists.typo
"$CAST_OCX" lock
PATH="$(dirname "$CAST_OCX"):$PATH"
# endregion setup

set +e
# region cast
cmake -S . -B build

sed -i 's/BINS jqq/BINS jq/' CMakeLists.txt

cmake -S . -B build
# endregion cast
set -e

# Verification: the fix worked, and the typo fails with status 1 naming the typo and the real binary.
grep -q 'BINS jq)' CMakeLists.txt
test -f build/CMakeCache.txt
cp CMakeLists.typo CMakeLists.txt
rc=0
out=$(cmake -S . -B check 2>&1) || rc=$?
test "$rc" -eq 1
grep -q 'jqq' <<<"$out"
grep -qE "jq\b" <<<"$out"
