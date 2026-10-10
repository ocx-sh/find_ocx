---
paths:
  - "**/conanfile.py"
  - "**/conanfile.txt"
  - "**/conandata.yml"
  - "**/conan.lock"
  - "**/conanws.yml"
  - "**/conanws.py"
  - "**/vcpkg.json"
  - "**/vcpkg-configuration.json"
  - "**/portfile.cmake"
summary: "The C++ package-manager index: the gate, the non-negotiables, the manager and lock-of-record decisions, and where the Conan 2 and vcpkg depth lives for conanfiles, conan.lock, vcpkg manifests and portfiles"
keywords: cpp,c++,cmake,conan,conan2,conanfile,conan.lock,conandata,vcpkg,vcpkg.json,portfile,triplet,lockfile,baseline,tool-requires,binary-cache,fetchcontent,cpm,package-manager
license: Apache-2.0
repository: https://github.com/ocx-sh/grimoire-lore
---

# C++ Packaging

One manager of record per configure, one lock of record per acquisition
mechanism, and every tool pinned where it is provisioned. The rest names a
mistake Conan or vcpkg lets through with exit 0.

Contents: [The Gate](#the-gate) · [Non-Negotiables](#non-negotiables) ·
[Rules This File Owns](#rules-this-file-owns) ·
[Where the Depth Is](#where-the-depth-is) · [Severity](#severity) ·
[Siblings](#siblings)

**Before trusting any rule below, know what a green configure does not
prove.** It does not prove the vcpkg triplet you named was used: a
`VCPKG_TARGET_TRIPLET` set after `project()` is never read and the default
triplet builds (`CMK-VCPKG-04`). It does not prove the binary cache ran,
because `x-gha` warns, exits 0 and builds everything from source
(`CMK-VCPKG-08`). It does not prove the Conan profile's C++ standard held,
because a later `set(CMAKE_CXX_STANDARD 20)` wins with one `STATUS` line that
neither `-Werror=dev` nor `-Werror=author` promotes (`CMK-CONAN-10`). It does
not prove the lock applied, because `--lockfile-partial` and an empty
`--lockfile=` both let `conan install` drift and exit 0 (`CMK-CONAN-09`). And
it does not prove the MSVC runtime matches a static-CRT triplet, which fails
only at link (`CMK-VCPKG-06`). All five look exactly like a pass.

## The Gate

Run it after every change, narrowest first. Conan 2.32.0, vcpkg-tool
2026-09-26 and CMake 3.31.12, 4.3.4 and 4.4.2, verified 2026-09-26.

```sh
# Conan leg: the project's pinned Conan, never a conan found on PATH
conan install . --lockfile=conan.lock --build=missing
cmake --preset conan-release --fresh -Werror=dev > configure.log 2>&1
grep -e 'has been modified to' configure.log   # CMK-CONAN-10: empty output is the pass
cmake --build --preset conan-release
# vcpkg leg: the tool bootstrapped from the pinned vcpkg root, never the runner image's
"$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
cmake --preset vcpkg-release --fresh -Werror=dev
cmake --build --preset vcpkg-release
# Authors only: a recipe (runs its test_package), then a port or overlay port
conan create . --build=missing
PORT=zlib   # the port you are editing
"$VCPKG_ROOT/vcpkg" install "$PORT" --overlay-ports=ports --classic
```

Preset names are examples. `cmake` is the pinned CMake the leg installs
(`CMK-VER-03`), never the runner default. Spell the configure gate for that binary (`CMK-CORE-01`):
`-Werror=dev` on CMake ≤ 4.3 and on any command line that serves both sides,
`-Werror=author` only on CMake ≥ 4.4. Measured 2026-09-26 with a planted
`AUTHOR_WARNING` through a preset: `-Werror=dev` fails the configure on
3.31.12, 4.3.4 and 4.4.2, while `-Werror=author` exits 0 on 3.31.12 and 4.3.4.
Run it through the leg's own `--preset`, because a preset's
`"warnings": {"deprecated": false}` beats the flag. Drop `--lockfile` only
where no `requires` or `tool_requires` uses a version range (`CMK-CONAN-09`). A portfile is also a
CMake file, so `gersemi --check` applies to it as a SHOULD, never `--diff`
(`CMK-CORE-04`, owned by `cmake-build`).

A task is done when a command, its exit code, and the tree it ran against are
all named. Narration is not evidence.

## Non-Negotiables

Every line below blocks a merge. IDs resolve to the depth files in
[Where the Depth Is](#where-the-depth-is) or to the named `cmake-build` file,
where each rule carries its rationale and verification.

| # | Rule | ID |
|---|---|---|
| 1 | vcpkg's `vcpkg.cmake` and Conan's `conan_toolchain.cmake` never reach one configure, directly or chained. Compose any other toolchain only through `VCPKG_CHAINLOAD_TOOLCHAIN_FILE` or Conan's `tools.cmake.cmaketoolchain:user_toolchain`. | CMK-TC-02, CMK-TC-01, CMK-VCPKG-05 |
| 2 | Every acquisition mechanism the tree reaches has its own lock-of-record entry, checked by that mechanism's rule. A pristine `conan.lock` says nothing about a `GIT_TAG main` beside it. | CMK-PKG-01, CMK-DEP-01, CMK-DEP-03 |
| 3 | An application whose `requires` or `tool_requires` use a version range commits `conan.lock`, and CI passes `--lockfile=conan.lock` explicitly. Never `--lockfile-partial`, never an empty `--lockfile=`, never a hand edit of the lock. | CMK-CONAN-09 |
| 4 | A top-level vcpkg manifest is reproducible through `builtin-baseline`, a registry `baseline`, or a vcpkg root pinned to a commit in CI. vcpkg has no lockfile, no dependency provider and no CPS: never write, cache-key or promise any of them, and never promise CI that "fails on drift". | CMK-VCPKG-01, CMK-VCPKG-11 |
| 5 | Conan 2 only: `from conan import ConanFile` and `conan.tools.*`, names through `cpp_info.set_property`. Never `from conans`, `generators = "cmake"`, `conan_basic_setup`, `conanbuildinfo`, `cpp_info.names` or `cpp_info.filenames`. | CMK-CONAN-01, CMK-CONAN-02 |
| 6 | Build tools are `tool_requires`, never `build_requires`. A `tool_requires` that CMake must `find_package` under `CMakeDeps` is listed in `build_context_activated`. | CMK-CONAN-03, CMK-CONAN-06 |
| 7 | Once `conan_toolchain.cmake` loads, the profile owns `CMAKE_CXX_STANDARD`, `CMAKE_CXX_EXTENSIONS` and `CMAKE_MSVC_RUNTIME_LIBRARY`. No unguarded `set()` of them after `project()`, no `-DCMAKE_CXX_STANDARD` beside the toolchain, and the configure log carries no `has been modified to` line. | CMK-CONAN-10, CMK-TGT-05, CMK-TGT-16 |
| 8 | `CMakeConfigDeps` is never paired with `find_package(... MODULE)` for a Conan package, because it writes no Find modules. | CMK-CONAN-05 |
| 9 | Every `conandata.yml` source entry carries a `sha256` and is fetched through `get(self, **self.conan_data[...])`, bar the two exceptions `CMK-CONAN-23` names. Never call `self.info.header_only()`, which does not exist in Conan 2. | CMK-CONAN-23, CMK-CONAN-16 |
| 10 | The cmake-conan provider enters only through `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` from a preset or the command line, never from a `CMakeLists.txt`. Never rely on it feeding `find_program`, `find_library` or `find_path`, and never offer `cmake_language(DEFER)` as the ordering fix. | CMK-TC-04, CMK-TC-05 |
| 11 | vcpkg's toolchain file comes from a configure preset or `-D`, and every `VCPKG_*` input is set before the first `project()`, preferably in that same preset. A later write is a silent no-op. | CMK-VCPKG-04, CMK-TC-03 |
| 12 | `overrides`, registries and `overlay-ports` live only in the top-level project. A manifest that ships as a dependency states floors with `"version>="`. | CMK-VCPKG-02 |
| 13 | Never name `x-gha` in `VCPKG_BINARY_SOURCES`, and never introduce vcpkg-artifacts or `VCPKG_PREFER_SYSTEM_LIBS`. Artifacts are "announced for removal", never "removed" (as of 2026-09-26). | CMK-VCPKG-08, CMK-VCPKG-10 |
| 14 | A static-CRT triplet gets a project-set `CMAKE_MSVC_RUNTIME_LIBRARY` in the preset or before the first `project()`. A port sets the runtime only derived from `VCPKG_CRT_LINKAGE`, never as a constant. | CMK-VCPKG-06, CMK-VCPKG-15 |
| 15 | A new or edited port uses the `vcpkg_cmake_*` helpers, never `vcpkg_configure_cmake`, `vcpkg_install_cmake`, `vcpkg_fixup_cmake_targets` or their siblings, which still run silently. | CMK-VCPKG-13 |
| 16 | Never commit `CMakeUserPresets.json`. A hand-written one makes Conan skip its `conan-*` presets without a word. | CMK-CI-02, CMK-CONAN-08 |

## Rules This File Owns

The acquisition choice, the lock of record, tool provisioning and the CI cache
shape.
Every command runs from the repository root. Commands that read CI assume it
lives in `.github`: point them at your CI directory otherwise.

| Situation | Strategy that fits | Why |
|---|---|---|
| The dependency has no CMake build, or Bazel or Meson builds the same tree | System package or a vendored copy | FetchContent and CPM assume the dependency speaks CMake |
| A few header-only or fast-building dependencies, no registry of record | FetchContent or CPM | No packaging step, and every clean tree rebuilds from source |
| Cross-compiling with tools that run during the build | Conan `tool_requires` or vcpkg `"host": true` | Only the two managers split build and host |
| One binary cache and an audit or SBOM surface for an organisation | Conan or vcpkg | Neither CPM nor system packages offer either |
| A platform registry already exists (a distro) | System packages, a manager only for the gaps | One ABI story per configure (`CMK-TC-02`) |
| A first-party repository choosing between CMake plus a manager and Bazel | Decide on the build system, not the manager | `BZL-CC-24`: `rules_foreign_cc` is for third-party code you will not port, never a first-party strategy |

No row is a mandate. A library only the other manager carries comes in through
a vcpkg overlay port, a local Conan recipe, or FetchContent under `CMK-DEP-01`
and `CMK-DEP-03`, never through the second manager's toolchain. The one
citable adoption figure is the ISO C++ 2024 survey (Conan 19.34 %, vcpkg
19.10 %). The 2025 edition publishes no percentages, so never quote one.

| Build-tool mechanism | What pins the version | Offline story |
|---|---|---|
| Conan `tool_requires` (recipe, or a profile's `[tool_requires]`) | The package reference, plus `conan.lock` when ranged | Conan remote and binary cache |
| vcpkg `"host": true` dependency | The same baseline as every other dependency | vcpkg binary and asset caches |
| An external hash-verified provisioner | The hash written at that call site | Whatever mirror that site names |
| The runner or container image | The image digest, if pinned, otherwise nothing | None of its own |

```sh
# CMK-PKG-01: each non-empty list names a mechanism in reach. Run the owning check named after it.
grep -rl --include='conanfile.py' --include='conanfile.txt' -e requires .                                  # CMK-CONAN-09
grep -rl --include='vcpkg.json' --exclude-dir=vcpkg --exclude-dir=vcpkg_installed -e dependencies .       # CMK-VCPKG-01, CMK-PKG-02
grep -rl --include='CMakeLists.txt' --include='*.cmake' --exclude-dir=_deps --exclude-dir=vcpkg -e FetchContent_Declare -e CPMAddPackage -e ExternalProject_Add -e HunterGate .   # CMK-DEP-01..03, -05, -06
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-PKG-01 | A tree that reaches more than one acquisition mechanism keeps a lock-of-record entry for every mechanism it reaches, each checked by that mechanism's rule, not only the primary manager's. The entries: `CMK-CONAN-09` (Conan), `CMK-VCPKG-01` and `CMK-PKG-02` (vcpkg), `CMK-DEP-01` to `CMK-DEP-03` (FetchContent, CPM, ExternalProject), `CMK-DEP-05` (the CPM bootstrap), `CMK-DEP-06` (HunterGate). A git submodule is pinned by its gitlink and needs no entry. | The per-mechanism rules do not compose. A pristine `conan.lock` says nothing about a `FetchContent_Declare(... GIT_TAG main)` beside it, and the secondary mechanism is where pins go missing unnoticed. Floor: any, because it composes already-versioned rules. | The block above. All three empty means nothing is fetched, a pass. Each non-empty list is the trigger for the check named beside it, and a triggered check that was not run, or that reports a finding, is the finding. Planted 2026-09-26: a ranged `conanfile.txt`, a bare `vcpkg.json` and a `GIT_TAG main` fetch listed all three mechanisms, and a pinned Conan-only tree listed only Conan. | MUST |
| CMK-PKG-02 | Pin the vcpkg tool as well as the port versions: bootstrap it from the pinned vcpkg root (`bootstrap-vcpkg` reads the root's `scripts/vcpkg-tool-metadata.txt`), or pin an explicit vcpkg-tool release and its hash. Never run a runner image's preinstalled vcpkg. | `builtin-baseline` pins ports, not the tool. The registry root names the tool it bootstraps: it read `2026-07-27` on 2026-09-25, while vcpkg-tool 2026-09-26 was already out. A runner image's vcpkg changes whenever the image does. The root also fixes the CMake that port builds run: at root `11ace80` vcpkg-tool 2026-07-27 downloaded CMake 4.4.3 for them although 4.4.2 was on `PATH` (measured 2026-09-26), so that CMake is pinned here, not by the project's CI. Floor: a registry carrying `scripts/vcpkg-tool-metadata.txt`, re-checked each registry tag. | `grep -rn -e VCPKG_INSTALLATION_ROOT -e 'C:\\vcpkg' .github` Empty output is the pass, and any line is the finding. Then read CI for a fixed-SHA vcpkg checkout followed by `bootstrap-vcpkg`, or a hashed tool download. Neither is the finding. | SHOULD |
| CMK-PKG-03 | For every build tool whose version changes the output (a code generator, a required CMake or Ninja floor), state which mechanism in the table above supplies it and pin it there. "Whatever the runner image ships" is not a mechanism. | Runner images ship different tools on the same day (CMake 3.31.6 on `ubuntu-24.04`, 4.4.2 on `macos-15`, as of 2026-09-26), and a `protoc` skew between runs changes generated code without any error. Floor: any. | Reading heuristic. For each tool the docs or CI name, find a `tool_requires` entry, a `"host": true` entry, a hash-verified download or a digest-pinned image. None for a version-sensitive tool is the finding. | SHOULD |
| CMK-PKG-04 | In CI, cache the manager's content-addressed store (vcpkg's binary cache or `files` provider directory, Conan's package cache) and run the install step on every job. Never skip `vcpkg install` or `conan install` on an `actions/cache` hit. A cached installed tree is keyed on a hash of the manifest or lock and the baseline. | vcpkg's binary cache is keyed by an ABI hash over port files, triplet, both compilers and the CMake version, so the store never serves a stale archive. A cached `installed/` tree with the install skipped on a hit freezes the dependency set at the first save, silently. Floor: any `actions/cache` version. | `grep -rn -C3 -e 'cache-hit' .github` lists guarded steps: one guarding a `vcpkg install` or `conan install` is the finding, and empty output is the pass. `grep -rn -A12 -e 'actions/cache' .github` lists cache steps: a `path:` naming `installed` or `vcpkg_installed` whose `key:` has no `hashFiles(` over `vcpkg.json` or `conan.lock` is the finding. | SHOULD |

## Where the Depth Is

Read the file for the work you are about to do, not for the topic it is filed
under. One level deep. These files do not point at each other.

| Doing… | Read |
|---|---|
| Editing a `conanfile.py`, `conanfile.txt`, `conandata.yml` or `conan.lock`; choosing a generator; wiring Conan into CMake; running `conan install` in CI; publishing a Conan recipe | [cpp-packaging/conan.md](cpp-packaging/conan.md) |
| Writing or changing a Conan profile, which has no fixed file name and so loads no rule by glob at all | [cpp-packaging/conan.md](cpp-packaging/conan.md), read from here, because this line is the only route |
| Editing `vcpkg.json` or `vcpkg-configuration.json`, a triplet or a `portfile.cmake`; wiring vcpkg into CMake; caching its binaries or assets in CI | [cpp-packaging/vcpkg.md](cpp-packaging/vcpkg.md) |
| Composing toolchain files, injecting a dependency provider, or ordering what the first `project()` reads | `cmake-build/toolchains-and-providers.md` (`CMK-TC`, sibling set) |
| Adding or pinning a FetchContent, CPM, Hunter or `find_package` dependency beside a manager, or finding out which copy was used | `cmake-build/dependencies.md` (`CMK-DEP`, sibling set) |
| Guarding the language standard or the MSVC runtime in `CMakeLists.txt` | `cmake-build/targets.md` (`CMK-TGT`, sibling set) |
| Editing `CMakePresets.json` or a pipeline that runs CMake, or pinning the CMake it uses | `cmake-build/presets-and-ci.md` and `versions-and-policies.md` (sibling set) |
| Feeding Conan or vcpkg packages to a Bazel build of the same code | `cmake-build/bazel-seam.md` (`CMK-BZL-14`, `CMK-BZL-15`, sibling set) |

## Severity

MUST = Block: fix before it lands. SHOULD = Warn: fix, or state why not in the
commit body. CONSIDER = Suggest: never blocks, never re-raised after a decline.

Rules marked **pinned** in a depth file encode an agreed decision rather than a
derivable fact: `CMakeDeps` as the explicit-flow generator until a Conan
changelog calls `CMakeConfigDeps` stable (`CMK-CONAN-04`), the explicit
`conan install` flow over the cmake-conan provider (`CMK-CONAN-07`), and vcpkg
entering through its toolchain before the first `project()` (`CMK-VCPKG-04`).
They are defaults an adopter may override once, repository-wide, never per
leg. Overriding one is a decision. Ignoring one is a violation.

Every verification states what empty output means. Before adding one, watch it
go red against a deliberately broken copy. A check that cannot fail launders an
unchecked change as a checked one.

## Siblings

- **`cmake-build`**, the CMake side of every seam here: toolchains and
  providers, FetchContent and CPM, targets, presets and CI, the configure gate
  and its `CMK-CORE` rows. Loads on `CMakeLists.txt`, `*.cmake` and presets.
  A `portfile.cmake` loads both rules on purpose, and a vcpkg triplet loads
  only `cmake-build`, whose index routes it to `cpp-packaging/vcpkg.md`.
- **`python-quality`**, which also loads on every `conanfile.py` and owns its
  Python style. The Conan API rules stay here.
- **`bazel-quality`**, for a repository that also builds with Bazel. It owns
  `BZL-CC-24` and every Bazel-side fact, and this set cites them by ID only.
