#!/usr/bin/env bash
# cast: true
# doc: tutorial/first-configure
# title: First configure and build
# dir: hello-jq
# description: Configure a project that includes find_ocx, then build it; the build runs a pinned jq nobody installed.

# Environment: see site/scripts/run-cast-script.sh ($CAST_OCX is the host ocx, setup only).
# The cast region is what the page shows; setup and verification run silently.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cp "$FIND_OCX_ROOT/site/casts/fixtures/tutorial__first-configure"/* .
"$CAST_OCX" lock
# endregion setup

# region cast
cmake -S . -B build

cmake --build build
# endregion cast

# Verification: runs in the test, is neither shown nor recorded.
test -f build/CMakeCache.txt
grep -q 'jq' ocx.lock
