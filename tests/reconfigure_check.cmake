# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Script mode (cmake -P): configures FIXTURE_SRC twice into FIXTURE_BIN and
# asserts the second configure hits the reconfigure memoization (no ocx
# re-execution) by matching the status line.

foreach(var FIXTURE_SRC FIXTURE_BIN MODULE_PATH OCX_EXE)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "reconfigure_check: -D${var}=... is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${FIXTURE_BIN}")
set(configure
  "${CMAKE_COMMAND}" -S "${FIXTURE_SRC}" -B "${FIXTURE_BIN}"
  "-DCMAKE_MODULE_PATH=${MODULE_PATH}" "-DOCX_EXECUTABLE=${OCX_EXE}")

execute_process(COMMAND ${configure} RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "reconfigure_check: first configure failed:\n${out}\n${err}")
endif()
if(out MATCHES "up to date \\(memoized\\)")
  message(FATAL_ERROR "reconfigure_check: first configure must not be memoized:\n${out}")
endif()

execute_process(COMMAND ${configure} RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "reconfigure_check: second configure failed:\n${out}\n${err}")
endif()
if(NOT out MATCHES "up to date \\(memoized\\)")
  message(FATAL_ERROR "reconfigure_check: second configure did not memoize:\n${out}")
endif()
message(STATUS "reconfigure_check: ok")
