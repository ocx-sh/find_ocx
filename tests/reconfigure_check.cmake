# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Script mode (cmake -P): configures a scratch copy of FIXTURE_SRC four times
# and asserts the memoization per package: baseline (no hits), repeat (all
# hit), one changed input - the frozen package's snapshot leaf - (only that
# package re-runs), repeat (it hits again). Every configure runs under GATE.

foreach(
  var
  FIXTURE_SRC
  FIXTURE_BIN
  MODULE_PATH
  OCX_EXE
  GATE
)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "reconfigure_check: -D${var}=... is required")
  endif()
endforeach()

# Packages in the fixture: a memo hit prints "find_ocx: <name> up to date (memoized)".
set(untouched JQ JQ_LAZY JQ_SUB)
set(touched JQ_FROZEN)

file(REMOVE_RECURSE "${FIXTURE_BIN}" "${FIXTURE_BIN}-src")
file(COPY "${FIXTURE_SRC}/" DESTINATION "${FIXTURE_BIN}-src")
set(
  configure
  "${CMAKE_COMMAND}"
  "${GATE}"
  -S
  "${FIXTURE_BIN}-src"
  -B
  "${FIXTURE_BIN}"
  "-DCMAKE_MODULE_PATH=${MODULE_PATH}"
  "-DOCX_EXECUTABLE=${OCX_EXE}"
  -DOCX_FROZEN=
  -DOCX_INDEX=
)

# Runs one configure into `out`, failing on a non-zero exit or a deprecation.
function(run_configure step out_var)
  execute_process(COMMAND ${configure} RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "reconfigure_check: ${step} configure failed:\n${out}\n${err}")
  endif()
  if("${out}${err}" MATCHES "CMake Deprecation Warning")
    message(FATAL_ERROR "reconfigure_check: ${step} configure deprecated:\n${out}\n${err}")
  endif()
  set(${out_var} "${out}" PARENT_SCOPE)
endfunction()

function(assert_memo step out expect_hit)
  foreach(name IN LISTS ARGN)
    if(out MATCHES "find_ocx: ${name} up to date \\(memoized\\)")
      set(hit TRUE)
    else()
      set(hit FALSE)
    endif()
    if(NOT hit STREQUAL expect_hit)
      message(
        FATAL_ERROR
        "reconfigure_check: ${step}: ${name} memoized=${hit}, expected ${expect_hit}:\n${out}"
      )
    endif()
  endforeach()
endfunction()

run_configure(baseline out)
assert_memo(baseline "${out}" FALSE ${untouched} ${touched})

run_configure(repeat out)
assert_memo(repeat "${out}" TRUE ${untouched} ${touched})

# Changed input: an appended newline leaves the JSON valid and changes the
# leaf's sha256, which the frozen package's fingerprint includes.
set(leaf "${FIXTURE_BIN}-src/.ocx/ocx.sh/p/jqlang/jq.json")
if(NOT EXISTS "${leaf}")
  message(FATAL_ERROR "reconfigure_check: snapshot leaf missing: ${leaf}")
endif()
file(APPEND "${leaf}" "\n")
run_configure(changed out)
assert_memo(changed "${out}" FALSE ${touched})
assert_memo(changed "${out}" TRUE ${untouched})

run_configure(restored out)
assert_memo(restored "${out}" TRUE ${untouched} ${touched})

message(STATUS "reconfigure_check: ok")
