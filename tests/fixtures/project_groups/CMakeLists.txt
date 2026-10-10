# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: ocx_project() with GROUPS default lint - the top-level tools AND
# the lint group's tools compose into one environment, so both BINS resolve
# and execute through the exported RUN commands. No host shellcheck is
# needed: it is provisioned from ocx.lock.

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_project_groups LANGUAGES NONE)

include(ocx)

ocx_project(NAME TOOLS GROUPS default lint BINS jq shellcheck)

foreach(var OCX_TOOLS_RUN OCX_TOOLS_RUN_JQ OCX_TOOLS_RUN_SHELLCHECK)
  if(NOT DEFINED CACHE{${var}})
    message(FATAL_ERROR "project_groups fixture: ${var} missing")
  endif()
endforeach()

add_custom_target(
  groups_assert
  ALL
  COMMAND ${OCX_TOOLS_RUN_JQ} -n -e [[1 == 1]]
  COMMAND ${OCX_TOOLS_RUN_SHELLCHECK} "${CMAKE_CURRENT_SOURCE_DIR}/hello.sh"
  VERBATIM
)
