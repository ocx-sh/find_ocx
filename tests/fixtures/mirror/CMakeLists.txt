# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: the CLI is bootstrapped from a mirror - OCX_INSTALL_DIST_URL and
# OCX_INSTALL_MIRROR_URL point at the static tree make_mirror.cmake wrote -
# not from the vendored dist snapshot and not from GitHub. Driven by
# tests/mirror_check.cmake; deliberately gets no OCX_EXECUTABLE.
#   -DMIRROR_EXPECT_VERSION=<version>  the version the mirror serves
#   -DMIRROR_EXPECT_CACHE=<dir>        where the bootstrapped binary must land

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_mirror LANGUAGES NONE)

foreach(var MIRROR_EXPECT_VERSION MIRROR_EXPECT_CACHE)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "mirror fixture: -D${var}=... is required")
  endif()
endforeach()

include(ocx)

ocx_bootstrap()
find_package(ocx REQUIRED)

if(NOT OCX_VERSION_STRING VERSION_EQUAL MIRROR_EXPECT_VERSION)
  message(
    FATAL_ERROR
    "mirror fixture: expected ocx ${MIRROR_EXPECT_VERSION}, found '${OCX_VERSION_STRING}'"
  )
endif()
cmake_path(IS_PREFIX MIRROR_EXPECT_CACHE "${OCX_EXECUTABLE}" NORMALIZE under_cache)
if(NOT under_cache)
  message(
    FATAL_ERROR
    "mirror fixture: ${OCX_EXECUTABLE} is not under the bootstrap cache ${MIRROR_EXPECT_CACHE}"
  )
endif()
message(STATUS "mirror fixture: ok (ocx ${OCX_VERSION_STRING} from the mirror)")
