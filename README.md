# find_ocx

CMake support for [OCX](https://ocx.sh) — the OCI-backed package manager.
Two copy-and-own files bootstrap a pinned, sha256-verified `ocx` CLI and
provision development tools through it: as command-list launchers, as
content roots for `find_package`, or as foreign-platform content.

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
ocx_package(NAME jq PACKAGE ocx.sh/jq:latest PULL)
```

No ocx installation required: the pinned CLI is bootstrapped at first
configure (per-machine cache, manifest sha256 enforced). The classic find
module works too — `find_package(ocx REQUIRED)`, with `-DOCX_BOOTSTRAP=ON`
for the same zero-setup behavior.

Requires CMake **3.19** (`Findocx.cmake` alone works on 3.15). Script mode
(`cmake -P`) is fully supported.

## How it works

1. `ocx_bootstrap()` (implicit on first use) downloads the **pinned** ocx
   release listed in the dist.json snapshot embedded in `ocx.cmake`
   (sha256-verified) into `~/.cache/find_ocx`, shared by all build trees.
2. `ocx_project()` / `ocx_package()` shell out to that binary:
   `ocx lock --check` (staleness gate, always), `ocx pull` /
   `ocx package install` (eager mode), `ocx --format json env` (foreign
   platforms).
3. The exported `OCX_<NAME>_RUN` variables are plain CMake command lists
   re-entering `ocx run` / `ocx package exec` — no wrapper scripts, fully
   cross-platform, generator expressions compose naturally, and content
   materializes lazily on first execution into the shared content-addressed
   `OCX_HOME` store.
4. Reconfigures are memoized by input fingerprints: unchanged inputs spawn
   no ocx process at all (`-DOCX_REFRESH=ON` bypasses once).

## Corporate mirrors

Same knobs as the [setup.ocx.sh installer](https://github.com/ocx-sh/setup.ocx.sh)
and [rules_ocx](https://github.com/ocx-sh/rules_ocx). Every `OCX_*` knob
follows the snapshot pattern: the CMake cache variable wins; otherwise the
environment value at *first* configure is snapshotted into the cache.

| Variable | Effect |
| --- | --- |
| `OCX_INSTALL_DIST_URL` | Fetch the release manifest from your mirror instead of the embedded snapshot. |
| `OCX_INSTALL_MIRROR_URL` | Rewrite the ocx binary download to `<mirror>/<tag>/<filename>`. The manifest sha256 is still enforced. |
| `OCX_MIRRORS` | JSON map `{"ocx.sh": "https://mirror.corp/ocx"}` — package pulls go to the mirror; lock digests stay keyed to the upstream host. |
| `OCX_INSECURE_REGISTRIES` | Allow plain-HTTP mirrors (comma list). |
| `OCX_AUTH_<REGISTRY>_{TYPE,USER,TOKEN}` | Registry credentials — **environment only**, never snapshotted into CMakeCache.txt. |

Also passed through when set: `OCX_HOME`, `OCX_OFFLINE`, `OCX_FROZEN`,
`OCX_REMOTE`, `OCX_JOBS`, `OCX_INDEX`, `OCX_DEFAULT_REGISTRY`.

## Lazy vs eager

Launchers are lazy by default — a configure touches the network only for
what it actually needs. `PULL` (per call) or `-DOCX_PULL=ON` (global,
recommended for CI) materializes at configure time, fails fast, and enables
the `<name>_ROOT` export. Reproducibility tiers per package: commit an
`INDEX` snapshot, pin per-platform digests with `PINS`, or float and read
the resolved digest from the configure log.

## API docs

<https://ocx-sh.github.io/find_ocx/> — extracted from the `.rst` blocks in
the module sources (Sphinx + the CMake domain). Regenerate locally with
`ocx run -- task docs`.

## Examples

- [`examples/project`](examples/project) — workspace toolchain: zero-arg
  `ocx_project()`, group launchers, genexes in commands, ctest usage
- [`examples/package`](examples/package) — ad-hoc jq: floating + eager,
  digest-pinned + lazy, `<name>_ROOT`

## Testing

The harness dogfoods find_ocx: the CMake versions under test are
provisioned as OCX packages (`ocx.sh/cmake:<tag>`) through `ocx_package()`
itself, and each fixture runs on every version via
`ctest --build-and-test` — on Linux, macOS, and Windows.

```sh
ocx run -- task verify
```

## License

Apache-2.0. See [LICENSE](LICENSE).
