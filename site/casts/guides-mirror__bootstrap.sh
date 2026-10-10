#!/usr/bin/env bash
# cast: true
# doc: guides-mirror/bootstrap
# title: Bootstrap ocx through an internal mirror
# description: Where github.com is unreachable the bootstrap fails with a hint; point it at an internal mirror and the pinned ocx downloads and verifies.

# Error cast: the region runs with errexit off because the first configure must fail.
# The verification repeats that configure and asserts status and message.
# Setup fakes the corporate network: a loopback mirror plus a dead proxy.
# Needs python3 and network access to fetch the release once.
set -euo pipefail

# region setup
mkdir cmake
cp "$FIND_OCX_ROOT/Findocx.cmake" "$FIND_OCX_ROOT/ocx.cmake" cmake/
cp "$FIND_OCX_ROOT/site/casts/fixtures/guides-mirror__bootstrap"/* .
mkdir "$CAST_TMP/mirror"
python3 "$FIND_OCX_ROOT/site/scripts/make-cast-mirror.py" cmake/ocx.cmake "$CAST_TMP/mirror"
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$CAST_TMP/mirror" </dev/null >"$CAST_TMP/mirror.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
until python3 -c "import socket; socket.create_connection(('127.0.0.1', $port), 1)" 2>/dev/null; do sleep 0.1; done
MIRROR=http://127.0.0.1:$port
# Everything but the loopback mirror is unreachable.
export HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 NO_PROXY=127.0.0.1 no_proxy=127.0.0.1
# endregion setup

set +e
# region cast
cmake -S . -B build

export OCX_INSTALL_DIST_URL="$MIRROR/dist.json" OCX_INSTALL_MIRROR_URL="$MIRROR"

cmake -S . -B build --fresh
# endregion cast
set -e

# Verification: the bootstrap failed with status 1 and the mirror hint, then succeeded through the mirror.
test -f build/CMakeCache.txt
grep -q 'ocx-.*\.tar\.xz\|ocx-.*\.zip' "$CAST_TMP/mirror.log"
rm -rf "$HOME/.cache" check
rc=0
out=$(env -u OCX_INSTALL_DIST_URL -u OCX_INSTALL_MIRROR_URL cmake -S . -B check 2>&1) || rc=$?
test "$rc" -eq 1
grep -q 'OCX_INSTALL_MIRROR_URL' <<<"$out"
