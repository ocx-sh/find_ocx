# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Configures with the module included and no ocx call, so tests/i2_check.cmake
# can read which config files the build tree regenerates on.
cmake_minimum_required(VERSION 3.20)
project(runtime_core_watch LANGUAGES NONE)
include(ocx)
