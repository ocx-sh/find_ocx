# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: find_package(ocx REQUIRED) with the OCX_EXECUTABLE the harness
# passes, or the one the test replaces it with.

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_i3_find_module LANGUAGES NONE)

find_package(ocx REQUIRED)
message(STATUS "find_module fixture: ocx ${OCX_VERSION_STRING} at ${OCX_EXECUTABLE}")
