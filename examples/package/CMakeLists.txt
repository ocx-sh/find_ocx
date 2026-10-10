# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Example: ad-hoc packages straight from the registry - floating (eager,
# logs how to pin the tag), index-digest-pinned + lazy
# (materializes on first build-time execution), and the <name>_ROOT export:
# find_package() reads it, find_program() needs it as HINTS.
#
#   cmake -S . -B build && cmake --build build && ctest --test-dir build

cmake_minimum_required(VERSION 3.25...4.4)
project(ocx_example_package LANGUAGES NONE)

enable_testing()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../..")
include(ocx)

# Floating + eager: resolved at configure time; the log says how to pin the
# tag. Floating with no index in effect is a hard error by default
# (reproducible-first) - OCX_ALLOW_FLOATING is the explicit, deliberate
# escape hatch. Exports jq_ROOT
# (CMP0074) - a subsequent find_package(jq)/find_program would search the
# OCX-provisioned content.
# region pull-root
# region eager
set(OCX_ALLOW_FLOATING ON)
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest PULL)
unset(OCX_ALLOW_FLOATING)
message(STATUS "example: jq content at ${jq_ROOT}")
# endregion eager
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

# region index-digest
# Index-digest-pinned + lazy: one image index digest pins every platform and
# ocx selects the leaf for the building one. Read it with
# `ocx package inspect ocx.sh/jqlang/jq:1.8.2` (pinned_digest). Nothing is
# fetched until the first execution.
# region pinned-lazy
ocx_package(
  NAME jq_pinned
  PACKAGE
    ocx.sh/jqlang/jq:1.8.2@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
  BINS jq
  NO_ROOT
)
# endregion pinned-lazy
# endregion index-digest

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
