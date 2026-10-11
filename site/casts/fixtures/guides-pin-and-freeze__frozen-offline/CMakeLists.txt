# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

cmake_minimum_required(VERSION 3.25...4.4)
project(frozen_offline LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest BINS jq NO_ROOT)
add_custom_target(check ALL COMMAND ${OCX_JQ_RUN_JQ} -n -e "1 == 1" VERBATIM)
