# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Script-mode cases of the runtime core, selected by -DCASE=<name> and driven
# by tests/i2_check.cmake (which asserts exit status and output):
#   cmake -DCMAKE_MODULE_PATH=<repo> -DCASE=<name> -DSCRATCH=<dir> -P case.cmake

include(ocx)

function(expect_contains what haystack needle)
  if(NOT "${haystack}" MATCHES "(^|;)${needle}(;|$)")
    message(FATAL_ERROR "case ${CASE}: ${what} lacks '${needle}':\n${haystack}")
  endif()
endfunction()

function(expect_lacks what haystack needle)
  if("${haystack}" MATCHES "(^|;)${needle}(;|$)")
    message(FATAL_ERROR "case ${CASE}: ${what} must not contain '${needle}':\n${haystack}")
  endif()
endfunction()

if(CASE STREQUAL "managed_unsynced")
  # A [managed] block with no synced snapshot fails every ocx command with
  # exit 78 before any registry is contacted.
  set(OCX_ALLOW_FLOATING ON)
  ocx_package(NAME UNSYNCED PACKAGE ocx.sh/jqlang/jq:latest NO_INDEX PULL NO_ROOT)

elseif(CASE STREQUAL "policy_conflict")
  ocx_policy(ALLOW_YANKED)
  ocx_policy(ALLOW_YANKED) # identical repeat: no-op
  ocx_policy(ALLOW_UNVERIFIED)

elseif(CASE STREQUAL "policy_late")
  __ocx_env_prefix(prefix)
  ocx_policy(ALLOW_YANKED)

elseif(CASE STREQUAL "policy_relative_root")
  ocx_policy(SIGSTORE_TRUSTED_ROOT relative/root.json)

elseif(CASE STREQUAL "prefix_default")
  # The pinned set, explicit knobs removed, site knobs forwarded or removed.
  __ocx_env_prefix(prefix)
  foreach(pin IN ITEMS OCX_PROJECT= OCX_GLOBAL=0 OCX_QUIET=0 OCX_NO_PROJECT=1
      OCX_NO_CONFIG_REFRESH=1 OCX_NO_CONSENT=1 OCX_SELF_UPDATE=manual
      --unset=OCX_NO_VERIFY --unset=OCX_ALLOW_YANKED --unset=OCX_INDEX
      OCX_JOBS=4)
    expect_contains("prefix" "${prefix}" "${pin}")
  endforeach()
  expect_lacks("prefix" "${prefix}" "OCX_AUTH_[A-Z_]*=[^;]*")
  __ocx_policy_env(policy)
  if(NOT "${policy}" STREQUAL "")
    message(FATAL_ERROR "case ${CASE}: unset policy must yield no env, got '${policy}'")
  endif()

elseif(CASE STREQUAL "prefix_policy")
  ocx_policy(ALLOW_UNVERIFIED SIGSTORE_TRUSTED_ROOT "${SCRATCH}/root.json")
  ocx_policy(ALLOW_UNVERIFIED SIGSTORE_TRUSTED_ROOT "${SCRATCH}/root.json")
  __ocx_policy_env(policy)
  expect_contains("policy env" "${policy}" "OCX_NO_VERIFY=1")
  expect_contains("policy env" "${policy}" "OCX_SIGSTORE_TRUSTED_ROOT=${SCRATCH}/root.json")
  expect_lacks("policy env" "${policy}" "OCX_ALLOW_YANKED=1")
  __ocx_env_prefix(prefix)
  expect_contains("prefix" "${prefix}" "OCX_NO_VERIFY=1")
  expect_contains("prefix" "${prefix}" "--unset=OCX_ALLOW_YANKED")
  expect_lacks("prefix" "${prefix}" "--unset=OCX_NO_VERIFY")

elseif(CASE STREQUAL "translucent")
  __ocx_translucent_env(env CONFIG "${SCRATCH}/c.toml" NO_CONFIG ON)
  expect_contains("translucent env" "${env}" "OCX_NO_CONFIG=1")
  expect_contains("translucent env" "${env}" "OCX_CONFIG=${SCRATCH}/c.toml")
  expect_contains("translucent env" "${env}" "OCX_PATCH_SNAPSHOT=")
  __ocx_translucent_env(none)
  if(NOT "${none}" STREQUAL "")
    message(FATAL_ERROR "case ${CASE}: no keywords must yield no env, got '${none}'")
  endif()
  # A keyword outranks the ambient value in the composed prefix.
  __ocx_env_prefix(prefix ${env})
  expect_contains("prefix" "${prefix}" "OCX_CONFIG=${SCRATCH}/c.toml")
  expect_lacks("prefix" "${prefix}" "OCX_PATCHES=[^;]+")

elseif(CASE STREQUAL "translucent_relative")
  __ocx_translucent_env(env CONFIG relative/config.toml)

elseif(CASE STREQUAL "error_message")
  # Only `error:` lines survive, chain repeats collapse, semicolons stay.
  __ocx_error_message(msg "Installing packages: a/b:1\npulling count=1\nerror: boom: x; y: boom: x; y\n")
  if(NOT msg STREQUAL "boom: x; y")
    message(FATAL_ERROR "case ${CASE}: got '${msg}'")
  endif()
  __ocx_error_message(msg "error: one\r\nerror: two: two\r\nerror: one\r\n")
  if(NOT msg STREQUAL "one\ntwo")
    message(FATAL_ERROR "case ${CASE}: got '${msg}'")
  endif()
  __ocx_error_message(msg "2026-10-10T17:06:40.092928Z ERROR gone: gone\n2026-10-10T17:06:40Z WARN noise\n")
  if(NOT msg STREQUAL "gone")
    message(FATAL_ERROR "case ${CASE}: got '${msg}'")
  endif()
  __ocx_error_message(msg "no marker here\n")
  if(NOT msg STREQUAL "no marker here")
    message(FATAL_ERROR "case ${CASE}: got '${msg}'")
  endif()

elseif(CASE STREQUAL "hints")
  foreach(code IN ITEMS 64 65 69 74 75 77 78 79 80 81 83 84 85 86 87)
    __ocx_default_hint(${code} hint)
    if(hint STREQUAL "")
      message(FATAL_ERROR "case ${CASE}: no default hint for exit ${code}")
    endif()
  endforeach()
  __ocx_default_hint(78 hint)
  if(NOT hint MATCHES "ocx lock" OR NOT hint MATCHES "ocx config update"
      OR NOT hint MATCHES "OCX_NO_CONFIG=1")
    message(FATAL_ERROR "case ${CASE}: exit 78 hint is incomplete: ${hint}")
  endif()
  __ocx_default_hint(79 hint)
  if(NOT hint MATCHES "ocx patch sync")
    message(FATAL_ERROR "case ${CASE}: exit 79 hint is incomplete: ${hint}")
  endif()

elseif(CASE STREQUAL "shim_run")
  # OCX_EXECUTABLE is the fake_ocx shim; failures and counter come from env.
  __ocx_run(WHAT "running the shim" COMMAND package list RETRIES 2
    OUTPUT_VARIABLE out)
  if(NOT out MATCHES "\"ok\":true")
    message(FATAL_ERROR "case ${CASE}: unexpected shim output '${out}'")
  endif()
  message(STATUS "case ${CASE}: ok")

else()
  message(FATAL_ERROR "case.cmake: unknown CASE '${CASE}'")
endif()
