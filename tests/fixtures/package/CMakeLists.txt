# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: ocx_package() eager (PULL -> <name>_ROOT export) and lazy
# (package exec launcher, materializes on first build-time execution),
# plus the index ladder: .ocx/ discovery, NO_INDEX opt-out, and the
# UPDATE_COMMAND composition.

cmake_minimum_required(VERSION 3.19)
project(fixture_package LANGUAGES NONE)

include(ocx)

# NO_INDEX skips the committed .ocx/ discovery -> floating, which is a
# hard error unless explicitly allowed (the error path is covered by the
# floating_fatal fixture).
set(OCX_ALLOW_FLOATING ON)
ocx_package(NAME jq PACKAGE ocx.sh/jq:latest PULL NO_INDEX)
if(NOT DEFINED CACHE{jq_ROOT} OR NOT EXISTS "${jq_ROOT}")
  message(FATAL_ERROR "package fixture: jq_ROOT not exported or missing (${jq_ROOT})")
endif()

ocx_package(NAME JQ_LAZY PACKAGE ocx.sh/jq:latest BINS jq NO_ROOT NO_INDEX)
unset(OCX_ALLOW_FLOATING)

add_custom_target(jq_lazy_assert ALL
  COMMAND ${OCX_JQ_LAZY_RUN_JQ} -n -e [[1 == 1]]
  VERBATIM
)

# Frozen + lazy via the discovery ladder: no INDEX argument - the tag
# resolves from the committed ./.ocx snapshot found upward from this
# directory. The exported launcher carries --index --frozen into every
# execution.
ocx_package(NAME JQ_FROZEN PACKAGE ocx.sh/jq:latest BINS jq NO_ROOT)
if(NOT "${OCX_JQ_FROZEN_RUN}" MATCHES "--index;.*\\.ocx;--frozen")
  message(FATAL_ERROR
    "package fixture: discovered .ocx not composed into the launcher: "
    "'${OCX_JQ_FROZEN_RUN}'")
endif()

add_custom_target(jq_frozen_assert ALL
  COMMAND ${OCX_JQ_FROZEN_RUN_JQ} -n -e [[1 == 1]]
  VERBATIM
)

# Discovery bound: a nested project() scope must not see this .ocx.
add_subdirectory(subproject)

# Command composition: INDEX defaults to the discovered .ocx, packages
# collected from the frozen registration above.
ocx_index(UPDATE_COMMAND index_refresh)
if(NOT "${index_refresh}" MATCHES "--index;.*\\.ocx;index;update;ocx\\.sh/jq$")
  message(FATAL_ERROR
    "package fixture: ocx_index(UPDATE_COMMAND) composed '${index_refresh}'")
endif()
