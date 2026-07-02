# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture (negative): the committed ocx.lock is stale relative to ocx.toml;
# ocx_project() must fail the configure with the actionable exit-65 hint.

cmake_minimum_required(VERSION 3.19)
project(fixture_stale_lock LANGUAGES NONE)

include(ocx)

ocx_project(NAME STALE)

message(FATAL_ERROR "stale_lock fixture: configure must have failed at ocx_project()")
