# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: ocx_project() with defaults - the ocx.toml next to this file is
# found by the upward search, the lock is checked, and the exported RUN
# command lists execute tools (lazily) at build time, with a generator
# expression in the arguments.

cmake_minimum_required(VERSION 3.19)
project(fixture_project_run LANGUAGES NONE)

include(ocx)

ocx_project(NAME TOOLS BINS jq)

if(NOT DEFINED CACHE{OCX_TOOLS_RUN} OR NOT DEFINED CACHE{OCX_TOOLS_RUN_JQ})
  message(FATAL_ERROR "project_run fixture: RUN result variables missing")
endif()

# jq -e sets the exit code from the filter result: a real assertion, run
# through the composed project environment, with a genex argument.
add_custom_target(jq_assert ALL
  COMMAND ${OCX_TOOLS_RUN} jq -n -e --arg config "$<CONFIG>"
          [[{"greeting":"hello"} | .greeting == "hello"]]
  COMMAND ${OCX_TOOLS_RUN_JQ} --version
  VERBATIM
)
