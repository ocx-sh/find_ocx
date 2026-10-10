# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Example: one committed ocx config for every build, ignoring the config files
# of the machine that runs it.
#
#   cmake -S . -B build && cmake --build build && ctest --test-dir build

cmake_minimum_required(VERSION 3.25...4.4)
project(ocx_example_policy LANGUAGES NONE)

enable_testing()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../..")
include(ocx)

# region config
ocx_project(NAME TOOLS BINS jq
  CONFIG "${CMAKE_CURRENT_SOURCE_DIR}/ocx-config.toml"
  NO_CONFIG)
# endregion

add_test(NAME jq_runs COMMAND ${OCX_TOOLS_RUN_JQ} -n -e "true")
