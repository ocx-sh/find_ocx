#!/usr/bin/env bash
# cast: true
# doc: guides-cross-build/foreign-paths
# title: Tool content for another platform
# description: Ask for Windows content on a Unix host, read the BINS error, then use the exported paths instead of a runnable command.
#
# Harness contract: see site/scripts/run-cast-script.sh. Error cast: the region runs with errexit off because
# the first configure must fail; the verification repeats that configure and asserts status and message.
# windows/amd64 is foreign on every host that runs this script (asciinema has no Windows build).
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
project(cross_build LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_project(NAME WIN PLATFORM windows/amd64 BINS jq)
file(GLOB files RELATIVE "${OCX_WIN_PATHS}" "${OCX_WIN_PATHS}/*")
message(STATUS "windows/amd64 content: ${files}")
CMAKE
cp CMakeLists.txt CMakeLists.bins
PATH="$(dirname "$CAST_OCX"):$PATH"
ocx lock
# endregion setup

set +e
# region cast
cmake -S . -B build

sed -i 's/ BINS jq//' CMakeLists.txt

cmake -S . -B build
# endregion cast
set -e

# Verification: the fix configured and listed the Windows binary; BINS on a foreign platform fails with status 1.
test -f build/CMakeCache.txt
cp CMakeLists.bins CMakeLists.txt
rc=0
out=$(cmake -S . -B check 2>&1) || rc=$?
test "$rc" -eq 1
grep -q 'PLATFORM is incompatible with BINS' <<<"$out"
sed -i 's/ BINS jq//' CMakeLists.txt
out=$(cmake -S . -B check2 2>&1)
grep -q 'windows/amd64 content: jq.exe' <<<"$out"
