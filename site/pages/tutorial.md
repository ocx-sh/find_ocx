---
title: Run jq in a CMake build without installing it
description: Add find_ocx to an empty CMake project and run a pinned jq from a build target, with nothing installed beyond CMake and the ocx CLI.
---
<!-- doc_type: tutorial -->
<!-- doc_tier: first-steps -->

In this tutorial you add find_ocx to an empty CMake project and run `jq` from a build target.
The build prints the `jq` version it ran.
You never install `jq`, and anyone who clones the project gets the same version.

You need CMake 3.25 or later and network access to the OCX registry or a mirror.
You also need the `ocx` CLI 0.6 or later ([install it](https://ocx.sh/install/)), once, to write the lock.

## Vendor the two files {#vendor-the-module}

Download `Findocx.cmake` and `ocx.cmake` from the [release assets](https://github.com/ocx-sh/find_ocx/releases).
Put both in a `cmake/` directory of an empty project.

Run `ls cmake`.
It lists `Findocx.cmake` and `ocx.cmake`.
Copying these files into your repository is the whole installation.

## Pin the tool {#pin-the-tool}

Create `ocx.toml` in the project root, next to the `CMakeLists.txt` you write in the next step.
It names the tools your build runs.

<!-- snippet: examples/tutorial/ocx.toml#tools -->

The tag `latest` is a moving target.
The lock step below freezes it to exact digests.

## Declare the project {#declare-the-project}

Create `CMakeLists.txt`.

<!-- snippet: examples/tutorial/CMakeLists.txt#full -->

The `include(ocx)` line is passive, so it defines commands and fetches nothing.
The `ocx_project` command reads `ocx.toml` and `ocx.lock`, and it exports `OCX_TOOLS_RUN`.
That variable is a plain CMake command list that runs a tool from the pinned toolchain.
The `show_jq` target uses it to run `jq --version` on every build.

## Lock, configure and build {#lock-configure-build}

Run three commands.
The first writes `ocx.lock`, and the second configures the project.
The third builds it, which runs `jq`.

<!-- snippet: site/casts/tutorial__first-configure.sh#cast -->

<!-- cast: tutorial/first-configure -->

The lock step prints a table with the index digest that pins `jq`.
The build ends with a line like `jq-1.8.2`.
Your paths, digests and timings differ from the recording.

That `jq` was fetched into the OCX store on first use and never reached your `PATH`.
The lock file fixes its version, so a rebuild on any machine prints the same line.
Run the configure command again.
With unchanged inputs find_ocx reports that the project is up to date and does not resolve or pull again.

`ocx lock` also warns about merge conflicts in your lock file.
Add the line `ocx.lock merge=union` to a `.gitattributes` file, so branches that both change the lock merge cleanly.

## What you built {#what-you-built}

You have a CMake project that runs a tool nobody installed, at a version the lock file fixes.
Commit `ocx.toml`, `ocx.lock` and the `cmake/` directory.
A teammate or a CI runner then builds with nothing installed beyond CMake.

## Next steps {#next-steps}

- [Add a tool to the project](guides/add-a-tool.md) to run more tools and keep rarely used ones in groups.
- [Pin and freeze tag resolution](guides/pin-and-freeze.md) to make `ocx_package` reproducible without a project file.
- [Read how find_ocx works](concepts/how-it-works.md) for what ran under the hood.
- [Fix a failing configure](troubleshooting/configure-errors.md) when a step above does not end as described.
