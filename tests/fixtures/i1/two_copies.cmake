# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Child of module_checks.cmake (script mode): loads two vendored copies of
# ocx.cmake, COPY_A then COPY_B, and reports what the GLOBAL property
# recorded for the first.
#
#   cmake -DCOPY_A=<ocx.cmake> -DCOPY_B=<ocx.cmake> -P two_copies.cmake

include("${COPY_A}")
get_property(recorded_version GLOBAL PROPERTY __OCX_MODULE_VERSION)
get_property(recorded_file GLOBAL PROPERTY __OCX_MODULE_FILE)
message(STATUS "two_copies: first ${recorded_version} ${recorded_file}")

include("${COPY_B}")
message(STATUS "two_copies: both loaded")
