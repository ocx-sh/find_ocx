# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: foreign PLATFORM provisioning - content only, no RUN commands.
# Only exercised on Linux hosts (see the harness).

cmake_minimum_required(VERSION 3.19)
project(fixture_foreign_platform LANGUAGES NONE)

include(ocx)

# Under test: foreign-platform env export, not pinning - allow the
# floating tag (the reproducibility gate is covered by floating_fatal).
set(OCX_ALLOW_FLOATING ON)
ocx_package(NAME JQ_ARM PACKAGE ocx.sh/jq:latest PLATFORM linux/arm64 NO_ROOT)

# Ordered preference list: a single resolution requesting arm64 else amd64.
# Same content-only export contract (first-match wins at the CLI).
ocx_package(NAME JQ_PREF PACKAGE ocx.sh/jq:latest PLATFORM linux/arm64 linux/amd64 NO_ROOT)

foreach(case JQ_ARM JQ_PREF)
  if(DEFINED CACHE{OCX_${case}_RUN})
    message(FATAL_ERROR "foreign_platform fixture: RUN vars must not exist for a foreign platform (${case})")
  endif()
  if(NOT DEFINED CACHE{OCX_${case}_PATHS} OR "$CACHE{OCX_${case}_PATHS}" STREQUAL "")
    message(FATAL_ERROR "foreign_platform fixture: OCX_${case}_PATHS is empty")
  endif()
  foreach(dir IN LISTS OCX_${case}_PATHS)
    if(NOT EXISTS "${dir}")
      message(FATAL_ERROR "foreign_platform fixture: env path '${dir}' does not exist (${case})")
    endif()
  endforeach()
  message(STATUS "foreign_platform fixture: ok ${case} ($CACHE{OCX_${case}_PATHS})")
endforeach()
