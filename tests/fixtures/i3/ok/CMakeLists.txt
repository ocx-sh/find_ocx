# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: ocx_package behaviors that need no failing call - PINS keyed on the
# effective platform, an index digest in PACKAGE, BINS validated against the
# closure, identical re-entry, a single-path <name>_ROOT and the CONFIG
# keywords reaching the exported launcher.

cmake_minimum_required(VERSION 3.19)
project(fixture_i3_ok LANGUAGES NONE)

include(ocx)

set(jq_index "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6")

# PINS: one distinct fake digest per platform, the host's must be selected
# (a floating tag with no matching pin would be the reproducibility error).
__ocx_host_info(host_triple host_platform host_ext)
set(pins "")
set(expected "")
foreach(entry IN ITEMS linux/amd64=a linux/arm64=b darwin/amd64=c darwin/arm64=d windows/amd64=e windows/arm64=f)
  string(REPLACE "=" ";" parts "${entry}")
  list(GET parts 0 pin_platform)
  list(GET parts 1 digit)
  string(REPEAT "${digit}" 64 hex)
  list(APPEND pins "${pin_platform}=sha256:${hex}")
  if(pin_platform STREQUAL "${host_platform}")
    set(expected "sha256:${hex}")
  endif()
endforeach()
ocx_package(NAME PINNED PACKAGE ocx.sh/jqlang/jq:latest PINS ${pins})
list(FIND OCX_PINNED_RUN "ocx.sh/jqlang/jq:latest@${expected}" index)
if(index EQUAL -1)
  message(FATAL_ERROR "i3 ok fixture: host pin ${expected} not in '${OCX_PINNED_RUN}'")
endif()

# An index digest in PACKAGE pins all platforms; BINS jq is declared.
ocx_package(NAME DIGEST PACKAGE "${jq_index}" BINS jq)
if(NOT DEFINED CACHE{OCX_DIGEST_RUN_JQ})
  message(FATAL_ERROR "i3 ok fixture: OCX_DIGEST_RUN_JQ missing")
endif()
set(before "${OCX_DIGEST_RUN}")
ocx_package(NAME DIGEST PACKAGE "${jq_index}" BINS jq)
if(NOT "${before}" STREQUAL "${OCX_DIGEST_RUN}")
  message(FATAL_ERROR "i3 ok fixture: identical re-entry changed OCX_DIGEST_RUN")
endif()

# <name>_ROOT is one path; a changed root drops the stale <name>_DIR.
set(jqroot_ROOT "/old/root" CACHE PATH "stale root" FORCE)
set(jqroot_DIR "/stale/dir" CACHE PATH "stale dir")
ocx_package(NAME jqroot PACKAGE "${jq_index}" PULL)
if(NOT EXISTS "${jqroot_ROOT}" OR jqroot_ROOT MATCHES "[\r\n{}]")
  message(FATAL_ERROR "i3 ok fixture: jqroot_ROOT is not a single existing path: '${jqroot_ROOT}'")
endif()
if(NOT "${jqroot_ROOT}" STREQUAL "${OCX_JQROOT_CONTENT}")
  message(FATAL_ERROR "i3 ok fixture: jqroot_ROOT '${jqroot_ROOT}' != OCX_JQROOT_CONTENT '${OCX_JQROOT_CONTENT}'")
endif()
if(DEFINED CACHE{jqroot_DIR})
  message(FATAL_ERROR "i3 ok fixture: jqroot_DIR survived a changed jqroot_ROOT")
endif()

# CONFIG keywords land in the exported launcher's environment.
ocx_package(NAME CFG PACKAGE "${jq_index}" NO_CONFIG
  PATCH_SNAPSHOT "${CMAKE_CURRENT_LIST_DIR}/patches.json")
if(NOT "${OCX_CFG_RUN}" MATCHES "(^|;)OCX_NO_CONFIG=1(;|$)"
    OR NOT "${OCX_CFG_RUN}" MATCHES "(^|;)OCX_PATCH_SNAPSHOT=[^;]*/patches\\.json(;|$)")
  message(FATAL_ERROR "i3 ok fixture: CONFIG keywords missing from '${OCX_CFG_RUN}'")
endif()
