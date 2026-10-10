<!-- doc_type: explanation -->
<!-- description: Why find_ocx shells out to the ocx CLI instead of re-implementing it in CMake, and what runs at configure and build time. -->
# How find_ocx works

This page explains what find_ocx runs at configure and build time, and why every resolution step stays inside the `ocx` binary.

## Why it never re-implements ocx {#why-shell-out}

The OCI protocol, registry authentication and the package store all belong to ocx.
If the module copied them into CMake, every ocx change would need a matching CMake change.
So find_ocx runs the `ocx` binary for every resolution and parses its JSON.
The durable contracts are the `ocx.lock` digests and the OCI manifests.
A missing capability becomes an issue against ocx, not a workaround in this module.

## What runs, in order {#order}

1. `include(ocx)` is passive. It defines commands and fetches nothing.
2. The first provisioning call picks the CLI. It uses `OCX_EXECUTABLE`, then an `ocx` on `PATH`, then a pinned bootstrap that is sha256-verified and cached once per machine. The first configure of a build tree prints the choice unless you set `OCX_EXECUTABLE`. [Two entry points](entry-points.md#which-binary) lists the rules.
3. Every `ocx` call goes through one wrapper. It sets a fixed environment and retries exit 75 twice on the calls that download. Any other non-zero exit becomes a configure error with a hint. [Environment and config](env-and-config.md) lists the environment, and [Exit codes](../troubleshooting/exit-codes.md) lists the hints.
4. `ocx_project` runs `ocx lock --check` as an offline staleness gate. `ocx_package` resolves its reference through the [index ladder](reproducible-first.md#index-ladder).
5. Eager mode adds `ocx pull` or `ocx package install`. A foreign `PLATFORM` also composes the environment.
A project uses `ocx env --pinned` and a package uses `ocx package env`, so the paths do not depend on the platform ocx rendered last.
6. Each name in `BINS` is checked against what the package declares, using `ocx inspect --closure`. A name that does not exist stops the configure.
7. The call exports `OCX_<NAME>_RUN` and the other [result variables](../reference/commands.md#ocx_project).
8. With unchanged inputs, a later configure skips steps 4 to 7. [Lazy versus eager](lazy-vs-eager.md#memoized) explains how.

## What a command list is {#command-lists}

`OCX_<NAME>_RUN` is a plain CMake list.
For a project it re-enters `ocx exec`, and for a package it re-enters `ocx package exec`.
No wrapper script is written, so the list works in `add_custom_command`, in `add_test`, and with generator expressions.
The content downloads on first execution into the shared, content-addressed `OCX_HOME` store.

## What is shared {#shared}

The bootstrap cache and the `OCX_HOME` store belong to the machine, not to the build tree.
A package is fetched once per machine, and every build tree reuses it.

`ocx_project` also writes a `.ocx/toolchain` directory next to `ocx.toml`.
It holds links that ocx renders, and ocx writes its own `.gitignore` inside it.
That directory is not the committed `.ocx/` index snapshot described in [Reproducible first](reproducible-first.md#index-ladder).

## Where to go next {#next}

- [Two entry points](entry-points.md) explains which binary runs.
- [Lazy versus eager](lazy-vs-eager.md) explains when the network is touched.
- [Reproducible first](reproducible-first.md) explains why a floating tag is an error.
- [Environment and config](env-and-config.md) explains which `OCX_*` variables reach ocx.
