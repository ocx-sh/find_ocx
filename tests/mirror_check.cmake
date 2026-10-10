# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Script mode (cmake -P): bootstrap the CLI from a local static mirror
# (fully offline, file:// URLs). Builds the mirror from OCX_EXE with
# tests/fixtures/mirror/make_mirror.cmake, then asserts
#   1. a fresh bootstrap cache is filled from the mirror, and
#   2. an archive that no longer matches the manifest's sha256 is refused
#      and nothing lands in the cache - the hash, not the mirror, is the
#      trust boundary.
# Each configure runs under GATE (-Werror=dev, or -Werror=author on 4.4+).

foreach(
  var
  FIXTURE_SRC
  SCRATCH
  MODULE_PATH
  OCX_EXE
  GATE
)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "mirror_check: -D${var}=... is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${SCRATCH}")
set(MIRROR_DIR "${SCRATCH}/mirror")
include("${FIXTURE_SRC}/make_mirror.cmake")

# Runs one fixture configure against the mirror into its own cache and build
# directory; sets <prefix>_RC and <prefix>_OUT.
function(configure_from_mirror prefix)
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" "${GATE}" -S "${FIXTURE_SRC}" -B "${SCRATCH}/${prefix}-build"
      "-DCMAKE_MODULE_PATH=${MODULE_PATH}" "-DOCX_INSTALL_DIST_URL=${MIRROR_DIST_URL}"
      "-DOCX_INSTALL_MIRROR_URL=${MIRROR_URL}" "-DOCX_INSTALL_VERSION=${MIRROR_VERSION}"
      "-DOCX_BOOTSTRAP_CACHE=${SCRATCH}/${prefix}-cache" -DOCX_EXECUTABLE= -DOCX_FROZEN=
      -DOCX_INDEX= "-DMIRROR_EXPECT_VERSION=${MIRROR_VERSION}"
      "-DMIRROR_EXPECT_CACHE=${SCRATCH}/${prefix}-cache"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
  )
  set(${prefix}_RC "${rc}" PARENT_SCOPE)
  set(${prefix}_OUT "${out}\n${err}" PARENT_SCOPE)
endfunction()

configure_from_mirror(good)
if(NOT good_RC EQUAL 0)
  message(FATAL_ERROR "mirror_check: bootstrap from the mirror failed:\n${good_OUT}")
endif()
if(NOT good_OUT MATCHES "mirror fixture: ok")
  message(FATAL_ERROR "mirror_check: fixture did not report success:\n${good_OUT}")
endif()
if(good_OUT MATCHES "CMake Deprecation Warning")
  message(FATAL_ERROR "mirror_check: deprecation warning:\n${good_OUT}")
endif()

# Tamper: same name and size class, different bytes.
file(APPEND "${MIRROR_DIR}/v${MIRROR_VERSION}/ocx-${triple}.tar.gz" "tampered")
configure_from_mirror(bad)
if(bad_RC EQUAL 0)
  message(FATAL_ERROR "mirror_check: a tampered archive must fail the configure:\n${bad_OUT}")
endif()
if(NOT bad_OUT MATCHES "CMake Error at [^\n]*\\(message\\)")
  message(FATAL_ERROR "mirror_check: tampered archive: no CMake Error diagnostic:\n${bad_OUT}")
endif()
file(GLOB_RECURSE landed "${SCRATCH}/bad-cache/ocx" "${SCRATCH}/bad-cache/ocx.exe")
if(landed)
  message(FATAL_ERROR "mirror_check: tampered archive left a binary in the cache: ${landed}")
endif()

message(STATUS "mirror_check: ok")
