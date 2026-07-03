# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Negative fixture (script mode): with OCX_BOOTSTRAP=OFF, no
# OCX_EXECUTABLE, and no ocx on PATH the first provisioning call must
# fail with the actionable policy error instead of downloading.

include(ocx)
# PATH-first resolution would legitimately pick up the harness ocx: scrub
# PATH so the fixture exercises the "nothing found + OFF" error.
# (find_program still searches system dirs; ocx is not installed there.)
set(ENV{PATH} "")
ocx_package(NAME POLICY PACKAGE ocx.sh/jq:latest)
