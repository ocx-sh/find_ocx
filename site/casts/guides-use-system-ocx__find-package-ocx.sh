#!/usr/bin/env bash
# cast: true
# doc: guides-use-system-ocx/find-package-ocx
# title: find_package(ocx) and the system ocx
# description: find_package(ocx) fails when no ocx is installed, bootstraps the pinned one on request, and prefers an installed ocx.
#
# Harness contract: see site/scripts/run-cast-script.sh. Error cast: the region runs with errexit off because
# the first configure must fail; the verification repeats that configure and asserts status and message.
set -euo pipefail

# region setup
mkdir -p cmake ~/.local/bin
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cat > CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.19)
project(system_ocx LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
find_package(ocx REQUIRED)
message(STATUS "ocx ${OCX_VERSION_STRING} at ${OCX_EXECUTABLE}")
CMAKE
ln -s "$CAST_OCX" ~/.local/bin/ocx
# endregion setup

set +e
# region cast
cmake -S . -B build

cmake -S . -B build -DOCX_BOOTSTRAP=ON

PATH="$HOME/.local/bin:$PATH" cmake -S . -B system
# endregion cast
set -e

# Verification: no ocx fails with status 1 and names ocx; the bootstrap and the installed ocx both resolve.
test -f build/CMakeCache.txt
test -f system/CMakeCache.txt
rc=0
out=$(cmake -S . -B check 2>&1) || rc=$?
test "$rc" -eq 1
grep -qi "could not find ocx\|ocx was not found\|ocx not found" <<<"$out"
out=$(PATH="$HOME/.local/bin:$PATH" cmake -S . -B check2 2>&1)
grep -q "ocx [0-9][0-9.]* at $HOME/.local/bin/ocx" <<<"$out"
