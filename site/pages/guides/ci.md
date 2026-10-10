---
title: Reproduce the build in CI
description: Run the same pinned ocx and the same locked tools on Linux, macOS and Windows CI runners as on a laptop.
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

A build passes on your laptop and fails on a CI runner because the two machines carry different tool versions.
A README line such as "install jq 1.7 first" cannot prevent that, and `FetchContent` or CPM fetch sources to compile, not a pinned `jq` for a custom command.

This page sets up a CI job that runs the same `ocx` and the same locked tools on Linux, macOS and Windows.
The job fails at configure time when a tool is missing or the lock is stale.
It assumes a project that already calls `ocx_project` or `ocx_package`, as in the [tutorial](../tutorial.md).

## Run one ocx on every runner {#same-ocx}

By default find_ocx uses an `ocx` found on `PATH` and downloads its pinned one only when there is none.
A runner image can therefore carry a different `ocx` than your laptop.

Configure with `-DOCX_BOOTSTRAP=ALWAYS`.
The `PATH` search is skipped, so every runner downloads and runs the identical sha256-verified binary.
Add `-DOCX_INSTALL_VERSION=<version>` to choose a version other than the one pinned by your find_ocx release.

The tool versions come from `ocx.lock`, not from the CLI.
`ocx.lock` stores one digest per tool and platform, so all three runners pull the same bytes.

## Fetch every tool during configure {#pull-at-configure}

Add `-DOCX_PULL=ON`.
Every `ocx_project` and `ocx_package` call then installs its content while CMake configures, instead of when a build step first runs the tool.
A package that does not resolve fails the `Configure` step, and the cache holds the content before the build starts.

`ocx_project` also runs `ocx lock --check` on every configure.
When `ocx.toml` changed and `ocx.lock` did not, the job fails with exit code 65 and the instruction to run `ocx lock` and commit the result.
The [exit codes](../troubleshooting/exit-codes.md) page lists every code the module reports.

## Keep the caches between runs {#cache}

find_ocx writes to two places.

- The ocx store, which holds installed packages. It is `~/.ocx` unless `OCX_HOME` names another directory.
- The bootstrap cache, which holds the downloaded `ocx`. It is per machine unless `OCX_BOOTSTRAP_CACHE` names another directory.

Home directories on hosted runners are not always writable or stable.
Point both variables into the workspace and restore that directory with your CI cache, keyed on `ocx.lock`.
A changed lock then produces a fresh cache, and an unchanged one skips every download.

## Prove that the build works offline {#offline}

Configure a second, empty build directory with `OCX_OFFLINE=1` after the first configure.
It succeeds only if the store holds everything the build needs, so a hidden download shows up as a failed job.

## Put it together {#workflow}

This GitHub Actions workflow applies all four settings on three operating systems.

<!-- snippet: examples/ci/github-actions.yml#workflow -->

find_ocx's own lint step checks the file with `actionlint`.
The same flags work in any CI system, because they are plain CMake and environment settings.

A leg that cannot reach the registry exits with code 69 or 75.
`ocx.cmake` retries a temporary failure (75) twice before it gives up.

For every variable on this page, see the [variable reference](../reference/variables.md).

## Next steps {#next-steps}

- [Build behind a mirror or offline](mirror.md) when the runners cannot reach the public hosts.
- [Pin and freeze tag resolution](pin-and-freeze.md) for packages without a project file.
- [Exit codes](../troubleshooting/exit-codes.md) to map a failed job to its cause.
