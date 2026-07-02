# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: ocx_bootstrap() downloads the pinned CLI (sha256-enforced, into
# the per-machine cache), then find_package(ocx) finds it via the
# OCX_EXECUTABLE hint. Deliberately does NOT receive -DOCX_EXECUTABLE.

cmake_minimum_required(VERSION 3.19)
project(fixture_bootstrap LANGUAGES NONE)

include(ocx)

ocx_bootstrap()
find_package(ocx REQUIRED)

if(NOT OCX_VERSION_STRING VERSION_EQUAL __OCX_PIN_VERSION)
  message(FATAL_ERROR
    "bootstrap fixture: expected ocx ${__OCX_PIN_VERSION}, "
    "found '${OCX_VERSION_STRING}' at ${OCX_EXECUTABLE}")
endif()
if(NOT TARGET ocx::ocx)
  message(FATAL_ERROR "bootstrap fixture: imported target ocx::ocx missing")
endif()
message(STATUS "bootstrap fixture: ok (ocx ${OCX_VERSION_STRING})")
