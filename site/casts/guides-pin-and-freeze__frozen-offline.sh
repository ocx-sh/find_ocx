#!/usr/bin/env bash
# cast: true
# doc: guides-pin-and-freeze/frozen-offline
# title: Configure and build offline from a snapshot
# description: With a committed index snapshot and a warm cache, a configure and a build need no network.
#
# Harness contract: see site/scripts/run-cast-script.sh. Setup stands in for an earlier online session: it
# commits the snapshot and warms OCX_HOME. The region then runs with OCX_OFFLINE=1; the verification repeats
# the configure with every network route dead, so a quiet network fallback cannot pass.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cat > CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.19)
project(frozen_offline LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest BINS jq NO_ROOT)
add_custom_target(check ALL
  COMMAND ${OCX_JQ_RUN_JQ} -n -e "1 == 1"
  VERBATIM)
CMAKE
PATH="$(dirname "$CAST_OCX"):$PATH"
ocx --index .ocx index update ocx.sh/jqlang/jq:latest
cmake -S . -B build
cmake --build build
rm -rf build
# endregion setup

# region cast
OCX_OFFLINE=1 cmake -S . -B build

OCX_OFFLINE=1 cmake --build build
# endregion cast

# Verification: the same configure and build pass with every route to the network dead.
rm -rf build
dead=http://127.0.0.1:9
HTTP_PROXY=$dead HTTPS_PROXY=$dead http_proxy=$dead https_proxy=$dead OCX_OFFLINE=1 cmake -S . -B build
HTTP_PROXY=$dead HTTPS_PROXY=$dead http_proxy=$dead https_proxy=$dead OCX_OFFLINE=1 cmake --build build
