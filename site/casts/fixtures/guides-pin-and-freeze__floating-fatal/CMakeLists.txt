# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

cmake_minimum_required(VERSION 3.25...4.4)
project(floating_fatal LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest BINS jq)
