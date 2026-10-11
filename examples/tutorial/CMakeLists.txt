# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Example: the tutorial project (site/pages/tutorial.md). It expects
# ocx.cmake and Findocx.cmake in a cmake/ directory next to this file and an
# ocx.lock written by `ocx lock`; site/casts/tutorial__first-configure.sh
# builds exactly that in an empty directory and runs it.

# region full
cmake_minimum_required(VERSION 3.25...4.4)
project(hello_jq LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_project(NAME TOOLS BINS jq)

add_custom_target(show_jq ALL COMMAND ${OCX_TOOLS_RUN} jq --version VERBATIM)
# endregion
