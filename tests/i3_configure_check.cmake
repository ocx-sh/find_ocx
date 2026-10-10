# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Script mode (cmake -P): configures FIXTURE_SRC into a fresh FIXTURE_BIN and
# checks the outcome. With EXPECT_FAIL (a regex) the configure must exit 1 AND
# print the diagnostic; otherwise it must exit 0, match EXPECT_OK when given,
# and build when BUILD is set. Optional: CASE (forwarded as -DI3_CASE),
# OPTIONS (extra -D arguments, "|"-separated), GENERATOR.

foreach(var FIXTURE_SRC FIXTURE_BIN MODULE_PATH OCX_EXE)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "i3_configure_check: -D${var}=... is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${FIXTURE_BIN}")
set(
  configure
  "${CMAKE_COMMAND}"
  -Werror=dev
  -S
  "${FIXTURE_SRC}"
  -B
  "${FIXTURE_BIN}"
  "-DCMAKE_MODULE_PATH=${MODULE_PATH}"
  "-DOCX_EXECUTABLE=${OCX_EXE}"
  -DOCX_FROZEN=
  -DOCX_INDEX=
)
if(DEFINED GENERATOR AND NOT "${GENERATOR}" STREQUAL "")
  list(APPEND configure -G "${GENERATOR}")
endif()
if(DEFINED CASE)
  list(APPEND configure "-DI3_CASE=${CASE}")
endif()
if(DEFINED OPTIONS)
  string(REPLACE "|" ";" extra_options "${OPTIONS}")
  list(APPEND configure ${extra_options})
endif()

execute_process(
  COMMAND ${configure}
  RESULT_VARIABLE rc
  OUTPUT_VARIABLE out
  ERROR_VARIABLE err
  ENCODING UTF-8
)
# CMake re-wraps long diagnostics: match on whitespace-collapsed text.
string(REGEX REPLACE "[ \t\r\n]+" " " text "${out} ${err}")

if(DEFINED EXPECT_FAIL)
  if(NOT rc EQUAL 1)
    message(
      FATAL_ERROR
      "i3_configure_check: expected configure exit 1, got '${rc}':\n${out}\n${err}"
    )
  endif()
  if(NOT text MATCHES "${EXPECT_FAIL}")
    message(FATAL_ERROR "i3_configure_check: no match for '${EXPECT_FAIL}' in:\n${out}\n${err}")
  endif()
  message(STATUS "i3_configure_check: ok (failed as expected)")
  return()
endif()

if(NOT rc EQUAL 0)
  message(FATAL_ERROR "i3_configure_check: configure failed (${rc}):\n${out}\n${err}")
endif()
if(DEFINED EXPECT_OK AND NOT text MATCHES "${EXPECT_OK}")
  message(FATAL_ERROR "i3_configure_check: no match for '${EXPECT_OK}' in:\n${out}\n${err}")
endif()
if(BUILD)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" --build "${FIXTURE_BIN}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
    ENCODING UTF-8
  )
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "i3_configure_check: build failed (${rc}):\n${out}\n${err}")
  endif()
endif()
message(STATUS "i3_configure_check: ok")
