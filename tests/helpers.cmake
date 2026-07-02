# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Repo-internal test helpers - never part of the published module files.

# Adds one test per CMake version: the fixture is configured AND built with
# the OCX-provisioned cmake (ocx package exec ocx.sh/cmake:<tag> -- ctest
# --build-and-test). Fixtures self-assert at configure/build time.
function(ocx_add_cmake_version_test fixture)
  cmake_parse_arguments(arg "NO_EXECUTABLE" "" "VERSIONS;OPTIONS" ${ARGN})
  set(common_options "-DCMAKE_MODULE_PATH=${CMAKE_SOURCE_DIR}")
  if(DEFINED OCX_BOOTSTRAP_CACHE AND NOT "${OCX_BOOTSTRAP_CACHE}" STREQUAL "")
    list(APPEND common_options "-DOCX_BOOTSTRAP_CACHE=${OCX_BOOTSTRAP_CACHE}")
  endif()
  if(NOT arg_NO_EXECUTABLE)
    list(APPEND common_options "-DOCX_EXECUTABLE=${OCX_EXECUTABLE}")
  endif()
  foreach(v IN LISTS arg_VERSIONS)
    set(bin_dir "${CMAKE_BINARY_DIR}/fixtures/${fixture}-cmake${v}")
    add_test(
      NAME ${fixture}.cmake${v}
      COMMAND ${OCX_CMAKE_${v}_RUN} ctest --build-and-test
        "${CMAKE_SOURCE_DIR}/tests/fixtures/${fixture}"
        "${bin_dir}"
        --build-generator "${CMAKE_GENERATOR}"
        --build-options -Werror=dev ${common_options} ${arg_OPTIONS}
    )
  endforeach()
endfunction()

# Negative test: a doctored ocx.lock must fail the configure with the
# actionable exit-65 hint.
function(ocx_add_stale_lock_test)
  cmake_parse_arguments(arg "" "" "VERSIONS" ${ARGN})
  foreach(v IN LISTS arg_VERSIONS)
    set(bin_dir "${CMAKE_BINARY_DIR}/fixtures/stale_lock-cmake${v}")
    add_test(
      NAME stale_lock.cmake${v}
      COMMAND ${OCX_CMAKE_${v}_RUN} cmake -Werror=dev
        -S "${CMAKE_SOURCE_DIR}/tests/fixtures/stale_lock"
        -B "${bin_dir}"
        "-DCMAKE_MODULE_PATH=${CMAKE_SOURCE_DIR}"
        "-DOCX_EXECUTABLE=${OCX_EXECUTABLE}"
    )
    set_tests_properties(stale_lock.cmake${v} PROPERTIES
      PASS_REGULAR_EXPRESSION "run 'ocx lock'")
  endforeach()
endfunction()

# Negative test: OCX_BOOTSTRAP=OFF must turn the implicit bootstrap into a
# hard error when no OCX_EXECUTABLE is provided.
function(ocx_add_bootstrap_off_test)
  cmake_parse_arguments(arg "" "" "VERSIONS" ${ARGN})
  foreach(v IN LISTS arg_VERSIONS)
    add_test(
      NAME bootstrap_off.cmake${v}
      COMMAND ${OCX_CMAKE_${v}_RUN} cmake
        "-DCMAKE_MODULE_PATH=${CMAKE_SOURCE_DIR}"
        -DOCX_BOOTSTRAP=OFF
        -P "${CMAKE_SOURCE_DIR}/tests/fixtures/bootstrap_off.cmake"
    )
    set_tests_properties(bootstrap_off.cmake${v} PROPERTIES
      PASS_REGULAR_EXPRESSION "implicit bootstrap is disabled")
  endforeach()
endfunction()

# Script mode: ocx.cmake must work under `cmake -P` (no project(), no
# generator, no persistent cache).
function(ocx_add_script_mode_test)
  cmake_parse_arguments(arg "" "" "VERSIONS" ${ARGN})
  foreach(v IN LISTS arg_VERSIONS)
    add_test(
      NAME script_mode.cmake${v}
      COMMAND ${OCX_CMAKE_${v}_RUN} cmake
        "-DCMAKE_MODULE_PATH=${CMAKE_SOURCE_DIR}"
        "-DOCX_EXECUTABLE=${OCX_EXECUTABLE}"
        -P "${CMAKE_SOURCE_DIR}/tests/fixtures/script_mode.cmake"
    )
  endforeach()
endfunction()

# Memoization test: configure the package fixture twice; the second
# configure must report the fingerprint hit instead of re-running ocx.
function(ocx_add_memoize_test)
  cmake_parse_arguments(arg "" "" "VERSIONS" ${ARGN})
  foreach(v IN LISTS arg_VERSIONS)
    add_test(
      NAME memoize.cmake${v}
      COMMAND ${OCX_CMAKE_${v}_RUN} cmake
        "-DFIXTURE_SRC=${CMAKE_SOURCE_DIR}/tests/fixtures/package"
        "-DFIXTURE_BIN=${CMAKE_BINARY_DIR}/fixtures/memoize-cmake${v}"
        "-DMODULE_PATH=${CMAKE_SOURCE_DIR}"
        "-DOCX_EXE=${OCX_EXECUTABLE}"
        -P "${CMAKE_SOURCE_DIR}/tests/reconfigure_check.cmake"
    )
  endforeach()
endfunction()
