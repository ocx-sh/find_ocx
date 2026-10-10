---
title: Make the build find provisioned content
description: Pull a package at configure time so find_package, find_library and find_program search the copy find_ocx provisioned, never the host copy.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

# Make the build find provisioned content

Your build needs a library or a tool that CMake locates with `find_package`, `find_library` or `find_program`.
Left alone, those commands return whatever the host has, so two machines build against two different copies and the log looks fine on both.
A README line that says "install it first" does not change that.
This page pulls the package at configure time and points the search at the provisioned content.

The example accepts a floating tag to stay short.
In your project, freeze the tag first with [Pin and freeze tag resolution](pin-and-freeze.md).

## Pull the package and export its root {#pull}

Add `PULL` to the `ocx_package` call.
find_ocx installs the package during configure and sets `<name>_ROOT` to the content root, following policy CMP0074.

<!-- snippet: examples/package/CMakeLists.txt#pull-root -->

The variable keeps the case of `NAME`, so this call sets `jq_ROOT`.
Add `NO_ROOT` to suppress the export.
To pull every package at configure time, for example in CI, configure with `-DOCX_PULL=ON`.

## Search with find_package or find_library {#find-package}

`find_package(<name>)` and the `find_*` calls inside find modules read `<name>_ROOT`.
They search the provisioned content first when the package ships a find module or a config file.

When the root changes, find_ocx also clears the cached `<name>_DIR`.
Without that, `find_package` would keep answering with the copy it found before.

A package that ships only a program has nothing for `find_package` to read.
`find_package(jq)` reports that jq is not found, even though the content is there.
Use `find_program` for such a package.

## Locate a program in the content {#find-program}

A top-level `find_program` ignores `<name>_ROOT`, so a plain `find_program(JQ_EXE jq)` returns the host `jq` when one exists.
Name the content root as a hint and turn off the default search paths.

<!-- snippet: examples/package/CMakeLists.txt#find-program -->

Where the program sits depends on the package.
For `jq` it is the content root, and many packages use a `bin` directory, so the call lists both.
The recording shows the plain call returning the host copy and the hinted call returning the provisioned one.

<!-- cast: guides-find-package/find-program -->

`find_program` stores its answer in the CMake cache.
After you change the pin, delete the entry with `-UJQ_EXE` or use a fresh build directory.

If you only need to run the tool, skip the search.
The `OCX_<NAME>_RUN` command list from `ocx_package` runs it from the pin, as [Add or change a pinned tool](add-a-tool.md) shows.

## Next steps {#next-steps}

- [Pin and freeze tag resolution](pin-and-freeze.md) fixes what the tag means.
- [Use an ocx you already installed](use-system-ocx.md) covers `find_package(ocx)`.
- [`ocx_package`](../reference/commands/ocx_package.md) lists every keyword.
