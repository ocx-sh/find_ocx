# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Repo-internal tests of the bootstrap and dist pipeline (never part of the
# published module files). Included once from CMakeLists.txt after
# tests/helpers.cmake; needs OCX_TEST_CMAKE_VERSIONS and the per-version
# OCX_CMAKE_<v>_RUN / OCX_CMAKE_<v>_TEST_LABEL variables it defines.
#
#   dist_script         unit tests of the scripts/update_dist.py guards
#   dist_check          the embedded snapshot and CI pins pass --check
#   bootstrap_dist/...  ocx_bootstrap of the pin from a fake file:// distribution
#   module_checks/...   second-copy version FATAL, ocx_self_update name, policy pin

find_program(OCX_TEST_PYTHON NAMES python3 python)
if(NOT OCX_TEST_PYTHON)
  message(FATAL_ERROR
    "find_ocx: python3 is required for the dist guard tests (scripts/update_dist.py)")
endif()

add_test(
  NAME dist_script
  COMMAND
    "${OCX_TEST_PYTHON}" -I -m unittest discover -s scripts -p update_dist_test.py
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
add_test(
  NAME dist_check
  COMMAND "${OCX_TEST_PYTHON}" -I scripts/update_dist.py --check
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
set_tests_properties(dist_script dist_check PROPERTIES TIMEOUT 60)

foreach(v IN LISTS OCX_TEST_CMAKE_VERSIONS)
  add_test(
    NAME bootstrap_dist/${OCX_CMAKE_${v}_TEST_LABEL}
    COMMAND
      ${OCX_CMAKE_${v}_RUN} cmake "-DMODULE_DIR=${CMAKE_SOURCE_DIR}"
      "-DOCX_EXE=${OCX_EXECUTABLE}"
      "-DSCRATCH=${CMAKE_BINARY_DIR}/fixtures/bootstrap_dist-cmake${v}" -P
      "${CMAKE_SOURCE_DIR}/tests/fixtures/i1/bootstrap_dist.cmake")
  add_test(
    NAME module_checks/${OCX_CMAKE_${v}_TEST_LABEL}
    COMMAND
      ${OCX_CMAKE_${v}_RUN} cmake "-DMODULE_DIR=${CMAKE_SOURCE_DIR}"
      "-DSCRATCH=${CMAKE_BINARY_DIR}/fixtures/module_checks-cmake${v}" -P
      "${CMAKE_SOURCE_DIR}/tests/fixtures/i1/module_checks.cmake")
  set_tests_properties(
    bootstrap_dist/${OCX_CMAKE_${v}_TEST_LABEL}
    module_checks/${OCX_CMAKE_${v}_TEST_LABEL}
    PROPERTIES TIMEOUT 300)
endforeach()
