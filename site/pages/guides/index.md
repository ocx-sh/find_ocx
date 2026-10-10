---
title: Everyday guides
description: Task guides for a project that already runs a pinned tool in its build, from adding a tool to upgrading find_ocx.
---
<!-- doc_type: landing -->
<!-- doc_tier: everyday -->

These guides are for a CMake project that already runs a pinned tool and needs to change, freeze or debug what it pins.

## Change what the build runs {#change-what-the-build-runs}

- [Add a tool to the project](add-a-tool.md): edit `ocx.toml`, refresh the lock and get the build green for everyone
- [Pin and freeze tag resolution](pin-and-freeze.md): fix what `latest` means and refresh it on purpose
- [Make the build find provisioned content](find-package.md): point `find_package` and `find_program` at what the build fetched

## Control which ocx runs {#control-which-ocx-runs}

- [Use an installed ocx](use-system-ocx.md): prefer the `ocx` on `PATH` and tell which binary a configure runs
- [Update the vendored files](update-vendored.md): move `ocx.cmake` and `Findocx.cmake` to another release
- [Move from 0.3 to 0.4](migrate-04.md): find every build line the new release breaks

## When a configure surprises you {#when-a-configure-surprises-you}

- [Lazy versus eager](../concepts/lazy-vs-eager.md): when a configure touches the network and how to force a refresh
- [Fix a failing configure](../troubleshooting/configure-errors.md): the message, its cause and the fix
- [Read an exit code](../troubleshooting/exit-codes.md): each code the module reports and what to do next

## Go further {#go-further}

The [integration guides](ci.md) cover CI, [mirrors and offline builds](mirror.md), [cross builds](cross-build.md) and [organisation-wide policy](policy-and-config.md).
