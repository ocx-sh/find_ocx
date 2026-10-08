<!-- doc_type: tutorial -->
<!-- doc_tier: first-steps -->
<!-- description: Add find_ocx to a CMake project and run a pinned jq from a build target without installing it. -->
# Run jq in a CMake build without installing it

In this tutorial you add find_ocx to a CMake project and run `jq` from a build target.
You never install `jq` on your machine.

You need CMake 3.19 or later.
You also need the `ocx` CLI once, to write the lock file ([install it](https://ocx.sh/install/)).
find_ocx downloads its own pinned `ocx` for the build.

## Vendor the two files

Download `Findocx.cmake` and `ocx.cmake` from the [release assets](https://github.com/ocx-sh/find_ocx/releases).
Put both in a `cmake/` directory of an empty project.

Check that `cmake/ocx.cmake` and `cmake/Findocx.cmake` exist next to where your `CMakeLists.txt` will be.

## Pin the tool

Create `ocx.toml` next to the `cmake/` directory.

--8<-- "examples/project/ocx.toml" from="^\[tools\]" to="^jq =" title="ocx.toml"

Write the lock file and keep both files in version control.

```console
ocx lock
```

Check that `ocx.lock` exists. It holds the exact digest of `jq`.

## Declare the project

Create `CMakeLists.txt` with the project header.

--8<-- "examples/project/CMakeLists.txt" from="^cmake_minimum_required" to="^project" title="CMakeLists.txt"

Add the vendored directory to the module path and include the module.

--8<-- "README.md" from="^list\(APPEND CMAKE_MODULE_PATH" to="^include\(ocx\)" title="CMakeLists.txt"

The include is passive.
It defines commands and fetches nothing yet.

## Run jq from a target

Add the toolchain and a target that runs `jq` on every build.
`ocx_project` reads `ocx.toml` and `ocx.lock`, and `OCX_TOOLS_RUN` is the command that runs a tool from that toolchain.

--8<-- "examples/project/CMakeLists.txt" from="^# The ocx.toml next to this file" to="^\)$" title="CMakeLists.txt"

## Configure and build

Configure the project.

```console
cmake -S . -B build
```

The first configure downloads the pinned `ocx` into a per-machine cache and checks that `ocx.lock` is current.
It does not download `jq` yet.

Build the project.

```console
cmake --build build
```

The build runs the `validate` target, which materializes `jq` on first execution and then runs it.
The build ends without an error.
Run the configure command again: with unchanged inputs, no `ocx` process starts at all.

## What you built

You have a CMake project that runs a tool nobody installed, at a version the lock file fixes.
Anyone who clones the project gets the same `jq`.

Next steps:

- [Run workspace tools from ocx.toml](guides/workspace-tools.md) to add more tools and groups.
- [Pin and freeze tag resolution](guides/pin-and-freeze.md) to use `ocx_package` without a project file.
- [How find_ocx works](concepts/how-it-works.md) for what ran under the hood.
