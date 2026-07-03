# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Example: project-shipped index snapshot. The committed .ocx/ directory
# freezes every floating-tag resolution in this project - reproducible
# without a single digest in the CMake code. Refresh deliberately, review
# the diff, commit.
#
#   cmake -S . -B build && ctest --test-dir build
#   cmake --build build --target index-update   # deliberate refresh

cmake_minimum_required(VERSION 3.19)
project(ocx_example_frozen_index LANGUAGES NONE)

enable_testing()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../..")
include(ocx)

# Fail-fast when the snapshot is missing, and lock the discovered .ocx/
# into OCX_INDEX for this directory and below. (Each ocx_package would
# also discover it on its own - FIND REQUIRED makes the intent explicit.)
ocx_index(FIND REQUIRED)

# Floating tag, no INDEX argument, no digests: resolves frozen from the
# committed snapshot (.ocx/ocx.sh/jq.json).
ocx_package(NAME jq PACKAGE ocx.sh/jq:latest BINS jq NO_ROOT)

add_test(NAME jq_frozen COMMAND ${OCX_JQ_RUN_JQ} -n -e "1 == 1")

# Deliberate refresh flow: the module composes the command, the caller
# decides how it runs - here a build target. Never wired up automatically:
# a refresh that runs on its own would paper over drift instead of
# surfacing it.
ocx_index(UPDATE_COMMAND refresh)
add_custom_target(index-update
  COMMAND ${refresh}
  COMMAND ${CMAKE_COMMAND} -E echo
    "index snapshot refreshed - review the diff and commit the result"
  VERBATIM)
