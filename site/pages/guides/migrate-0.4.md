---
title: Move from 0.3 to 0.4
description: Fix the lines of your build files that find_ocx 0.4 breaks, in order, from the CMake floor to the removed platform list and ocx run.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

# Move from 0.3 to 0.4

Your project builds with find_ocx 0.3, and 0.4 changes several things at once.
The CMake floor rises, the pinned `ocx` jumps from 0.3.11 to 0.6.5, and a platform list that worked in 0.3 is an error in 0.4.
This page lists each break in the order to fix it, so the upgrade lands in one change.
The [changelog](https://github.com/ocx-sh/find_ocx/blob/main/CHANGELOG.md) has the full list of changes.

## Update the vendored files {#update-files}

Move `ocx.cmake` and `Findocx.cmake` to the 0.4 release together, with the script-mode update in [Update the vendored files](update-vendored.md).
Remove a `-DOCX_INSTALL_VERSION` that pins an old CLI.
A 0.3 CLI cannot read the lock files that 0.6.5 writes.

## Run CMake 3.25 or later {#cmake-floor}

In 0.4 the module stops at include time on any CMake below 3.25.
The 0.3 floor was 3.19 for `ocx.cmake` and 3.15 for `Findocx.cmake`.
CI legs that run CMake 3.24 or below need a 3.25 binary.
Your own `cmake_minimum_required` can stay as it is.

## Regenerate locks {#locks}

The pinned `ocx` writes lock files with `lock_version = 3`, and it rejects version 2 with exit code 78.
Run `ocx lock` next to each `ocx.toml` with an `ocx` of version 0.6 or later, and commit the new `ocx.lock`.

## Replace platform lists {#platform-list}

In 0.4, `PLATFORM` takes exactly one platform, because the `ocx` CLI accepts one `-p` value.
A list, whether written as several arguments or as a `;`-list in `OCX_DEFAULT_PLATFORM`, stops the configure.
Pick the platform you really need.

```diff
-ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:1.8.2 PLATFORM linux/arm64 linux/amd64)
+ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:1.8.2 PLATFORM linux/amd64)
```

`PINS` still takes one digest per platform, so a project that pins digests for five platforms keeps its call.

## Replace deprecated ocx verbs {#verbs}

The command lists that find_ocx exports, such as `OCX_<NAME>_RUN`, call `ocx exec` from 0.4 on, so they need no change.
Your own files do.
Search your CMake files, scripts and CI definitions for `ocx run`, and replace it with `ocx exec`.
The CLI prints a rename warning for `ocx run` today and removes it in ocx 0.7.
`ocx package run` is already gone, so use `ocx package exec`, and the `package describe` and `package info` subcommands are deprecated too.

## Fix `BINS` names {#bins}

`BINS` entries are checked against the executables that the selected packages provide.
A typo, or a name from a group you did not select in `GROUPS`, stops the configure and lists the declared names.
Fix the name, or add the group as shown in [Add or change a pinned tool](add-a-tool.md#select-group).
A package that does not list all its executables skips the check.

## Read the new exit-code hints {#hints}

From 0.4, a failed `ocx` call prints a hint for exit codes 64 to 87, and a transient failure with exit code 75 is retried twice.
[Exit codes](../troubleshooting/exit-codes.md) maps each code to its cause and fix.

## Adopt the new keywords {#new-keywords}

Nothing below is required, and your 0.3 calls keep working.

- `CONFIG`, `NO_CONFIG` and `PATCH_SNAPSHOT` on `ocx_project` and `ocx_package` choose the `ocx` configuration and the patch snapshot per call.
- `ocx_policy` sets download rules such as `ALLOW_UNVERIFIED`, `ALLOW_YANKED` and `SIGSTORE_TRUSTED_ROOT` in code, never from the environment.
- From 0.4, a changed `<name>_ROOT` also clears the cached `<name>_DIR`, so `find_package` stops answering with the old copy.

[Apply organisation-wide rules](policy-and-config.md) shows the three in use.

## Check the result {#check}

Configure from a fresh build directory and read the first lines of the log.
The status line names the `ocx` that ran, as [Use an ocx you already installed](use-system-ocx.md#which) describes.
A build log without the `ocx run` rename warning shows that your files use the new verbs.

## Next steps {#next-steps}

- [Fix a failing configure](../troubleshooting/configure-errors.md) covers errors you meet on the way.
- [Pin and freeze tag resolution](pin-and-freeze.md) applies if you come from 0.2, where floating tags still resolved.
