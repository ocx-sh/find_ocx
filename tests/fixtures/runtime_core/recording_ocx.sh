#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Set OCX_EXECUTABLE to this wrapper: it appends each call's arguments and the
# translucent variables it received to $RECORD_OCX_LOG, then runs the real
# ocx ($RECORD_OCX_REAL).
{
  echo "call: $*"
  echo "OCX_NO_CONFIG=${OCX_NO_CONFIG-<unset>}"
  echo "OCX_CONFIG=${OCX_CONFIG-<unset>}"
  echo "OCX_PATCH_SNAPSHOT=${OCX_PATCH_SNAPSHOT-<unset>}"
} >> "$RECORD_OCX_LOG"
exec "$RECORD_OCX_REAL" "$@"
