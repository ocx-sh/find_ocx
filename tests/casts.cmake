# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Registers every docs cast script (site/casts/*.sh) as the ctest doc/<key>,
# <key> being the script's "# doc:" line. The script is the test: it runs
# through the same wrapper the recorder uses, against the real module in
# FIND_OCX_ROOT, and passes or fails without asciinema. The recording
# (site/scripts/record-casts.mjs) is a view on a passing script and is never
# part of this gate.
#
# Not registered on Windows: the scripts are bash, and asciinema, which
# records them for the site, has no Windows build.
if(CMAKE_HOST_WIN32)
  return()
endif()

file(GLOB cast_scripts CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/../site/casts/*.sh")
foreach(script IN LISTS cast_scripts)
  file(STRINGS "${script}" doc_line LIMIT_COUNT 1 REGEX "^# doc: ")
  if(NOT doc_line MATCHES "^# doc: (.+)$")
    message(FATAL_ERROR "casts: ${script} has no '# doc: <key>' header")
  endif()
  set(doc "${CMAKE_MATCH_1}")
  add_test(NAME "doc/${doc}"
    COMMAND "${CMAKE_CURRENT_LIST_DIR}/../site/scripts/run-cast-script.sh" "${script}")
  set_tests_properties("doc/${doc}" PROPERTIES LABELS docs TIMEOUT 300)
endforeach()
