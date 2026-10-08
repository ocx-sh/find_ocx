<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->
<!-- description: Find the ocx CLI with find_package(ocx), and make find_package search content that find_ocx pulled. -->
# Use find_package with find_ocx

Use this page to find the `ocx` CLI the classic way with `find_package(ocx)`, and to let a later `find_package(<name>)` search content that find_ocx provisioned.

## Find the ocx CLI

Use `find_package(ocx)` when a system `ocx` should win over the pinned bootstrap.
The module honors `-DOCX_EXECUTABLE`, searches `PATH`, and defines the `ocx::ocx` imported target.

--8<-- "examples/find_package/CMakeLists.txt" from="^cmake_minimum_required" title="examples/find_package/CMakeLists.txt"

Configure and test it. `-DOCX_BOOTSTRAP=ON` falls back to the pinned CLI when none is found.

```console
cmake -S . -B build -DOCX_BOOTSTRAP=ON && ctest --test-dir build
```

The module needs CMake 3.15, or 3.19 with `ocx.cmake` next to `Findocx.cmake` when you use the bootstrap.
To choose between this and `include(ocx)`, see [Two entry points](../concepts/entry-points.md).

## Make find_package search a pulled package

Pull a package at configure time with `PULL`.
find_ocx then sets `<name>_ROOT` to the package content root, following policy CMP0074.
A later `find_package(<name>)` or `find_library` call searches that content.

--8<-- "examples/package/CMakeLists.txt" from="^set\(OCX_ALLOW_FLOATING ON\)" to="^message" title="examples/package/CMakeLists.txt"

Add `NO_ROOT` to suppress the export.
To pull every package at configure time, for example in CI, configure with `-DOCX_PULL=ON`.

The example opts out of the floating-tag check on purpose.
In your project, freeze the tag first: see [Pin and freeze tag resolution](pin-and-freeze.md).

Needs addressed: problems 4 and 7 of the [use-case research](https://github.com/ocx-sh/find_ocx/blob/main/.agents/research/docs-use-cases.md).
