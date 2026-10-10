<!-- doc_type: troubleshooting -->
<!-- description: Fixes for a configure that fails on a stale lock, floating tag, nested launcher or BINS name. -->
# Fix a failing configure

Each entry below starts with the message you see, then names the cause and the fix.
A failing `ocx` call reports its exit status and ends with a `hint:` line.
[Exit codes](exit-codes.md) maps every status to a cause.
For a duplicate `NAME` or a second copy of the module, see [Fix a module conflict](module-conflicts.md).

## Error: the lock check fails with exit 65 {#stale-lock}

```text
error: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`
```

This issue occurs when `ocx.toml` changed after `ocx.lock` was written.
`ocx_project` runs `ocx lock --check` on every configure, which is an offline staleness gate:

<!-- snippet: tests/fixtures/stale_lock/CMakeLists.txt#stale-lock -->

Run `ocx lock` next to `ocx.toml`, review the diff and commit `ocx.lock`.

A missing lock file and a lock file of format version 2 both exit 78 with a message that says to run `ocx lock`.
A lock file in a format the configure's ocx does not know is rejected as well.
Compare `ocx version` with the binary the configure uses, as [Two entry points](../concepts/entry-points.md#which-binary) explains.
Then lock with that binary.

## Error: a floating tag stops the configure {#floating-tag}

```text
find_ocx: ocx_package DRIFTY: 'ocx.sh/jqlang/jq:latest' is floating and no index snapshot is in effect - resolution is not reproducible
```

This issue occurs when a package uses a floating tag such as `:latest`, and neither an index snapshot nor a digest fixes it:

<!-- snippet: tests/fixtures/floating_fatal.cmake#floating -->

find_ocx is [reproducible first](../concepts/reproducible-first.md), so it refuses to resolve the tag live.
Pick one fix:

- Commit an index snapshot. Run `ocx --index .ocx index update ocx.sh/jqlang/jq:latest` in the directory that holds `CMakeLists.txt`, then commit `.ocx`.
- Pin a digest. Use `PACKAGE ocx.sh/jqlang/jq@sha256:<index digest>`, or add `PINS`.
- Accept drift for one run. Configure with `-DOCX_ALLOW_FLOATING=ON`, which prints the digests that seed `PINS`.

[Pin and freeze tag resolution](../guides/pin-and-freeze.md) walks through the first two.
If the call stops earlier with `NAME and PACKAGE are required`, add `NAME`.
A one-line `ocx_package(PACKAGE ...)` copied from an article often lacks it.

## Error: a nested configure fails with the exit-81 refresh hint {#nested-configure}

```text
error: failed to find package: ocx.sh/jqlang/jq:latest — frozen mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:latest'; run `ocx index update` or pin a digest
```

This issue occurs when a find_ocx configure runs inside an ocx launcher, such as an `ExternalProject`, `ctest --build-and-test` or a superbuild.
The launchers `ocx exec`, `ocx package exec` and every `OCX_<NAME>_RUN` list export `OCX_FROZEN` and `OCX_INDEX` into child processes.
The inner configure stores those values as if you had set them, but the outer index does not list the inner packages.

Pass both variables empty to the nested configure.
An empty `OCX_INDEX` drops the inherited value without hiding a snapshot that the inner project commits itself.
The repository's own test harness does this for every fixture it configures:

<!-- snippet: tests/helpers.cmake#nested-opt-out -->

On a command line, append the same two options:

<!-- doc-norun: fragment, the options go on the command line of the nested configure -->

```console-norun
cmake -DOCX_FROZEN= -DOCX_INDEX= ...
```

<!-- /doc-norun -->

## Error: a BINS name does not resolve {#bins}

This issue occurs when `BINS` lists a name that the package or the selected groups do not expose.
The message names the unknown entry.

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
