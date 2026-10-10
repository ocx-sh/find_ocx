# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Toolchain file that provisions foreign-platform content (a sysroot or a cross
# tool) through ocx. CMake reads it more than once per configure, so the calls
# below re-run with identical arguments: that re-entry must be a no-op, not a
# duplicate-NAME error. The file carries no guard of its own on purpose.

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
  PACKAGE
    ocx.sh/jqlang/jq:1.8.2@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
  PLATFORM ${__foreign}
  NO_INDEX
  NO_ROOT
)

ocx_project(NAME FT_PROJ TOML "${CMAKE_CURRENT_LIST_DIR}/ocx.toml" PLATFORM ${__foreign})
