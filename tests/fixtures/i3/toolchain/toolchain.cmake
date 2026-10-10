# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# CMake includes a toolchain file twice per configure: the second, identical
# ocx_package call must be a no-op instead of the duplicate-NAME error.

include(ocx)
ocx_package(
  NAME TC
  PACKAGE ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
  BINS jq
)
