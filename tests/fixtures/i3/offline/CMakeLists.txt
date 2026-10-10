# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: with OCX_OFFLINE and a package that is not in the local store, the
# BINS check is skipped (ocx exits 79), so even a misspelled name configures.
# Run with -DOCX_OFFLINE=1 and -DOCX_HOME=<empty directory>.

cmake_minimum_required(VERSION 3.19)
project(fixture_i3_offline LANGUAGES NONE)

include(ocx)

if(NOT OCX_OFFLINE OR NOT OCX_HOME)
  message(FATAL_ERROR "i3 offline fixture: run with -DOCX_OFFLINE=1 -DOCX_HOME=<empty dir>")
endif()

ocx_package(
  NAME OFF
  PACKAGE ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
  BINS jqq
)
if(NOT DEFINED CACHE{OCX_OFF_RUN_JQQ})
  message(FATAL_ERROR "i3 offline fixture: OCX_OFF_RUN_JQQ missing")
endif()
