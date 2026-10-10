# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Writes a static release mirror of one ocx CLI into MIRROR_DIR - the layout
# a corporate mirror of github.com/ocx-sh/ocx releases serves:
#   <MIRROR_DIR>/dist.json                          the release manifest
#   <MIRROR_DIR>/v<version>/ocx-<triple>.tar.gz     the CLI archive
# The archive is built from the ocx binary at OCX_EXE for the host triple, so
# no network is involved. Run standalone (cmake -P) or include() it; both set
#   MIRROR_VERSION    the CLI version the mirror serves
#   MIRROR_DIST_URL   value for OCX_INSTALL_DIST_URL
#   MIRROR_URL        value for OCX_INSTALL_MIRROR_URL
#
#   cmake -DOCX_EXE=<ocx> -DMIRROR_DIR=<dir> -P make_mirror.cmake

foreach(var OCX_EXE MIRROR_DIR)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "make_mirror: -D${var}=... is required")
  endif()
endforeach()

cmake_host_system_information(RESULT raw_arch QUERY OS_PLATFORM)
string(TOLOWER "${raw_arch}" raw_arch)
if(raw_arch MATCHES "^(x86_64|amd64|x64)$")
  set(arch x86_64)
elseif(raw_arch MATCHES "^(aarch64|arm64)$")
  set(arch aarch64)
else()
  message(FATAL_ERROR "make_mirror: unsupported host architecture '${raw_arch}'")
endif()
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
  set(triple "${arch}-unknown-linux-musl")
  set(exe_ext "")
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
  set(triple "${arch}-apple-darwin")
  set(exe_ext "")
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
  set(triple "${arch}-pc-windows-msvc")
  set(exe_ext ".exe")
else()
  message(FATAL_ERROR "make_mirror: unsupported host OS '${CMAKE_HOST_SYSTEM_NAME}'")
endif()

execute_process(
  COMMAND "${OCX_EXE}" version
  RESULT_VARIABLE rc
  OUTPUT_VARIABLE version
  ERROR_VARIABLE err
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT rc EQUAL 0 OR NOT version MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+")
  message(FATAL_ERROR "make_mirror: '${OCX_EXE} version' gave '${version}' (${rc}): ${err}")
endif()

set(tag "v${version}")
set(filename "ocx-${triple}.tar.gz")
file(REMOVE_RECURSE "${MIRROR_DIR}")
set(stage "${MIRROR_DIR}/.stage")
file(MAKE_DIRECTORY "${stage}/ocx-${triple}" "${MIRROR_DIR}/${tag}")
file(COPY "${OCX_EXE}" DESTINATION "${stage}/ocx-${triple}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E tar czf "${MIRROR_DIR}/${tag}/${filename}" "ocx-${triple}"
  WORKING_DIRECTORY "${stage}"
  RESULT_VARIABLE rc
  ERROR_VARIABLE err
)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "make_mirror: archiving failed (${rc}): ${err}")
endif()
file(REMOVE_RECURSE "${stage}")
file(SHA256 "${MIRROR_DIR}/${tag}/${filename}" sha)

# file:// URLs: absolute POSIX paths already start with '/'; Windows drive
# paths (C:/...) need the extra slash after the authority.
if(MIRROR_DIR MATCHES "^/")
  set(base "file://${MIRROR_DIR}")
else()
  set(base "file:///${MIRROR_DIR}")
endif()

set(row_url "${base}/${tag}/${filename}")
file(
  WRITE "${MIRROR_DIR}/dist.json"
  "{\"schema\":1,\"latest\":{\"version\":\"${version}\",\"channel\":\"stable\"},"
  "\"latest_next\":null,\"releases\":[{\"version\":\"${version}\",\"channel\":\"stable\","
  "\"tag\":\"${tag}\",\"target\":\"${triple}\",\"filename\":\"${filename}\","
  "\"sha256\":\"${sha}\",\"url\":\"${row_url}\"}]}\n"
)

set(MIRROR_VERSION "${version}")
set(MIRROR_DIST_URL "${base}/dist.json")
set(MIRROR_URL "${base}")
if(CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
  message(STATUS "make_mirror: ocx ${version} for ${triple}")
  message(STATUS "make_mirror: OCX_INSTALL_DIST_URL=${MIRROR_DIST_URL}")
  message(STATUS "make_mirror: OCX_INSTALL_MIRROR_URL=${MIRROR_URL}")
endif()
