# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Shared body of the ambient-environment fixtures: the caller exported
# hostile OCX_* variables before include(ocx); the project tier must still
# configure and expose its launcher.

# Work on a copy: the project tier renders .ocx/toolchain next to ocx.toml.
file(COPY "${CMAKE_CURRENT_LIST_DIR}/project_run/ocx.toml"
  "${CMAKE_CURRENT_LIST_DIR}/project_run/ocx.lock"
  DESTINATION "${CMAKE_BINARY_DIR}/project")

ocx_project(NAME AMBIENT TOML "${CMAKE_BINARY_DIR}/project/ocx.toml" BINS jq)

if(NOT DEFINED CACHE{OCX_AMBIENT_RUN_JQ})
  message(FATAL_ERROR "ambient fixture: OCX_AMBIENT_RUN_JQ missing")
endif()
