# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Script mode (cmake -P): target selection of ocx_bootstrap. A Windows host
# prefers the gnullvm archive and falls back to msvc; an explicit TRIPLE is
# tried alone. CASE=neither must fail with the not-found diagnostic.
#   cmake -DMODULE_DIR=<repo> [-DCASE=neither] -P select_release.cmake

if(NOT DEFINED MODULE_DIR)
  message(FATAL_ERROR "select_release: -DMODULE_DIR=... is required")
endif()
include("${MODULE_DIR}/ocx.cmake")

function(row target)
  set(
    row
    "{\"version\":\"1.2.3\",\"tag\":\"v1.2.3\",\"target\":\"${target}\",\"filename\":\"ocx-${target}.zip\",\"sha256\":\"00\",\"url\":\"https://example.invalid/${target}\"}"
  )
  set(row "${row}" PARENT_SCOPE)
endfunction()

function(manifest out)
  set(rows "")
  foreach(target IN LISTS ARGN)
    row("${target}")
    list(APPEND rows "${row}")
  endforeach()
  list(JOIN rows "," joined)
  set(${out} "{\"schema\":1,\"releases\":[${joined}]}" PARENT_SCOPE)
endfunction()

function(expect name manifest_targets candidates want)
  manifest(m ${manifest_targets})
  __ocx_select_release("${m}" 1.2.3 "${candidates}" url sha tag filename target)
  if(NOT target STREQUAL want OR NOT url STREQUAL "https://example.invalid/${want}")
    message(FATAL_ERROR "select_release[${name}]: took '${target}' (${url}), want '${want}'")
  endif()
endfunction()

set(CMAKE_HOST_SYSTEM_NAME Windows)
__ocx_target_candidates(win "")
if(NOT win MATCHES "^[^;]+-pc-windows-gnullvm;[^;]+-pc-windows-msvc$")
  message(FATAL_ERROR "select_release: Windows candidates are '${win}'")
endif()
list(GET win 0 gnullvm)
list(GET win 1 msvc)

if(CASE STREQUAL "neither")
  manifest(m other-target)
  __ocx_select_release("${m}" 1.2.3 "${win}" url sha tag filename target)
  return()
endif()

expect(only_gnullvm "${gnullvm}" "${win}" "${gnullvm}")
expect(only_msvc "${msvc}" "${win}" "${msvc}")
expect(both "${msvc};${gnullvm}" "${win}" "${gnullvm}")

__ocx_target_candidates(override "${msvc}")
if(NOT override STREQUAL msvc)
  message(FATAL_ERROR "select_release: an override must stand alone, got '${override}'")
endif()
expect(override "${gnullvm};${msvc}" "${override}" "${msvc}")
