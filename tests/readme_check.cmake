# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# doc: readme/quick-start
# title: README quick start
# expect_exit: 0
#
# Script mode (cmake -P): the README quick start cannot use the site's snippet
# directive, because GitHub renders the README as is. This check keeps its two
# fences equal to the regions of examples/tutorial that the site pages and the
# tutorial recording use, so the README never shows code that no test runs.
#   cmake -DROOT=<repository> -P tests/readme_check.cmake

if(NOT DEFINED ROOT)
  message(FATAL_ERROR "readme_check: -DROOT=<repository root> is required")
endif()

# Lines between "# region <name>" and "# endregion", the markers stripped.
function(region_of file name out_var)
  file(STRINGS "${file}" lines ENCODING UTF-8)
  set(inside FALSE)
  set(body "")
  foreach(line IN LISTS lines)
    if(line STREQUAL "# region ${name}")
      set(inside TRUE)
    elseif(line STREQUAL "# endregion")
      set(inside FALSE)
    elseif(inside)
      string(APPEND body "${line}\n")
    endif()
  endforeach()
  if(body STREQUAL "")
    message(FATAL_ERROR "readme_check: no region '${name}' in ${file}")
  endif()
  set(${out_var} "${body}" PARENT_SCOPE)
endfunction()

file(READ "${ROOT}/README.md" readme ENCODING UTF-8)
region_of("${ROOT}/examples/tutorial/ocx.toml" tools toml_body)
region_of("${ROOT}/examples/tutorial/CMakeLists.txt" full cmake_body)

function(expect_fence lang body)
  string(FIND "${readme}" "```${lang}\n${body}```" at)
  if(at EQUAL -1)
    message(FATAL_ERROR
      "readme_check: the README ${lang} fence differs from examples/tutorial:\n${body}")
  endif()
endfunction()

expect_fence(toml "${toml_body}")
expect_fence(cmake "${cmake_body}")
