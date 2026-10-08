<!-- doc_type: landing -->
<!-- doc_tier: first-steps -->
<!-- description: CMake support for OCX, with pinned and sha256-verified tools in a CMake build. -->
# find_ocx

find_ocx runs pinned, sha256-verified tools such as `jq` or `shellcheck` from your CMake build, using the [OCX](https://ocx.sh) package manager.

--8<-- "examples/project/CMakeLists.txt" from="^# The ocx.toml next to this file" to="^\)$" title="examples/project/CMakeLists.txt"

```console
cmake -S . -B build && cmake --build build
```

[Run jq in a CMake build](tutorial.md) walks through this example step by step.

You need CMake 3.19 and network access or a mirror.
You do not need to install `ocx`.
An `ocx` on `PATH` is used when present, otherwise the pinned CLI is bootstrapped on first configure into a per-machine cache.
`Findocx.cmake` alone works on CMake 3.15.

## Pick a goal

- [Run workspace tools from ocx.toml](guides/workspace-tools.md): launchers, groups and generator expressions
- [Pin and freeze tag resolution](guides/pin-and-freeze.md): an index snapshot or per-platform digests
- [Use find_package with find_ocx](guides/find-package.md): find the CLI, or search a pulled package
- [Reproduce the build in CI](guides/ci.md): Linux, macOS and Windows with one configuration
- [Build behind a mirror or offline](guides/mirror.md): mirrors, credentials and no downloads
- [Cross-build with foreign-platform content](guides/cross-build.md): content for a platform other than the host
- [Update the vendored files](guides/update-vendored.md): refresh `ocx.cmake` and `Findocx.cmake`
- [Fix a failing configure](guides/nested-builds.md): nested builds, floating tags and stale locks

## Understand it

- [How find_ocx works](concepts/how-it-works.md)
- [Two entry points](concepts/entry-points.md)
- [Reproducible first](concepts/reproducible-first.md)
- [Lazy versus eager](concepts/lazy-vs-eager.md)

## Look it up

- [Commands](reference/commands.md), [variables](reference/variables.md) and [Findocx.cmake](reference/findocx.md)
- [Examples](reference/examples.md): the four tested projects in `examples/`
