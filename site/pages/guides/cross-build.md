<!-- doc_type: how-to -->
<!-- doc_tier: integration -->
<!-- description: Provision content for a platform other than the host from the same lock, for cross builds. -->
# Cross-build with foreign-platform content

Use `PLATFORM` to provision a package or a project toolchain for a platform other than the host, for example to bundle `linux/arm64` content.

## Request a foreign platform

Pass `PLATFORM` to `ocx_package` or `ocx_project`.
The default comes from `OCX_DEFAULT_PLATFORM`, and empty means the host.

The commands below come from the `foreign_platform` test fixture, which runs in find_ocx's own test suite.

--8<-- "tests/fixtures/foreign_platform/CMakeLists.txt" from="^set\(OCX_ALLOW_FLOATING ON\)" to="^ocx_package" title="tests/fixtures/foreign_platform/CMakeLists.txt"

## Read the exported content

A foreign platform exports content, not commands.
Foreign binaries cannot execute, so `OCX_<NAME>_RUN` is not defined and passing `BINS` is an error.

Use these variables instead:

- `OCX_<NAME>_PATHS` lists the content paths.
- `OCX_<NAME>_ENV_<KEY>` holds each environment value the package sets.

The fixture checks that the paths exist.

--8<-- "tests/fixtures/foreign_platform/CMakeLists.txt" from="^foreach" to="^endforeach" title="tests/fixtures/foreign_platform/CMakeLists.txt"

The harness runs this fixture on Linux hosts only.
For the signatures, see [`ocx_project` and `ocx_package`](../reference/commands.md).
Needs addressed: problem 6 of the [use-case research](https://github.com/ocx-sh/find_ocx/blob/main/.agents/research/docs-use-cases.md).
