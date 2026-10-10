# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Example: bundle linux/arm64 content, resolved from the same ocx.lock as the
# host build, into an install tree.
#
#   cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake
#   cmake --install build --prefix out

cmake_minimum_required(VERSION 3.25...4.4)
project(ocx_example_cross_build LANGUAGES NONE)

enable_testing()

# region bundle
# toolchain.cmake provisioned the arm64 content: OCX_TARGET_PATHS lists the
# content directories, OCX_TARGET_ENV_KEYS the environment keys the packages set.
foreach(dir IN LISTS OCX_TARGET_PATHS)
  install(DIRECTORY "${dir}/" DESTINATION payload USE_SOURCE_PERMISSIONS)
endforeach()
# endregion

if(NOT OCX_TARGET_PATHS)
  message(FATAL_ERROR "pass -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake")
endif()
foreach(dir IN LISTS OCX_TARGET_PATHS)
  if(NOT EXISTS "${dir}/jq")
    message(FATAL_ERROR "no jq in ${dir}")
  endif()
endforeach()
message(STATUS "example: arm64 content at ${OCX_TARGET_PATHS}")
