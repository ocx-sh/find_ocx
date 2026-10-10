# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Script mode (cmake -P): negative-test driver. Runs `cmake ${EXPECT_ARGS}`
# and passes only when the exit status is EXPECT_EXIT (default 1) AND the
# output carries a `CMake [Deprecation] Error [(dev)] at ... (message):`
# header followed by EXPECT_REGEX. Whitespace is flattened first: CMake wraps long messages.
#
#   cmake -DEXPECT_ARGS=<;-list> -DEXPECT_REGEX=<regex> [-DEXPECT_EXIT=<n>] \
#         -P tests/expect_failure.cmake

foreach(var EXPECT_ARGS EXPECT_REGEX)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "expect_failure: -D${var}=... is required")
  endif()
endforeach()
if(NOT DEFINED EXPECT_EXIT)
  set(EXPECT_EXIT 1)
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${EXPECT_ARGS}
  RESULT_VARIABLE rc
  OUTPUT_VARIABLE out
  ERROR_VARIABLE err
)
set(report "exit status: ${rc}\n${out}\n${err}")

if(NOT "${rc}" STREQUAL "${EXPECT_EXIT}")
  message(FATAL_ERROR "expect_failure: expected exit status ${EXPECT_EXIT}\n${report}")
endif()

string(REGEX REPLACE "[ \t\r\n]+" " " flat "${out} ${err}")
if(
  NOT
    "${flat}"
      MATCHES
      "CMake (Deprecation )?Error( \\([a-z]+\\))? at .*\\(message\\): .*(${EXPECT_REGEX})"
)
  message(
    FATAL_ERROR
    "expect_failure: no 'CMake Error ... (message):' carrying /${EXPECT_REGEX}/\n${report}"
  )
endif()
if("${flat}" MATCHES "CMake Deprecation Warning")
  message(FATAL_ERROR "expect_failure: deprecation warning in the output\n${report}")
endif()
