#!/usr/bin/env bash
# cast: true
# doc: guides-use-system-ocx/find-package-ocx
# title: find_package(ocx) and the system ocx
# description: find_package(ocx) fails when no ocx is installed, bootstraps the pinned one on request, and prefers an installed ocx.

# Error cast: the region runs with errexit off because the first configure must fail.
# The verification repeats that configure and asserts status and message.
set -euo pipefail

# region setup
mkdir -p cmake ~/.local/bin
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cp "$FIND_OCX_ROOT/site/casts/fixtures/guides-use-system-ocx__find-package-ocx"/* .
ln -s "$CAST_OCX" ~/.local/bin/ocx
# endregion setup

set +e
# region cast
cmake -S . -B build

cmake -S . -B build -DOCX_BOOTSTRAP=ON

PATH="$HOME/.local/bin:$PATH" cmake -S . -B system
# endregion cast
set -e

# Verification: no ocx fails with status 1 and names ocx; the bootstrap and the installed ocx both resolve.
test -f build/CMakeCache.txt
test -f system/CMakeCache.txt
rc=0
out=$(cmake -S . -B check 2>&1) || rc=$?
test "$rc" -eq 1
grep -q "Could NOT find ocx (missing: OCX_EXECUTABLE)" <<<"$out"
out=$(PATH="$HOME/.local/bin:$PATH" cmake -S . -B check2 2>&1)
grep -q "ocx [0-9][0-9.]* at $HOME/.local/bin/ocx" <<<"$out"
