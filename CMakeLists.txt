# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Repo-internal test harness (not part of the published module). Dogfoods
# ocx.cmake: the CMake versions under test are provisioned as OCX packages -
# the declared 3.25 floor, 3.31 and the newest line, 4.4.

cmake_minimum_required(VERSION 3.25...4.4)
project(find_ocx LANGUAGES NONE)

enable_testing()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}")
include(ocx)

# The committed .ocx/ snapshot (ocx.sh/p/<owner>/<name>.json) freezes the tags
# below - CI tag resolution is hermetic. FIND REQUIRED locks the discovery
# into OCX_INDEX (fail-fast, dogfoods the ladder).
ocx_index(FIND REQUIRED)
ocx_package(NAME UV PACKAGE ocx.sh/astral-sh/uv:latest BINS uv NO_ROOT)
ocx_package(NAME CMAKE_3_31 PACKAGE ocx.sh/kitware/cmake:3.31 PULL NO_ROOT)
ocx_package(NAME CMAKE_4_4 PACKAGE ocx.sh/kitware/cmake:4.4 PULL NO_ROOT)
# The floor leg is the PyPI wheel (ocx.sh/kitware/cmake starts at 3.31), pinned
# exactly so it cannot drift. `uv tool run` is uvx.
set(
  OCX_CMAKE_3_25_RUN
  ${OCX_UV_RUN_UV}
  tool
  run
  --from
  cmake==3.25.2
)
set(OCX_TEST_CMAKE_VERSIONS 3_25 3_31 4_4)

# Refresh flow: `cmake --build build --target ocx-index-update` (or
# `task index:update`), review the diff, commit.
ocx_index(UPDATE_COMMAND index_refresh)
add_custom_target(
  ocx-index-update
  COMMAND ${index_refresh}
  COMMAND
    ${CMAKE_COMMAND} -E echo
    "find_ocx: index snapshot refreshed - review the diff and commit the result"
  VERBATIM
)

include(tests/helpers.cmake)

# Test names are <test>/cmake-<full-version> (tree in IDE test explorers);
# probe the provisioned cmakes once for their resolved versions.
foreach(v IN LISTS OCX_TEST_CMAKE_VERSIONS)
  ocx_cmake_test_label(OCX_CMAKE_${v}_TEST_LABEL ${v})
endforeach()

ocx_add_cmake_version_test(bootstrap VERSIONS ${OCX_TEST_CMAKE_VERSIONS} NO_EXECUTABLE)
ocx_add_cmake_version_test(project_run VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_cmake_version_test(project_groups VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_cmake_version_test(package VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
  ocx_add_cmake_version_test(foreign_platform VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
  # Needs the idempotent re-entry of ocx_package()/ocx_project() for a
  # toolchain file that CMake reads more than once.
  ocx_add_cmake_version_test(
    foreign_toolchain
    VERSIONS ${OCX_TEST_CMAKE_VERSIONS}
    OPTIONS
      "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_SOURCE_DIR}/tests/fixtures/foreign_toolchain/toolchain.cmake"
  )
endif()
ocx_add_stale_lock_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_bootstrap_off_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_bootstrap_empty_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_floating_fatal_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_memoize_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_script_mode_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_self_update_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_mirror_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_gate_canary_test(VERSIONS ${OCX_TEST_CMAKE_VERSIONS})

include(tests/i2.cmake)
include(tests/i3.cmake)
include(tests/i1.cmake)

include(tests/casts.cmake)

# The README quick-start fences must equal the examples/tutorial regions.
add_test(
  NAME readme_check
  COMMAND
    ${CMAKE_COMMAND} -DROOT=${CMAKE_CURRENT_SOURCE_DIR} -P
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/readme_check.cmake
)
set_tests_properties(readme_check PROPERTIES TIMEOUT 30)

# Docs check: the exit-code table on the troubleshooting page matches the hint table (no ocx needed).
include(tests/hint_table_check.cmake)
