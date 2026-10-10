# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: provisioning from a CMAKE_TOOLCHAIN_FILE (see toolchain.cmake).
# Configure with -DCMAKE_TOOLCHAIN_FILE=<this directory>/toolchain.cmake.

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_i3_toolchain LANGUAGES NONE)

if(NOT CMAKE_TOOLCHAIN_FILE MATCHES "toolchain\\.cmake$")
  message(FATAL_ERROR "i3 toolchain fixture: run with -DCMAKE_TOOLCHAIN_FILE=.../toolchain.cmake")
endif()
if(NOT DEFINED CACHE{OCX_TC_RUN_JQ})
  message(FATAL_ERROR "i3 toolchain fixture: OCX_TC_RUN_JQ missing")
endif()
