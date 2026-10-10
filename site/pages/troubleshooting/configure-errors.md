<!-- doc_type: troubleshooting -->
<!-- description: Fixes for a configure that fails on a stale lock, floating tag, nested launcher or BINS name. -->
# Fix a failing configure

Each entry below starts with the message you see, then names the cause and the fix.
A failing `ocx` call reports its exit status and ends with a `hint:` line.
[Exit codes](exit-codes.md) maps every status to a cause.
For a duplicate `NAME` or a second copy of the module, see [Fix a module conflict](module-conflicts.md).

## Error: the lock check fails {#stale-lock}

```log
find_ocx: checking <dir>/ocx.toml against its lockfile failed (exit 65): ocx --project <dir>/ocx.toml lock --check
ocx.lock does not match ocx.toml; run `ocx lock` to update it
hint: run 'ocx lock' next to <dir>/ocx.toml and commit the updated ocx.lock
```

This issue occurs when `ocx.toml` changed after `ocx.lock` was written, and the exit code is 65.
`ocx_project` runs `ocx lock --check` on every configure, which is an offline staleness gate:

<!-- snippet: tests/fixtures/stale_lock/CMakeLists.txt#stale-lock -->

Run `ocx lock` next to `ocx.toml`, review the diff and commit `ocx.lock`.

**A missing or unusable lock** gives exit 78 and these lines:

```log
find_ocx: checking <dir>/ocx.toml against its lockfile failed (exit 78): ocx --project <dir>/ocx.toml lock --check
ocx.lock not found at <dir>/ocx.lock; run `ocx lock` to create it
hint: no ocx.lock next to <dir>/ocx.toml, a version 2 lock, or unusable config - run 'ocx lock' and commit it, or read the message above
```

The first case is `ocx.toml` with no `ocx.lock` beside it.
A lock file of format version 2 gives the same exit code and a different second line:

```log
<dir>/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`
```

A lock file in a format that the configure's `ocx` does not know is rejected the same way.

Run `ocx lock` with the binary that the configure uses, then commit `ocx.lock`.
[Two entry points](../concepts/entry-points.md#which-binary) lists which binary that is.
On a machine with no `ocx`, [write the first lock with the downloaded CLI](../guides/add-a-tool.md#bootstrapped-lock).

## Error: a floating tag stops the configure {#floating-tag}

```log
find_ocx: ocx_package DRIFTY: 'ocx.sh/jqlang/jq:latest' is floating and no index snapshot is in effect - resolution is not reproducible
fix (pick one): commit a snapshot ('ocx --index .ocx index update ocx.sh/jqlang/jq:latest' next to your CMakeLists, or set OCX_INDEX); pin digests with PINS or @sha256:; or accept drift explicitly with -DOCX_ALLOW_FLOATING=ON
```

This issue occurs when a package uses a floating tag such as `:latest`, and neither an index snapshot nor a digest fixes it:

<!-- snippet: tests/fixtures/floating_fatal.cmake#floating -->

find_ocx is [reproducible first](../concepts/reproducible-first.md), so it refuses to resolve the tag live.
Pick one fix:

- Commit an index snapshot. Run `ocx --index .ocx index update ocx.sh/jqlang/jq:latest` in the directory that holds `CMakeLists.txt`, then commit `.ocx`.
- Pin a digest. Use `PACKAGE ocx.sh/jqlang/jq@sha256:<index digest>`, or add `PINS`.
- Accept drift for one run. Configure with `-DOCX_ALLOW_FLOATING=ON`. A `PULL` call then prints a `PINS` line with the digest, and a lazy call only warns that the tag can drift.

[Pin and freeze tag resolution](../guides/pin-and-freeze.md) walks through the first two.
If the call stops earlier with `NAME and PACKAGE are required`, add `NAME`.
A one-line `ocx_package(PACKAGE ...)` copied from an article often lacks it.

## Error: a nested configure fails with the exit-81 refresh hint {#nested-configure}

```log
find_ocx: installing ocx.sh/kitware/cmake:3.31 failed (exit 81): ocx --index <outer index> --frozen --format json package install ocx.sh/kitware/cmake:3.31
failed to install package: ocx.sh/kitware/cmake:3.31 — frozen mode refused to resolve unpinned reference 'ocx.sh/kitware/cmake:3.31'; run `ocx index update` or pin a digest
hint: package not in the committed index snapshot - refresh it with 'ocx --index <outer index> index update ocx.sh/kitware/cmake:3.31'
```

This issue occurs when a find_ocx configure runs inside an ocx launcher, such as an `ExternalProject`, `ctest --build-and-test` or a superbuild.
A launcher that runs with an index or in frozen mode exports `OCX_FROZEN` and `OCX_INDEX` into child processes.
That covers `ocx package exec --frozen` and every `OCX_<NAME>_RUN` list of an `ocx_package` that has an index snapshot.
The inner configure stores those values as if you had set them, but the outer index does not list the inner packages.
A launcher without an index or frozen mode, such as `ocx exec` for a project, exports neither variable.

Pass both variables empty to the nested configure.
An empty `OCX_INDEX` drops the inherited value without hiding a snapshot that the inner project commits itself.
The repository's own test harness does this for every fixture it configures:

<!-- snippet: tests/helpers.cmake#nested-opt-out -->

On a command line, append the same two options:

<!-- doc-norun: fragment, the options go on the command line of the nested configure -->

```bash-norun
cmake -DOCX_FROZEN= -DOCX_INDEX= ...
```

<!-- /doc-norun -->

## Error: a BINS name does not resolve {#bins}

```log
find_ocx: ocx_project TOOLS (<dir>/ocx.toml): BINS jqq: not a declared binary or entrypoint
declared: jq
hint: BINS names are executable names, check the spelling
```

This issue occurs when `BINS` lists a name that the package or the selected groups do not expose.
The message names the unknown entry and lists the names that are declared.
`ocx_package` prints the same message with its package reference in place of the `ocx.toml` path.

A name that exists only in a group that you did not select gets a different message:

```log
find_ocx: ocx_project TOOLS (<dir>/ocx.toml): BINS shellcheck: declared only in a group that was not requested
hint: add the group to GROUPS (the [tools] table is the group 'default'), e.g.  GROUPS default <group>
```

Two causes cover most cases:

- The name is misspelled. Compare it with the names that the package exposes.
- The tool lives in a group other than the default one. `ocx_project` selects only the default group unless `GROUPS` lists more, so `GROUPS lint` alone also drops the top-level tools.

Name the default group next to the others:

<!-- doc-norun: fragment, it needs a lint group in ocx.toml -->

```cmake-norun
ocx_project(NAME TOOLS GROUPS default lint BINS jq shellcheck)
```

<!-- /doc-norun -->

find_ocx checks `BINS` against the packages for this reason.
Without the check, a copy of the tool on the host `PATH` would hide the mistake and the build would pass on your machine only.

Two cases skip the check and print a status line instead:

```log
find_ocx: <what>: BINS not validated (OCX_OFFLINE and the package is not in the local store)
find_ocx: <what>: BINS <names> not validated (the package does not declare all of its binaries)
```

A skipped check means a wrong name fails later, when a build step runs the tool.
