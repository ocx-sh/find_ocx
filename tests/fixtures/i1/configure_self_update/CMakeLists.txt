# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Negative fixture (project configure): ocx_self_update rewrites the vendored
# files and must refuse to run outside script mode.

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_self_update_configure LANGUAGES NONE)

include(ocx)

ocx_self_update()
