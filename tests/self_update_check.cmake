# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Script mode (cmake -P): self-update check against a fake file:// release.
# Copies the vendored ocx.cmake/Findocx.cmake from MODULE_DIR into a
# scratch dir, builds a doctored "release" (version stamp 9.9.9) with a
# matching SHA256SUMS, then asserts that
#   1. cmake -DOCX_SELF_UPDATE_VERSION=v9.9.9 -DOCX_SELF_UPDATE_URL=file://…
#      -P <copy>/ocx.cmake replaces both files (hash-verified renames), and
#   2. a mirror URL without an explicit version is a hard error.
# Fully offline.

foreach(var MODULE_DIR SCRATCH)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "self_update_check: -D${var}=... is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${SCRATCH}")

# Vendored copy under test.
file(COPY "${MODULE_DIR}/ocx.cmake" "${MODULE_DIR}/Findocx.cmake"
  DESTINATION "${SCRATCH}/vendored")

# Fake release: the current sources with the version stamp doctored.
file(READ "${MODULE_DIR}/ocx.cmake" module_content)
if(NOT module_content MATCHES "set\\(__OCX_MODULE_VERSION \"([^\"]+)\"\\)")
  message(FATAL_ERROR "self_update_check: version stamp not found in ocx.cmake")
endif()
set(old_version "${CMAKE_MATCH_1}")
string(REPLACE
  "set(__OCX_MODULE_VERSION \"${old_version}\")"
  "set(__OCX_MODULE_VERSION \"9.9.9\")"
  module_content "${module_content}")
set(release "${SCRATCH}/release/v9.9.9")
file(WRITE "${release}/ocx.cmake" "${module_content}")
file(COPY "${MODULE_DIR}/Findocx.cmake" DESTINATION "${release}")

file(SHA256 "${release}/ocx.cmake" module_sha)
file(SHA256 "${release}/Findocx.cmake" find_sha)
file(WRITE "${release}/SHA256SUMS"
  "${module_sha}  ocx.cmake\n${find_sha}  Findocx.cmake\n")

# file:// URL: absolute POSIX paths already start with '/'; Windows drive
# paths (C:/...) need the extra slash after the authority.
if(SCRATCH MATCHES "^/")
  set(base "file://${SCRATCH}/release")
else()
  set(base "file:///${SCRATCH}/release")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DOCX_SELF_UPDATE_VERSION=v9.9.9
    "-DOCX_SELF_UPDATE_URL=${base}"
    -P "${SCRATCH}/vendored/ocx.cmake"
  RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "self_update_check: self-update failed:\n${out}\n${err}")
endif()
if(NOT "${out}${err}" MATCHES "${old_version} -> 9\\.9\\.9 \\(v9\\.9\\.9\\)")
  message(FATAL_ERROR "self_update_check: missing old -> new report:\n${out}\n${err}")
endif()

file(SHA256 "${SCRATCH}/vendored/ocx.cmake" updated_module_sha)
file(SHA256 "${SCRATCH}/vendored/Findocx.cmake" updated_find_sha)
if(NOT updated_module_sha STREQUAL module_sha OR NOT updated_find_sha STREQUAL find_sha)
  message(FATAL_ERROR "self_update_check: vendored files do not match the release")
endif()
if(EXISTS "${SCRATCH}/vendored/.ocx-self-update-tmp")
  message(FATAL_ERROR "self_update_check: temp dir left behind")
endif()

# Mirror without an explicit version must fail actionably.
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DOCX_SELF_UPDATE_URL=${base}"
    -P "${SCRATCH}/vendored/ocx.cmake"
  RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(rc EQUAL 0)
  message(FATAL_ERROR "self_update_check: mirror without version must fail")
endif()
if(NOT err MATCHES "OCX_SELF_UPDATE_VERSION")
  message(FATAL_ERROR "self_update_check: unexpected error output:\n${err}")
endif()

message(STATUS "self_update_check: ok")
