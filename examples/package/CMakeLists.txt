# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Example: ad-hoc packages straight from the registry - floating (eager,
# prints the resolved digest to copy into PINS), digest-pinned + lazy
# (materializes on first build-time execution), and the <name>_ROOT export:
# find_package() reads it, find_program() needs it as HINTS.
#
#   cmake -S . -B build && cmake --build build && ctest --test-dir build

cmake_minimum_required(VERSION 3.25...4.4)
project(ocx_example_package LANGUAGES NONE)

enable_testing()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../..")
include(ocx)

# Floating + eager: resolved at configure time; the log suggests the PINS
# line for reproducibility. Floating with no index in effect is a hard
# error by default (reproducible-first) - OCX_ALLOW_FLOATING is the
# explicit, deliberate escape hatch, and this exact flow is how the PINS
# digests below were generated in the first place. Exports jq_ROOT
# (CMP0074) - a subsequent find_package(jq)/find_program would search the
# OCX-provisioned content.
# region pull-root
set(OCX_ALLOW_FLOATING ON)
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest PULL)
unset(OCX_ALLOW_FLOATING)
message(STATUS "example: jq content at ${jq_ROOT}")
# endregion pull-root

# region find-program
# find_program() ignores <name>_ROOT - only find_package() reads it - so hand
# the content root over as HINTS. NO_DEFAULT_PATH keeps a host jq from
# answering; NO_CACHE re-searches when jq_ROOT moves to another digest.
find_program(JQ_EXECUTABLE NAMES jq HINTS "${jq_ROOT}" "${jq_ROOT}/bin" NO_DEFAULT_PATH NO_CACHE)
if(NOT JQ_EXECUTABLE)
  message(FATAL_ERROR "example: no jq under ${jq_ROOT}")
endif()
message(STATUS "example: find_program found ${JQ_EXECUTABLE}")
# endregion find-program

# region pins
# Digest-pinned + lazy: per-platform manifest digests (from
# `ocx package install -p <platform>` or the ocx.lock of a project);
# nothing is fetched until the first execution.
ocx_package(
  NAME jq_pinned
  PACKAGE ocx.sh/jqlang/jq:1.8.2
  BINS jq
  NO_ROOT
  PINS
    "linux/amd64=sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    "linux/arm64=sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
    "darwin/amd64=sha256:f750c91d28769d12298ba9a4c10340152fcbdd48c48102bf275c21d736cc72a2"
    "darwin/arm64=sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1"
    "windows/amd64=sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989"
)
# endregion pins

add_custom_target(
  pretty
  ALL
  COMMAND ${OCX_JQ_PINNED_RUN_JQ} . "${CMAKE_CURRENT_SOURCE_DIR}/data.json"
  VERBATIM
)

add_test(
  NAME jq_found_by_find_program
  COMMAND ${JQ_EXECUTABLE} -e ".target == \"cmake\"" "${CMAKE_CURRENT_SOURCE_DIR}/data.json"
)

add_test(
  NAME jq_pinned_filter
  COMMAND ${OCX_JQ_PINNED_RUN_JQ} -e ".target == \"cmake\"" "${CMAKE_CURRENT_SOURCE_DIR}/data.json"
)

# Frozen-index + lazy with an explicit INDEX override: the tag resolves
# from the committed snapshot (index/ocx.sh/p/jqlang/jq.json) - reproducible
# without digests in this file. Prefer a project-shipped .ocx/ directory
# (auto-discovered; see the frozen_index example); an explicit INDEX
# points anywhere. Refresh deliberately (compose the command with
# ocx_index(UPDATE_COMMAND ...)), review the diff, commit.
# region index-dir
ocx_package(
  NAME jq_frozen
  PACKAGE ocx.sh/jqlang/jq:latest
  BINS jq
  NO_ROOT
  INDEX "${CMAKE_CURRENT_SOURCE_DIR}/index"
)
# endregion index-dir

add_test(
  NAME jq_frozen_filter
  COMMAND ${OCX_JQ_FROZEN_RUN_JQ} -e ".target == \"cmake\"" "${CMAKE_CURRENT_SOURCE_DIR}/data.json"
)
