# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Negative fixture (script mode): a floating tag with no index snapshot
# in effect and no digest pin must fail the configure - reproducible
# first. (OCX_ALLOW_FLOATING=ON is the explicit escape hatch.)

include(ocx)
ocx_package(NAME DRIFTY PACKAGE ocx.sh/jq:latest)
