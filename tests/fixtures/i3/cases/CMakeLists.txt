# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Negative fixture: one failing command call per configure, selected with
# -DI3_CASE=<case>. The harness asserts the exit status and the diagnostic.
# The .ocx/ next to this file holds only a rendered toolchain, never an index.

cmake_minimum_required(VERSION 3.19)
project(fixture_i3_cases LANGUAGES NONE)

include(ocx)

# Image index digest of ocx.sh/jqlang/jq:latest: pins every platform.
set(jq_index "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6")

if(I3_CASE STREQUAL "platform_list_keyword")
  ocx_package(NAME X PACKAGE "${jq_index}" PLATFORM linux/arm64 linux/amd64)
elseif(I3_CASE STREQUAL "platform_list_quoted")
  ocx_package(NAME X PACKAGE "${jq_index}" PLATFORM "linux/arm64;linux/amd64")
elseif(I3_CASE STREQUAL "default_platform_list")
  set(OCX_DEFAULT_PLATFORM "linux/arm64;linux/amd64")
  ocx_package(NAME X PACKAGE "${jq_index}")
elseif(I3_CASE STREQUAL "project_platform_list")
  ocx_project(NAME X TOML "${CMAKE_CURRENT_LIST_DIR}/../groups/ocx.toml" PLATFORM "linux/arm64;linux/amd64")
elseif(I3_CASE STREQUAL "bins_foreign")
  ocx_package(NAME X PACKAGE "${jq_index}" PLATFORM linux/arm64 BINS jq)
elseif(I3_CASE STREQUAL "unknown_keyword")
  ocx_package(NAME X PACKAGE "${jq_index}" BOGUS)
elseif(I3_CASE STREQUAL "bins_typo")
  ocx_package(NAME X PACKAGE "${jq_index}" BINS jqq)
elseif(I3_CASE STREQUAL "toolchain_not_index")
  ocx_index(FIND REQUIRED)
elseif(I3_CASE STREQUAL "reentry_differs")
  ocx_package(NAME X PACKAGE "${jq_index}")
  ocx_package(NAME X PACKAGE "${jq_index}" BINS jq)
elseif(I3_CASE STREQUAL "config_missing")
  ocx_package(NAME X PACKAGE "${jq_index}" PULL CONFIG "${CMAKE_CURRENT_LIST_DIR}/no-such-config.toml")
else()
  message(FATAL_ERROR "i3 cases fixture: unknown I3_CASE '${I3_CASE}'")
endif()

message(FATAL_ERROR "i3 cases fixture: case '${I3_CASE}' must have failed before this line")
