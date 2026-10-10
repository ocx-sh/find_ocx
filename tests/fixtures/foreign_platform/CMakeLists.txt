# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: foreign PLATFORM provisioning - content only, no RUN commands,
# at both tiers. Only exercised on Linux hosts (see the harness).

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_foreign_platform LANGUAGES NONE)

include(ocx)

# Under test: foreign-platform env export, not pinning - allow the
# floating tag (the reproducibility gate is covered by floating_fatal).
set(OCX_ALLOW_FLOATING ON)
ocx_package(NAME JQ_ARM PACKAGE ocx.sh/jqlang/jq:latest PLATFORM linux/arm64 NO_ROOT)

# Project tier: a copy of the project_run declaration, so the toolchain
# links ocx renders land in the build tree.
set(project_dir "${CMAKE_BINARY_DIR}/foreign_project")
file(
  COPY
    "${CMAKE_CURRENT_SOURCE_DIR}/../project_run/ocx.toml"
    "${CMAKE_CURRENT_SOURCE_DIR}/../project_run/ocx.lock"
  DESTINATION "${project_dir}"
)
ocx_project(NAME TOOLS_ARM TOML "${project_dir}/ocx.toml" PLATFORM linux/arm64)

foreach(case JQ_ARM TOOLS_ARM)
  if(DEFINED CACHE{OCX_${case}_RUN})
    message(
      FATAL_ERROR
      "foreign_platform fixture: RUN vars must not exist for a foreign platform (${case})"
    )
  endif()
  if(NOT DEFINED CACHE{OCX_${case}_PATHS} OR "$CACHE{OCX_${case}_PATHS}" STREQUAL "")
    message(FATAL_ERROR "foreign_platform fixture: OCX_${case}_PATHS is empty")
  endif()
  foreach(dir IN LISTS OCX_${case}_PATHS)
    if(NOT EXISTS "${dir}")
      message(FATAL_ERROR "foreign_platform fixture: env path '${dir}' does not exist (${case})")
    endif()
  endforeach()
  message(STATUS "foreign_platform fixture: ok ${case} ($CACHE{OCX_${case}_PATHS})")
endforeach()

# The project tier must export digest paths of the arm64 leaf, not the
# toolchain links (those point at whichever platform ocx rendered last).
file(READ "${project_dir}/ocx.lock" lock_text)
if(NOT lock_text MATCHES "\"linux/arm64\" = \"sha256:([0-9a-f]+)\"")
  message(FATAL_ERROR "foreign_platform fixture: no linux/arm64 digest in the lock")
endif()
string(SUBSTRING "${CMAKE_MATCH_1}" 0 2 store_prefix)
string(SUBSTRING "${CMAKE_MATCH_1}" 2 30 store_rest)
foreach(dir IN LISTS OCX_TOOLS_ARM_PATHS)
  if(dir MATCHES "/toolchain/links/" OR NOT dir MATCHES "sha256/${store_prefix}/${store_rest}")
    message(
      FATAL_ERROR
      "foreign_platform fixture: project path '${dir}' is not the pinned "
      "linux/arm64 store path (sha256/${store_prefix}/${store_rest})"
    )
  endif()
endforeach()
