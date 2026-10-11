---
title: Move from 0.3 to 0.4
description: Fix the lines of your build files that find_ocx 0.4 breaks, in order, from the CMake floor to the removed PINS keyword and the ocx run rename.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

# Move from 0.3 to 0.4

Your project builds with find_ocx 0.3, and 0.4 changes several things at once.
The CMake floor rises, and the pinned `ocx` jumps from 0.3.11 to 0.6.5.
An exported `OCX_NO_VERIFY` or `OCX_ALLOW_YANKED` stops working, and `PINS` and `PLATFORM` lists are errors.
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

## Drop platform lists from main {#platform-list}

Release 0.3.0 only ever took one `PLATFORM` value, so this applies only if you tracked the main branch ([#2](https://github.com/ocx-sh/find_ocx/pull/2)) and wrote a list.
In 0.4, `PLATFORM` takes exactly one platform, because the `ocx` CLI accepts one `-p` value.
A list, whether written as several arguments or as a `;`-list in `OCX_DEFAULT_PLATFORM`, stops the configure.
Pick the platform you really need.

<!-- doc-norun: shows a rejected call, and the i3 tests platform_list_keyword and platform_list_quoted assert the same error -->
```diff
-ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:1.8.2 PLATFORM linux/arm64 linux/amd64)
+ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:1.8.2 PLATFORM linux/amd64)
```
<!-- /doc-norun -->

## Replace `PINS` with an index digest {#pins}

0.4 removes the `PINS` keyword of `ocx_package`.
A call that passes `PINS` stops the configure with `PINS was removed`, whether `PINS` stands before or after `BINS`.
`PINS` mapped a platform key to one leaf manifest digest and rewrote the reference by string match, so `ocx` never checked that the leaf fits the platform.
A wrong digest installed the wrong binary without a message, and a key such as `linux/amd64` cannot carry `+features`.

Pin the image index digest in `PACKAGE` instead, or commit an index snapshot.
One index digest covers every platform, and `ocx` selects the leaf for the building platform, features included.

<!-- doc-norun: shows a rejected call, and the i3 tests pins_removed and pins_after_bins assert the error -->
```diff
 ocx_package(
   NAME jq
-  PACKAGE ocx.sh/jqlang/jq:1.8.2
-  PINS
-    "linux/amd64=sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
-    "linux/arm64=sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
+  PACKAGE ocx.sh/jqlang/jq:1.8.2@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
 )
```
<!-- /doc-norun -->

[Pin an image index digest](pin-digests.md#read-digest) shows how to read the index digest of a tag.

## Move `OCX_NO_VERIFY` and `OCX_ALLOW_YANKED` into `ocx_policy` {#policy}

In 0.3, the ambient environment reached every `ocx` call.
A CI job that exported `OCX_ALLOW_YANKED=1` or `OCX_NO_VERIFY=1` resolved yanked versions or skipped verification.
In 0.4, both variables are removed from every call, and only `ocx_policy` sets them.
A job that still exports one of them fails to resolve the yanked tag, or enforces verification, with no message about the variable.

Search your CI definitions and scripts for both names.
Where the intent is deliberate, state it in the listfile, before the first `ocx_project` or `ocx_package`:

```cmake
ocx_policy(ALLOW_YANKED)
ocx_policy(ALLOW_UNVERIFIED)
```

[Apply organisation-wide download rules](policy-and-config.md) shows the command in use.
The other `OCX_*` variables keep their effect, in the classes that [Environment and config](../concepts/env-and-config.md) lists.

## Check the `.ocx/` snapshot {#index}

In 0.3, any `.ocx/` directory counted as an index snapshot.
In 0.4 it counts only when it holds a `config.json` or a `<registry>/p/` directory.
A `.ocx/` that holds only the `toolchain/` links that `ocx pull` renders is no snapshot, and a package behind it is floating again.
Regenerate a snapshot that an earlier CLI created with `ocx_index(UPDATE_COMMAND)`, because the leaves follow the layout of ocx 0.6.

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

From 0.4, a failed `ocx` call prints a hint for exit codes 64 to 87, and a download that fails with exit code 75 is retried twice.
[Exit codes](../troubleshooting/exit-codes.md) maps each code to its cause and fix.

## Adopt the new keywords {#new-keywords}

Nothing below is required.

- `CONFIG`, `NO_CONFIG` and `PATCH_SNAPSHOT` on `ocx_project` and `ocx_package` choose the `ocx` configuration and the patch snapshot per call.
- `ocx_policy` also takes `SIGSTORE_TRUSTED_ROOT`, in code and never from the environment.
- From 0.4, a changed `<name>_ROOT` also clears the cached `<name>_DIR`, so `find_package` stops answering with the old copy.

[Apply organisation-wide download rules](policy-and-config.md) shows the three in use.

## Check the result {#check}

Configure from a fresh build directory and read the first lines of the log.
The status line names the `ocx` that ran, as [Use an ocx you already installed](use-system-ocx.md#which) describes.
A build log without the `ocx run` rename warning shows that your files use the new verbs.

## Next steps {#next-steps}

- [Fix a failing configure](../troubleshooting/configure-errors.md) covers errors you meet on the way.
- [Pin and freeze tag resolution](pin-and-freeze.md) applies if you come from 0.2, where floating tags still resolved.
