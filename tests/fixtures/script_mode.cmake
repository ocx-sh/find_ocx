# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Fixture: ocx.cmake in script mode (cmake -P) - no project(), no
# generator, no persistent cache. Both tiers must provision and execute.
#
#   cmake -DCMAKE_MODULE_PATH=<repo> [-DOCX_EXECUTABLE=<ocx>] \
#         -P tests/fixtures/script_mode.cmake

include(ocx)

# Package tier: eager install + exec through the RUN command list.
ocx_package(NAME jq_script PACKAGE ocx.sh/jq:latest PULL NO_ROOT)
if(NOT EXISTS "${OCX_JQ_SCRIPT_CONTENT}")
  message(FATAL_ERROR "script_mode fixture: OCX_JQ_SCRIPT_CONTENT missing")
endif()
execute_process(
  COMMAND ${OCX_JQ_SCRIPT_RUN} jq -n -e "1 == 1"
  RESULT_VARIABLE rc
  OUTPUT_QUIET
)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "script_mode fixture: package-tier jq exec failed (${rc})")
endif()

# Project tier: explicit TOML (script mode has no project() search bound).
get_filename_component(__toml "${CMAKE_CURRENT_LIST_DIR}/project_run/ocx.toml" ABSOLUTE)
ocx_project(NAME tools_script TOML "${__toml}" BINS jq)
execute_process(
  COMMAND ${OCX_TOOLS_SCRIPT_RUN_JQ} -n -e "\"a\" == \"a\""
  RESULT_VARIABLE rc
  OUTPUT_QUIET
)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "script_mode fixture: project-tier jq exec failed (${rc})")
endif()

message(STATUS "script_mode fixture: ok")
