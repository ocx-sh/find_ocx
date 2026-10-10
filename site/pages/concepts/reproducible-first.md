<!-- doc_type: explanation -->
<!-- description: Why a floating tag without a snapshot or digest is a hard error, and how locks, index snapshots and digest pins keep resolution fixed. -->
# Reproducible first

This page explains why find_ocx fails a configure on an unpinned floating tag, and how locks, index snapshots and digest pins keep resolution fixed.

## Why a floating tag is an error {#why-hard-error}

A floating tag such as `:latest` or `:3.31` names whatever the registry holds today.
Two machines, or the same machine a week apart, can resolve it to different bytes.
A configure that works today and changes tomorrow is harder to debug than one that stops at once.
So find_ocx refuses to resolve a floating tag live.
The configure fails unless something fixes what the tag means.

## Three ways to fix a tag {#ways-to-pin}

| Pin | Where it lives | What it fixes | How you refresh it |
|---|---|---|---|
| Lock file | `ocx.lock` next to `ocx.toml` | Every tool of `ocx_project`, per platform | `ocx lock`, then commit |
| Index snapshot | A committed `.ocx/` directory | Every tag of `ocx_package` that the snapshot lists | `ocx_index(UPDATE_COMMAND)`, then commit |
| Digest | `@sha256:` in `PACKAGE`, or `PINS` | One reference | Edit the digest by hand |

An `@sha256:` digest of the image index pins all platforms at once.
`PINS` maps each platform to its own manifest digest, and stays valid when you need that granularity.
For one pinned line that works on every platform, prefer `PACKAGE ocx.sh/jqlang/jq@sha256:<index digest>`.

## The index ladder {#index-ladder}

An index snapshot is a directory of `<registry>/p/<repo>.json` files that the CLI owns.
You commit it like a lock file.
Each `ocx_package` finds its snapshot in this order:

1. The `INDEX <dir>` argument.
2. The `OCX_INDEX` variable.
3. The nearest `.ocx/` directory between the calling directory and the last `project()` source directory.

`NO_INDEX` skips all three.
A `.ocx/` directory counts only when it holds a `config.json` or a `<registry>/p/` directory.
The `.ocx/toolchain` directory that `ocx_project` writes is therefore never mistaken for a snapshot.
A vendored subproject with its own `project()` gets its own bound, so snapshots do not leak across projects.

`ocx_index(FIND REQUIRED)` runs that discovery once, fails fast when nothing is committed, and locks the result into `OCX_INDEX`.

<!-- snippet: examples/frozen_index/CMakeLists.txt#frozen-index -->

## Snapshots never refresh themselves {#deliberate-refresh}

`ocx_index(UPDATE_COMMAND <var>)` composes the refresh command and leaves it to you to run.
A build target, a script or a CI job that opens a pull request all work.
Nothing runs it on its own, because a refresh that runs by itself would hide drift instead of showing it.
Run the command, review the diff of the `.ocx/` files and commit.

The refresh command runs without `OCX_FROZEN`, because `ocx index update` cannot run in frozen mode.
It names the tags your calls use.
By hand, a bare `ocx --index .ocx index update <repo>` records every tag of the repository, and `<repo>:<tag>` records only that tag.

## The frozen configure {#frozen-configure}

A frozen configure is the freshness gate.
Set `OCX_FROZEN=1`, and every `ocx` call resolves only from the lock, the snapshot or a digest.
A tag the snapshot does not list stops the configure with exit 81 when the call has `BINS` or `PULL`, because those run `ocx` at configure time:

```text
find_ocx: inspecting ocx_package X (ocx.sh/jqlang/jq:9.9.9) failed (exit 81): ocx --index <dir>/.ocx --frozen --format json package inspect --closure ocx.sh/jqlang/jq:9.9.9
failed to inspect package: ocx.sh/jqlang/jq:9.9.9 — frozen mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:9.9.9'; run `ocx index update` or pin a digest
hint: package not in the committed index snapshot - refresh it with 'ocx --index <dir>/.ocx index update ocx.sh/jqlang/jq:9.9.9'
```

A lazy call without `BINS` runs no `ocx` at configure time, so the same refusal comes at the first build step that runs the tool.

`OCX_FROZEN` is a site variable.
The first configure of a build directory snapshots it into the cache, so use a fresh build directory to try it.
[Environment and config](env-and-config.md#site) explains the stickiness.

A package with an index in effect already carries `--index <dir> --frozen` in its `OCX_<NAME>_RUN` list.
Setting `OCX_FROZEN` extends the same rule to the configure itself.
To prepare an offline build, fetch with `PULL` while online, as [Lazy versus eager](lazy-vs-eager.md#offline) shows.

## Where the digests are visible {#digests}

The snapshot files hold every digest, and the lock file holds those of a project.
An eager install of a floating tag also logs a line that suggests the `PINS` entry for your platform.
A lazy configure of a floating tag only warns that the tag can drift, and it prints no digest.

The escape hatch is `-DOCX_ALLOW_FLOATING=ON`, which downgrades the error to a drift warning.
It is useful for one run, to print the digests that seed `PINS`.

## Related pages {#related}

- [Pin and freeze tag resolution](../guides/pin-and-freeze.md) sets this up step by step.
- [Error: a floating tag stops the configure](../troubleshooting/configure-errors.md#floating-tag) fixes the failure.
- [Lazy versus eager](lazy-vs-eager.md) explains when the network is touched.
