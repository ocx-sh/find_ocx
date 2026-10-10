# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Toolchain file that provisions foreign-platform content (a sysroot or a
# cross tool) through ocx. CMake reads a toolchain file more than once per
# configure, so the ocx_package()/ocx_project() calls below run again with
# identical arguments: that re-entry has to be a no-op, not a duplicate-NAME
# error. The file carries no guard of its own on purpose.

include(ocx)

# The content for a platform other than the host's: it is exported as
# paths and environment values, never as runnable commands.
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
  set(__foreign linux/amd64)
else()
  set(__foreign linux/arm64)
endif()

ocx_package(
  NAME FT_PKG
  PACKAGE ocx.sh/jqlang/jq:1.8.2
  PLATFORM ${__foreign}
  NO_INDEX
  NO_ROOT
  PINS
    "linux/amd64=sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    "linux/arm64=sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
)

ocx_project(NAME FT_PROJ TOML "${CMAKE_CURRENT_LIST_DIR}/ocx.toml" PLATFORM ${__foreign})
