#!/usr/bin/env bash
# cast: true
# doc: guides-add-a-tool/bins-typo
# title: A misspelled BINS name
# description: Name a binary the package does not provide, read the configure error that lists the real names, then fix the spelling.

# Error cast: the region runs with errexit off because the first configure must fail.
# The verification repeats that configure and asserts status and message.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cp "$FIND_OCX_ROOT/site/casts/fixtures/guides-add-a-tool__bins-typo"/* .
cp CMakeLists.txt CMakeLists.typo
"$CAST_OCX" lock
PATH="$(dirname "$CAST_OCX"):$PATH"
# endregion setup

set +e
# region cast
cmake -S . -B build

sed -i.bak 's/BINS jqq/BINS jq/' CMakeLists.txt

cmake -S . -B build
# endregion cast
set -e

# Verification: the fix worked, and the typo fails with status 1 naming the typo and the real binary.
grep -q 'BINS jq)' CMakeLists.txt
test -f build/CMakeCache.txt
cp CMakeLists.typo CMakeLists.txt
rc=0
out=$(cmake -S . -B check 2>&1) || rc=$?
test "$rc" -eq 1
grep -q 'jqq' <<<"$out"
grep -qE "jq\b" <<<"$out"
