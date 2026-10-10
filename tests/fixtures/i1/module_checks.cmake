# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Script mode (cmake -P): module-level contracts of ocx.cmake. A second copy
# with another version is FATAL; the first load is a GLOBAL property;
# ocx_self_update is public, takes no arguments and refuses a project
# configure; statically, definitions sit inside the policy pin, every
# file(DOWNLOAD) verifies TLS and is bounded, and the floor is 3.25.
#   cmake -DMODULE_DIR=<repo> -DSCRATCH=<dir> -P module_checks.cmake

foreach(var MODULE_DIR SCRATCH)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "module_checks: -D${var}=... is required")
  endif()
endforeach()

set(module "${MODULE_DIR}/ocx.cmake")
file(REMOVE_RECURSE "${SCRATCH}")
file(READ "${module}" content)
if(NOT content MATCHES "set\\(__OCX_MODULE_VERSION \"([^\"]+)\"\\)")
  message(FATAL_ERROR "module_checks: version stamp not found in ocx.cmake")
endif()
set(version "${CMAKE_MATCH_1}")

# run(<name> <FAIL regex | OK> <command...>): status and diagnostic together.
function(i1_run name expect)
  execute_process(
    COMMAND ${ARGN}
    WORKING_DIRECTORY "${SCRATCH}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
    ENCODING UTF-8)
  if(expect STREQUAL "OK")
    if(NOT rc EQUAL 0)
      message(FATAL_ERROR "module_checks[${name}]: exit ${rc}\n${out}\n${err}")
    endif()
  else()
    if(rc EQUAL 0)
      message(FATAL_ERROR "module_checks[${name}]: expected a failure, got exit 0:\n${out}")
    endif()
    # CMake wraps long diagnostics: compare with whitespace collapsed.
    string(REGEX REPLACE "[ \n]+" " " flat_err "${err}")
    if(NOT flat_err MATCHES "${expect}")
      message(FATAL_ERROR "module_checks[${name}]: exit ${rc} but stderr lacks '${expect}':\n${err}")
    endif()
  endif()
  set(out "${out}" PARENT_SCOPE)
  set(err "${err}" PARENT_SCOPE)
endfunction()

# --- 1 + 2: second copies ----------------------------------------------------
file(MAKE_DIRECTORY "${SCRATCH}/a" "${SCRATCH}/b" "${SCRATCH}/same")
file(COPY_FILE "${module}" "${SCRATCH}/a/ocx.cmake")
file(COPY_FILE "${module}" "${SCRATCH}/same/ocx.cmake")
string(REPLACE
  "set(__OCX_MODULE_VERSION \"${version}\")" "set(__OCX_MODULE_VERSION \"9.9.9\")"
  other "${content}")
file(WRITE "${SCRATCH}/b/ocx.cmake" "${other}")

set(two "${CMAKE_COMMAND}" "-DCOPY_A=${SCRATCH}/a/ocx.cmake")
set(fixtures "${CMAKE_CURRENT_LIST_DIR}")
i1_run(second_copy_other_version "two copies of ocx\\.cmake with different versions"
  ${two} "-DCOPY_B=${SCRATCH}/b/ocx.cmake" -P "${fixtures}/two_copies.cmake")
string(REGEX REPLACE "[ \n]+" " " flat_err "${err}")
if(NOT flat_err MATCHES "${version} from [^ ]*a/ocx\\.cmake and 9\\.9\\.9 from [^ ]*b/ocx\\.cmake")
  message(FATAL_ERROR "module_checks: the error must name both copies:\n${err}")
endif()
i1_run(second_copy_same_version OK
  ${two} "-DCOPY_B=${SCRATCH}/same/ocx.cmake" -P "${fixtures}/two_copies.cmake")
if(NOT out MATCHES "two_copies: first ${version} .*a/ocx\\.cmake")
  message(FATAL_ERROR "module_checks: first load not recorded:\n${out}")
endif()
if(NOT out MATCHES "two_copies: both loaded")
  message(FATAL_ERROR "module_checks: same-version copies must both load:\n${out}")
endif()

# --- 3: the public self-update entry -----------------------------------------
i1_run(self_update_name "ocx_self_update: unexpected arguments: BOGUS"
  "${CMAKE_COMMAND}" "-DCMAKE_MODULE_PATH=${MODULE_DIR}" -P "${fixtures}/self_update_name.cmake")
i1_run(self_update_configure "runs in script mode only"
  "${CMAKE_COMMAND}" -S "${fixtures}/configure_self_update" -B "${SCRATCH}/configure"
  "-DCMAKE_MODULE_PATH=${MODULE_DIR}")

# --- 4: static contracts -----------------------------------------------------
# Definitions sit between the single PUSH and the single POP.
file(STRINGS "${module}" span REGEX "^[ \t]*(cmake_policy\\((PUSH|POP)\\)|function\\(|macro\\()")
list(LENGTH span span_len)
list(GET span 0 span_first)
math(EXPR span_last_index "${span_len} - 1")
list(GET span ${span_last_index} span_last)
list(FILTER span INCLUDE REGEX "cmake_policy")
list(LENGTH span pins)
if(NOT span_first MATCHES "cmake_policy\\(PUSH\\)" OR NOT span_last MATCHES "cmake_policy\\(POP\\)"
    OR NOT pins EQUAL 2)
  message(FATAL_ERROR
    "module_checks: every function/macro must sit between the one "
    "cmake_policy(PUSH) and the one cmake_policy(POP) of ocx.cmake")
endif()
if(NOT content MATCHES "\ncmake_policy\\(VERSION 3\\.25\\.\\.\\.4\\.4\\)\n")
  message(FATAL_ERROR "module_checks: the module policy must be VERSION 3.25...4.4")
endif()
if(NOT content MATCHES "VERSION_LESS 3\\.25\\)")
  message(FATAL_ERROR "module_checks: the version floor guard must be 3.25")
endif()

# Every download checks its status, verifies TLS and is bounded.
string(REGEX MATCHALL "file\\(DOWNLOAD[ \n][^)]*\\)" downloads "${content}")
list(LENGTH downloads download_count)
if(download_count LESS 5)
  message(FATAL_ERROR "module_checks: expected at least the 5 file(DOWNLOAD) calls, found ${download_count}")
endif()
foreach(call IN LISTS downloads)
  foreach(keyword IN ITEMS "TLS_VERIFY ON" "TIMEOUT" "STATUS")
    if(NOT call MATCHES "${keyword}")
      message(FATAL_ERROR "module_checks: file(DOWNLOAD) lacks ${keyword}:\n${call}")
    endif()
  endforeach()
endforeach()

message(STATUS "module_checks: ok")
