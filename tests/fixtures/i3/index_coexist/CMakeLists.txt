# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: a .ocx/ holding both the rendered toolchain and an index snapshot
# is still found as the index; the toolchain alone is not (see cases).

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_i3_index_coexist LANGUAGES NONE)

include(ocx)

ocx_index(FIND REQUIRED)
if(NOT "${OCX_INDEX}" STREQUAL "${CMAKE_CURRENT_SOURCE_DIR}/.ocx")
  message(FATAL_ERROR "i3 index_coexist fixture: OCX_INDEX is '${OCX_INDEX}'")
endif()
