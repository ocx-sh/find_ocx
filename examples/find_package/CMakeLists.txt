# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Example: classic discovery via the find module. find_package(ocx) honors
# an ocx already on PATH or an explicit -DOCX_EXECUTABLE; with
# -DOCX_BOOTSTRAP=ON it falls back to bootstrapping the pinned CLI when
# none is found (zero-setup; needs CMake 3.19 and ocx.cmake next to
# Findocx.cmake). This is the entry point for projects that want the
# system ocx to win.
#
#   cmake -S . -B build -DOCX_BOOTSTRAP=ON && ctest --test-dir build

cmake_minimum_required(VERSION 3.15)
project(ocx_example_find_package LANGUAGES NONE)

enable_testing()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../..")
find_package(ocx REQUIRED)

message(STATUS "example: ocx ${OCX_VERSION_STRING} at ${OCX_EXECUTABLE}")

add_test(NAME ocx_version COMMAND ocx::ocx version)
