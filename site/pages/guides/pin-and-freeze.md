<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->
<!-- description: Freeze floating tags with a committed index snapshot or per-platform digests, and refresh them on purpose. -->
# Pin and freeze tag resolution

Use a committed `.ocx/` index snapshot or per-platform digests so a floating tag such as `:latest` resolves the same way on every machine.
Without one of them, a floating tag is a hard configure error.

## Commit an index snapshot

Create the snapshot for the packages you use and commit it like a lock file.

```console
ocx --index .ocx index update ocx.sh/jqlang/jq ocx.sh/kitware/cmake
git add .ocx
```

Then fail fast in `CMakeLists.txt` when the snapshot is missing.

--8<-- "examples/frozen_index/CMakeLists.txt" from="^# Fail-fast" to="^ocx_package" title="examples/frozen_index/CMakeLists.txt"

Each `ocx_package` call discovers the nearest `.ocx/` directory by itself.
The `ocx_index(FIND REQUIRED)` call only makes the intent explicit.

## Refresh the snapshot on purpose

Snapshots are never updated automatically.
Compose the refresh command and decide how it runs. Here it is a build target.

--8<-- "examples/frozen_index/CMakeLists.txt" from="^ocx_index\(UPDATE_COMMAND" to="VERBATIM\)$" title="examples/frozen_index/CMakeLists.txt"

1. Run `cmake --build build --target index-update`.
2. Review the diff of `.ocx/`.
3. Commit the result.

A tag that is missing from the snapshot makes the next frozen configure fail with a refresh hint.

## Pin per-platform digests instead

Pin a manifest digest for each platform when you want no snapshot directory.
Nothing is downloaded until the first build-time execution.

--8<-- "examples/package/CMakeLists.txt" from="^ocx_package\(NAME jq_pinned" to="^\)$" title="examples/package/CMakeLists.txt"

Get the digests from `ocx package install -p <platform>` or from the `ocx.lock` of a project.
You can also print them once with a floating pull, which needs the explicit escape hatch.

--8<-- "examples/package/CMakeLists.txt" from="^set\(OCX_ALLOW_FLOATING ON\)" to="^unset" title="examples/package/CMakeLists.txt"

## Point at a snapshot elsewhere

Use `INDEX` to freeze against any directory.

--8<-- "examples/package/CMakeLists.txt" from="^ocx_package\(NAME jq_frozen" to=index.\)$ title="examples/package/CMakeLists.txt"

For why a floating tag is an error, see [Reproducible first](../concepts/reproducible-first.md).
Needs addressed: problem 3 of the [use-case research](https://github.com/ocx-sh/find_ocx/blob/main/.agents/research/docs-use-cases.md).
