<!-- doc_type: readme -->

# find_ocx

CMake support for [OCX](https://ocx.sh) — the OCI-backed package manager.
Two copy-and-own files bootstrap a pinned, sha256-verified `ocx` CLI and
provision development tools through it.
Tools arrive as command-list launchers, as content roots for `find_package`,
or as foreign-platform content.

find_ocx deliberately **never re-implements OCX internals in CMake**. All
resolution goes through the `ocx` binary; the durable contracts are
`ocx.lock` digests and the OCI manifests.

## Quick start

Vendor `Findocx.cmake` + `ocx.cmake` from the
[release assets](https://github.com/ocx-sh/find_ocx/releases) into your
repository (e.g. `cmake/`):

```cmake
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)

# Flagship: the workspace toolchain from ./ocx.toml + ./ocx.lock (lazy).
ocx_project(BINS jq)
add_custom_command(
  OUTPUT pretty.json
  COMMAND ${OCX_PROJECT_RUN_JQ} . ${CMAKE_SOURCE_DIR}/data.json > pretty.json
)

# Ad-hoc: a single package. PULL exports jq_ROOT (CMP0074) so a following
# find_package/find_library searches the OCX-provisioned content.
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest PULL)
```

No ocx installation required: the pinned CLI is bootstrapped at first
configure (per-machine cache, manifest sha256 enforced). The classic find
module works too — `find_package(ocx REQUIRED)`, with `-DOCX_BOOTSTRAP=ON`
for the same zero-setup behavior.

Requires CMake **3.25** (`Findocx.cmake` alone works on 3.15). Script mode
(`cmake -P`) is fully supported.

## Documentation

Guides, concepts and the command and variable reference are at
<https://ocx.sh/integrations/cmake/>.

## Examples

- [`examples/project`](examples/project) — workspace toolchain: zero-arg
  `ocx_project()`, group launchers, genexes in commands, ctest usage
- [`examples/package`](examples/package) — ad-hoc jq: floating + eager,
  digest-pinned + lazy, `<name>_ROOT`
- [`examples/frozen_index`](examples/frozen_index) — a committed `.ocx/`
  snapshot and a deliberate refresh target
- [`examples/find_package`](examples/find_package) — classic
  `find_package(ocx)` discovery

## Testing

The harness dogfoods find_ocx.
The CMake versions under test are provisioned as OCX packages
(`ocx.sh/kitware/cmake:<tag>`) through `ocx_package()` itself, and each fixture runs on every version via
`ctest --build-and-test` — on Linux, macOS, and Windows.

```sh
ocx run -- task verify
```

## License

Apache-2.0. See [LICENSE](LICENSE).
