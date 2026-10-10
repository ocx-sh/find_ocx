---
title: Pin and freeze tag resolution
description: Freeze a floating package tag with a committed index snapshot or digests, refresh it on purpose, and run a frozen or offline configure.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

# Pin and freeze tag resolution

A configure stopped because `ocx_package` got a floating tag such as `:latest` and nothing fixes what that tag means.
A moving tag builds one tool version today and another next month, and a host `find_program` has the same problem with whatever is installed.
FetchContent hashes the sources it downloads, but a tool tag has no such hash until you record one.
This page freezes the tag with an index snapshot or a digest, refreshes it on purpose, and runs a frozen configure.

`ocx_project` builds are already frozen by `ocx.lock`, so this page covers `ocx_package`.

## See why the configure stopped {#floating-error}

The error names the package and lists three ways out.
The recording shows it for a `jq:latest` package.

<!-- cast: guides-pin-and-freeze/floating-fatal -->

The three ways are a committed snapshot, a [digest](pin-digests.md), or `OCX_ALLOW_FLOATING=ON`.
The last one accepts drift and belongs in throwaway experiments only.
[Reproducible first](../concepts/reproducible-first.md) explains the reasoning.

## Commit an index snapshot {#snapshot}

A snapshot is a directory named `.ocx/` that records what each tag resolved to.
Create it from the directory that holds your `CMakeLists.txt`, once per tag you use, and commit it like a lock file.
The command for `jq` is `ocx --index .ocx index update ocx.sh/jqlang/jq:latest`.
A bare repository, without `:latest`, records every tag the registry lists and makes a larger diff.

Every `ocx_package` call finds the nearest `.ocx/` directory by itself.
`ocx_index(FIND REQUIRED)` makes that explicit and stops the configure when the snapshot is missing.

<!-- snippet: examples/frozen_index/CMakeLists.txt#snapshot -->

## Refresh the snapshot on purpose {#refresh}

Nothing updates a snapshot by itself, because a silent refresh would hide drift.
`ocx_index(UPDATE_COMMAND)` composes the refresh command, and you decide how it runs.
Here it is a build target.

<!-- snippet: examples/frozen_index/CMakeLists.txt#refresh -->

1. Run `cmake --build build --target index-update`.
2. Review the diff of `.ocx/`.
3. Commit the result.

The composed command runs without frozen mode, so it works while `OCX_FROZEN` is set.
A tag that is missing from the snapshot makes the next frozen configure fail with exit code 81 and a refresh hint.

## Run a frozen configure {#frozen-configure}

Set `OCX_FROZEN` to a truthy value such as `1` before the first configure of a build directory.
Every `ocx` call then refuses a tag that is neither in the snapshot nor in the lock, with exit code 81.
Frozen mode is not an offline mode, because ocx may still fetch content it has pinned.

Each `OCX_*` setting is stored on the first configure and stays for that build directory.
Use a fresh build directory when you change it.

To build with no network, fill the local store first.
Configure once online with `-DOCX_PULL=ON`, because a lazy configure leaves the store empty.
Then configure a fresh directory with `OCX_FROZEN=1` and `OCX_OFFLINE=1`.
[Lazy versus eager](../concepts/lazy-vs-eager.md) explains the difference.

<!-- cast: guides-pin-and-freeze/frozen-offline -->

## Point at a snapshot elsewhere {#index-dir}

Give `ocx_package` an `INDEX` directory to freeze against a snapshot outside the project tree.
`NO_INDEX` skips every snapshot for one call.

<!-- snippet: examples/package/CMakeLists.txt#index-dir -->

## Next steps {#next-steps}

- [Pin digests instead of a snapshot](pin-digests.md) fixes a tag without a snapshot directory.
- [Add or change a pinned tool](add-a-tool.md) covers `ocx_project` and its lock.
- [Route package pulls through a mirror](mirror-packages.md) covers mirrors and credentials.
- [`ocx_index`](../reference/commands/ocx_index.md) lists every keyword.
