# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Runtime-core tests: env classes, ocx_policy, exit-code hints and the
# retry policy of __ocx_run. Included from the top-level CMakeLists.txt after
# the harness has probed the CMake versions (OCX_TEST_CMAKE_VERSIONS,
# OCX_CMAKE_<v>_RUN, OCX_CMAKE_<v>_TEST_LABEL).

# Ambient hostile OCX_* variables must not break a configure.
ocx_add_cmake_version_test(ambient_quiet_global VERSIONS ${OCX_TEST_CMAKE_VERSIONS})
ocx_add_cmake_version_test(ambient_no_config VERSIONS ${OCX_TEST_CMAKE_VERSIONS})

# Env prefix, policy, hint table, managed-config gate and retry policy
# against a fake ocx (tests/i2_check.cmake).
foreach(v IN LISTS OCX_TEST_CMAKE_VERSIONS)
  add_test(
    NAME runtime_core/${OCX_CMAKE_${v}_TEST_LABEL}
    COMMAND ${OCX_CMAKE_${v}_RUN} cmake
      "-DMODULE_DIR=${CMAKE_SOURCE_DIR}"
      "-DSCRATCH=${CMAKE_BINARY_DIR}/fixtures/runtime_core-cmake${v}"
      "-DOCX_EXE=${OCX_EXECUTABLE}"
      -P "${CMAKE_SOURCE_DIR}/tests/i2_check.cmake"
  )
  set_tests_properties(runtime_core/${OCX_CMAKE_${v}_TEST_LABEL}
    PROPERTIES TIMEOUT 120 FIXTURES_REQUIRED ocx_fixtures)
endforeach()
