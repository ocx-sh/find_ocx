# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: ambient OCX_QUIET=1 (blank JSON output) and OCX_GLOBAL=1 (rejects
# --project) must not break the configure - find_ocx pins both.

cmake_minimum_required(VERSION 3.19)
project(fixture_ambient_quiet_global LANGUAGES NONE)

set(ENV{OCX_QUIET} 1)
set(ENV{OCX_GLOBAL} 1)
include(ocx)
include("${CMAKE_CURRENT_LIST_DIR}/../ambient_env_body.cmake")
