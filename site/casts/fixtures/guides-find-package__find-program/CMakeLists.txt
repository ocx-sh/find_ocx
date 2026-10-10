# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

cmake_minimum_required(VERSION 3.25...4.4)
project(find_program_demo LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_package(NAME lychee PACKAGE ocx.sh/lychee/lychee:latest PULL)
message(STATUS "lychee_ROOT is ${lychee_ROOT}")

find_program(LYCHEE_EXE lychee)
message(STATUS "find_program found: ${LYCHEE_EXE}")
