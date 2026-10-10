# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Example: workspace toolchain from ocx.toml + ocx.lock.
#
#   cmake -S . -B build && cmake --build build && ctest --test-dir build
#
# In your own project, vendor Findocx.cmake + ocx.cmake into cmake/ and
# adjust CMAKE_MODULE_PATH accordingly.

cmake_minimum_required(VERSION 3.25...4.4)
project(ocx_example_project LANGUAGES NONE)

enable_testing()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../..")
include(ocx)

# The ocx.toml next to this file is found by the upward search; the lock
# is verified; nothing is pulled yet (lazy). NAME picks the prefix of the
# result variables: NAME TOOLS -> OCX_TOOLS_RUN, OCX_TOOLS_RUN_JQ
# (defaults to PROJECT -> OCX_PROJECT_RUN).
ocx_project(NAME TOOLS BINS jq)

# Build-time tool use, lazily materialized on first execution. Generator
# expressions compose naturally - the command is a plain CMake list.
add_custom_target(
  validate
  ALL
  COMMAND ${OCX_TOOLS_RUN} jq -n -e --arg config "$<CONFIG>" [[$config | length >= 0]]
  VERBATIM
)

# region lazy-group
# The lint group only materializes when someone builds the 'lint' target.
ocx_project(NAME LINT GROUPS lint)
add_custom_target(
  lint
  COMMAND ${OCX_LINT_RUN} shellcheck "${CMAKE_CURRENT_SOURCE_DIR}/hello.sh"
  VERBATIM
)
# endregion lazy-group

add_test(
  NAME data_valid
  COMMAND ${OCX_TOOLS_RUN_JQ} -e ".greeting == \"hello\"" "${CMAKE_CURRENT_SOURCE_DIR}/data.json"
)

# region combined-groups
# A BINS entry from a non-default group needs that group in GROUPS, and
# 'default' keeps the top-level [tools] in the same environment.
ocx_project(NAME DEV GROUPS default lint BINS jq shellcheck)
add_test(
  NAME shellcheck_hello
  COMMAND ${OCX_DEV_RUN_SHELLCHECK} "${CMAKE_CURRENT_SOURCE_DIR}/hello.sh"
)
# endregion combined-groups
