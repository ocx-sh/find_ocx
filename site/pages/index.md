---
title: find_ocx
description: Run pinned, sha256-verified command-line tools from a CMake build without installing them, using the OCX package manager.
---
<!-- doc_type: landing -->
<!-- doc_tier: first-steps -->

find_ocx runs pinned, sha256-verified tools such as `jq` or `shellcheck` from your CMake build without installing them, using the [OCX](https://ocx.sh) package manager.

<!-- snippet: examples/tutorial/CMakeLists.txt#full -->

## Why not install the tool first {#why}

A build that needs `jq` usually says "install jq first" in its README.
Or it calls `find_program` and takes whatever the host has.
Every machine then runs its own version.

FetchContent and CPM fetch sources to compile.
The vcpkg and Conan clients must be installed and configured before the build starts.
With find_ocx, a prebuilt tool runs at the digest your `ocx.lock` fixes, on every machine.

[Run jq in a CMake build](tutorial.md) is the shortest path to a first result.

## Pick a goal {#pick-a-goal}

This documentation is for CMake authors and the platform engineers who run their builds.

- [Everyday guides](guides/index.md): add a tool, freeze a tag, find provisioned content, update the vendored files
- [Reproduce the build in CI](guides/ci.md): the same tool versions on Linux, macOS and Windows
- [Build behind a mirror or offline](guides/mirror.md): internal hosts, credentials and no downloads
- [Fix a failing configure](troubleshooting/configure-errors.md): the error text, its cause and the fix

## Understand it {#understand-it}

- [How find_ocx works](concepts/how-it-works.md)
- [Reproducible first](concepts/reproducible-first.md)
- [Environment and config](concepts/env-and-config.md)

## Look it up {#look-it-up}

- [Commands](reference/commands.md), [variables](reference/variables.md) and [Findocx.cmake](reference/findocx.md)
