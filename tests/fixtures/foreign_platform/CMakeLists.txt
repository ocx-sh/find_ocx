# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: foreign PLATFORM provisioning - content only, no RUN commands.
# Only exercised on Linux hosts (see the harness).

cmake_minimum_required(VERSION 3.19)
project(fixture_foreign_platform LANGUAGES NONE)

include(ocx)

ocx_package(NAME JQ_ARM PACKAGE ocx.sh/jq:latest PLATFORM linux/arm64 NO_ROOT)

if(DEFINED CACHE{OCX_JQ_ARM_RUN})
  message(FATAL_ERROR "foreign_platform fixture: RUN vars must not exist for a foreign platform")
endif()
if(NOT DEFINED CACHE{OCX_JQ_ARM_PATHS} OR "$CACHE{OCX_JQ_ARM_PATHS}" STREQUAL "")
  message(FATAL_ERROR "foreign_platform fixture: OCX_JQ_ARM_PATHS is empty")
endif()
foreach(dir IN LISTS OCX_JQ_ARM_PATHS)
  if(NOT EXISTS "${dir}")
    message(FATAL_ERROR "foreign_platform fixture: env path '${dir}' does not exist")
  endif()
endforeach()
message(STATUS "foreign_platform fixture: ok (${OCX_JQ_ARM_PATHS})")
