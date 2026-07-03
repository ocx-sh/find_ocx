# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: ocx_package() eager (PULL -> <name>_ROOT export) and lazy
# (package exec launcher, materializes on first build-time execution).

cmake_minimum_required(VERSION 3.19)
project(fixture_package LANGUAGES NONE)

include(ocx)

ocx_package(NAME jq PACKAGE ocx.sh/jq:latest PULL)
if(NOT DEFINED CACHE{jq_ROOT} OR NOT EXISTS "${jq_ROOT}")
  message(FATAL_ERROR "package fixture: jq_ROOT not exported or missing (${jq_ROOT})")
endif()

ocx_package(NAME JQ_LAZY PACKAGE ocx.sh/jq:latest BINS jq NO_ROOT)

add_custom_target(jq_lazy_assert ALL
  COMMAND ${OCX_JQ_LAZY_RUN_JQ} -n -e [[1 == 1]]
  VERBATIM
)

# Frozen + lazy: the tag resolves from the committed index snapshot
# (index/ocx.sh/jq.json); the exported launcher carries --index --frozen
# into every execution, and -Werror=dev proves the floating warning is
# suppressed when INDEX is given.
ocx_package(NAME JQ_FROZEN PACKAGE ocx.sh/jq:latest BINS jq NO_ROOT
  INDEX "${CMAKE_CURRENT_SOURCE_DIR}/index")

add_custom_target(jq_frozen_assert ALL
  COMMAND ${OCX_JQ_FROZEN_RUN_JQ} -n -e [[1 == 1]]
  VERBATIM
)

# Command composition: repos collected from the INDEX registration above.
ocx_index_update_command(index_refresh INDEX "${CMAKE_CURRENT_SOURCE_DIR}/index")
if(NOT "${index_refresh}" MATCHES "--index;.*/index;index;update;ocx\\.sh/jq$")
  message(FATAL_ERROR
    "package fixture: ocx_index_update_command composed '${index_refresh}'")
endif()
