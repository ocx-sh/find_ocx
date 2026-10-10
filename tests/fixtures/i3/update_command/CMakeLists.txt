# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: the refresh command of ocx_index(UPDATE_COMMAND) runs with
# OCX_FROZEN neutralized (configured with -DOCX_FROZEN=ON: `index update`
# refuses to run frozen) and records only the tags it is given.

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_i3_update_command LANGUAGES NONE)

include(ocx)

if(NOT OCX_FROZEN)
  message(FATAL_ERROR "i3 update_command fixture: run with -DOCX_FROZEN=ON")
endif()

ocx_index(
  UPDATE_COMMAND
  refresh
  INDEX
  "${CMAKE_BINARY_DIR}/index"
  PACKAGES
  ocx.sh/jqlang/jq:1.8.2@sha256:0000000000000000000000000000000000000000000000000000000000000000
  ocx.sh/kitware/cmake
)

foreach(entry IN LISTS refresh)
  if(entry MATCHES "^OCX_FROZEN=")
    message(FATAL_ERROR "i3 update_command fixture: '${entry}' in '${refresh}'")
  endif()
endforeach()
if(NOT "${refresh}" MATCHES ";--unset=OCX_FROZEN;")
  message(FATAL_ERROR "i3 update_command fixture: OCX_FROZEN not unset in '${refresh}'")
endif()
if(NOT "${refresh}" MATCHES ";index;update;ocx\\.sh/jqlang/jq:1\\.8\\.2;ocx\\.sh/kitware/cmake$")
  message(FATAL_ERROR "i3 update_command fixture: refs are not tag-only: '${refresh}'")
endif()

# The command is evaluated from quoted arguments: a path may hold a closing
# bracket sequence without ending the argument early.
ocx_index(
  UPDATE_COMMAND
  delimited
  INDEX
  "${CMAKE_BINARY_DIR}/a]==]b"
  PACKAGES
  ocx.sh/jqlang/jq:1
)
# (a list search would treat the brackets as nesting, so search the string.)
string(FIND "${delimited}" ";--index;${CMAKE_BINARY_DIR}/a]==]b;index;update;" delimited_index)
if(delimited_index EQUAL -1)
  message(FATAL_ERROR "i3 update_command fixture: a ]==] path was split: '${delimited}'")
endif()
