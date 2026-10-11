#!/usr/bin/env bash
# cast: true
# doc: guides-cross-build/foreign-paths
# title: Tool content for another platform
# description: Ask for Windows content on a Unix host, read the BINS error, then use the exported paths instead of a runnable command.

# Error cast: the region runs with errexit off because the first configure must fail.
# The verification repeats that configure and asserts status and message.
# windows/amd64 is foreign on every host that runs this script.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cp "$FIND_OCX_ROOT/site/casts/fixtures/guides-cross-build__foreign-paths"/* .
cp CMakeLists.txt CMakeLists.bins
PATH="$(dirname "$CAST_OCX"):$PATH"
ocx lock
# endregion setup

set +e
# region cast
cmake -S . -B build

sed -i.bak 's/ BINS jq//' CMakeLists.txt

cmake -S . -B build
# endregion cast
set -e

# Verification: the fix configured and listed the Windows binary; BINS on a foreign platform fails with status 1.
test -f build/CMakeCache.txt
cp CMakeLists.bins CMakeLists.txt
rc=0
out=$(cmake -S . -B check 2>&1) || rc=$?
test "$rc" -eq 1
grep -q 'PLATFORM is incompatible with BINS' <<<"$out"
sed -i.bak 's/ BINS jq//' CMakeLists.txt
out=$(cmake -S . -B check2 2>&1)
grep -q 'windows/amd64 content: jq.exe' <<<"$out"
