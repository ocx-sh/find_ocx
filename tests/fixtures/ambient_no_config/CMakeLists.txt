# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: an ambient OCX_NO_CONFIG=1 (translucent, inherited) configures
# green.

cmake_minimum_required(VERSION 3.19)
project(fixture_ambient_no_config LANGUAGES NONE)

set(ENV{OCX_NO_CONFIG} 1)
include(ocx)
include("${CMAKE_CURRENT_LIST_DIR}/../ambient_env_body.cmake")
