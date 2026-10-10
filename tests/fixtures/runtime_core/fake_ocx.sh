#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Stand-in for the ocx CLI (set OCX_EXECUTABLE to it). Counts invocations in
# $FAKE_OCX_STATE; the first $FAKE_OCX_FAIL_COUNT calls print an ocx-style
# error and exit $FAKE_OCX_FAIL_RC, later calls succeed with a JSON report.
n=0
[ -f "$FAKE_OCX_STATE" ] && n=$(cat "$FAKE_OCX_STATE")
n=$((n + 1))
echo "$n" > "$FAKE_OCX_STATE"
if [ "$n" -le "${FAKE_OCX_FAIL_COUNT:-0}" ]; then
  echo "Installing packages: shim/pkg:1" >&2
  echo "error: shim failure $n: shim failure $n" >&2
  exit "${FAKE_OCX_FAIL_RC:-75}"
fi
echo '{"ok":true}'
