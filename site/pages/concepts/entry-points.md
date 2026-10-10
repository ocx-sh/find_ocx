<!-- doc_type: explanation -->
<!-- description: The two ways CMake reaches ocx, include(ocx) and find_package(ocx), which binary runs, and which ocx version to expect. -->
# Two entry points

This page explains the two ways a CMake project reaches ocx, `include(ocx)` and `find_package(ocx)`, and how find_ocx picks the binary that runs.
Knowing the order lets you tell, before a configure, which `ocx` it will execute.

## include(ocx): the provisioner {#include-ocx}

`include(ocx)` is passive.
It defines commands and fetches nothing.
The first `ocx_project` or `ocx_package` call resolves the CLI and provisions through it.
Use this entry point when the build should fetch what it needs.

## find_package(ocx): the discoverer {#find-package-ocx}

`find_package(ocx REQUIRED)` is a classic find module.
It honors `-DOCX_EXECUTABLE`, searches `PATH` and checks the version through `find_package_handle_standard_args`.
It then defines the `ocx::ocx` imported target and `OCX_VERSION_STRING`.
With `-DOCX_BOOTSTRAP=ON` it falls back to the bootstrap when it finds nothing.

<!-- snippet: examples/find_package/CMakeLists.txt#find-package -->

Use this entry point when a system `ocx` should win, or when you only need the binary as a target.

## Which binary runs {#which-binary}

The first match wins, in both entry points.

| Order | Source | Notes |
|---|---|---|
| 1 | The `OCX_EXECUTABLE` cache variable | You set it, a previous `find_package(ocx)` set it, or an earlier bootstrap set it. Both entry points honor it, so they compose in either order. |
| 2 | An `ocx` on `PATH` | The configure log prints `using ocx from PATH` and the path. |
| 3 | The pinned bootstrap | A sha256-verified download of `OCX_INSTALL_VERSION`, which defaults to the pin embedded in `ocx.cmake`. |

The entry points differ only in the default for step 3:

| `OCX_BOOTSTRAP` | `include(ocx)` | `find_package(ocx)` |
|---|---|---|
| unset | Bootstraps when steps 1 and 2 find nothing. | Never bootstraps, so `REQUIRED` fails. |
| `ON` | Same as unset. | Bootstraps when steps 1 and 2 find nothing. |
| `ALWAYS` | Skips step 2, so every machine runs the identical pin. | Same. |
| `OFF` | Fails the configure unless step 1 or 2 finds a binary. | Same as unset. |

`OCX_EXECUTABLE` plus `-DOCX_BOOTSTRAP=OFF` is the fully explicit mode.
It needs only `ocx.cmake` vendored, because `Findocx.cmake` is the optional front door.

To see which binary a configure used, read `OCX_EXECUTABLE` in `CMakeCache.txt`, then run that binary with `version`.
The CLI rejects `ocx --version`.

## Which ocx version to expect {#supported-range}

Each find_ocx release is built and tested against one ocx release, the embedded pin.
A bootstrap always runs that pin.

A `PATH` ocx is used as it is, so its version may differ from the pin.
find_ocx calls `ocx exec`, `ocx package exec` and `ocx inspect --closure`.
Those commands exist since ocx 0.6.0, so an earlier binary fails with exit 64.
A lock file in a format the binary does not know fails with exit 78.
[Exit codes](../troubleshooting/exit-codes.md) maps both to a fix.

Set `OCX_BOOTSTRAP=ALWAYS` when every developer and CI runner must run the tested binary.
To use a system ocx on purpose, see [Use a system ocx](../guides/use-system-ocx.md).
