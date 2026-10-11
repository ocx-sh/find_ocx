# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Script mode (cmake -P): which ocx a build directory settles on, across
# reconfigures. The pinned CLI comes from a local file:// mirror built from
# OCX_EXE (make_mirror.cmake) and the PATH ocx is OCX_EXE itself, so the two
# are told apart by where they live. Offline; every configure runs under GATE.
#   1. An empty -DOCX_EXECUTABLE= does not block the PATH search.
#   2. A path the module chose (PATH) is chosen again: OCX_BOOTSTRAP=ALWAYS
#      moves an existing build directory to the pin.
#   3. A bootstrapped path is chosen again too: another OCX_INSTALL_VERSION
#      reaches the bootstrap instead of "up to date".
#   4. A path that does not exist is an error naming it, with bootstrap OFF.
#   5. OCX_BOOTSTRAP=OFF with an empty OCX_EXECUTABLE still searches PATH.

foreach(
  var
  FIXTURE_SRC
  MIRROR_FIXTURE
  SCRATCH
  MODULE_PATH
  OCX_EXE
  GATE
)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "executable_check: -D${var}=... is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${SCRATCH}")
set(MIRROR_DIR "${SCRATCH}/mirror")
include("${MIRROR_FIXTURE}/make_mirror.cmake")
set(cache "${SCRATCH}/cache")

get_filename_component(ocx_dir "${OCX_EXE}" DIRECTORY)
if(CMAKE_HOST_WIN32)
  set(path_with_ocx "${ocx_dir};$ENV{PATH}")
else()
  set(path_with_ocx "${ocx_dir}:$ENV{PATH}")
endif()

# configure(<step> <build dir name> <OK|FAIL> [REGEX <re>] [REPORT <re>] ARGS <-D...>...)
# One configure of the fixture with OCX_EXE's directory on PATH. REGEX matches
# the whitespace-flattened output; REPORT matches the executable the fixture reports.
function(configure step build expect)
  cmake_parse_arguments(PARSE_ARGV 3 c "" "REGEX;REPORT" "ARGS")
  if(NOT "${c_UNPARSED_ARGUMENTS}" STREQUAL "")
    message(FATAL_ERROR "executable_check: unknown arguments '${c_UNPARSED_ARGUMENTS}'")
  endif()
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" -E env "PATH=${path_with_ocx}" "${CMAKE_COMMAND}" ${GATE} -S
      "${FIXTURE_SRC}" -B "${SCRATCH}/${build}" "-DCMAKE_MODULE_PATH=${MODULE_PATH}"
      "-DOCX_INSTALL_DIST_URL=${MIRROR_DIST_URL}" "-DOCX_INSTALL_MIRROR_URL=${MIRROR_URL}"
      "-DOCX_INSTALL_VERSION=${MIRROR_VERSION}" "-DOCX_BOOTSTRAP_CACHE=${cache}" -DOCX_FROZEN=
      -DOCX_INDEX= ${c_ARGS}
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
    ENCODING UTF-8
  )
  string(REGEX REPLACE "[ \t\r\n]+" " " flat "${out} ${err}")
  if(expect STREQUAL "OK" AND NOT rc EQUAL 0)
    message(FATAL_ERROR "executable_check[${step}]: configure failed (${rc}):\n${out}\n${err}")
  elseif(expect STREQUAL "FAIL" AND rc EQUAL 0)
    message(FATAL_ERROR "executable_check[${step}]: expected a failure:\n${out}\n${err}")
  endif()
  if(c_REGEX AND NOT flat MATCHES "${c_REGEX}")
    message(FATAL_ERROR "executable_check[${step}]: no match for /${c_REGEX}/:\n${out}\n${err}")
  endif()
  if(c_REPORT)
    if(NOT out MATCHES "provenance fixture: executable \\[([^]]*)\\]")
      message(FATAL_ERROR "executable_check[${step}]: no report:\n${out}\n${err}")
    endif()
    if(NOT CMAKE_MATCH_1 MATCHES "${c_REPORT}")
      message(
        FATAL_ERROR
        "executable_check[${step}]: executable '${CMAKE_MATCH_1}' does not match /${c_REPORT}/"
      )
    endif()
  endif()
endfunction()

# The cache path as ocx_bootstrap writes it (CMake spelling).
cmake_path(SET cache_prefix NORMALIZE "${cache}")
string(REGEX REPLACE "([][+.*()^$?|\\\\])" "\\\\\\1" cache_re "${cache_prefix}")

# 1. empty OCX_EXECUTABLE, PATH has ocx.
configure(path_search build OK REGEX "using ocx from PATH" REPORT "^(.*)$" ARGS -DOCX_EXECUTABLE=)
# 2. same build directory, now ALWAYS: the PATH choice is not sticky.
configure(
  always_after_path
  build
  OK
  REGEX "using bootstrapped ocx ${MIRROR_VERSION}"
  REPORT "^${cache_re}"
  ARGS -DOCX_BOOTSTRAP=ALWAYS
)
# 3. same build directory, another version: the bootstrapped choice is not sticky.
configure(
  version_after_bootstrap
  build
  FAIL
  REGEX "ocx 0\\.0\\.1 for [^ ]+ not found in the dist manifest"
  ARGS -DOCX_BOOTSTRAP=ALWAYS -DOCX_INSTALL_VERSION=0.0.1
)
# 4. a path that does not exist.
configure(
  typo
  typo-build
  FAIL
  REGEX "OCX_EXECUTABLE='/typo/ocx' does not exist"
  ARGS -DOCX_EXECUTABLE=/typo/ocx -DOCX_BOOTSTRAP=OFF
)
# 5. OFF forbids the download, not the PATH search.
configure(
  off_path
  off-build
  OK
  REGEX "using ocx from PATH"
  ARGS -DOCX_EXECUTABLE= -DOCX_BOOTSTRAP=OFF
)
# 6. A lower-case value counts: 'always' skips the PATH ocx.
configure(
  lower_case
  lower-build
  OK
  REGEX "using bootstrapped ocx ${MIRROR_VERSION}"
  REPORT "^${cache_re}"
  ARGS -DOCX_EXECUTABLE= -DOCX_BOOTSTRAP=always
)

message(STATUS "executable_check: ok")
