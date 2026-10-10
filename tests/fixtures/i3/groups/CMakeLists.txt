# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: ocx_project with two groups (jq in [tools], shellcheck in
# [group.lint]). I3_CASE selects a failing BINS check; without it the project
# configures with both groups and the RUN commands execute at build time.

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_i3_groups LANGUAGES NONE)

include(ocx)

# A copy keeps the toolchain links ocx renders out of the source tree.
set(project_dir "${CMAKE_BINARY_DIR}/project")
file(
  COPY "${CMAKE_CURRENT_SOURCE_DIR}/ocx.toml" "${CMAKE_CURRENT_SOURCE_DIR}/ocx.lock"
  DESTINATION "${project_dir}"
)
set(toml "${project_dir}/ocx.toml")

if(I3_CASE STREQUAL "bins_typo")
  ocx_project(NAME G TOML "${toml}" BINS jqq)
elseif(I3_CASE STREQUAL "bins_group")
  ocx_project(NAME G TOML "${toml}" BINS shellcheck)
elseif(I3_CASE STREQUAL "bins_group_not_default")
  ocx_project(NAME G TOML "${toml}" GROUPS lint BINS jq)
endif()
if(NOT "${I3_CASE}" STREQUAL "")
  message(FATAL_ERROR "i3 groups fixture: case '${I3_CASE}' must have failed before this line")
endif()

ocx_project(NAME G TOML "${toml}" GROUPS default lint BINS jq shellcheck)
foreach(result OCX_G_RUN OCX_G_RUN_JQ OCX_G_RUN_SHELLCHECK)
  if(NOT DEFINED CACHE{${result}})
    message(FATAL_ERROR "i3 groups fixture: ${result} missing")
  endif()
endforeach()
if(NOT "${OCX_G_RUN}" MATCHES ";exec;-g;default,lint;--lazy-mode;never;--pinned;--$")
  message(FATAL_ERROR "i3 groups fixture: RUN is not an ocx exec launcher: '${OCX_G_RUN}'")
endif()

# Re-entry with identical arguments is a no-op (a toolchain file is included
# twice); the launcher stays as it was.
set(before "${OCX_G_RUN}")
ocx_project(NAME G TOML "${toml}" GROUPS default lint BINS jq shellcheck)
if(NOT "${before}" STREQUAL "${OCX_G_RUN}")
  message(FATAL_ERROR "i3 groups fixture: identical re-entry changed OCX_G_RUN")
endif()

add_custom_target(
  run_tools
  ALL
  COMMAND ${OCX_G_RUN_JQ} --version
  COMMAND ${OCX_G_RUN_SHELLCHECK} --version
  VERBATIM
)
