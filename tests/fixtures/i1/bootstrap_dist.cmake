# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Script mode (cmake -P): ocx_bootstrap() of the pin from a fake file://
# distribution, offline. The payload is OCX_EXE (the pinned version) archived
# as a release ships it: nested ocx-<triple>/ocx in .tar.gz on unix, flat
# ocx.exe in .zip on Windows.
#   cmake -DMODULE_DIR=<repo> -DOCX_EXE=<ocx> -DSCRATCH=<dir> -P bootstrap_dist.cmake

foreach(var MODULE_DIR OCX_EXE SCRATCH)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "bootstrap_dist: -D${var}=... is required")
  endif()
endforeach()

include("${MODULE_DIR}/ocx.cmake")
set(pin "${__OCX_PIN_VERSION}")
__ocx_host_info(triple platform exe_ext)

execute_process(
  COMMAND "${OCX_EXE}" version
  RESULT_VARIABLE rc
  OUTPUT_VARIABLE real_version
  ERROR_VARIABLE err
  ENCODING UTF-8
)
string(STRIP "${real_version}" real_version)
if(NOT rc EQUAL 0 OR NOT real_version VERSION_EQUAL pin)
  message(
    FATAL_ERROR
    "bootstrap_dist: OCX_EXE=${OCX_EXE} must be the pinned ocx ${pin} "
    "(reports '${real_version}', exit ${rc})\n${err}"
  )
endif()

file(REMOVE_RECURSE "${SCRATCH}")

function(i1_file_url path out_var)
  # POSIX absolute paths already start with '/'; Windows drive paths need
  # the extra slash after the authority.
  if(path MATCHES "^/")
    set(${out_var} "file://${path}" PARENT_SCOPE)
  else()
    set(${out_var} "file:///${path}" PARENT_SCOPE)
  endif()
endfunction()

function(
  i1_write_manifest
  file
  version
  filename
  sha
  url
)
  file(
    WRITE "${file}"
    "{\"schema\":1,\"latest\":{\"version\":\"${version}\",\"channel\":\"stable\"},"
    "\"latest_next\":null,\"releases\":[{\"version\":\"${version}\","
    "\"channel\":\"stable\",\"tag\":\"v${version}\",\"target\":\"${triple}\","
    "\"filename\":\"${filename}\",\"sha256\":\"${sha}\",\"url\":\"${url}\"}]}\n"
  )
endfunction()

# --- the release archive -----------------------------------------------------
file(REAL_PATH "${OCX_EXE}" real_exe)
set(stage "${SCRATCH}/stage")
file(MAKE_DIRECTORY "${stage}/ocx-${triple}" "${SCRATCH}/stage_zip" "${SCRATCH}/mirror/v${pin}")
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
  set(filename "ocx-${triple}.zip")
  file(COPY_FILE "${real_exe}" "${stage}/ocx.exe")
  set(
    pack
    tar
    cf
    "${SCRATCH}/${filename}"
    --format=zip
    ocx.exe
  )
else()
  set(filename "ocx-${triple}.tar.gz")
  file(COPY_FILE "${real_exe}" "${stage}/ocx-${triple}/ocx")
  file(WRITE "${stage}/ocx-${triple}/README.md" "fake release\n")
  set(pack tar czf "${SCRATCH}/${filename}" "ocx-${triple}")
endif()
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E ${pack}
  WORKING_DIRECTORY "${stage}"
  RESULT_VARIABLE rc
  ERROR_VARIABLE err
)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "bootstrap_dist: cannot pack ${filename}: ${err}")
endif()
file(SHA256 "${SCRATCH}/${filename}" sha)

# The Windows layout (a flat ocx.exe in a .zip) is also exercised on unix:
# zip keeps the executable bit, so the extracted binary still runs.
if(NOT CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
  set(zip_filename "ocx-${triple}.zip")
  file(COPY_FILE "${real_exe}" "${SCRATCH}/stage_zip/ocx")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar cf "${SCRATCH}/${zip_filename}" --format=zip ocx
    WORKING_DIRECTORY "${SCRATCH}/stage_zip"
    RESULT_VARIABLE rc
    ERROR_VARIABLE err
  )
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "bootstrap_dist: cannot pack ${zip_filename}: ${err}")
  endif()
  file(SHA256 "${SCRATCH}/${zip_filename}" zip_sha)
endif()

# The mirror serves <mirror>/<tag>/<filename>.
file(COPY_FILE "${SCRATCH}/${filename}" "${SCRATCH}/mirror/v${pin}/${filename}")
i1_file_url("${SCRATCH}/mirror" mirror_url)
i1_file_url("${SCRATCH}/${filename}" archive_url)

# --- manifests ---------------------------------------------------------------
set(zeros "0000000000000000000000000000000000000000000000000000000000000000")
i1_write_manifest("${SCRATCH}/direct.json" "${pin}" "${filename}" "${sha}" "${archive_url}")
# A row whose own url is unreachable: only the mirror rewrite can serve it.
if(DEFINED zip_sha)
  i1_file_url("${SCRATCH}/${zip_filename}" zip_url)
  i1_write_manifest("${SCRATCH}/flat_zip.json" "${pin}" "${zip_filename}" "${zip_sha}" "${zip_url}")
endif()
i1_write_manifest(
  "${SCRATCH}/mirrored.json"
  "${pin}"
  "${filename}"
  "${sha}"
  "https://invalid.example/ocx-sh/ocx/releases/download/v${pin}/${filename}"
)
i1_write_manifest("${SCRATCH}/bad_hash.json" "${pin}" "${filename}" "${zeros}" "${archive_url}")
i1_write_manifest("${SCRATCH}/other_version.json" "0.0.1" "${filename}" "${sha}" "${archive_url}")
i1_write_manifest("${SCRATCH}/traversal.json" "${pin}" "../evil.tar.gz" "${sha}" "${archive_url}")
# A manifest named <sha256>.json is verified against its own name.
file(SHA256 "${SCRATCH}/direct.json" manifest_sha)
file(COPY_FILE "${SCRATCH}/direct.json" "${SCRATCH}/${manifest_sha}.json")
file(COPY_FILE "${SCRATCH}/direct.json" "${SCRATCH}/${zeros}.json")

# i1_case(<name> [FAIL <regex>] [DEFINES <-D...>...] [ARGS <ocx_bootstrap args>...])
# Runs bootstrap_child.cmake in its own work dir and cache. A case either
# succeeds and reports the pin, or exits nonzero with FAIL matching stderr:
# status and diagnostic together, never one alone.
function(i1_case name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "FAIL" "DEFINES;ARGS")
  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "i1_case(${name}): unexpected arguments ${arg_UNPARSED_ARGUMENTS}")
  endif()
  set(cache "${SCRATCH}/cache-${name}")
  set(work "${SCRATCH}/work-${name}")
  file(MAKE_DIRECTORY "${work}")
  execute_process(
    COMMAND
      "${CMAKE_COMMAND}" -E env --unset=OCX_EXECUTABLE --unset=OCX_INSTALL_DIST_URL
      --unset=OCX_INSTALL_MIRROR_URL --unset=OCX_INSTALL_VERSION --unset=OCX_BOOTSTRAP_CACHE
      "${CMAKE_COMMAND}" -Werror=dev "-DCMAKE_MODULE_PATH=${MODULE_DIR}"
      "-DOCX_BOOTSTRAP_CACHE=${cache}" ${arg_DEFINES} "-DBOOT_ARGS=${arg_ARGS}" -P
      "${CMAKE_CURRENT_LIST_DIR}/bootstrap_child.cmake"
    WORKING_DIRECTORY "${work}"
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
    ENCODING UTF-8
  )
  if(arg_FAIL)
    if(rc EQUAL 0)
      message(FATAL_ERROR "bootstrap_dist[${name}]: expected a failure, got exit 0:\n${out}")
    endif()
    # CMake wraps long diagnostics: compare with whitespace collapsed.
    string(REGEX REPLACE "[ \n]+" " " flat_err "${err}")
    if(NOT flat_err MATCHES "${arg_FAIL}")
      message(
        FATAL_ERROR
        "bootstrap_dist[${name}]: exit ${rc} but stderr lacks '${arg_FAIL}':\n${err}"
      )
    endif()
    return()
  endif()
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "bootstrap_dist[${name}]: exit ${rc}\n${out}\n${err}")
  endif()
  if(NOT out MATCHES "using bootstrapped ocx ${pin} ")
    message(FATAL_ERROR "bootstrap_dist[${name}]: no bootstrap report for ${pin}:\n${out}")
  endif()
  if(NOT out MATCHES "bootstrap_child: reports ${pin}\n")
    message(FATAL_ERROR "bootstrap_dist[${name}]: binary does not report ${pin}:\n${out}")
  endif()
  if(NOT EXISTS "${cache}/${pin}/${triple}/ocx${exe_ext}")
    message(
      FATAL_ERROR
      "bootstrap_dist[${name}]: ${cache}/${pin}/${triple}/ocx${exe_ext} was not cached"
    )
  endif()
endfunction()

# DIST_MANIFEST, the row's own file:// url.
i1_case(dist_manifest ARGS DIST_MANIFEST "${SCRATCH}/direct.json")
if(DEFINED zip_sha)
  i1_case(flat_zip ARGS DIST_MANIFEST "${SCRATCH}/flat_zip.json")
endif()
# OCX_INSTALL_DIST_URL replaces the snapshot; the DIST_MANIFEST keyword wins over
# it (a keyword beats the ambient value), so an unreachable URL is never fetched.
i1_file_url("${SCRATCH}/direct.json" direct_url)
i1_case(dist_url DEFINES "-DOCX_INSTALL_DIST_URL=${direct_url}")
i1_case(
  dist_manifest_over_url
  DEFINES "-DOCX_INSTALL_DIST_URL=file://${SCRATCH}/no-such-dist.json"
  ARGS DIST_MANIFEST "${SCRATCH}/direct.json"
)
# OCX_INSTALL_CA_BUNDLE must name a file before the first download; an existing
# file is accepted (file:// downloads ignore it).
i1_case(
  ca_bundle_missing
  DEFINES "-DOCX_INSTALL_CA_BUNDLE=${SCRATCH}/no-such-ca.pem"
  ARGS DIST_MANIFEST "${SCRATCH}/direct.json"
  FAIL "OCX_INSTALL_CA_BUNDLE='[^']*no-such-ca\\.pem' is not a readable file"
)
i1_case(
  ca_bundle_dir
  DEFINES "-DOCX_INSTALL_CA_BUNDLE=${SCRATCH}"
  ARGS DIST_MANIFEST "${SCRATCH}/direct.json"
  FAIL "OCX_INSTALL_CA_BUNDLE='[^']*' is not a readable file"
)
file(WRITE "${SCRATCH}/ca.pem" "")
i1_case(
  ca_bundle_file
  DEFINES "-DOCX_INSTALL_CA_BUNDLE=${SCRATCH}/ca.pem"
  ARGS DIST_MANIFEST "${SCRATCH}/direct.json"
)
# The path check runs on a warm cache too, not only before a download.
file(COPY "${SCRATCH}/cache-ca_bundle_file/" DESTINATION "${SCRATCH}/cache-ca_bundle_missing_warm")
i1_case(
  ca_bundle_missing_warm
  DEFINES "-DOCX_INSTALL_CA_BUNDLE=${SCRATCH}/no-such-ca.pem"
  FAIL "OCX_INSTALL_CA_BUNDLE='[^']*no-such-ca\\.pem' is not a readable file"
)
# A <sha256>.json manifest whose name is its digest is verified and accepted...
i1_file_url("${SCRATCH}/${manifest_sha}.json" named_url)
i1_case(dist_url_sha_named DEFINES "-DOCX_INSTALL_DIST_URL=${named_url}")
# ...and one whose name lies about its digest is refused.
i1_file_url("${SCRATCH}/${zeros}.json" lying_url)
i1_case(
  dist_url_sha_lies
  DEFINES "-DOCX_INSTALL_DIST_URL=${lying_url}"
  FAIL "HASH mismatch|failed to fetch the dist manifest"
)
# The mirror rewrite serves a row whose own url is unreachable.
i1_case(
  mirror
  DEFINES "-DOCX_INSTALL_MIRROR_URL=${mirror_url}"
  ARGS DIST_MANIFEST "${SCRATCH}/mirrored.json"
)
# The row sha256 is enforced whichever manifest and url served the bytes.
i1_case(
  row_hash_mismatch
  ARGS DIST_MANIFEST "${SCRATCH}/bad_hash.json"
  FAIL "HASH mismatch|download of .* failed"
)
# An archive that unpacks to a binary of another version is refused and removed.
i1_case(
  wrong_version
  ARGS VERSION 0.0.1 DIST_MANIFEST "${SCRATCH}/other_version.json"
  FAIL "reports version ${pin}, expected 0\\.0\\.1"
)
if(EXISTS "${SCRATCH}/cache-wrong_version/0.0.1/${triple}/ocx${exe_ext}")
  message(FATAL_ERROR "bootstrap_dist: the mismatching binary stayed in the cache")
endif()
# tag and filename are path segments: a manifest cannot walk out of them.
i1_case(traversal ARGS DIST_MANIFEST "${SCRATCH}/traversal.json" FAIL "not a single path segment")
# Keyword hygiene.
i1_case(unparsed ARGS BOGUS FAIL "unexpected arguments: BOGUS")
i1_case(missing_value ARGS DIST_MANIFEST FAIL "missing value for DIST_MANIFEST")
i1_case(
  missing_file
  ARGS DIST_MANIFEST "${SCRATCH}/nope.json"
  FAIL "DIST_MANIFEST .* does not exist"
)

message(STATUS "bootstrap_dist: ok (ocx ${pin}, ${filename})")
