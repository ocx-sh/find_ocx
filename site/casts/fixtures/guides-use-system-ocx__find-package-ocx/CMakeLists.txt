# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

cmake_minimum_required(VERSION 3.25...4.4)
project(system_ocx LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
find_package(ocx REQUIRED)
message(STATUS "ocx ${OCX_VERSION_STRING} at ${OCX_EXECUTABLE}")
