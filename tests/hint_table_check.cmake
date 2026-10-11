# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Docs check: the exit codes ocx.cmake has a hint for must equal the codes in the table of
# site/pages/troubleshooting/exit-codes.md. include() registers the test, -P runs the check.
# A code counts when "EQUAL <n>" appears in __ocx_default_hint() or a __OCX_HINT_<n> variable
# exists. Another table shape fails with "no codes found", never a silent pass.

if(NOT CMAKE_SCRIPT_MODE_FILE)
  add_test(
    NAME hint_table
    COMMAND
      "${CMAKE_COMMAND}" "-DMODULE_FILE=${CMAKE_SOURCE_DIR}/ocx.cmake"
      "-DPAGE_FILE=${CMAKE_SOURCE_DIR}/site/pages/troubleshooting/exit-codes.md" -P
      "${CMAKE_CURRENT_LIST_FILE}"
  )
  __ocx_test_props(hint_table SCRIPT)
  set_tests_properties(hint_table PROPERTIES TIMEOUT 30)
  return()
endif()

foreach(var MODULE_FILE PAGE_FILE)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "hint_table_check: -D${var}=... is required")
  endif()
endforeach()

file(READ "${MODULE_FILE}" module ENCODING UTF-8)
file(READ "${PAGE_FILE}" page ENCODING UTF-8)

# Codes the module has a hint for. CMake regex has no lazy quantifier, so cut
# the function body with string(FIND).
set(module_codes "")
string(FIND "${module}" "function(__ocx_default_hint" begin)
if(NOT begin EQUAL -1)
  string(SUBSTRING "${module}" ${begin} -1 tail)
  string(FIND "${tail}" "\nendfunction()" length)
  string(SUBSTRING "${tail}" 0 ${length} body)
  string(REGEX MATCHALL "EQUAL \"?[0-9]+" hits "${body}")
  foreach(hit IN LISTS hits)
    string(REGEX MATCH "[0-9]+$" code "${hit}")
    list(APPEND module_codes ${code})
  endforeach()
endif()
string(REGEX MATCHALL "__OCX_HINT_[0-9]+" hits "${module}")
foreach(hit IN LISTS hits)
  string(REGEX MATCH "[0-9]+$" code "${hit}")
  list(APPEND module_codes ${code})
endforeach()

# Codes in the first column of the page's table.
set(page_codes "")
string(REGEX MATCHALL "\n\\| *[0-9]+ *\\|" rows "${page}")
foreach(row IN LISTS rows)
  string(REGEX MATCH "[0-9]+" code "${row}")
  list(APPEND page_codes ${code})
endforeach()

foreach(side module page)
  if("${${side}_codes}" STREQUAL "")
    message(FATAL_ERROR "hint_table_check: no codes found in the ${side} table")
  endif()
  list(REMOVE_DUPLICATES ${side}_codes)
  list(SORT ${side}_codes COMPARE NATURAL)
endforeach()

set(only_module ${module_codes})
set(only_page ${page_codes})
list(REMOVE_ITEM only_module ${page_codes})
list(REMOVE_ITEM only_page ${module_codes})
if(only_module OR only_page)
  message(
    FATAL_ERROR
    "hint_table_check: the ocx.cmake hint table and the exit-codes page disagree\n"
    "  in ocx.cmake only: ${only_module}\n"
    "  on the page only:  ${only_page}"
  )
endif()
message(STATUS "hint_table_check: ok (${module_codes})")
