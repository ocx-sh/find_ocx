#!/usr/bin/env bash
# cast: true
# doc: guides-add-a-tool/bootstrapped-lock
# title: Write the first lock without an installed ocx
# description: On a machine with no ocx, the first configure downloads the pinned ocx and stops for the missing lock; that ocx then writes it.

# Error cast: the region runs with errexit off because the first configure must fail.
# The wrapper gives the script a PATH without ocx, so the pinned download is the only ocx here.
# The project is examples/tutorial, the same files the tutorial page shows.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cp "$FIND_OCX_ROOT/examples/tutorial/ocx.toml" "$FIND_OCX_ROOT/examples/tutorial/CMakeLists.txt" .
# endregion setup

set +e
# region cast
cmake -S . -B build

"$(cmake -L -N build | sed -n 's/^OCX_EXECUTABLE:FILEPATH=//p')" lock

cmake -S . -B build
# endregion cast
set -e

# Verification: the lock exists and the repeated configure passed; a fresh configure without a lock fails with status 1 and the hint.
test -f ocx.lock
test -f build/CMakeFiles/cmake.check_cache
rm ocx.lock
rc=0
out=$(cmake -S . -B check 2>&1) || rc=$?
test "$rc" -eq 1
grep -q "ocx.lock not found" <<<"$out"
