---
title: Add or change a pinned tool
description: Add a tool to ocx.toml, refresh ocx.lock and select its group in CMake, so every teammate and CI runner builds with the same copy.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

# Add or change a pinned tool

A build needs one more command-line tool, say `shellcheck`, and every machine has a different copy or none.
A README line that says "install shellcheck first" drifts, and `find_program` takes whatever the host offers.
FetchContent and CPM fetch sources to compile, and vcpkg and Conan centre on libraries built with your toolchain.
Pinning one prebuilt tool for one build step is not what they are built for.
This page adds the tool to `ocx.toml`, refreshes `ocx.lock` and selects the tool in CMake, so a teammate who pulls the change gets the same copy.

You need a project that already calls `ocx_project`, as in the [tutorial](../tutorial.md).
You also need an `ocx` CLI on the machine that writes the lock, or the CLI that find_ocx downloads, as the [next section](#bootstrapped-lock) shows.
Machines that only build do not need one.

## Add the tool to a group {#edit-toml}

Put a tool every target uses under `[tools]`.
Put a tool that few targets use in its own group, here `lint`.

<!-- snippet: examples/project/ocx.toml -->

The tools under `[tools]` form the group named `default`.

## Refresh the lock and commit it {#refresh-lock}

Run `ocx lock` in the directory that holds `ocx.toml`.
The lock records the digest of every tool on every platform.
Commit `ocx.toml` and `ocx.lock` together.

If you skip this step, the next configure stops with exit code 65 and names the command to run.
The recording shows that failure and the repair.

<!-- cast: guides-add-a-tool/stale-lock -->

`ocx lock` also asks you to add one line to `.gitattributes`.
Add it, so two branches that each add a tool merge without a conflict in the lock.

```text
ocx.lock merge=union
```

## Write the first lock without an installed ocx {#bootstrapped-lock}

A configure checks the lock and never writes it.
A project with an `ocx.toml` and no `ocx.lock` therefore stops the first configure with exit code 78 and this message:

```text
ocx.lock not found at <path>/ocx.lock; run `ocx lock` to create it
```

On a machine with no `ocx`, that stop comes after the configure has downloaded the pinned CLI, and `OCX_EXECUTABLE` in the cache names it.
Run that binary to write the lock, then configure again.
The recording runs the three commands on a machine with no `ocx`.

<!-- cast: guides-add-a-tool/bootstrapped-lock -->

`cmake -L -N build` prints the cache entry `OCX_EXECUTABLE`, and the `sed` filter keeps its value.
The command substitution needs a POSIX shell.
On Windows, copy the path from the `OCX_EXECUTABLE:FILEPATH=` line and run `<path> lock` in the directory of `ocx.toml`.

The CLI that wrote the lock is the one the next configure runs, so both agree on the lock format.
A lock that a different `ocx` wrote can fail with exit code 78, as [Fix a failing configure](../troubleshooting/configure-errors.md#stale-lock) describes.

## Select the group in CMake {#select-group}

`ocx_project` provisions the `default` group unless you name groups.
Name `default` next to each extra group, or the top-level tools leave the environment.
`BINS` lists the executables you want as variables, so the call below exports `OCX_DEV_RUN_SHELLCHECK` and `OCX_DEV_RUN_JQ`.

<!-- snippet: examples/project/CMakeLists.txt#combined-groups -->

Use the variable anywhere CMake takes a command list, as the test above does.
The command resolves `shellcheck` from the locked group, never from the host `PATH`.

A `BINS` name that the selected groups do not provide stops the configure.
The error names the entry and lists the names that are declared, so a typo or a forgotten group shows up at once.

<!-- cast: guides-add-a-tool/bins-typo -->

## Keep a group out of the default environment {#lazy-group}

Give the group its own `ocx_project` call when only one target needs it.
The group costs nothing until someone builds that target.

<!-- snippet: examples/project/CMakeLists.txt#lazy-group -->

## Check that the pin runs {#verify}

Configure, build and test the project.
The `shellcheck_hello` test passes on a machine whose `PATH` has no `shellcheck`, because the launcher puts the locked copy first.
A teammate gets the new tool by pulling and configuring, with no install step.

## Leave `.ocx/toolchain` out of version control {#toolchain-dir}

The first run creates `.ocx/toolchain` next to `ocx.toml`.
It holds links into the local store and carries its own `.gitignore`, so git skips it without a rule from you.
It is not the committed `.ocx/` index snapshot of [Pin and freeze tag resolution](pin-and-freeze.md), which holds a `<registry>/p/` directory instead.

## Next steps {#next-steps}

- [Pin and freeze tag resolution](pin-and-freeze.md) freezes floating tags for `ocx_package`.
- [Fix a failing configure](../troubleshooting/configure-errors.md) maps an error to its cause.
- [`ocx_project`](../reference/commands.md#ocx_project) lists every keyword.
