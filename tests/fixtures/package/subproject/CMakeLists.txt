# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Own project() = own discovery bound: the parent's ../.ocx snapshot must
# NOT leak into this scope (a vendored subproject resolves against its own
# snapshot or not at all).

project(fixture_subproject LANGUAGES NONE)

set(OCX_ALLOW_FLOATING ON)
ocx_package(NAME JQ_SUB PACKAGE ocx.sh/jq:latest BINS jq NO_ROOT)
if("${OCX_JQ_SUB_RUN}" MATCHES "--index")
  message(FATAL_ERROR
    "package fixture: outer .ocx leaked across a nested project() bound: "
    "'${OCX_JQ_SUB_RUN}'")
endif()
