# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Script mode (cmake -P): negative-test driver. Runs `cmake ${EXPECT_ARGS}` and
# passes only on exit status EXPECT_EXIT (default 1) plus a `CMake Error at ...
# (message):` header carrying EXPECT_REGEX, matched on whitespace-flattened
# output because CMake wraps long messages.
#   -DEXPECT_ARGS=<;-list> -DEXPECT_REGEX=<regex> [-DEXPECT_EXIT=<n>]

foreach(var EXPECT_ARGS EXPECT_REGEX)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "expect_failure: -D${var}=... is required")
  endif()
endforeach()
if(NOT DEFINED EXPECT_EXIT)
  set(EXPECT_EXIT 1)
endif()

# The gate does nothing under -P below 4.4, where the warning check below
# stands in for it; from 4.4 the script run is gated like a configure.
list(FIND EXPECT_ARGS -P script_flag)
if(NOT script_flag EQUAL -1 AND CMAKE_VERSION VERSION_GREATER_EQUAL 4.4)
  list(PREPEND EXPECT_ARGS -Werror=author)
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
if("${flat}" MATCHES "CMake (Deprecation )?Warning")
  message(FATAL_ERROR "expect_failure: warning in the output\n${report}")
endif()
