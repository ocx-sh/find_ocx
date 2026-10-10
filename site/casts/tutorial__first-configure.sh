#!/usr/bin/env bash
# cast: true
# doc: tutorial/first-configure
# title: Lock, configure and build
# dir: hello-jq
# description: Write the lock file, configure a project that includes find_ocx, then build it; the build runs a pinned jq nobody installed.

# Environment: see site/scripts/run-cast-script.sh ($CAST_OCX is the host ocx).
# The cast region is what the page shows; setup and verification run silently.
# The project is examples/tutorial, the same files the tutorial page shows.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cp "$FIND_OCX_ROOT/examples/tutorial/ocx.toml" "$FIND_OCX_ROOT/examples/tutorial/CMakeLists.txt" .
PATH="$(dirname "$CAST_OCX"):$PATH"
# endregion setup

# region cast
ocx lock

cmake -S . -B build

cmake --build build
# endregion cast

# Verification: runs in the test, is neither shown nor recorded.
test -f ocx.lock
cmake --build build > build.log 2>&1
grep -q "^jq-" build.log
