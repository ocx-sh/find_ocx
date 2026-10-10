# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: foreign-platform content provisioned from a toolchain file
# (-DCMAKE_TOOLCHAIN_FILE=.../toolchain.cmake, set by the harness). Only
# exercised on Linux hosts, like foreign_platform.

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_foreign_toolchain LANGUAGES NONE)

foreach(name FT_PKG FT_PROJ)
  if(DEFINED CACHE{OCX_${name}_RUN})
    message(FATAL_ERROR "foreign_toolchain fixture: ${name} must export no RUN command")
  endif()
  if(NOT DEFINED CACHE{OCX_${name}_PATHS} OR "$CACHE{OCX_${name}_PATHS}" STREQUAL "")
    message(FATAL_ERROR "foreign_toolchain fixture: OCX_${name}_PATHS is empty")
  endif()
  foreach(dir IN LISTS OCX_${name}_PATHS)
    if(NOT EXISTS "${dir}")
      message(FATAL_ERROR "foreign_toolchain fixture: ${name} path '${dir}' does not exist")
    endif()
  endforeach()
  message(STATUS "foreign_toolchain fixture: ok ${name} ($CACHE{OCX_${name}_PATHS})")
endforeach()
