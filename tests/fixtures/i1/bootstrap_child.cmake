# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Child of bootstrap_dist.cmake (script mode): runs ocx_bootstrap(${BOOT_ARGS})
# with no OCX_EXECUTABLE in play and reports the version the binary prints.
#
#   cmake -DCMAKE_MODULE_PATH=<repo> -DOCX_BOOTSTRAP_CACHE=<dir> \
#         "-DBOOT_ARGS=<ocx_bootstrap arguments, ;-separated>" -P bootstrap_child.cmake

include(ocx)

ocx_bootstrap(${BOOT_ARGS})

execute_process(
  COMMAND "${OCX_EXECUTABLE}" version
  RESULT_VARIABLE rc
  OUTPUT_VARIABLE reported
  ERROR_VARIABLE err
  ENCODING UTF-8
)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "bootstrap_child: '${OCX_EXECUTABLE} version' exited ${rc}\n${err}")
endif()
string(STRIP "${reported}" reported)
message(STATUS "bootstrap_child: executable ${OCX_EXECUTABLE}")
message(STATUS "bootstrap_child: reports ${reported}")
