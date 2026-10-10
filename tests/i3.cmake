# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Command tests for ocx_project, ocx_package and ocx_index. Every test runs
# tests/i3_configure_check.cmake under each provisioned CMake: it configures a
# fixture from tests/fixtures/i3 into a fresh build tree and asserts the exit
# status together with the diagnostic (CMK-TEST-03).

# ocx_i3_add_test(<name> <fixture> VERSIONS <v>... [CASE <case>]
#                 [EXPECT_FAIL <regex>] [EXPECT_OK <regex>] [BUILD]
#                 [OPTIONS <-D...>...])
function(ocx_i3_add_test name fixture)
  cmake_parse_arguments(PARSE_ARGV 2 arg "BUILD" "CASE;EXPECT_FAIL;EXPECT_OK" "VERSIONS;OPTIONS")
  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "ocx_i3_add_test: unknown arguments '${arg_UNPARSED_ARGUMENTS}'")
  endif()
  list(JOIN arg_OPTIONS "|" options)
  foreach(v IN LISTS arg_VERSIONS)
    set(
      args
      "-DFIXTURE_SRC=${CMAKE_SOURCE_DIR}/tests/fixtures/i3/${fixture}"
      "-DFIXTURE_BIN=${CMAKE_BINARY_DIR}/fixtures/i3-${name}-cmake${v}"
      "-DMODULE_PATH=${CMAKE_SOURCE_DIR}"
      "-DOCX_EXE=${OCX_EXECUTABLE}"
      "-DGENERATOR=${CMAKE_GENERATOR}"
      "-DOPTIONS=${options}"
    )
    if(arg_CASE)
      list(APPEND args "-DCASE=${arg_CASE}")
    endif()
    if(arg_EXPECT_FAIL)
      list(APPEND args "-DEXPECT_FAIL=${arg_EXPECT_FAIL}")
    endif()
    if(arg_EXPECT_OK)
      list(APPEND args "-DEXPECT_OK=${arg_EXPECT_OK}")
    endif()
    if(arg_BUILD)
      list(APPEND args -DBUILD=ON)
    endif()
    add_test(
      NAME i3_${name}/${OCX_CMAKE_${v}_TEST_LABEL}
      COMMAND
        ${OCX_CMAKE_${v}_RUN} cmake ${args} -P "${CMAKE_SOURCE_DIR}/tests/i3_configure_check.cmake"
    )
    __ocx_test_props(i3_${name}/${OCX_CMAKE_${v}_TEST_LABEL})
  endforeach()
endfunction()

set(i3_versions ${OCX_TEST_CMAKE_VERSIONS})

# PLATFORM is single-valued: a keyword list, a quoted list and a list in
# OCX_DEFAULT_PLATFORM all fail, at both tiers.
ocx_i3_add_test(
  platform_list_keyword
  cases
  VERSIONS ${i3_versions}
  CASE platform_list_keyword
  EXPECT_FAIL "unknown arguments 'linux/amd64' \\(PLATFORM takes a single ocx platform\\)"
)
ocx_i3_add_test(
  platform_list_quoted
  cases
  VERSIONS ${i3_versions}
  CASE platform_list_quoted
  EXPECT_FAIL "PLATFORM takes a single ocx platform, got 'linux/arm64;linux/amd64'"
)
ocx_i3_add_test(
  default_platform_list
  cases
  VERSIONS ${i3_versions}
  CASE default_platform_list
  EXPECT_FAIL "OCX_DEFAULT_PLATFORM takes a single ocx platform"
)
ocx_i3_add_test(
  project_platform_list
  cases
  VERSIONS ${i3_versions}
  CASE project_platform_list
  EXPECT_FAIL "PLATFORM takes a single ocx platform, got 'linux/arm64;linux/amd64'"
)
ocx_i3_add_test(
  bins_foreign
  cases
  VERSIONS ${i3_versions}
  CASE bins_foreign
  EXPECT_FAIL "PLATFORM is incompatible with BINS"
)
ocx_i3_add_test(
  unknown_keyword
  cases
  VERSIONS ${i3_versions}
  CASE unknown_keyword
  EXPECT_FAIL "ocx_package: unknown arguments 'BOGUS'"
)

# BINS is validated against what the closure declares, lazy and eager alike.
ocx_i3_add_test(
  bins_typo_package
  cases
  VERSIONS ${i3_versions}
  CASE bins_typo
  EXPECT_FAIL "BINS jqq: not a declared binary or entrypoint declared: jq "
)
ocx_i3_add_test(
  bins_typo_project
  groups
  VERSIONS ${i3_versions}
  CASE bins_typo
  EXPECT_FAIL "BINS jqq: not a declared binary or entrypoint declared: jq "
)
ocx_i3_add_test(
  bins_group_not_requested
  groups
  VERSIONS ${i3_versions}
  CASE bins_group
  EXPECT_FAIL
    "BINS shellcheck: declared only in a group that was not requested hint: add the group to GROUPS"
)
ocx_i3_add_test(
  bins_group_not_default
  groups
  VERSIONS ${i3_versions}
  CASE bins_group_not_default
  EXPECT_FAIL
    "BINS jq: declared only in a group that was not requested hint: add the group to GROUPS"
)

# Offline with a cold store: the check is skipped, not a failure.
ocx_i3_add_test(
  bins_offline_cold
  offline
  VERSIONS ${i3_versions}
  EXPECT_OK "BINS not validated \\(OCX_OFFLINE"
  OPTIONS -DOCX_OFFLINE=1 "-DOCX_HOME=${CMAKE_BINARY_DIR}/fixtures/i3-offline-home"
)

# Re-entry: identical calls are no-ops (asserted inside the ok and groups
# fixtures), a different call under the same NAME is the duplicate error.
ocx_i3_add_test(
  toolchain_reentry
  toolchain
  VERSIONS ${i3_versions}
  OPTIONS "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_SOURCE_DIR}/tests/fixtures/i3/toolchain/toolchain.cmake"
)
ocx_i3_add_test(
  reentry_differs
  cases
  VERSIONS ${i3_versions}
  CASE reentry_differs
  EXPECT_FAIL "duplicate ocx_package NAME 'X'"
)

# A .ocx/ with only the rendered toolchain is not an index snapshot; one that
# holds both is.
ocx_i3_add_test(
  toolchain_not_index
  cases
  VERSIONS ${i3_versions}
  CASE toolchain_not_index
  EXPECT_FAIL "no \\.ocx index snapshot"
)
ocx_i3_add_test(index_coexist index_coexist VERSIONS ${i3_versions})

# ocx_index keeps empty arguments on the way to the verb and rejects them.
ocx_i3_add_test(
  index_empty_value
  cases
  VERSIONS ${i3_versions}
  CASE index_empty_value
  EXPECT_FAIL "ocx_index\\(UPDATE_COMMAND\\): empty argument"
)
ocx_i3_add_test(
  index_missing_value
  cases
  VERSIONS ${i3_versions}
  CASE index_missing_value
  # CMake 4 under -Werror=dev trips CMP0174 inside cmake_parse_arguments
  # first; either way the configure fails on the dangling keyword.
  EXPECT_FAIL "INDEX need a value|INDEX keyword was followed by an empty string or no value"
)
ocx_i3_add_test(
  index_find_empty
  cases
  VERSIONS ${i3_versions}
  CASE index_find_empty
  EXPECT_FAIL "ocx_index\\(FIND\\): empty argument"
)

# The commands reject an empty argument (an unset variable) like ocx_index does.
ocx_i3_add_test(
  package_empty_value
  cases
  VERSIONS ${i3_versions}
  CASE package_empty_value
  EXPECT_FAIL "ocx_package: empty argument in"
)
ocx_i3_add_test(
  package_empty_name
  cases
  VERSIONS ${i3_versions}
  CASE package_empty_name
  EXPECT_FAIL "ocx_package: empty argument in"
)
ocx_i3_add_test(
  project_empty_value
  cases
  VERSIONS ${i3_versions}
  CASE project_empty_value
  EXPECT_FAIL "ocx_project: empty argument in"
)

# CONFIG reaches the CLI: a missing file is the CLI's own error.
ocx_i3_add_test(
  config_missing
  cases
  VERSIONS ${i3_versions}
  CASE config_missing
  EXPECT_FAIL "config file not found"
)

# Positive paths: PINS per platform, index digest, <name>_ROOT, CONFIG env,
# project groups with real ocx exec launchers.
ocx_i3_add_test(package_ok ok VERSIONS ${i3_versions})
ocx_i3_add_test(project_groups groups VERSIONS ${i3_versions} BUILD)

# UPDATE_COMMAND neutralizes OCX_FROZEN even when the configure snapshotted it.
ocx_i3_add_test(update_command update_command VERSIONS ${i3_versions} OPTIONS -DOCX_FROZEN=ON)
