#!/usr/bin/env bash
# cast: true
# doc: guides-find-package/find-program
# title: find_program does not search the package root
# description: Provision a package with PULL, watch find_program miss its binary, then point find_program at the exported root.
#
# Harness contract: see site/scripts/run-cast-script.sh. Both configures in the region succeed (find_program
# reports NOTFOUND, it does not fail); the verification asserts the NOTFOUND and then the hit.
set -euo pipefail

# The demonstration needs a tool the host does not provide; a host lychee would make the first search succeed.
! command -v lychee >/dev/null || { echo "a host lychee is on PATH; pick another tool for this cast" >&2; exit 1; }

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cat > CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.19)
project(find_program_demo LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_package(NAME lychee PACKAGE ocx.sh/lychee/lychee:latest PULL)
message(STATUS "lychee_ROOT is ${lychee_ROOT}")

find_program(LYCHEE_EXE lychee)
message(STATUS "find_program found: ${LYCHEE_EXE}")
CMAKE
PATH="$(dirname "$CAST_OCX"):$PATH"
ocx --index .ocx index update ocx.sh/lychee/lychee:latest
# endregion setup

# region cast
cmake -S . -B build

cat >> CMakeLists.txt <<'CMAKE'
find_program(LYCHEE_EXE lychee HINTS "${lychee_ROOT}" NO_DEFAULT_PATH)
message(STATUS "with HINTS found: ${LYCHEE_EXE}")
CMAKE

cmake -S . -B build
# endregion cast

# Verification: the first search missed, the hinted search hit a file under the package root.
out=$(cmake -S . -B check 2>&1)
grep -q 'find_program found: LYCHEE_EXE-NOTFOUND' <<<"$out"
hit=$(sed -n 's/^-- with HINTS found: //p' <<<"$out")
test -x "$hit"
