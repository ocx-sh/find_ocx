---
title: The Bazel Seam and Dual Builds
summary: "The CMK-BZL family: what a CMake project owes a rules_foreign_cc wrap, which CMake that wrap runs, how a CMake and a Bazel description of one codebase stay in step, and what Conan and vcpkg reach across the seam"
---

# The Bazel Seam and Dual Builds

Owns the wrapped project's side of rules_foreign_cc's `cmake()` contract, the
CMake the wrapper provisions, the sync between a CMake and a Bazel description of
one codebase, and the Conan and vcpkg bridges into Bazel. Neighbours own every
general rule a wrap merely exercises: offline configure is `CMK-DEP`
(`dependencies.md`), the toolchain file `CMK-TC` (`toolchains-and-providers.md`),
flags, PIC and library type `CMK-TGT` (`targets.md`), destinations and relocation
`CMK-INST` (`install-and-export.md`), the floor's spelling `CMK-VER`
(`versions-and-policies.md`), the gate `CMK-CORE` (the index), and the hosted
runner's offline form `CMK-CI` (`presets-and-ci.md`). Conan and vcpkg in general
are `CMK-CONAN` and `CMK-VCPKG` in the `cpp-packaging` rule set. The Bazel half
(the `cmake()` attributes, `out_*` names, the compile database, when to wrap at
all) is `BZL-CC-22`, `BZL-CC-23`, `BZL-CC-24` and `BZL-CC-28` in `bazel-quality`,
cited and never restated.

Contents: [The Wrap Simulation](#the-wrap-simulation) · [The CMake the Wrapper Runs](#the-cmake-the-wrapper-runs) ·
[The Symlink Farm](#the-symlink-farm) · [CI and Generated Descriptions](#ci-and-generated-descriptions) ·
[Before Reporting Drift or Writing a Mapping](#before-reporting-drift-or-writing-a-mapping) ·
[Package Managers Across the Seam](#package-managers-across-the-seam) ·
[What Agents Get Wrong Here](#what-agents-get-wrong-here) · [Re-check](#re-check)

## The Wrap Simulation

Binds a library shipping a package that anyone may wrap with rules_foreign_cc's
`cmake()`. At 0.16.0 (2026-09-15) that rule runs configure, build and install as
one `block-network` action and reaches the project only through `-D` cache
entries and a toolchain file whose flags arrive as `CMAKE_<LANG>_FLAGS_INIT`
seeds. The script stands in for it without Bazel, and one run answers five rows.
Run it from the project root on the wrapper's CMake line (3.31 by default,
`CMK-BZL-08`), on Linux with unprivileged user namespaces. On a hosted
`ubuntu-24.04` runner use a `--network none` container instead (`CMK-CI-05`).
Floor: CMake 3.25. Measured 2026-09-26 on 3.31.12 and 4.4.2. A real wrap
(rules_foreign_cc 0.16.0 on Bazel 9.2.0, 2026-09-26) confirmed rows 01, 02, 05
and 07 and the dropped seed in row 03.

```sh
set -e
rm -rf build-wrap wrap-prefix wrap-listing.txt wrap-configure.log
# Gate per binary (CMK-CORE-01): -Werror=dev on the wrapper's 3.31 line, -Werror=author on 4.4.
GATE=-Werror=dev
# Stands in for the wrapper's synthesised toolchain file: flags arrive only as _INIT seeds.
printf 'set(CMAKE_C_FLAGS_INIT "-fPIC -DWRAP_SEED=1")\nset(CMAKE_CXX_FLAGS_INIT "-fPIC -DWRAP_SEED=1")\nmessage(STATUS "CALLER_TOOLCHAIN_LOADED")\n' >wrap-toolchain.cmake
# No FETCHCONTENT_FULLY_DISCONNECTED: the wrapper passes none, and it hides a fetch.
unshare -rn cmake -S . -B build-wrap "$GATE" -DCMAKE_POLICY_DEFAULT_CMP0170=NEW \
  -DCMAKE_TOOLCHAIN_FILE="$PWD/wrap-toolchain.cmake" -DCMAKE_INSTALL_PREFIX="$PWD/wrap-prefix" \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DBUILD_SHARED_LIBS=OFF >wrap-configure.log 2>&1 || { cat wrap-configure.log; exit 1; }
unshare -rn cmake --build build-wrap -j 4
cmake --install build-wrap
find wrap-prefix -type f -o -type l | sort >wrap-listing.txt
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-BZL-01 | Make configure, build and install succeed with no network, given only `-D` cache entries. Give every fetch a cache-entry route to a local copy: `FETCHCONTENT_SOURCE_DIR_<NAME>`, `FETCHCONTENT_TRY_FIND_PACKAGE_MODE` or `FIND_PACKAGE_ARGS` (CMake ≥ 3.24), or an `option()` that turns the fetch off. `FETCHCONTENT_FULLY_DISCONNECTED=ON` counts only when paired with `FETCHCONTENT_SOURCE_DIR_<NAME>`. | A git fetch fails at configure inside the network-blocked action. `FULLY_DISCONNECTED` alone only skips population: below policy version 3.30 it warns and configures with the dependency silently absent, and with CMP0170 NEW it is a hard error (measured 2026-09-26 on 3.31.12 and 4.4.2). The general offline rule, and the grep that lists what needs a switch, are `CMK-DEP-16`. | The simulation exits 0 and `grep -n -e 'Failed to clone' -e 'Could not resolve host' -e 'FETCHCONTENT_FULLY_DISCONNECTED is set to true' wrap-configure.log` prints nothing: the pass. A non-zero exit, or any line, is the finding. | MUST |
| CMK-BZL-02 | Owned by `CMK-TC-01`. This ID keeps only the wrap probe: the caller's toolchain file must be the one that loads. | Passing `CMAKE_TOOLCHAIN_FILE` suppresses the wrapper's crosstool synthesis, so the caller's file carries the whole compiler setup. A project `set(CMAKE_TOOLCHAIN_FILE …)` before `project()` beats it with no warning (measured on 3.31.12 and 4.4.2). | After the simulation, `grep -c -e 'CALLER_TOOLCHAIN_LOADED' wrap-configure.log`. `0` is the finding. Any higher count is the pass. | MUST |
| CMK-BZL-03 | Owned by `CMK-TGT-04` (never overwrite the flags variables) and `CMK-TGT-12` (PIC). This ID keeps the wrap probe and one clause: never make PIC depend on `CMAKE_POSITION_INDEPENDENT_CODE`, because the wrapper delivers `-fPIC` as a flag. | Since rules_foreign_cc 0.16.0 PIC arrives inside the `_INIT` seed. `set(CMAKE_C_FLAGS "-O2")` discards the seed, and the shared link fails with `relocation R_X86_64_32 … recompile with -fPIC`. A hard-coded `CMAKE_POSITION_INDEPENDENT_CODE OFF` does not block the flag (both measured on 3.31.12 and 4.4.2). So the fix for a wrapped PIC failure is the flags write, never the variable. In a real wrap on Bazel 9.2.0 the seed carries `-fPIC`, and the write removes it from the compile line (measured 2026-09-26). | After the simulation, `grep -c -e 'WRAP_SEED' build-wrap/compile_commands.json`. `0` is the finding (the seed was dropped). Any higher count is the pass. Makefile and Ninja generators only. A successful link is not a pass: a compiler that always emits PIC links either way. | MUST |
| CMK-BZL-04 | Owned by `CMK-INST-10` (no absolute install `DESTINATION`). This ID keeps only the wrap consequence. | The wrap installs into a Bazel-managed output tree. A declared `out_*` file sent elsewhere fails the build with `missing expected installed output`. An undeclared file sent to a path the sandbox can write lands on the host outside every Bazel output, and the build passes (measured 2026-09-26, rules_foreign_cc 0.16.0 on Bazel 9.2.0). | `CMK-INST-10`'s grep, or its CMake 4.4 diagnostic. This ID adds no command. | MUST |
| CMK-BZL-05 | Install to a fresh prefix and check two things. Every file sits at a stable name under `include/`, `lib/` or `bin/` that the wrapping target's `out_*` attributes can name. No installed file contains the source, build or install path: a `*Config.cmake`, `*Targets*.cmake` or `.pc` file, or a header `configure_file()` wrote. | A produced file that no attribute names never becomes a Bazel output, and nothing reports it (`BZL-CC-23` owns that side). The sandbox path disappears after the action, so an embedded absolute path breaks every consumer. A real wrap on Bazel 9.2.0 wrote the per-action sandbox path into a configured header (measured 2026-09-26). Relocation in general is `CMK-INST-01` and `CMK-INST-02`. This row adds only the diff against the declared names. | After the simulation, `grep -rn -e "$PWD" wrap-prefix`. Empty output is the pass. Any line is the finding. Then diff `wrap-listing.txt` by hand against the `out_*` names the wrapping `BUILD.bazel` declares or would need to declare. A name in only one list is the finding. | MUST |
| CMK-BZL-07 | Owned by `CMK-TGT-11` (library type from a cache entry). This ID keeps only the wrap consequence. | `cache_entries` is the only channel the wrapper has into the project, so a hard-coded `STATIC` or `SHARED` turns the choice between `out_static_libs` and `out_shared_libs` into source-reading. In a real wrap a hard-coded `STATIC` under `BUILD_SHARED_LIBS=ON` fails with `missing expected installed output: lib/libmylib.so` (measured 2026-09-26 on Bazel 9.2.0). | `CMK-TGT-11`'s verification. This ID adds no command. | SHOULD |

## The CMake the Wrapper Runs

The CMake inside the wrap is the wrapper's, never the host's. At rules_foreign_cc
0.16.0 the default is 3.31.12 (measured 2026-09-26: every wrap on Bazel 9.2.0 ran
`cmake-3.31.12-linux-x86_64`) and the prebuilt table runs 3.19.8 to 4.0.7 (read
2026-09-26). The first command, run in the consuming Bazel workspace, names the
line a consumer picked (empty output: the default). Floor: CMake 3.25, 4.3 for CPS.

```sh
grep -rn -e 'tools.cmake' -e 'cmake_version' --include='MODULE.bazel' --include='WORKSPACE*' .
grep -rn -e 'install(PACKAGE_INFO' -e 'export(PACKAGE_INFO' --include='*.cmake' --include='CMakeLists.txt' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-BZL-08 | Keep `cmake_minimum_required`'s lower bound at or below the CMake the wrapper provisions (3.31.12 by default at rules_foreign_cc 0.16.0). Guard every newer feature with `if(CMAKE_VERSION VERSION_GREATER_EQUAL x.y)`, CPS export (`install(PACKAGE_INFO)`, CMake ≥ 4.3) included, and always ship the CMake-script Config package beside CPS. The range spelling is `CMK-VER-02`. | A `VERSION 4.1` floor fails on 3.31.12 with `CMake 4.1 or higher is required`. A guarded `install(PACKAGE_INFO)` is skipped on 3.31.12 and emitted on 4.4.2 (measured 2026-09-26). The floor error and an unguarded `install(PACKAGE_INFO)` both fail inside a real wrap on Bazel 9.2.0. No CMake in the wrapper's table reaches 4.3, so a CPS-only package is unconsumable through the wrap. | Run the simulation on the line the first grep names. A configure error there is the finding. Then the second grep: empty output is the pass. Each hit must sit inside a `CMAKE_VERSION` guard next to an `install(EXPORT)` Config package, and an unguarded hit is the finding. | MUST |

```cmake
# wrong: an unguarded install(PACKAGE_INFO …) is an unknown mode on 3.31.12
# right: Config always, CPS only where the running CMake has it
install(
    EXPORT mylibTargets
    NAMESPACE mylib::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/mylib
)
if(CMAKE_VERSION VERSION_GREATER_EQUAL 4.3)
    install(PACKAGE_INFO mylib EXPORT mylibTargets)
endif()
```

## The Symlink Farm

Bazel's sandbox is a tree of symlinks: real directories, and a link for each file. The farm reproduces it without Bazel. Run
it from the project root. Floor: CMake 3.19 for `file(REAL_PATH)`. Measured
2026-09-26 on 3.31.12 and 4.4.2.

```sh
rm -rf ../wrap-farm ../wrap-farm-build ../wrap-farm-prefix
cp -rs "$PWD" ../wrap-farm
cmake -S ../wrap-farm -B ../wrap-farm-build -Werror=dev -DCMAKE_INSTALL_PREFIX="$PWD/../wrap-farm-prefix"
cmake --build ../wrap-farm-build
cmake --install ../wrap-farm-build
find ../wrap-farm-prefix -type l -lname '/*'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-BZL-06 | Install real files, never symlinks. Resolve each header and data file through `file(REAL_PATH)` and install the result with `install(FILES)`. Resolving a directory changes nothing, because `install(DIRECTORY)` copies the links inside it. | From the farm, the installed header is an absolute link to a path outside the prefix. A `file(REAL_PATH)` source installs a regular file. A real wrap on Bazel 9.2.0 installs the same absolute link from a plain `install(DIRECTORY include/ …)`, and from one whose directory went through `file(REAL_PATH)` first (measured 2026-09-26, the directory case also through the farm on 3.31.12 and 4.4.2). This matches rules_foreign_cc [#1129](https://github.com/bazel-contrib/rules_foreign_cc/issues/1129) ("invalid symlink" in the tree artifact), open on 2026-09-26. A local consumer still builds. The break needs a remote cache or remote execution round trip, not reproduced here, hence SHOULD. | The farm block above. Empty `find` output is the pass. Any line is the finding. The relative namelinks `install(TARGETS)` makes for shared libraries stay inside the prefix and are not findings. | SHOULD |

## CI and Generated Descriptions

Binds a project that keeps both a CMake and a Bazel description of one codebase,
and every agent that reports on one. abseil, googletest and grpc test Bazel from
scripts under `ci/` or `tools/internal_ci/`, so read those too (`-s` silences a
missing directory). Set `FILE` to each file you will edit or report on. Floor: any CMake.

```sh
grep -rls -e 'bazel test' -e 'bazelisk test' .github ci tools/internal_ci
grep -rls -e 'ctest' -e 'cmake --build' .github ci tools/internal_ci
grep -rln -i -e 'auto-generated' -e 'automatically generated' -e 'do not edit' --include='*.cmake' --include='CMakeLists.txt' --include='BUILD.bazel' .
FILE=BUILD.bazel
grep -rl -F -e "$FILE" --include='*.yml' --include='*.yaml' --include='*.sh' --include='*.py' --include='*.cmake' --include='Makefile' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-BZL-09 | Build and test both descriptions in CI on the same trigger. Report a job that only builds one side as partial sync, never as tested. **pinned**: SHOULD is a default an adopter raises to MUST once, repository-wide. | Of 11 dual repositories read on 2026-09-26, 7 build and test both, Catch2 and gflags only build the Bazel side, and zlib and nlohmann/json never build Bazel in CI while staying healthy and maintained, which is why this is not MUST. | The first two greps. Empty Bazel-test output while a `MODULE.bazel` exists is the finding (partial or no sync). An empty `.github/workflows` alone is never evidence of no CI. | SHOULD |
| CMK-BZL-10 | Keep one source of truth for dependency versions. Generate one side's pins from the other and run a staleness test in CI. Never hand-maintain two pins for one dependency. | protocolbuffers/protobuf generates `cmake/dependencies.cmake` from `MODULE.bazel`, a daily job runs every `staleness_test` target, and a post-submit job regenerates. The two hand-maintained pairs read on 2026-09-26 (yaml-cpp and benchmark) had both drifted on googletest. | The third grep. A hit: read the generator, then confirm a CI job runs its staleness check, and no such job is the finding. Empty output while `MODULE.bazel` and the CMake side pin the same package is the finding (hand-maintained), then measure the drift with `CMK-BZL-12`. | SHOULD |
| CMK-BZL-11 | Treat a file with a generated header, or one a script or CI step regenerates, as derived. Name its generator in the change or the report before editing it or claiming drift in it, and never hand-edit it. | Generation runs both ways. grpc/grpc generates its root `CMakeLists.txt` from Bazel metadata, protobuf generates its CMake pins from `MODULE.bazel`, and nlohmann/json regenerates `BUILD.bazel` from a CMake script on every pull request with no generated header at all. A hand edit is overwritten, and a version that matches by construction is not drift. | The last two greps, once per file. A hit on either marks the file derived, and an edit or drift claim that does not name the generator is the finding. Both empty means hand-authored: edit freely. | MUST |

## Before Reporting Drift or Writing a Mapping

No build catches these. They govern what an agent writes in a report. Module and
package names usually differ (`abseil-cpp` against `absl`), so set both, taking
`CMAKE_NAME` from the dependency's Config package or the `find_package` call. The
bare `$BZL_NAME` alternative catches a vendored directory (`googletest-1.16.0`). Floor: any CMake.

```sh
BZL_NAME=abseil-cpp
CMAKE_NAME=absl
grep -rn -e "bazel_dep(name = \"$BZL_NAME\"" --include='MODULE.bazel' .
grep -rn -i -e "find_package($CMAKE_NAME" -e "FetchContent_Declare($CMAKE_NAME" -e "ExternalProject_Add($CMAKE_NAME" -e "$BZL_NAME" --include='*.cmake' --include='CMakeLists.txt' .
git ls-tree -r HEAD | grep -e '^160000'
grep -rn -e 'NAMESPACE' -e 'ALIAS' --include='*.cmake' --include='CMakeLists.txt' .
grep -rn -A2 -e 'cc_library(' --include='BUILD.bazel' --include='BUILD' .
grep -rn -e 'module(' --include='MODULE.bazel' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-BZL-12 | Report "not knowable statically" whenever the CMake side carries no version token: an unversioned `find_package`, a git submodule gitlink, or a vcpkg-baseline resolution. Never report such a pair as "same" or "no drift". | google/re2's `find_package(absl REQUIRED)` carries no version against `abseil-cpp 20250814.1` in its `MODULE.bazel`, and its CI resolves through a vcpkg baseline, a third source. With one name for both sides the CMake grep reads "no pair" for exactly that pair. | The first three commands. A CMake-side hit with no version argument or `GIT_TAG`, or any gitlink line, reads NOT KNOWABLE. A versioned vendored directory, or two concrete versions, is compared. An empty CMake side is no pair. A report of "same" or "no drift" for a NOT KNOWABLE pair is the finding. | MUST |
| CMK-BZL-13 | Never derive a Bazel label from a CMake imported target, or the reverse. Read both descriptions before writing a mapping. | 6 of 8 pairs measured on 2026-09-26 fail a pattern match: `ZLIB::ZLIB` is `@zlib//:z`, `GTest::gtest` is `@googletest//:gtest`, and `nlohmann_json::nlohmann_json` is `@nlohmann_json//:json`. | The last three commands. A mapping written without both outputs in hand is the finding. Empty output on either side means that side has no mapping to derive: read the other side only. | MUST |

## Package Managers Across the Seam

Binds an application consuming packages that also builds with Bazel. The third
command runs against a vcpkg checkout. Source read 2026-09-26 at Conan 2.32.0,
vcpkg 2026.07.29 and vcpkg-tool 2026-07-27. CMK-BZL-14 was measured end to end on
Conan 2.32.0 and Bazel 9.2.0 (2026-09-26). Floor: Conan 2.30.0 and Bazel 7.2.0 for CMK-BZL-14, any vcpkg for CMK-BZL-15.

```sh
grep -rn -e 'BazelDeps' --include='conanfile.py' --include='conanfile.txt' .
grep -rn -e 'conan_deps.MODULE.bazel' --include='MODULE.bazel' .
grep -rln -i -e 'bazel' "$VCPKG_ROOT/scripts"
grep -n -e 'bazel_dep(name = "rules_cc"' MODULE.bazel
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-BZL-14 | Wire Conan into a Bzlmod root module with the generated include: `BazelDeps` plus `include("//<generators-folder>:conan_deps.MODULE.bazel")` in the root `MODULE.bazel`, paired with `BazelToolchain`'s `conan_bzl.rc` passed as `--bazelrc=… --config=conan-config`. When the root module has its own `bazel_dep(name = "rules_cc", …)`, delete that line, because the generated file declares one. Never edit the generated file, never hand-write a `local_path_override` for Conan output, and never state that Conan's Bazel support is WORKSPACE-only. | Conan 2.30.0 added the include file ([conan-io/conan#20042](https://github.com/conan-io/conan/pull/20042)), unchanged at 2.32.0. Bazel's `include()` (Bazel ≥ 7.2.0) works only in the root module, so a module published to the BCR cannot use this path. The docs landing page shows only WORKSPACE and no adopter was found, hence SHOULD. The generated file wires Conan's rules_cc extension, which Conan labels Bazel 9+. On Bazel 7.1 to 8.x Conan points to `conan_deps_module_extension.bzl` through a hand-written `use_extension`. Measured 2026-09-26 on Bazel 9.2.0: the include built and ran a `cc_binary` against Conan's zlib 1.3.1. The generated file declares `bazel_dep(name = "rules_cc", version = "0.2.17")`, so a second one in the root fails with `The repo name 'rules_cc' cannot be defined by a bazel_dep`. Without the root's line, resolution still picked the 0.2.18 that rules_foreign_cc 0.16.0 needs. | The first two greps. A `BazelDeps` hit with an empty include grep is the finding. Both empty means not applicable. With the include present, the fourth grep must print nothing, and any line is the finding. | SHOULD |
| CMK-BZL-15 | State that vcpkg has no Bazel bridge: no `vcpkg export` Bazel format and no maintained `rules_vcpkg`. Offer hand-written repository rules over the vcpkg installed tree, or move that dependency to a BCR module or a rules_foreign_cc wrap. | The only Bazel paths in microsoft/vcpkg run the other way, acquiring Bazel for Bazel-built ports, and microsoft/vcpkg-tool has none. | A recommendation that names a vcpkg Bazel generator is the finding. Negative re-check, the third grep: it lists exactly two files, ending `scripts/cmake/vcpkg_find_acquire_program(BAZEL).cmake` and `scripts/test_ports/vcpkg-find-acquire-program/portfile.cmake`. Any other file is new: read it before citing this row. | MUST |

## What Agents Get Wrong Here

1. **Calling a dual repository "no sync" from an empty `.github/workflows`.**
   abseil and googletest test Bazel from Kokoro scripts (`CMK-BZL-09`).
2. **Treating a generated file as hand-written,** so a drift finding is false or
   a hand edit is erased. nlohmann/json's `BUILD.bazel` has no header (`CMK-BZL-11`).
3. **Reporting "no drift" when the CMake side carries no version,** or reading
   "no pair" from one name shared by both sides (`CMK-BZL-12`).
4. **Fixing a wrapped PIC failure with `CMAKE_POSITION_INDEPENDENT_CODE ON`**
   when a `set(CMAKE_C_FLAGS …)` dropped the injected `-fPIC` (`CMK-BZL-03`).
5. **Assuming the host's CMake runs inside the wrap,** then recommending CPS or
   a 4.x floor because "CMake 4.4 supports it" (`CMK-BZL-08`).
6. **Guessing `@zlib//:zlib` for `ZLIB::ZLIB`.** It is `@zlib//:z` (`CMK-BZL-13`).
7. **"Conan's Bazel support is WORKSPACE-only"** from the landing page, or a
   hand-written `local_path_override` (`CMK-BZL-14`).
8. **Inventing `rules_vcpkg` or `vcpkg export --bazel`** (`CMK-BZL-15`).
9. **Setting a convenience toolchain such as vcpkg's before `project()`,** which
   silently beats the caller's (`CMK-BZL-02`).
10. **Chasing a "missing file" when Bazel reports "invalid symlink"** after a
    wrapped install (`CMK-BZL-06`).
11. **Passing `FETCHCONTENT_FULLY_DISCONNECTED=ON` to the simulation,** which hides a fetch (`CMK-BZL-01`).
12. **Spelling the gate `-Werror=author` on the wrapper's 3.31 line,** where it is accepted and does nothing (`CMK-CORE-01`).
13. **Resolving the include directory through `file(REAL_PATH)` and calling the symlink fixed.**
    `install(DIRECTORY)` still copies each linked file as an absolute link (`CMK-BZL-06`).
14. **Editing the generated `conan_deps.MODULE.bazel`, or dropping the include,** when it
    collides with the root's own `rules_cc` pin. Delete the root's line instead (`CMK-BZL-14`).

## Re-check

- D5: the rules_foreign_cc default CMake and version table (`CMK-BZL-08`) at every release after 0.16.0.
- D4: Conan and vcpkg-tool tags (`CMK-BZL-14`, `CMK-BZL-15`), and the `rules_cc` pin in Conan's generated include.
- D1: the simulation's gate spelling on CMake 4.5 (`CMK-CORE-01`).
- Unmeasured as of 2026-09-26: the "invalid symlink" consumer break of rules_foreign_cc#1129
  through a remote cache, the wrapped PIC link failure inside a real wrap (the measuring
  compiler always emitted PIC), and the include file on Bazel 7.2 to 8.x.
