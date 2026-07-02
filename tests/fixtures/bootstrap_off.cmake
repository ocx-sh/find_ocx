# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Negative fixture (script mode): with OCX_BOOTSTRAP=OFF and no
# OCX_EXECUTABLE the first provisioning call must fail with the
# actionable policy error instead of downloading.

include(ocx)
ocx_package(NAME POLICY PACKAGE ocx.sh/jq:latest)
