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

elseif(CASE STREQUAL "bootstrap_then_policy")
  ocx_bootstrap()
  ocx_policy(ALLOW_YANKED)
  message(STATUS "case ${CASE}: ok")

elseif(CASE STREQUAL "policy_relative_root")
  ocx_policy(SIGSTORE_TRUSTED_ROOT relative/root.json)

elseif(CASE STREQUAL "prefix_default")
  # The pinned set, explicit knobs removed, site knobs forwarded or removed.
  __ocx_env_prefix(prefix)
  foreach(
    pin
    IN
    ITEMS
      OCX_PROJECT=
      OCX_GLOBAL=0
      OCX_QUIET=0
      OCX_NO_PROJECT=1
      OCX_NO_CONFIG_REFRESH=1
      OCX_NO_CONSENT=1
      OCX_SELF_UPDATE=manual
      --unset=OCX_NO_VERIFY
      --unset=OCX_ALLOW_YANKED
      --unset=OCX_INDEX
      OCX_JOBS=4
  )
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

elseif(CASE STREQUAL "ca_bundle_forward")
  # OCX_INSTALL_CA_BUNDLE reaches ocx as OCX_EXTRA_CA_CERTS only while
  # OCX_EXTRA_CA_CERTS itself is not set; an empty -DOCX_EXTRA_CA_CERTS= removes it.
  set(OCX_INSTALL_CA_BUNDLE "${SCRATCH}/ca.pem")
  file(WRITE "${OCX_INSTALL_CA_BUNDLE}" "") # every ocx call validates the path
  if(CA_CASE STREQUAL "unset")
    __ocx_env_prefix(prefix)
    expect_contains("prefix" "${prefix}" "OCX_EXTRA_CA_CERTS=${SCRATCH}/ca.pem")
  elseif(CA_CASE STREQUAL "explicit")
    set(OCX_EXTRA_CA_CERTS "/corp/own.pem")
    __ocx_env_prefix(prefix)
    expect_contains("prefix" "${prefix}" "OCX_EXTRA_CA_CERTS=/corp/own.pem")
    expect_lacks("prefix" "${prefix}" "OCX_EXTRA_CA_CERTS=${SCRATCH}/ca.pem")
  elseif(CA_CASE STREQUAL "cleared")
    set(OCX_EXTRA_CA_CERTS "")
    __ocx_env_prefix(prefix)
    expect_contains("prefix" "${prefix}" "--unset=OCX_EXTRA_CA_CERTS")
    expect_lacks("prefix" "${prefix}" "OCX_EXTRA_CA_CERTS=[^;]*")
  else()
    message(FATAL_ERROR "case ${CASE}: unknown CA_CASE '${CA_CASE}'")
  endif()

elseif(CASE STREQUAL "translucent_relative")
  __ocx_translucent_env(env CONFIG relative/config.toml)

elseif(CASE STREQUAL "error_message")
  # Only `error:` lines survive, chain repeats collapse, semicolons stay.
  __ocx_error_message(
    msg
    "Installing packages: a/b:1\npulling count=1\nerror: boom: x; y: boom: x; y\n"
  )
  if(NOT msg STREQUAL "boom: x; y")
    message(FATAL_ERROR "case ${CASE}: got '${msg}'")
  endif()
  __ocx_error_message(msg "error: one\r\nerror: two: two\r\nerror: one\r\n")
  if(NOT msg STREQUAL "one\ntwo")
    message(FATAL_ERROR "case ${CASE}: got '${msg}'")
  endif()
  __ocx_error_message(
    msg
    "2026-10-10T17:06:40.092928Z ERROR gone: gone\n2026-10-10T17:06:40Z WARN noise\n"
  )
  if(NOT msg STREQUAL "gone")
    message(FATAL_ERROR "case ${CASE}: got '${msg}'")
  endif()
  # Unbalanced brackets (TOML errors) must not glue lines together.
  __ocx_error_message(msg "error: bad toml: invalid [managed\nerror: expected ']'\n")
  if(NOT msg STREQUAL "bad toml: invalid [managed\nexpected ']'")
    message(FATAL_ERROR "case ${CASE}: got '${msg}'")
  endif()
  __ocx_error_message(msg "no marker here\n")
  if(NOT msg STREQUAL "no marker here")
    message(FATAL_ERROR "case ${CASE}: got '${msg}'")
  endif()

elseif(CASE STREQUAL "hints")
  foreach(
    code
    IN
    ITEMS 64 65 69 74 75 77 78 79 80 81 83 84 85 86 87
  )
    __ocx_default_hint(${code} hint)
    if(hint STREQUAL "")
      message(FATAL_ERROR "case ${CASE}: no default hint for exit ${code}")
    endif()
  endforeach()
  __ocx_default_hint(78 hint)
  if(
    NOT hint MATCHES "ocx lock"
    OR NOT hint MATCHES "ocx config update"
    OR NOT hint MATCHES "OCX_NO_CONFIG=1"
  )
    message(FATAL_ERROR "case ${CASE}: exit 78 hint is incomplete: ${hint}")
  endif()
  __ocx_default_hint(79 hint)
  if(NOT hint MATCHES "ocx patch sync")
    message(FATAL_ERROR "case ${CASE}: exit 79 hint is incomplete: ${hint}")
  endif()

elseif(CASE STREQUAL "shim_run")
  # OCX_EXECUTABLE is the fake_ocx shim; failures and counter come from env.
  __ocx_run(WHAT "running the shim" COMMAND package list RETRIES 2 OUTPUT_VARIABLE out)
  if(NOT out MATCHES "\"ok\":true")
    message(FATAL_ERROR "case ${CASE}: unexpected shim output '${out}'")
  endif()
  message(STATUS "case ${CASE}: ok")

elseif(CASE STREQUAL "translucent_calls")
  # NO_CONFIG and CONFIG reach every configure-time ocx call and the exported
  # RUN list, at both tiers, and outrank the ambient OCX_CONFIG /
  # OCX_PATCH_SNAPSHOT of the environment. OCX_EXECUTABLE is recording_ocx.sh,
  # which logs what each call received.
  set(log "${SCRATCH}/translucent.log")
  set(config "${SCRATCH}/config.toml")
  file(WRITE "${config}" "")
  set(
    jq_index
    "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6"
  )
  file(
    COPY
      "${CMAKE_CURRENT_LIST_DIR}/../i3/groups/ocx.toml"
      "${CMAKE_CURRENT_LIST_DIR}/../i3/groups/ocx.lock"
    DESTINATION "${SCRATCH}/project"
  )

  function(expect_calls_translucent tier min_calls)
    file(READ "${log}" text)
    string(
      REGEX MATCHALL
        "call: [^\n]*\nOCX_NO_CONFIG=[^\n]*\nOCX_CONFIG=[^\n]*\nOCX_PATCH_SNAPSHOT=[^\n]*"
      calls
      "${text}"
    )
    set(seen 0)
    foreach(call IN LISTS calls)
      if(call MATCHES "^call: version\n")
        continue()
      endif()
      math(EXPR seen "${seen} + 1")
      if(NOT call MATCHES "\nOCX_NO_CONFIG=1\nOCX_CONFIG=${config}\nOCX_PATCH_SNAPSHOT=$")
        message(FATAL_ERROR "case ${CASE}: ${tier} call did not get NO_CONFIG and CONFIG:\n${call}")
      endif()
    endforeach()
    if(seen LESS ${min_calls})
      message(FATAL_ERROR "case ${CASE}: ${tier} made only ${seen} ocx calls:\n${text}")
    endif()
    file(REMOVE "${log}")
  endfunction()

  ocx_package(NAME TRP PACKAGE "${jq_index}" PULL BINS jq NO_ROOT NO_CONFIG CONFIG "${config}")
  expect_calls_translucent("ocx_package" 3)
  expect_contains("ocx_package RUN" "${OCX_TRP_RUN}" "OCX_NO_CONFIG=1")
  expect_contains("ocx_package RUN" "${OCX_TRP_RUN}" "OCX_CONFIG=${config}")
  execute_process(COMMAND ${OCX_TRP_RUN_JQ} --version RESULT_VARIABLE rc OUTPUT_QUIET)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "case ${CASE}: the ocx_package RUN list failed (${rc})")
  endif()
  expect_calls_translucent("ocx_package RUN" 1)

  ocx_project(NAME TRJ TOML "${SCRATCH}/project/ocx.toml" PULL BINS jq NO_CONFIG CONFIG "${config}")
  expect_calls_translucent("ocx_project" 3)
  expect_contains("ocx_project RUN" "${OCX_TRJ_RUN}" "OCX_NO_CONFIG=1")
  expect_contains("ocx_project RUN" "${OCX_TRJ_RUN}" "OCX_CONFIG=${config}")
  execute_process(COMMAND ${OCX_TRJ_RUN_JQ} --version RESULT_VARIABLE rc OUTPUT_QUIET)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "case ${CASE}: the ocx_project RUN list failed (${rc})")
  endif()
  expect_calls_translucent("ocx_project RUN" 1)
  message(STATUS "case ${CASE}: ok")

else()
  message(FATAL_ERROR "case.cmake: unknown CASE '${CASE}'")
endif()
