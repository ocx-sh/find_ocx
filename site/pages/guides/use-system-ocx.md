---
title: Use an ocx you already installed
description: Make a configure run the ocx CLI that is installed on your machines, check which binary it picked, and find it with find_package(ocx).
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

# Use an ocx you already installed

Your developers and runners already have the `ocx` CLI, installed by your package manager or an image.
You want builds to use that copy and to know which one ran, not to download a second `ocx` on every fresh checkout.
This page makes a configure use the installed CLI, shows how to tell which binary it picked, and covers the classic `find_package(ocx)` entry point.

You need `ocx` installed on each machine.
The [installation page](https://ocx.sh/install/) lists the ways.

## Let the module pick up the CLI on PATH {#path}

Do nothing.
The first `ocx_project` or `ocx_package` call looks for the CLI in this order:

1. `OCX_EXECUTABLE`, when you set it.
2. An `ocx` on `PATH`.
3. A pinned CLI that find_ocx downloads into a per-machine cache.

Machines that have `ocx` stop at step 2 and download nothing.

## Tell which binary a configure runs {#which}

The first configure of a build tree names the choice in one status line.
It reads `find_ocx: using ocx from PATH (<path>) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead`, or `find_ocx: using bootstrapped ocx <version> (<path>)` when the pin was downloaded.
A later configure of the same tree reuses the cached answer and prints nothing, and so does an explicit `OCX_EXECUTABLE`.
The cache keeps the answer too, and `cmake -LA -N build` prints it as `OCX_EXECUTABLE`.
To read that binary's version, run `ocx version`, because the CLI has no `--version` flag.

## Name the binary yourself {#executable}

Set `OCX_EXECUTABLE` when several copies exist and one must win.
Pass `-DOCX_EXECUTABLE=/opt/ocx/bin/ocx`, or export the variable and the first configure stores it.

## Find the CLI with find_package {#find-package-ocx}

Use `find_package(ocx)` when your own CMake code runs `ocx`, for example in a custom command.
It honours `OCX_EXECUTABLE`, searches `PATH`, and defines the imported target `ocx::ocx`.
Point `CMAKE_MODULE_PATH` at the directory with your vendored `Findocx.cmake`, as the first line of the example does for this repository.

<!-- snippet: examples/find_package/CMakeLists.txt#find-ocx -->

Unlike `include(ocx)`, the find module does not download anything by default.
Add `-DOCX_BOOTSTRAP=ON` to fall back to the pinned CLI when none is found.
The recording configures the example and prints the version it found.

<!-- cast: guides-use-system-ocx/find-package-ocx -->

[Two entry points](../concepts/entry-points.md) compares the two ways to start.

## Forbid the download {#no-bootstrap}

Pass `-DOCX_BOOTSTRAP=OFF` on machines where configure must never download.
A missing CLI then stops the configure with this message:

```text
find_ocx: no ocx on PATH, OCX_EXECUTABLE is not set, and implicit bootstrap is disabled (OCX_BOOTSTRAP=OFF)
hint: install ocx on PATH or set OCX_EXECUTABLE to an ocx binary
```

An empty value, as in `-DOCX_BOOTSTRAP=`, counts as `OFF`.

## Run the pinned CLI everywhere {#always}

Pass `-DOCX_BOOTSTRAP=ALWAYS` to skip the `PATH` search.
Every machine then runs the identical pinned binary, which removes version differences between installs.
Use it when installed copies are old or unmanaged.

## Keep the installed CLI current {#versions}

find_ocx is tested against its pinned CLI version 0.6.5, which `OCX_INSTALL_VERSION` defaults to.
An `ocx` below 0.6.0 lacks verbs the module calls, and the configure then fails with exit code 64 and its hint.
Versions from 0.6.0 up to 0.6.5 are untested.
An `ocx` above 0.6.5 is expected to work until ocx removes a verb the module calls.
When in doubt, use `ALWAYS`.

## Next steps {#next-steps}

- [Build behind a mirror or offline](mirror.md) covers machines that cannot reach the download host.
- [Reproduce the build in CI](ci.md) pins one CLI for every runner.
- [`ocx_bootstrap`](../reference/commands/ocx_bootstrap.md) lists the bootstrap keywords.
