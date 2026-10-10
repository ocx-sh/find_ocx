#!/usr/bin/env bash
# cast: true
# doc: guides-pin-and-freeze/floating-fatal
# title: A floating tag is a configure error
# description: Request a floating tag with nothing to freeze it, read the configure error, then freeze the tag with an index snapshot.

# Error cast: the region runs with errexit off because the first configure must fail.
# The verification repeats that configure and asserts status and message.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cp "$FIND_OCX_ROOT/site/casts/fixtures/guides-pin-and-freeze__floating-fatal"/* .
PATH="$(dirname "$CAST_OCX"):$PATH"
# endregion setup

set +e
# region cast
cmake -S . -B build

ocx --index .ocx index update ocx.sh/jqlang/jq:latest

cmake -S . -B build
# endregion cast
set -e

# Verification: the snapshot froze the tag, and the unfrozen configure fails with status 1 and the message.
test -f build/CMakeCache.txt
test -n "$(find .ocx -name jq.json)"
mv .ocx .ocx.off
rc=0
out=$(cmake -S . -B check 2>&1) || rc=$?
test "$rc" -eq 1
grep -q "resolution is not reproducible" <<<"$out"
