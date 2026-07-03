# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Repo-internal test harness (not part of the published module). Dogfoods
# ocx.cmake: the CMake versions under test are provisioned as OCX packages
# from the mirror-cmake bundle (ocx.sh/cmake:<tag>).

cmake_minimum_required(VERSION 3.19)
project(find_ocx LANGUAGES NONE)

enable_testing()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}")
include(ocx)

# INDEX: the :3.31/:4 tags resolve frozen from the committed snapshot
# (tests/index/ocx.sh/cmake.json) - CI tag resolution is hermetic.
ocx_package(NAME CMAKE_3 PACKAGE ocx.sh/cmake:3.31 PULL NO_ROOT
  INDEX "${CMAKE_CURRENT_SOURCE_DIR}/tests/index")
ocx_package(NAME CMAKE_4 PACKAGE ocx.sh/cmake:4 PULL NO_ROOT
  INDEX "${CMAKE_CURRENT_SOURCE_DIR}/tests/index")
# TODO(mirror backfill): mirror-cmake versions.min is 3.31.0; enable once
# 3.19.x is published, see the plan's external prerequisite.
# ocx_package(NAME CMAKE_3_19 PACKAGE ocx.sh/cmake:3.19 PULL NO_ROOT)
set(OCX_TEST_CMAKE_VERSIONS 3 4)

# Refresh flow: `cmake --build build --target ocx-index-update` (or
# `task index:update`), review the diff, commit.
ocx_index_update()

include(tests/helpers.cmake)

# Test names are <test>/cmake-<full-version> (tree in IDE test explorers);
# probe the provisioned cmakes once for their resolved versions.
foreach(v IN LISTS OCX_TEST_CMAKE_VERSIONS)
  ocx_cmake_test_label(OCX_CMAKE_${v}_TEST_LABEL ${v})
endforeach()

ocx_add_cmake_version_test(bootstrap VERSIONS ${OCX_TEST_CMAKE_VERSIONS} NO_EXECUTABLE)
ocx_add_cmake_version_test(project_run VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_cmake_version_test(package VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
  ocx_add_cmake_version_test(foreign_platform VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
endif()
ocx_add_stale_lock_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_bootstrap_off_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_memoize_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_script_mode_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_self_update_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
