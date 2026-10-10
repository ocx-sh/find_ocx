#!/usr/bin/env bash
# cast: true
# doc: guides-pin-and-freeze/frozen-offline
# title: Run a frozen, offline configure
# description: With a committed index snapshot and a warm store, a frozen configure and a build need no network.

# Setup stands in for an earlier online session (snapshot committed, store filled by an eager configure).
# The verification repeats the run with every network route dead.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cp "$FIND_OCX_ROOT/site/casts/fixtures/guides-pin-and-freeze__frozen-offline"/* .
PATH="$(dirname "$CAST_OCX"):$PATH"
ocx --index .ocx index update ocx.sh/jqlang/jq:latest
cmake -S . -B build -DOCX_PULL=ON
rm -rf build
# endregion setup

# region cast
OCX_FROZEN=1 OCX_OFFLINE=1 cmake -S . -B build

OCX_OFFLINE=1 cmake --build build
# endregion cast

# Verification: the same configure and build pass with every route to the network dead.
rm -rf build
dead=http://127.0.0.1:9
HTTP_PROXY=$dead HTTPS_PROXY=$dead http_proxy=$dead https_proxy=$dead OCX_FROZEN=1 OCX_OFFLINE=1 cmake -S . -B build
HTTP_PROXY=$dead HTTPS_PROXY=$dead http_proxy=$dead https_proxy=$dead OCX_OFFLINE=1 cmake --build build
