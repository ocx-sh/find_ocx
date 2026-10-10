---
title: Cross-build with foreign-platform content
description: Provision tools or libraries for a platform other than the host from the same ocx.lock, in a toolchain file or a project.
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

You build on one CPU or operating system for another, for example `linux/arm64` from an x86-64 laptop.
The target needs its own binaries, and copying them from another machine leaves two sets of versions to keep in sync.

This page provisions the content of the target platform from the same `ocx.lock` as your native build.
It then hands the content to CMake, either from a toolchain file or from `CMakeLists.txt`.
It assumes a project with a committed `ocx.toml` and `ocx.lock`, as in the [tutorial](../tutorial.md).
A lock stores one digest per tool and platform, so no second lock is needed.

## Request the platform {#request-the-platform}

Pass `PLATFORM` to `ocx_project` or `ocx_package`.
Use the same `<os>/<arch>` names as the keys in `ocx.lock`, such as `linux/arm64`, `darwin/arm64` or `windows/amd64`.
`PLATFORM` takes one platform, and a list is a configure error.
To cover several targets, call the command once per platform with a different `NAME`.

`OCX_DEFAULT_PLATFORM` sets the platform for every call that has no `PLATFORM`.
An empty value means the host.

Foreign content is always downloaded at configure time, with or without `PULL`.
Foreign binaries cannot run on the host, so the lazy `OCX_<NAME>_RUN` commands do not exist.
Passing `BINS` together with `PLATFORM` is a configure error for the same reason.

## Provision in a toolchain file {#toolchain-file}

A toolchain file is the usual place to describe the target, so the provisioning call belongs there too.
CMake reads a toolchain file again for each compiler probe.
An `ocx_project` or `ocx_package` call with the same `NAME` and identical arguments does nothing on re-entry, so the call needs no guard.
A different call under the same `NAME` is a configure error.
The call registers `ocx.toml` and `ocx.lock` as configure dependencies, so the next build reruns the configure after you edit either one.

<!-- snippet: examples/cross_build/toolchain.cmake#toolchain -->

`OCX_TARGET_PATHS` lists the content directories of the target platform.
For a package that ships a sysroot, headers or libraries, `CMAKE_FIND_ROOT_PATH` lets `find_package` and `find_library` search it.
Use `CMAKE_SYSROOT` instead when the package is the whole sysroot.

The four `CMAKE_FIND_ROOT_PATH_MODE_*` lines narrow the search.
Without them, the libraries, headers and packages of the target fall back to the copies of the build machine.
The result links into a binary that cannot run on the target.
Programs stay on the build machine, because they run there.

The project tier renders its links into `.ocx/toolchain/` next to `ocx.toml`.
That directory ignores itself with its own `.gitignore`, so there is nothing to add to yours.
It is not the committed `.ocx/` index snapshot of [pin and freeze](pin-and-freeze.md), which sits in the same `.ocx/` directory under a registry name.

## Read the content in your build {#read-the-content}

A foreign call exports content, not commands.

- `OCX_<NAME>_PATHS` lists the content directories.
- `OCX_<NAME>_ENV_KEYS` lists the environment keys the packages set.
- `OCX_<NAME>_ENV_<KEY>` holds the value of each key.

These are internal cache variables, so `cmake -L` and `cmake-gui` do not list them.
Print them with `message(STATUS ...)` while you set up the build.

For `jq` the path is the package content directory, and the binary sits directly in it, not in a `bin` directory.
This example copies the content into an install tree that you ship to the target.

<!-- snippet: examples/cross_build/CMakeLists.txt#bundle -->

## Run it {#run-it}

The recording requests Windows content on a Unix host.
The first configure passes `BINS` together with `PLATFORM` and fails with `PLATFORM is incompatible with BINS`.
After the `sed` command drops `BINS`, the configure succeeds and prints the exported content path, which holds `jq.exe`.

<!-- snippet: site/casts/guides-cross-build__foreign-paths.sh#cast -->

<!-- cast: guides-cross-build/foreign-paths -->

## Pin a single package {#package-tier}

`ocx_package` accepts `PLATFORM` as well, but it has no lock.
A floating tag such as `:latest` is then a configure error until you pin it with a committed index snapshot or with `PINS`.
The [pin and freeze](pin-and-freeze.md) page shows both.
Use `OCX_ALLOW_FLOATING` only once, to print the digests that you then pin.

## Next steps {#next-steps}

- [Pin and freeze tag resolution](pin-and-freeze.md) to pin a foreign `ocx_package`.
- [Reproduce the build in CI](ci.md) to run the cross build on every push.
- [`ocx_project`](../reference/commands/ocx_project.md) and [`ocx_package`](../reference/commands/ocx_package.md) list the full signatures.
