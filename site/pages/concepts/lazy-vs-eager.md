<!-- doc_type: explanation -->
<!-- description: When a configure downloads package content, what PULL changes, how to prepare an offline build, and what a reconfigure costs. -->
# Lazy versus eager

This page explains when a configure downloads package content, what `PULL` changes, and what a reconfigure costs.
It helps you tell whether a configure touched the network, and how to force a refresh.

## Lazy by default {#lazy}

The exported `OCX_<NAME>_RUN` commands re-enter `ocx exec` or `ocx package exec`.
Those launchers install missing content on first execution.
So a configure downloads no package content, and the build downloads it when a target first runs the tool.

| Call | Content is downloaded | Why |
|---|---|---|
| `ocx_project` | On the first run of an `OCX_<NAME>_RUN` command | The lock check is offline and the launcher installs the rest. |
| `ocx_package` | On the first run of an `OCX_<NAME>_RUN` command | The same launcher mechanism. |
| Either with `PULL` | At configure | `ocx pull` or `ocx package install` runs before the call returns. |
| Either with a foreign `PLATFORM` | At configure | The paths in `OCX_<NAME>_PATHS` must point at content that exists. |

The bootstrap of the `ocx` binary is separate.
It downloads once per machine and logs the download.

To find out whether a configure needs the network, configure a fresh build directory with `-DOCX_OFFLINE=1`.
A call that needs content stops with exit 79 when the package is pinned and the store lacks it.
A tag that a snapshot resolves stops with exit 81 when its manifest is not cached.
The message names the command.
A lazy call with a digest reference and `BINS` passes, and prints a status line instead of checking the names:

```log
find_ocx: ocx_package X (<ref>): BINS not validated (OCX_OFFLINE and the package is not in the local store)
```

A configure that passes touched no network.

## Eager mode {#eager}

`PULL` on a call, or `-DOCX_PULL=ON` for every call, materializes content at configure time.
On `ocx_package`, `PULL` also exports `<name>_ROOT`, so a later `find_package` or `find_program` can search the content.
CI jobs often set `OCX_PULL=ON`, so a missing package fails the configure and warms the cache.

<!-- snippet: examples/package/CMakeLists.txt#eager -->

The `OCX_ALLOW_FLOATING` lines are there because this example resolves a floating tag live, to print its digest.
With a lock file, an index snapshot or a digest, the `ocx_package` line stands alone.
A lazy call pins the reference and waits for the first execution:

<!-- snippet: examples/package/CMakeLists.txt#pinned-lazy -->

## Preparing an offline build {#offline}

A lazy configure leaves the package store empty.
A later offline run of the tool then fails with exit 79 for a pinned package, because nothing was downloaded while the network was reachable.
The build step prints `error: failed to find package: <ref> — package not found`.
A tag that a snapshot resolves fails with exit 81 instead.

Fill the store first, with a configure that pulls. Then configure offline against the lock file or snapshot:

<!-- doc-norun: workflow fragment, it needs a project with a lock file and network access -->

```bash-norun
cmake -S . -B build -DOCX_PULL=ON
cmake -S . -B build-offline -DOCX_OFFLINE=1 -DOCX_FROZEN=1
```

<!-- /doc-norun -->

The second command reuses the filled store and refuses any network use.
It uses a new build directory because `OCX_OFFLINE` and `OCX_FROZEN` are site variables, and a build directory keeps the value of its first configure.

## Reconfigures are memoized {#memoized}

Each provisioning call fingerprints its inputs.
They are the module version, the ocx version and path, the contents of `ocx.toml` and `ocx.lock`, and the call's arguments.
When the fingerprint matches and the store paths still exist, no `ocx` process starts.
The log says `up to date (memoized)` instead, and the module's own test asserts that line on the second configure:

<!-- snippet: tests/reconfigure_check.cmake#memoized -->

A change to any input, or a store that lost the content, runs `ocx` again.
`-DOCX_REFRESH=ON` bypasses the memo once and then clears itself.

## Related pages {#related}

- [Reproduce the build in CI](../guides/ci.md) switches a CI job to eager mode.
- [Reproducible first](reproducible-first.md#frozen-configure) explains the frozen configure.
- [Environment and config](env-and-config.md#site) explains why a build directory keeps its first value.
