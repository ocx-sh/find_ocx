<!-- doc_type: explanation -->
<!-- doc_tier: everyday -->
<!-- description: The two ways CMake reaches ocx, include(ocx) and find_package(ocx), and which binary runs. -->
# Two entry points

This page explains the two ways a CMake project reaches ocx, `include(ocx)` and `find_package(ocx)`, and how find_ocx picks the binary that runs.

`include(ocx)` — **the provisioner.** The include itself is passive (definitions only); the first [`ocx_project`](/integrations/cmake/reference/commands/#ocx_project) / [`ocx_package`](/integrations/cmake/reference/commands/#ocx_package) call resolves the CLI and provisions through it.

`find_package(ocx REQUIRED)` — **the discoverer.** Classic find module: honors `-DOCX_EXECUTABLE`, searches `PATH`, checks the version via `find_package_handle_standard_args`, defines the `ocx::ocx` imported target. With `-DOCX_BOOTSTRAP=ON` it falls back to the bootstrap when nothing is found.

Which binary runs — first match wins, identical in both entry points:

1. The `OCX_EXECUTABLE` cache variable — set by you, by a previous `find_package(ocx)`, or by an earlier bootstrap. Both entry points honor it, so they compose in either order.
2. An `ocx` on `PATH`.
3. The pinned, sha256-verified bootstrap (version: `OCX_INSTALL_VERSION`, default: the embedded pin) — the default fallback under `include(ocx)`, the explicit `-DOCX_BOOTSTRAP=ON` opt-in under `find_package(ocx)`.

Two policy overrides: `-DOCX_BOOTSTRAP=ALWAYS` skips the `PATH` step — every developer and CI runner executes the identical pinned binary (hermeticity, the rules_ocx model). `-DOCX_BOOTSTRAP=OFF` forbids the implicit download for policy-strict environments: the configure fails with an actionable error unless step 1 or 2 provides a binary.

Vendoring only `ocx.cmake` is fully supported — `-DOCX_EXECUTABLE` plus `-DOCX_BOOTSTRAP=OFF` is the fully explicit mode. `Findocx.cmake` is the optional classic front door for projects that want `find_package` semantics and a system ocx to win.

To use the find module, see [Use find_package with find_ocx](../guides/find-package.md).
