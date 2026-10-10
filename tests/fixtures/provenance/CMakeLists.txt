# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: which ocx a provisioning call settles on. A lazy package with a
# digest runs nothing but 'ocx version', so the result is the choice itself.
# Driven by tests/executable_check.cmake; the report line is parsed there.

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_provenance LANGUAGES NONE)

include(ocx)

ocx_package(
  NAME P
  PACKAGE "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6"
  NO_ROOT
)
message(STATUS "provenance fixture: executable [${OCX_EXECUTABLE}]")
