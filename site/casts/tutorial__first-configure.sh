#!/usr/bin/env bash
# cast: true
# doc: tutorial/first-configure
# title: First configure and build
# description: Configure a project that includes find_ocx, then build it; the build runs a pinned jq nobody installed.
# expect_exit: 0
#
# Harness contract (site/scripts/run-cast-script.sh): cwd is an empty directory, HOME and OCX_HOME are
# throwaway, $FIND_OCX_ROOT is the repository, cmake and ocx are on PATH. The `cast` region is what the
# page shows and what the recording types; everything else runs silently.
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
project(hello_jq LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_project(NAME TOOLS BINS jq)
add_custom_target(validate ALL
  COMMAND ${OCX_TOOLS_RUN} jq -n -e "true"
  VERBATIM)
CMAKE
ocx lock
# endregion setup

# region cast
cmake -S . -B build

cmake --build build
# endregion cast

# Verification: runs in the test, is neither shown nor recorded.
test -f build/CMakeCache.txt
test -f ocx.lock
