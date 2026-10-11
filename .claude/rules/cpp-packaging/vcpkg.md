---
title: vcpkg at the CMake Seam
summary: The CMK-VCPKG family. Owns the vcpkg manifest and its baseline, wiring vcpkg's toolchain before the first project(), triplets and the MSVC runtime, the binary and asset caches CI names, dead and never-existing vcpkg surface, and authoring a port or overlay port
---

# vcpkg at the CMake Seam

Owns vcpkg as a CMake project meets it: the manifest and its baseline, how
`vcpkg.cmake` enters the configure, triplets and the MSVC runtime, the cache
providers CI names, dead or never-existing surface, and the ports you author.
Toolchain composition and the one-manager ban are CMK-TC in cmake-build's
`toolchains-and-providers.md` (CMK-TC-02 and CMK-TC-03 are cited, never
restated). The manager choice, the lock of record, pinning the vcpkg tool and
the outer CI cache are CMK-PKG in this rule's index. Conan is CMK-CONAN. The export namespace is CMK-INST in cmake-build's
`install-and-export.md`, and `CMAKE_POLICY_VERSION_MINIMUM` is CMK-DEP-15 in its
`dependencies.md`.

Written against vcpkg-tool 2026-09-26, the registry as of 2026-09-25 (last
release 2026.07.29) and the CMake floor 3.25, with CMake behaviour measured on
3.31.12, 4.3.4 and 4.4.2 (2026-09-26). vcpkg has no lockfile and no semantic
port linter, so every check here is a grep or a read.

Contents: [The Manifest](#the-manifest) ·
[Wiring vcpkg Into the Configure](#wiring-vcpkg-into-the-configure) ·
[Triplets and the MSVC Runtime](#triplets-and-the-msvc-runtime) ·
[CI Cache Providers](#ci-cache-providers) ·
[Dead and Never-Existing Surface](#dead-and-never-existing-surface) ·
[Authoring a Port](#authoring-a-port) ·
[What Agents Get Wrong Here](#what-agents-get-wrong-here) ·
[Re-check](#re-check)

## The Manifest

One pass over `vcpkg.json` and `vcpkg-configuration.json`, from the repository
root. A manifest is top-level when it is the one `vcpkg install` or the
toolchain runs against. A port's or a library's shipped manifest is not.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-VCPKG-01 | Make every top-level manifest reproducible: give it `builtin-baseline`, or a `vcpkg-configuration.json` whose default registry has a `baseline`, or pin the vcpkg root to a commit in CI. Prefer baseline plus pinned root at the same SHA. Move a baseline with `vcpkg x-update-baseline` (`--add-initial-baseline` the first time), never by hand. | A manifest with no baseline and no registry "operates according to the Classic mode algorithm and ignores all versioning information" (vcpkg docs, versioning). Measured on vcpkg-tool 2026-09-26: a constraint-free `"dependencies": ["foo"]` manifest installs whatever the checkout holds with no warning, while `"version>="` or `"overrides"` without a baseline is rejected outright. Apache Arrow pins its CI root to the SHA its `builtin-baseline` names. `x-update-baseline` is `x-`-prefixed, so experimental (as of 2026-09-26). Floor: manifest versioning, vcpkg-tool 2021 or later. | `grep -rL --include='vcpkg.json' --exclude-dir=vcpkg --exclude-dir=vcpkg_installed --exclude-dir=build -e '"builtin-baseline"' .` lists manifests without a baseline. Empty output is the pass. A listed top-level manifest is cleared only by a sibling `vcpkg-configuration.json` carrying `"baseline"` or by a pinned vcpkg checkout in CI, otherwise it is the finding. A listed port or library manifest is cleared by reading. | MUST |
| CMK-VCPKG-02 | Put `overrides`, registries and `overlay-ports` only in the top-level project. A library states a floor with `"version>="` on the dependency, never with `overrides` in the manifest it ships, and never ships an overlay its consumers are expected to pick up. | vcpkg ignores `overrides` in transitive manifests and every field of a dependency's `vcpkg-configuration.json` (vcpkg-json and vcpkg-configuration-json references, re-read 2026-09-26). Overlays come only from `--overlay-ports`, the top-level configuration and `VCPKG_OVERLAY_PORTS`, in that order. The author sees the override work in their own build, and every consumer silently loses it. Floor: vcpkg-tool 2026-09-26 (as of 2026-09-26). | Over each overlay or shipped port directory, found from `overlay-ports` in `vcpkg-configuration.json` or `VCPKG_OVERLAY_PORTS`, set as `OVERLAY_PORTS_DIR` (default `ports`): `grep -rn --include='vcpkg.json' --include='vcpkg-configuration.json' -e '"overrides"' -e '"overlay-ports"' -e '"registries"' -e '"default-registry"' "${OVERLAY_PORTS_DIR:-ports}"` Empty output is the pass. A `No such file or directory` error (exit 2) means the variable names the wrong directory: cesium-native at `13e1708` keeps its overlay in `extern/vcpkg/ports`, and the default errored there (2026-09-26). With no overlay or port directory named anywhere, the row is not applicable. A hit is the finding. The repository's own top-level manifest is out of scope. | MUST |
| CMK-VCPKG-03 | In a manifest that ships as a dependency, give dependencies `"default-features": false` unless a default feature is needed, mark every build-time tool (`vcpkg-cmake`, `vcpkg-cmake-config`, code generators) `"host": true`, and write `license` as an SPDX expression or `null`. | "Ports used by others should almost always use `"default-features": false`", and tools "should be marked as `"host": true`" so a cross build runs a host binary (vcpkg-json reference). The docs say "should", hence SHOULD. Floor: vcpkg registry 2026.07.29 (as of 2026-09-26). | `grep -rn -A2 --include='vcpkg.json' -e '"vcpkg-cmake' .` must show `"host": true` beside each hit. A hit without it is the finding, and empty output means not applicable. Default features and the license are read. | SHOULD |

## Wiring vcpkg Into the Configure

Read the presets, then the top-level `CMakeLists.txt` up to its first
`project()`. `CMK-VCPKG-04` is **pinned** (the provider stance): vcpkg enters
through its toolchain file, before the first `project()`. An adopter that
consumes a pre-installed prefix instead overrides this once, repository-wide.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-VCPKG-04 | Wire `scripts/buildsystems/vcpkg.cmake` through a configure preset (`toolchainFile`, or `cacheVariables.CMAKE_TOOLCHAIN_FILE`) or `-D`, and set every `VCPKG_*` input (triplet, manifest features, overlays, chainload) before the first `project()`, preferably in the same preset. **pinned**, see above. | vcpkg reads these when the first `project()` loads its toolchain, so a later write is a silent no-op. With the vcpkg-tool 2026-09-26 `vcpkg.cmake`, `set(VCPKG_TARGET_TRIPLET arm64-linux)` after `project()` found the x64-linux package and configure exited 0 (measured on 3.31.12, 4.3.4 and 4.4.2). This is the vcpkg trigger of CMK-TC-03. Floor: `cacheVariables` needs presets v1 (CMake 3.19), `toolchainFile` presets v3 (3.21), and `-D` works everywhere, all below 3.25. | `grep -rni --include='CMakeLists.txt' -e 'set(VCPKG_' -e 'list(APPEND VCPKG_' .` Empty output is the pass. Any hit in a subdirectory's `CMakeLists.txt` is the finding. For hits in the top-level file, `grep -ni -e 'project(' CMakeLists.txt` gives the first `project(` line, and a write numbered after it is the finding. Grepping both at once buries the writes on a large tree: openvino at `71a6aed` printed 29 `project(` lines and no write (2026-09-26). Reads after `project()`, such as `if(VCPKG_TARGET_TRIPLET MATCHES …)`, do not match. | MUST |
| CMK-VCPKG-05 | Compose another toolchain with vcpkg's only through `VCPKG_CHAINLOAD_TOOLCHAIN_FILE`. The ban on a second toolchain source, vcpkg's and Conan's together included, is CMK-TC-02 in cmake-build's `toolchains-and-providers.md`. | One configure loads exactly one toolchain file. A preset's `toolchainFile` beats its own `cacheVariables.CMAKE_TOOLCHAIN_FILE`, a command-line `-D` beats the preset, and the losing file is never read (measured on 3.31.12, 4.3.4 and 4.4.2). Floor: any. | CMK-TC-01's per-leg read and CMK-TC-02's grep, both owned by `toolchains-and-providers.md`. A second toolchain reaching a vcpkg leg other than through `VCPKG_CHAINLOAD_TOOLCHAIN_FILE` is the finding. | MUST |

```cmake
# wrong: vcpkg.cmake already ran inside project(), so this is ignored and configure exits 0. The preset below is the right form.
project(app LANGUAGES CXX)
set(VCPKG_TARGET_TRIPLET arm64-linux)
```

```json
{
  "name": "arm64-linux",
  "toolchainFile": "$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake",
  "cacheVariables": { "VCPKG_TARGET_TRIPLET": "arm64-linux" }
}
```

## Triplets and the MSVC Runtime

Grep the presets, CI files and triplet files. The CRT half is read-only on
Windows: the mechanism is read from vcpkg's scripts and CMake's documented
default, and the LNK2038 link failure is documented, not measured (as of
2026-09-26). A Conan leg's runtime belongs to CMK-CONAN-10.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-VCPKG-06 | Name the triplet explicitly per configure leg (`VCPKG_TARGET_TRIPLET` in the preset). When that triplet links the CRT statically (`*-windows-static`, `*-windows-static-release`, or `VCPKG_CRT_LINKAGE static`), set `CMAKE_MSVC_RUNTIME_LIBRARY` to `MultiThreaded$<$<CONFIG:Debug>:Debug>` yourself, in the preset's `cacheVariables` or before the first `project()`. With `x64-windows` or a `*-static-md` triplet, keep CMake's default. A `set()` after the first `project()`, guarded or not, does not satisfy this row, because nothing on a vcpkg leg defines the variable first. | The consumer toolchain `vcpkg.cmake` never sets the runtime (0 references, registry as of 2026-09-25), and CMake defaults to the DLL runtime, so a static-CRT triplet mismatches at link (LNK2038) with no configure diagnostic. The setter agents find in `scripts/toolchains/windows.cmake` loads only for port builds. The default triplet has been the host's since September 2023, so naming it is for ABI visibility, not to dodge an `x86` default. Floor: CMake 3.15 (CMP0091), Windows and MSVC only. | `grep -rn --include='CMakePresets.json' --include='CMakeLists.txt' --include='*.cmake' --include='*.yml' --include='*.yaml' --exclude-dir=vcpkg -e 'windows-static$' -e 'windows-static[^-]' -e 'windows-static-release' -e 'VCPKG_CRT_LINKAGE static' .` Empty output means not applicable. On a hit, `grep -rn --include='CMakeLists.txt' --include='CMakePresets.json' -e CMAKE_MSVC_RUNTIME_LIBRARY .` must print a line: empty output is the finding, and so is a `CMakeLists.txt` hit numbered after the first `project(`. Portfiles and triplets are left out on purpose, because their runtime lines would satisfy this check falsely (they are CMK-VCPKG-15's). | MUST |
| CMK-VCPKG-07 | Register every file a custom or overlay triplet `include()`s in `VCPKG_HASH_ADDITIONAL_FILES`, and never set `VCPKG_DISABLE_COMPILER_TRACKING`. | The binary-cache ABI hash covers the triplet's contents and name and both compilers, and its documented input list names no included file, so editing an included file restores stale binaries. The docs warn that disabling compiler tracking "can lead to ABI incompatibility in restored binary packages". Normative only (as of 2026-09-26). Floor: vcpkg registry 2026.07.29 (as of 2026-09-26). | The fenced block below, over the overlay-triplet directory found from `overlay-triplets` or `VCPKG_OVERLAY_TRIPLETS`, set as `OVERLAY_TRIPLETS_DIR` (default `triplets`). Empty output from both commands is the pass. A `No such file or directory` error means the variable names the wrong directory, and with no overlay triplets the row is not applicable. | SHOULD |

```sh
grep -rn --include='*.cmake' -e VCPKG_DISABLE_COMPILER_TRACKING "${OVERLAY_TRIPLETS_DIR:-triplets}"
grep -rln --include='*.cmake' -e 'include(' "${OVERLAY_TRIPLETS_DIR:-triplets}" | xargs -r grep -L -e VCPKG_HASH_ADDITIONAL_FILES
```

## CI Cache Providers

Grep the pipeline directory (`.github` below, or wherever CI lives). The outer
CI cache and its key are CMK-PKG-04 in this rule's index.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-VCPKG-08 | Never name `x-gha` in `VCPKG_BINARY_SOURCES` or `--binarysource`. Use `files`, `nuget`, `nugetconfig` or `http` without a caveat, and put a comment naming "experimental" beside any other `x-` provider. | The provider table marks `x-gha` removed and `x-azblob`, `x-azcopy`, `x-azcopy-sas`, `x-gcs`, `x-aws`, `x-aws-config`, `x-cos` and `x-az-universal` "will change or be removed without warning". vcpkg-tool 2026-09-26 only warns on `x-gha` and exits 0, so the job runs uncached and stays green. An unknown token is a hard error (exit 1), not a fallback to `files` (both measured 2026-09-26). Floor: vcpkg-tool 2026-09-26. | `grep -rn -e x-gha .github` Empty output is the pass. Then `grep -rn -e x-azblob -e x-azcopy -e x-gcs -e x-aws -e x-cos -e x-az-universal .github` lists each line that needs the comment. | MUST |
| CMK-VCPKG-09 | In an offline or air-gapped CI that sets `X_VCPKG_ASSET_SOURCES`, include `x-block-origin`. | Without it a mirror miss falls through to the upstream URL, the documented read, origin, write-back order, so the build is not offline. No surveyed project does this yet (as of 2026-09-26). Floor: vcpkg-tool 2026-09-26, and the feature is itself `x-`-prefixed. | The fenced block below. Empty output is the pass. | SHOULD |

```sh
grep -rln -e X_VCPKG_ASSET_SOURCES .github | xargs -r grep -L -e x-block-origin
```

## Dead and Never-Existing Surface

Grep the build, manifest and CI files, then read any prose you generate. A
`message(WARNING)` does not fail the configure gate: `VCPKG_PREFER_SYSTEM_LIBS`'s
deprecation line exited 0 under `-Werror=dev` on 3.31.12 and 4.3.4 and under
`-Werror=author` on 4.4.2 (measured 2026-09-26), so only the grep catches it.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-VCPKG-10 | Never introduce vcpkg-artifacts (`vcpkg-ce`, `vcpkg activate`, `VCPKG_ARTIFACTS_*`, a `"kind": "artifact"` registry) or `VCPKG_PREFER_SYSTEM_LIBS` into a consuming project. Replace `VCPKG_PREFER_SYSTEM_LIBS` with an empty overlay port (recipe below). Delete an inherited `"kind": "artifact"` registry entry when you edit its `vcpkg-configuration.json`. | Artifacts were announced for removal "after July 1" (vcpkg-tool 2026-05-27 release note) and still ship in vcpkg-tool 2026-09-26, so write "announced for removal", never "removed". `VCPKG_PREFER_SYSTEM_LIBS` is deprecated, warns at configure and has no announced removal date (as of 2026-09-26). Floor: re-check on every vcpkg-tool tag. | `grep -rn --include='CMakeLists.txt' --include='*.cmake' --include='*.json' --include='*.yml' --include='*.yaml' --include='*.sh' --include='*.ps1' --exclude-dir=vcpkg -e vcpkg-artifacts -e vcpkg-ce -e VCPKG_ARTIFACTS -e 'vcpkg activate' -e VCPKG_PREFER_SYSTEM_LIBS .` Empty output is the pass. A hit that is only a `"kind": "artifact"` registry naming `vcpkg-ce-catalog`, in a tree where `grep -rn --exclude-dir=.git -e 'vcpkg activate' -e x-vcpkg-artifacts .` prints nothing, is a scaffold from earlier `vcpkg new` releases: report it as a SHOULD cleanup, not this MUST. Measured 2026-09-26 on vcpkg-tool 2026-07-27: `vcpkg new --application` no longer writes the entry, and cesium-native at `13e1708` carries it inert (its configure logs name no artifact). `grep -w` does not narrow the pattern, because `-` is not a word character. Documentation is read, not grepped. | MUST |
| CMK-VCPKG-11 | Never state, generate or configure as if vcpkg had a lockfile (`vcpkg.lock`), a CMake dependency provider or CPS support, and never promise that vcpkg CI "fails on drift". Reproducibility in vcpkg is a baseline plus `"version>="` floors plus a pinned tool and root (CMK-VCPKG-01, CMK-PKG-02). | `vcpkg.cmake` registers no dependency provider and writes no CPS, and the vcpkg-tool 2026-09-26 tree has no lockfile, provider or CPS file. Selection is "the lowest version that matches all constraints", and the baseline is one of them, so the result is the highest of the baseline's version and every `version>=` in the graph. Only `overrides` pins below the baseline: `version>=` 1.7.15 on baseline `11ace808` installed cjson 1.7.19, and an `overrides` entry installed 1.7.15 (measured 2026-09-26, vcpkg-tool 2026-07-27, CMake 4.4.2). A manifest install leaves no lock behind. `vcpkg_installed/` is an install tree, not a lock. Floor: vcpkg-tool 2026-09-26. | `grep -rn --include='*.yml' --include='*.yaml' --include='*.json' --include='*.cmake' --include='CMakeLists.txt' --include='.gitignore' -e vcpkg.lock -e vcpkg-lock .` Empty output is the pass. Generated prose and docs are a reading check. | MUST |

The replacement for `VCPKG_PREFER_SYSTEM_LIBS`, per port you want taken from the
system: an overlay directory holding a directory named after the port, with two
files. Overlays are "considered before any registry lookups, or versioning
considerations", so any valid version works. `VCPKG_POLICY_EMPTY_PACKAGE`
disables every post-build check, the port installs nothing, and the consumer's
`find_package` falls through to the system copy. Register the overlay from the
top-level project only (CMK-VCPKG-02).

```json
{ "name": "zlib", "version": "1.0.0" }
```

```cmake
set(VCPKG_POLICY_EMPTY_PACKAGE enabled)
```

## Authoring a Port

For a `portfile.cmake` you write or edit, run from the port or overlay root.
Inside a port build, the `CMAKE_POLICY_VERSION_MINIMUM` of 3.5 that vcpkg
exports on CMake 4.0 and later is enough, because `vcpkg_cmake_configure` passes
no `-Werror=dev`. That is CMK-DEP-15's port-tool exception, owned by
cmake-build's `dependencies.md`.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-VCPKG-13 | In a new or edited port, use `vcpkg_cmake_configure`, `vcpkg_cmake_install` (or `vcpkg_cmake_build`) and `vcpkg_cmake_config_fixup`, with `vcpkg-cmake` and `vcpkg-cmake-config` as host dependencies (CMK-VCPKG-03). Never call `vcpkg_configure_cmake`, `vcpkg_build_cmake`, `vcpkg_install_cmake`, `vcpkg_fixup_cmake_targets`, `vcpkg_extract_source_archive_ex`, `vcpkg_apply_patches` or `vcpkg_build_msbuild`, nor `vcpkg_extract_source_archive` without `ARCHIVE`. Replace `vcpkg_copy_tool_dependencies` with `vcpkg_copy_tools` (SHOULD). | The maintainer guide deprecates all of them, and no registry port uses them any more (as of 2026-09-25). They are not removed: the files still ship and run, and only `vcpkg_apply_patches` and the old extract overload print a deprecation message, so an overlay port built on them passes silently. Mixing old and new is a `FATAL_ERROR`. Floor: vcpkg registry 2026.07.29 (as of 2026-09-26). | `grep -rlw --include='portfile.cmake' -e vcpkg_configure_cmake -e vcpkg_build_cmake -e vcpkg_install_cmake -e vcpkg_fixup_cmake_targets -e vcpkg_extract_source_archive_ex -e vcpkg_apply_patches -e vcpkg_build_msbuild .` Empty output is the pass (`-w` keeps `z_vcpkg_apply_patches` out). `grep -rn --include='portfile.cmake' -e 'vcpkg_extract_source_archive( *["$]' .` finds the old overload, and empty output is the pass. `grep -rlw --include='portfile.cmake' -e vcpkg_copy_tool_dependencies .` lists the SHOULD clause's findings, and empty output is its pass. | MUST *(new or edited ports)* |
| CMK-VCPKG-15 | Set `CMAKE_MSVC_RUNTIME_LIBRARY` in a port's `OPTIONS`, or a triplet's `VCPKG_CMAKE_CONFIGURE_OPTIONS` (`_RELEASE`, `_DEBUG`), only as a value derived from `VCPKG_CRT_LINKAGE`, never as a constant. | Both reach the inner `cmake` as command-line `-D`, and the port chainload toolchain sets the runtime as a non-`FORCE` cache entry, so the `-D` wins with exit 0 and no warning under `-Werror=dev` (measured on 3.31.12, 4.3.4 and 4.4.2). A constant silently defeats the triplet's CRT choice, and consumers meet LNK2038 at best (read-only on Windows). Floor: CMake 3.15 (CMP0091), Windows and MSVC only. | The fenced block below. Empty output from the first two commands is the pass. Each file the third lists is read: a runtime value outside a `VCPKG_CRT_LINKAGE` branch is the finding. | MUST |
| CMK-VCPKG-12 | Write hexadecimal strings in lower case: every `SHA512` argument, a hex `REF` and `git-tree` values. | The maintainer guide requires it: vcpkg normalizes case internally, but tooling built on its files may not. vcpkg itself accepts upper case, hence SHOULD. Floor: vcpkg registry 2026.07.29 (as of 2026-09-26). | `grep -rlP --include='portfile.cmake' -e 'SHA512\s+[0-9a-fA-F]*[A-F][0-9a-fA-F]*' .` Empty output is the pass. | SHOULD |
| CMK-VCPKG-14 | Name a Config package the port exports for a library whose upstream ships none `unofficial-<port>` in lower case, with targets in the `unofficial::<port>::` namespace. | The guide: configs "which are not in the upstream library, should have `unofficial-` as a prefix", and the registry has no counter-example. "Should", hence SHOULD. Floor: vcpkg registry 2026.07.29 (as of 2026-09-26). | Read the values `grep -rn --include='portfile.cmake' -e PACKAGE_NAME .` prints. A value other than `unofficial-` plus the port name, for a port whose upstream ships no Config, is the finding. Empty output means not applicable. | SHOULD |
| CMK-VCPKG-16 | Declare a port's single supported linkage with `vcpkg_check_linkage(ONLY_STATIC_LIBRARY)` or `(ONLY_DYNAMIC_LIBRARY)`, guarded by the matching `VCPKG_TARGET_IS_*`. Never state it only in prose, and never paper over missing exports with `CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS`. | This is the maintainer guide's own example, in its section against `CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS`. Floor: vcpkg registry 2026.07.29 (as of 2026-09-26). | Read beside `grep -rl --include='portfile.cmake' -e vcpkg_check_linkage .` A Windows-capable port whose upstream has no export macros or `.def` file and lacks the call is the finding. Empty output means no port declares a linkage, so read every Windows-capable port. | SHOULD |
| CMK-VCPKG-17 | Ship and install a `usage` file (`share/<port>/usage`) whenever consuming the port needs something non-obvious: an `unofficial-` package name, non-default components, a target name or a runtime asset path. | vcpkg's post-build check fails a port that holds `usage` and does not install it, but nothing makes the file exist. Floor: vcpkg registry 2026.07.29 (as of 2026-09-26). | Read: a port that passes `PACKAGE_NAME unofficial-` (CMK-VCPKG-14) with no `usage` file beside its `portfile.cmake` is the finding. | SHOULD |
| CMK-VCPKG-18 | Install the license with `vcpkg_install_copyright(FILE_LIST …)`, not a hand-written `file(INSTALL … RENAME copyright)` or a hand-built `share/${PORT}/copyright` path. | The guide calls the manual form discouraged in new ports but still allowed, hence SHOULD. Hand-rolled copies are still common in the registry, so copying a neighbour port copies the old form. Floor: vcpkg registry 2026.07.29 (as of 2026-09-26). | The fenced block below. Empty output is the pass. | SHOULD |
| CMK-VCPKG-21 | Never vendor a dependency's source inside a port. Split it into its own port, depend on it, and patch the upstream build to use it. | The guide's "Do not use vendored dependencies": two vendored copies conflict at link, the license becomes opaque, and every fix is made twice. Floor: vcpkg registry 2026.07.29 (as of 2026-09-26). | Read only, because a vendored copy has no keyword: an `add_subdirectory` into a bundled `third_party/` or `extern/` tree that no patch devendors is the finding. | SHOULD |

Outside vcpkg, a Config package written for a library that ships none follows
the same `unofficial-<name>` naming (CMK-VCPKG-14). CMK-INST-06 and CMK-INST-07
in cmake-build's `install-and-export.md` own the export namespace itself.

```sh
# CMK-VCPKG-15: a runtime in a portfile that never mentions VCPKG_CRT_LINKAGE
grep -rl --include='portfile.cmake' -e CMAKE_MSVC_RUNTIME_LIBRARY . | xargs -r grep -L -e VCPKG_CRT_LINKAGE
# CMK-VCPKG-15: an overlay triplet passing the runtime through configure options
grep -rl --include='*.cmake' -e VCPKG_CMAKE_CONFIGURE_OPTIONS "${OVERLAY_TRIPLETS_DIR:-triplets}" | xargs -r grep -l -e CMAKE_MSVC_RUNTIME_LIBRARY
# CMK-VCPKG-15: the read list, files that mention both
grep -rl --include='portfile.cmake' -e CMAKE_MSVC_RUNTIME_LIBRARY . | xargs -r grep -l -e VCPKG_CRT_LINKAGE
# CMK-VCPKG-18: a hand-installed copyright
grep -rlF --include='portfile.cmake' -e 'RENAME copyright' -e 'share/${PORT}/copyright' . | xargs -r grep -L -e vcpkg_install_copyright
```

```cmake
# wrong: the pre-2021 helpers, still shipped and silent in an overlay port
vcpkg_configure_cmake(SOURCE_PATH "${SOURCE_PATH}" PREFER_NINJA)
vcpkg_install_cmake()
vcpkg_fixup_cmake_targets(CONFIG_PATH lib/cmake/foo)

# right: the vcpkg-cmake helpers, with both helper ports as host dependencies
vcpkg_cmake_configure(SOURCE_PATH "${SOURCE_PATH}")
vcpkg_cmake_install()
vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/foo)
```

## What Agents Get Wrong Here

1. **Recommending `x-gha` for GitHub Actions caching**, a whole era's blog
   advice. vcpkg warns, exits 0 and runs uncached. `CMK-VCPKG-08`.
2. **Setting `VCPKG_TARGET_TRIPLET` or `CMAKE_TOOLCHAIN_FILE` after
   `project()`.** Nothing reads it, and the default triplet builds. `CMK-VCPKG-04`.
3. **Inventing a vcpkg lockfile**: `vcpkg.lock` in a cache key, `vcpkg_installed/`
   as a lock, CI that "fails on drift". `CMK-VCPKG-11`, then `CMK-VCPKG-01`.
4. **Putting `overrides` or `overlay-ports` in a library's manifest** on the npm
   `resolutions` model. It works only in the author's build. `CMK-VCPKG-02`.
5. **Assuming vcpkg's consumer toolchain sets the MSVC runtime from the
   triplet**, or asserting the old `x86-windows` default. `CMK-VCPKG-06`.
6. **Calling vcpkg-artifacts "removed"** or `x-update-baseline` "stable", or
   claiming vcpkg has a provider or CPS. `CMK-VCPKG-10`, `CMK-VCPKG-11`.
7. **Copying a pre-2021 port helper** such as `vcpkg_configure_cmake` from an
   old port, where it still runs silently. `CMK-VCPKG-13`.
8. **"Fixing" LNK2038 with a constant `-DCMAKE_MSVC_RUNTIME_LIBRARY` in a
   port's `OPTIONS`**, overriding the triplet for every consumer. `CMK-VCPKG-15`.
9. **Caching `installed/` and skipping `vcpkg install` on a cache hit**, which
   freezes the dependency set. CMK-PKG-04 in the index owns the cache shape.

## Re-check

- D3: vcpkg-artifacts removal, announced for after 2026-07-01 and not executed at vcpkg-tool 2026-09-26, and whether a `"kind": "artifact"` registry is then rejected (`CMK-VCPKG-10`).
- D4: Each vcpkg-tool tag: the provider table and `x-gha` warning (`CMK-VCPKG-08`), no lockfile, provider or CPS (`CMK-VCPKG-11`), the `x-` prefix on `x-update-baseline` (`CMK-VCPKG-01`).
