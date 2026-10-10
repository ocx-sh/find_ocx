# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Script mode (cmake -P): runs the runtime-core cases of
# tests/fixtures/runtime_core/case.cmake in child cmake processes and asserts
# exit status and diagnostics for each.
#   cmake -DMODULE_DIR=<repo> -DSCRATCH=<dir> -DOCX_EXE=<ocx> -P i2_check.cmake

foreach(var MODULE_DIR SCRATCH OCX_EXE)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "i2_check: -D${var}=... is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${SCRATCH}")
file(MAKE_DIRECTORY "${SCRATCH}")
set(case_file "${MODULE_DIR}/tests/fixtures/runtime_core/case.cmake")
if(CMAKE_HOST_WIN32)
  set(shim "${MODULE_DIR}/tests/fixtures/runtime_core/fake_ocx.cmd")
else()
  set(shim "${MODULE_DIR}/tests/fixtures/runtime_core/fake_ocx.sh")
endif()

# run_case(<case> <OK|FAIL> [REGEX <re>] [REJECT <re>] [DEFS <-D...>]
#          [ENV <VAR=value>...])
# Runs one case in a child cmake. OK demands exit 0; FAIL demands a nonzero
# exit; REGEX / REJECT match stdout+stderr. Sets <case>_OUT for the caller.
function(run_case case expect)
  cmake_parse_arguments(PARSE_ARGV 2 c "" "REGEX;REJECT" "DEFS;ENV")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env ${c_ENV}
      "${CMAKE_COMMAND}"
      "-DCMAKE_MODULE_PATH=${MODULE_DIR}" "-DCASE=${case}" "-DSCRATCH=${SCRATCH}"
      -DOCX_FROZEN= ${c_DEFS}
      -P "${case_file}"
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err
    ENCODING UTF-8)
  set(all "${out}${err}")
  if(expect STREQUAL "OK" AND NOT rc EQUAL 0)
    message(FATAL_ERROR "i2_check: ${case} must pass, exit ${rc}:\n${all}")
  elseif(expect STREQUAL "FAIL" AND rc EQUAL 0)
    message(FATAL_ERROR "i2_check: ${case} must fail, but exited 0:\n${all}")
  endif()
  if(c_REGEX AND NOT all MATCHES "${c_REGEX}")
    message(FATAL_ERROR "i2_check: ${case}: output lacks /${c_REGEX}/:\n${all}")
  endif()
  if(c_REJECT AND all MATCHES "${c_REJECT}")
    message(FATAL_ERROR "i2_check: ${case}: output must not match /${c_REJECT}/:\n${all}")
  endif()
endfunction()

# Env classes and helpers (no ocx involved).
run_case(prefix_default OK
  DEFS -DOCX_INDEX= -DOCX_JOBS=4 "-DOCX_EXECUTABLE=${shim}")
run_case(prefix_policy OK)
run_case(translucent OK)
run_case(error_message OK)
run_case(hints OK)

# Negative cases: exit status and diagnostic together.
run_case(translucent_relative FAIL REGEX "CONFIG must be an absolute path")
run_case(policy_relative_root FAIL REGEX "SIGSTORE_TRUSTED_ROOT must be an absolute path")
run_case(policy_conflict FAIL REGEX "conflicting second call")
run_case(policy_late FAIL REGEX "must be called before the first")

# A [managed] block with no synced snapshot: exit 78 with the actionable
# hint, no registry contacted (an empty OCX_HOME holds only that config).
file(MAKE_DIRECTORY "${SCRATCH}/managed_home")
file(WRITE "${SCRATCH}/managed_home/config.toml"
  "[managed]\nsource = \"ocx.sh/corp/config:1\"\n")
run_case(managed_unsynced FAIL
  REGEX "exit 78.*ocx config update"
  DEFS "-DOCX_EXECUTABLE=${OCX_EXE}" "-DOCX_HOME=${SCRATCH}/managed_home" -DOCX_INDEX=)
# ... and OCX_NO_CONFIG=1 lifts the gate for the discovered tier: offline,
# the same command now fails for another reason, never exit 78.
run_case(managed_unsynced FAIL
  REJECT "exit 78"
  DEFS "-DOCX_EXECUTABLE=${OCX_EXE}" "-DOCX_HOME=${SCRATCH}/managed_home" -DOCX_INDEX=
    -DOCX_OFFLINE=1
  ENV OCX_NO_CONFIG=1)

# Retry policy against the fake ocx: exit 75 is retried, anything else is not.
function(run_shim state_name fail_rc fail_count expect)
  set(state "${SCRATCH}/${state_name}.count")
  run_case(shim_run ${expect} ${ARGN}
    DEFS "-DOCX_EXECUTABLE=${shim}"
    ENV "FAKE_OCX_STATE=${state}" "FAKE_OCX_FAIL_RC=${fail_rc}"
      "FAKE_OCX_FAIL_COUNT=${fail_count}")
  file(STRINGS "${state}" calls LIMIT_COUNT 1)
  set(calls "${calls}" PARENT_SCOPE)
endfunction()

run_shim(retry75 75 2 OK REGEX "transient failure \\(exit 75\\)")
if(NOT calls EQUAL 3)
  message(FATAL_ERROR "i2_check: exit 75 twice then success must take 3 calls, got ${calls}")
endif()

run_shim(retry75_exhausted 75 9 FAIL REGEX "exit 75.*shim failure 3.*transient registry failure")
if(NOT calls EQUAL 3)
  message(FATAL_ERROR "i2_check: RETRIES 2 must stop after 3 calls, got ${calls}")
endif()

foreach(rc IN ITEMS 69 74 79)
  run_shim(no_retry${rc} ${rc} 9 FAIL REGEX "exit ${rc}")
  if(NOT calls EQUAL 1)
    message(FATAL_ERROR "i2_check: exit ${rc} must not be retried, got ${calls} calls")
  endif()
endforeach()

# The failure message is ocx's own, once, without the progress noise.
run_shim(message_only 69 9 FAIL REGEX "shim failure 1[\r\n]" REJECT "Installing packages")

message(STATUS "i2_check: ok")
