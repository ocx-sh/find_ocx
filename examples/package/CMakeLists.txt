# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Example: ad-hoc packages straight from the registry - floating (eager,
# prints the resolved digest to copy into PINS), digest-pinned + lazy
# (materializes on first build-time execution), and <name>_ROOT export for
# bootstrapping dependencies of find_package/find_library.
#
#   cmake -S . -B build && cmake --build build && ctest --test-dir build

cmake_minimum_required(VERSION 3.19)
project(ocx_example_package LANGUAGES NONE)

enable_testing()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../..")
include(ocx)

# Floating + eager: resolved at configure time; the log suggests the PINS
# line for reproducibility. Exports jq_ROOT (CMP0074) - a subsequent
# find_package(jq)/find_program would search the OCX-provisioned content.
ocx_package(NAME jq PACKAGE ocx.sh/jq:latest PULL)
message(STATUS "example: jq content at ${jq_ROOT}")

# Digest-pinned + lazy: per-platform manifest digests (from
# `ocx package install -p <platform>` or the ocx.lock of a project);
# nothing is fetched until the first execution.
ocx_package(NAME jq_pinned PACKAGE ocx.sh/jq:latest BINS jq NO_ROOT
  PINS
    "linux/amd64=sha256:11814b34158ab143969a8efffe59a320dd07c0b176a65366427514b326e2a347"
    "linux/arm64=sha256:1f31a7547df94c14075efbbadb1f89a8a8d2ae4635411e5a7a7192c5601032e7"
    "darwin/amd64=sha256:b17686a01c7d3d6252e4c8ce681ff8f06e6e06f293200a6b2f20e3923614a2cb"
    "darwin/arm64=sha256:5be7552a463835dead65ca4c858ebc10703a0d9cff7308967f04d08fa8e2da1a"
    "windows/amd64=sha256:8434027cf0a6c340a10e533ecdfd8137f085e476437352b98237294adf821c7d"
)

add_custom_target(pretty ALL
  COMMAND ${OCX_JQ_PINNED_RUN_JQ} . "${CMAKE_CURRENT_SOURCE_DIR}/data.json"
  VERBATIM
)

add_test(NAME jq_pinned_filter
  COMMAND ${OCX_JQ_PINNED_RUN_JQ} -e ".target == \"cmake\""
          "${CMAKE_CURRENT_SOURCE_DIR}/data.json")

# Frozen-index + lazy: the tag resolves from the committed snapshot
# (index/ocx.sh/jq.json) - reproducible without digests in this file.
# Refresh deliberately (`ocx --index index index update ocx.sh/jq`, or
# compose it with ocx_index_update_command()), review the diff, commit.
ocx_package(NAME jq_frozen PACKAGE ocx.sh/jq:latest BINS jq NO_ROOT
  INDEX "${CMAKE_CURRENT_SOURCE_DIR}/index")

add_test(NAME jq_frozen_filter
  COMMAND ${OCX_JQ_FROZEN_RUN_JQ} -e ".target == \"cmake\""
          "${CMAKE_CURRENT_SOURCE_DIR}/data.json")
