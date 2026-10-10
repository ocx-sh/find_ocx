# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Repo-internal test helpers - never part of the published module files.

# Wall-clock bound for every test; a ctest --timeout on the CI line covers
# anything registered outside these helpers.
if(NOT DEFINED OCX_TEST_TIMEOUT)
  set(OCX_TEST_TIMEOUT 600)
endif()

# Fixture build trees live under <build>/fixtures and are wiped before every
# run: a stale CMakeCache.txt hides first-configure behavior such as a
# toolchain file being read twice. Every test below requires this setup.
add_test(
  NAME fixtures_clean
  COMMAND "${CMAKE_COMMAND}" -E rm -rf "${CMAKE_BINARY_DIR}/fixtures"
)
set_tests_properties(fixtures_clean PROPERTIES FIXTURES_SETUP ocx_fixtures TIMEOUT 60)

# Probes the provisioned cmake for its full version and returns a test-name
# leaf like "cmake-3.31.8". Test names are slash-hierarchical
# (<test>/cmake-<version>) so IDE test explorers render a tree with one
# leaf per provisioned CMake version.
function(ocx_cmake_test_label out_var v)
  execute_process(
    COMMAND ${OCX_CMAKE_${v}_RUN} cmake --version
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
  )
  if(NOT rc EQUAL 0 OR NOT out MATCHES "cmake version ([0-9][^ \n]*)")
    message(FATAL_ERROR "helpers: cannot probe version of provisioned cmake:${v}:\n${out}${err}")
  endif()
  set(${out_var} "cmake-${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()

# The configure gate spelled for the leg's binary:
# -Werror=author maps onto dev on 4.4 and later, and does nothing below it.
# The leg's version comes from its test label, so call this after
# ocx_cmake_test_label().
function(ocx_cmake_test_gate out_var v)
  if(NOT "${OCX_CMAKE_${v}_TEST_LABEL}" MATCHES "^cmake-([0-9]+\\.[0-9]+)")
    message(FATAL_ERROR "helpers: no test label for cmake leg '${v}'")
  endif()
  if(CMAKE_MATCH_1 VERSION_GREATER_EQUAL 4.4)
    set(${out_var} -Werror=author PARENT_SCOPE)
  else()
    set(${out_var} -Werror=dev PARENT_SCOPE)
  endif()
endfunction()

# Properties shared by every test: the per-test timeout and, for a test whose
# command runs a `cmake -P` script, the deprecation substitute for the gate
# (the gate does nothing under -P on 4.3 and older).
function(__ocx_test_props name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "SCRIPT" "" "")
  set_tests_properties(
    ${name}
    PROPERTIES TIMEOUT ${OCX_TEST_TIMEOUT} FIXTURES_REQUIRED ocx_fixtures
  )
  if(arg_SCRIPT)
    set_tests_properties(
      ${name}
      PROPERTIES FAIL_REGULAR_EXPRESSION "CMake Warning;CMake Deprecation Warning"
    )
  endif()
endfunction()

# Adds one test per CMake version: the fixture is configured AND built with
# the provisioned cmake (<leg launcher> ctest --build-and-test). Fixtures
# self-assert at configure/build time.
function(ocx_add_cmake_version_test fixture)
  cmake_parse_arguments(PARSE_ARGV 1 arg "NO_EXECUTABLE" "" "VERSIONS;OPTIONS")
  # Fixtures run under the harness's frozen launcher (OCX_CMAKE_<v>_RUN
  # exports OCX_FROZEN/OCX_INDEX into children): clear both so fixtures
  # resolve independently of the outer index.
  set(common_options "-DCMAKE_MODULE_PATH=${CMAKE_SOURCE_DIR}" "-DOCX_FROZEN=" "-DOCX_INDEX=")
  if(DEFINED OCX_BOOTSTRAP_CACHE AND NOT "${OCX_BOOTSTRAP_CACHE}" STREQUAL "")
    list(APPEND common_options "-DOCX_BOOTSTRAP_CACHE=${OCX_BOOTSTRAP_CACHE}")
  endif()
  if(NOT arg_NO_EXECUTABLE)
    list(APPEND common_options "-DOCX_EXECUTABLE=${OCX_EXECUTABLE}")
  endif()
  foreach(v IN LISTS arg_VERSIONS)
    ocx_cmake_test_gate(gate ${v})
    set(bin_dir "${CMAKE_BINARY_DIR}/fixtures/${fixture}-cmake${v}")
    set(test_name ${fixture}/${OCX_CMAKE_${v}_TEST_LABEL})
    add_test(
      NAME ${test_name}
      COMMAND
        ${OCX_CMAKE_${v}_RUN} ctest --build-and-test "${CMAKE_SOURCE_DIR}/tests/fixtures/${fixture}"
        "${bin_dir}" --build-generator "${CMAKE_GENERATOR}" --build-options ${gate}
        ${common_options} ${arg_OPTIONS}
    )
    __ocx_test_props(${test_name})
  endforeach()
endfunction()

# Negative test: runs `cmake <ARGS>` under tests/expect_failure.cmake, which
# asserts the exit status AND the CMake Error diagnostic together: a bare
# PASS_REGULAR_EXPRESSION ignores the exit code, WILL_FAIL ignores why.
#   ocx_add_negative_test(<test> <v> REGEX <regex> ARGS <cmake args>... [EXIT <n>])
# <regex> must match the flattened message text after the severity header.
function(ocx_add_negative_test test v)
  cmake_parse_arguments(PARSE_ARGV 2 arg "" "REGEX;EXIT" "ARGS")
  if(NOT DEFINED arg_REGEX OR NOT DEFINED arg_ARGS)
    message(FATAL_ERROR "ocx_add_negative_test: REGEX and ARGS are required")
  endif()
  if(NOT DEFINED arg_EXIT)
    set(arg_EXIT 1)
  endif()
  set(test_name ${test}/${OCX_CMAKE_${v}_TEST_LABEL})
  add_test(
    NAME ${test_name}
    COMMAND
      ${OCX_CMAKE_${v}_RUN} cmake "-DEXPECT_ARGS=${arg_ARGS}" "-DEXPECT_REGEX=${arg_REGEX}"
      -DEXPECT_EXIT=${arg_EXIT} -P "${CMAKE_SOURCE_DIR}/tests/expect_failure.cmake"
  )
  __ocx_test_props(${test_name})
endfunction()

# Negative test: a doctored ocx.lock must fail the configure with the
# actionable hint.
function(ocx_add_stale_lock_test)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "" "VERSIONS")
  foreach(v IN LISTS arg_VERSIONS)
    ocx_cmake_test_gate(gate ${v})
    ocx_add_negative_test(
      stale_lock
      ${v}
      REGEX "ocx lock"
      ARGS
        ${gate}
        -S
        "${CMAKE_SOURCE_DIR}/tests/fixtures/stale_lock"
        -B
        "${CMAKE_BINARY_DIR}/fixtures/stale_lock-cmake${v}"
        "-DCMAKE_MODULE_PATH=${CMAKE_SOURCE_DIR}"
        "-DOCX_EXECUTABLE=${OCX_EXECUTABLE}"
        -DOCX_FROZEN=
        -DOCX_INDEX=
    )
  endforeach()
endfunction()

# Negative test: OCX_BOOTSTRAP=OFF must turn the implicit bootstrap into a
# hard error when no OCX_EXECUTABLE is provided.
function(ocx_add_bootstrap_off_test)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "" "VERSIONS")
  foreach(v IN LISTS arg_VERSIONS)
    ocx_add_negative_test(
      bootstrap_off
      ${v}
      REGEX "is disabled \\(OCX_BOOTSTRAP=OFF\\)"
      ARGS
        "-DCMAKE_MODULE_PATH=${CMAKE_SOURCE_DIR}"
        -DOCX_BOOTSTRAP=OFF
        -P
        "${CMAKE_SOURCE_DIR}/tests/fixtures/bootstrap_off.cmake"
    )
  endforeach()
endfunction()

# Negative test: a floating tag with no index in effect and no digest pin
# must fail the configure (reproducible-first gate).
function(ocx_add_floating_fatal_test)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "" "VERSIONS")
  foreach(v IN LISTS arg_VERSIONS)
    ocx_add_negative_test(
      floating_fatal
      ${v}
      REGEX "resolution is not reproducible"
      ARGS
        "-DCMAKE_MODULE_PATH=${CMAKE_SOURCE_DIR}"
        "-DOCX_EXECUTABLE=${OCX_EXECUTABLE}"
        -DOCX_FROZEN=
        -DOCX_INDEX=
        -P
        "${CMAKE_SOURCE_DIR}/tests/fixtures/floating_fatal.cmake"
    )
  endforeach()
endfunction()

# Script mode: ocx.cmake must work under `cmake -P` (no project(), no
# generator, no persistent cache).
function(ocx_add_script_mode_test)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "" "VERSIONS")
  foreach(v IN LISTS arg_VERSIONS)
    set(test_name script_mode/${OCX_CMAKE_${v}_TEST_LABEL})
    add_test(
      NAME ${test_name}
      COMMAND
        ${OCX_CMAKE_${v}_RUN} cmake "-DCMAKE_MODULE_PATH=${CMAKE_SOURCE_DIR}"
        "-DOCX_EXECUTABLE=${OCX_EXECUTABLE}" -DOCX_FROZEN= -DOCX_INDEX= -P
        "${CMAKE_SOURCE_DIR}/tests/fixtures/script_mode.cmake"
    )
    __ocx_test_props(${test_name} SCRIPT)
  endforeach()
endfunction()

# Self-update check: a doctored fake release behind a file:// base URL must
# replace the vendored ocx.cmake/Findocx.cmake in place (fully offline).
function(ocx_add_self_update_test)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "" "VERSIONS")
  foreach(v IN LISTS arg_VERSIONS)
    set(test_name self_update/${OCX_CMAKE_${v}_TEST_LABEL})
    add_test(
      NAME ${test_name}
      COMMAND
        ${OCX_CMAKE_${v}_RUN} cmake "-DMODULE_DIR=${CMAKE_SOURCE_DIR}"
        "-DSCRATCH=${CMAKE_BINARY_DIR}/fixtures/self_update-cmake${v}" -P
        "${CMAKE_SOURCE_DIR}/tests/self_update_check.cmake"
    )
    __ocx_test_props(${test_name} SCRIPT)
  endforeach()
endfunction()

# Memoization test: configure the package fixture four times - baseline,
# repeat (hit), one changed input (invalidated, others still hit), repeat
# (re-stored, hit again). See tests/reconfigure_check.cmake.
function(ocx_add_memoize_test)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "" "VERSIONS")
  foreach(v IN LISTS arg_VERSIONS)
    ocx_cmake_test_gate(gate ${v})
    set(test_name memoize/${OCX_CMAKE_${v}_TEST_LABEL})
    add_test(
      NAME ${test_name}
      COMMAND
        ${OCX_CMAKE_${v}_RUN} cmake "-DFIXTURE_SRC=${CMAKE_SOURCE_DIR}/tests/fixtures/package"
        "-DFIXTURE_BIN=${CMAKE_BINARY_DIR}/fixtures/memoize-cmake${v}"
        "-DMODULE_PATH=${CMAKE_SOURCE_DIR}" "-DOCX_EXE=${OCX_EXECUTABLE}" "-DGATE=${gate}" -P
        "${CMAKE_SOURCE_DIR}/tests/reconfigure_check.cmake"
    )
    __ocx_test_props(${test_name} SCRIPT)
  endforeach()
endfunction()

# Gate canary: an author warning and a deprecation warning must each fail the
# configure under the leg's gate. A green result means the gate is live.
function(ocx_add_gate_canary_test)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "" "VERSIONS")
  foreach(v IN LISTS arg_VERSIONS)
    ocx_cmake_test_gate(gate ${v})
    foreach(canary IN ITEMS author deprecation)
      ocx_add_negative_test(
        gate_canary_${canary}
        ${v}
        REGEX "gate canary"
        ARGS
          ${gate}
          -S
          "${CMAKE_SOURCE_DIR}/tests/fixtures/gate_canary"
          -B
          "${CMAKE_BINARY_DIR}/fixtures/gate_canary_${canary}-cmake${v}"
          -DCANARY=${canary}
      )
    endforeach()
  endforeach()
endfunction()
