#!/usr/bin/env bash
# cast: true
# doc: guides-add-a-tool/stale-lock
# title: Add a tool and refresh the lock
# description: Add a tool to ocx.toml without refreshing ocx.lock, read the configure error, then fix it with ocx lock.

# Error cast: the region runs with errexit off because the first configure must fail.
# The verification repeats that configure and asserts status and message.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cp "$FIND_OCX_ROOT/site/casts/fixtures/guides-add-a-tool__stale-lock"/* .
"$CAST_OCX" lock
PATH="$(dirname "$CAST_OCX"):$PATH"
# endregion setup

set +e
# region cast
echo 'shellcheck = "ocx.sh/shellcheck/shellcheck:latest"' >> ocx.toml

cmake -S . -B build

ocx lock

cmake -S . -B build
# endregion cast
set -e

# Verification: the fix worked, and a fresh stale lock fails with status 1 and the hint.
grep -q shellcheck ocx.lock
test -f build/CMakeCache.txt
echo 'yq = "ocx.sh/mikefarah/yq:latest"' >> ocx.toml
rc=0
out=$(cmake -S . -B check 2>&1) || rc=$?
test "$rc" -eq 1
grep -q "run 'ocx lock'" <<<"$out"
