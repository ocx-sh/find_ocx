---
title: Consuming Dependencies and Knowing Which Copy Won
summary: The CMK-DEP family. How a CMake project acquires, pins and resolves a third-party dependency (find_package, FetchContent, CPM, Hunter, vendoring, CPS import), how it injects policy into one, and how to prove which copy a configure used
---

# Consuming Dependencies and Knowing Which Copy Won

Owns the consuming side of the dependency seam: the pin on a fetched source,
who chooses between a fetched and an installed copy, the cache record of which
copy won, policy injected into a third-party project, the offline configure,
removed Find modules, CPS import, and the root-path traps of a cross build. It
does not own the toolchain file, `CMAKE_PROJECT_TOP_LEVEL_INCLUDES`, dependency
providers or the find-root modes a toolchain sets, which are `CMK-TC` in
`toolchains-and-providers.md`. Exporting a package, CPS export included, is
`CMK-INST` in `install-and-export.md`. The floor and the policy-adoption rules
are `CMK-VER` in `versions-and-policies.md`, and CMK-VER-06 cites CMK-DEP-15 and
CMK-DEP-30 rather than restating them. A module that downloads, and its
timeouts, is `CMK-MOD` in `module-authoring.md`. The container form of the
offline probe is CMK-CI-05 in `presets-and-ci.md`. The manager of record and
everything Conan- or vcpkg-specific belong to the `cpp-packaging` rule.

Contents: [Pins](#caught-by-grepping-the-acquisition-calls) ·
[Resolution Seam](#caught-by-a-consumer-configure) ·
[Which Copy Won](#caught-by-reading-the-cache-first) ·
[Policy Injection](#caught-by-grepping-for-policy-and-warning-knobs) ·
[Offline](#caught-by-a-configure-with-the-network-removed) ·
[find_package Calls](#caught-by-grepping-the-find_package-calls) ·
[Cross Builds](#caught-by-a-fresh-configure-under-a-root-path) ·
[What Agents Get Wrong Here](#what-agents-get-wrong-here) · [Re-check](#re-check)

Measured on CMake 3.31.12, 4.3.4 and 4.4.2 on 2026-09-26 unless a row names
otherwise. Rules assume the pinned floor, `cmake_minimum_required(VERSION
3.25...4.4)`. Every configure below runs under the configure gate of CMK-CORE-01
(`-Werror=author` on a CMake 4.4 or newer leg, `-Werror=dev` on 4.3 and older,
`-Werror=dev` when one command line serves both). Every probe that touches
FetchContent passes `-DCMAKE_POLICY_DEFAULT_CMP0170=NEW`, because without it a
disconnected configure of an empty source directory exits 0 on a range that
stops below 3.30. Run every command from the repository root.

## Caught by Grepping the Acquisition Calls

```sh
# CMK-DEP-01: literal branch pins, then a GIT_TAG whose value sits on the next line.
grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'GIT_TAG[[:space:]]+"?main\b' -e 'GIT_TAG[[:space:]]+"?master\b' -e 'GIT_TAG[[:space:]]+"?develop\b' -e 'GIT_TAG[[:space:]]+"?HEAD\b' -e '#main"' -e '#master"' .
grep -rnE -A1 --include='*.cmake' --include='CMakeLists.txt' -e 'GIT_TAG[[:space:]]*$' .
# CMK-DEP-02: a literal pin that is not 40-hex, then CPM shorthand without a #commit.
grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'GIT_TAG[[:space:]]+"?[^"[:space:])$]' . | grep -vE -e 'GIT_TAG[[:space:]]+"?[0-9a-f]{40}\b'
grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e '"gh:[^"#]*@[^"#]*"' .
# CMK-DEP-03: files holding a URL fetch and no hash at all.
grep -rlE --include='*.cmake' --include='CMakeLists.txt' -e '\bURL[[:space:]]+"?https?:' -e '\bURL[[:space:]]+"?\$\{' . | xargs -r grep -L -e URL_HASH -e URL_MD5
# CMK-DEP-04: the one-argument FetchContent_Populate.
grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'FetchContent_Populate[[:space:]]*\([[:space:]]*[A-Za-z0-9_]+[[:space:]]*\)' .
# CMK-DEP-05: a vendored CPM.cmake whose bootstrap download is not hash-checked.
grep -rl --include='CPM.cmake' -e 'CPM_DOWNLOAD_VERSION' . | xargs -r grep -L -e 'EXPECTED_HASH'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-DEP-01 | Never pin a fetched git dependency to a branch or `HEAD`, whether through `GIT_TAG`, a CPM shorthand `#ref` or `@ref`, in `FetchContent_Declare`, `ExternalProject_Add` or `CPMAddPackage`. Resolve every variable-valued or macro-parameter ref to its definition before judging it. "Opaque" is never a verdict. | A branch pin builds different code from the same commit, and OpenSSF Scorecard's Pinned-Dependencies check does not read CMake, so nothing else catches it. A `${VAR}` can hide a real hash or `"master"`, and its definition can sit outside any CMake file (arrow keeps its pins in `cpp/thirdparty/versions.txt`). Floor: FetchContent 3.11, any CPM. | Both DEP-01 lines above: any line = finding, empty = pass. The second prints the value on the following line, read it. For a `${VAR}` value run `NAME=EXAMPLE_TAG; grep -rn -e "set($NAME" .` with no `--include`, and for a macro parameter grep the macro's call sites. | MUST |
| CMK-DEP-02 | Pin to a full 40-hex commit, keeping the human-readable tag as a trailing comment (FetchContent) or as `gh:owner/repo#COMMIT@VERSION` (CPM). | CMake's FetchContent docs and CPM's README both recommend an immutable hash, and a tag can be moved. Real CPM refs are mostly tags, so a tag warns and does not block. Floor: as CMK-DEP-01. | Both DEP-02 lines above: each line is a literal non-hash pin or a CPM shorthand without `#COMMIT`. Empty = pass. | SHOULD |
| CMK-DEP-03 | Give every URL-form fetch a `URL_HASH`: `FetchContent_Declare`, the direct-population `FetchContent_Populate(NAME URL …)`, `ExternalProject_Add` and CPM `URL`. An artifact that changes under its pin ("nightly") is an explicit, commented opt-in. Download timeouts are CMK-MOD-17's (`module-authoring.md`). | Without the hash the bytes are whatever the server returns today. `cmake --help-module ExternalProject` (4.4.2) calls the hash "strongly recommended". Floor: 3.11. | DEP-03 line above: a listed file = finding, empty = pass at file grain. `\b` keeps `GIT_URL` out. A file mixing hashed and unhashed blocks passes the grep, so read each `URL` block in the files it did not list. | MUST |
| CMK-DEP-04 | Use `FetchContent_MakeAvailable`, never the one-argument `FetchContent_Populate(NAME)`. The multi-argument direct-population form is not deprecated and is not a finding. | CMP0169 (3.30) deprecates the one-argument form. Agents also flag the direct form as deprecated, which it is not. Floor: `MakeAvailable` 3.14, CMP0169 3.30. | DEP-04 line above: any line = finding, empty = pass. The regex matches a bare name in the parentheses only. | SHOULD |
| CMK-DEP-05 | A vendored `CPM.cmake` pins `CPM_DOWNLOAD_VERSION` and hash-checks its own bootstrap with `EXPECTED_HASH`. Treat `include(CPM.cmake)` as setting `CMAKE_POLICY_DEFAULT_CMP0077`, `_CMP0126`, `_CMP0135` and `_CMP0150` to `NEW` for every subproject added after it, CPM-managed or not. | An unhashed bootstrap runs whatever script the URL serves. The policy leak is measured on 3.31.12 and 4.4.2: the includer's own policies are untouched, but every later subproject's defaults change. Floor: CPM v0.43.2 (as of 2026-09-26). | DEP-05 line above: a listed file = finding, empty = pass. Then read: a non-CPM subproject with a floor below 3.13 added after the CPM include now runs with CMP0077 `NEW`. Say so in review. | SHOULD |
| CMK-DEP-06 | Do not introduce `HunterGate` into a new project. An existing call pins `URL` plus `SHA1` of Hunter v0.26.10 or later, the release with the last per-package CMake 4 fix (cpp-pm/hunter#858, Protobuf). A vendored `HunterGate.cmake` comes from cpp-pm/gate `9205073` or later, because the v0.9.2 tag writes a 3.2 floor into its bootstrap project. | Hunter is maintained (v0.26.12, 2026-09-22) but none of 45 surveyed public C++ projects adopts it, so this rests on adoption, not on normative text. CMake 4 support arrived per package across v0.26.7 to v0.26.10. Floor: any. | `grep -rn --include='*.cmake' --include='CMakeLists.txt' -e 'HunterGate(' .` Empty = not applicable. For a hit, read the release in its `URL`: older than v0.26.10 = finding. Then `grep -rn --include='HunterGate.cmake' -e '"cmake_minimum_required(VERSION' .` A value below 3.10 = finding (below 3.5 stops CMake 4 on an empty root, and the child's deprecation is never gated). Empty = not applicable. | CONSIDER |

A git submodule with `branch =` in `.gitmodules` is not floating (the gitlink
is a fixed commit), and a vendored directory is pinned by the repository
itself. Neither is a CMK-DEP-01 finding. A CI step running `git submodule
update --remote` is.

## Caught by a Consumer Configure

The order `FetchContent_MakeAvailable` follows, normative in FetchContent at
4.4.2 and measured where it matters. Read it with `--debug-find-pkg=NAME` on a
`--fresh` configure only (CMK-DEP-17).

| Step | What happens |
|---|---|
| 1 | `FETCHCONTENT_SOURCE_DIR_<X>` is set: that directory is added. No provider, no `find_package`, no `PATCH_COMMAND` (CMK-DEP-31) |
| 2 | A provider registered for `FETCHCONTENT_MAKEAVAILABLE_SERIAL` is called. If it satisfies the name, done |
| 3 | `find_package(<X> <FIND_PACKAGE_ARGS>)` runs when the declare carries `FIND_PACKAGE_ARGS` and `FETCHCONTENT_TRY_FIND_PACKAGE_MODE` is `OPT_IN` (the default), or the mode is `ALWAYS`. Never under `NEVER` |
| 4 | Already populated in this run: reused. The first `FetchContent_Declare` of a name wins |
| 5 | Populated from the declared details. `OVERRIDE_FIND_PACKAGE`, or a `FIND_PACKAGE_ARGS` declare that fell through to here, writes a version-less stub into `CMAKE_FIND_PACKAGE_REDIRECTS_DIR` that answers every later `find_package(<X>)` |
| plain `find_package` | Provider, then the redirects directory, then a cached valid compatible `<X>_DIR` used as is, then `<X>_ROOT`, `CMAKE_PREFIX_PATH` (variable, then environment), system paths. That order holds only while `CMAKE_FIND_ROOT_PATH` and `CMAKE_SYSROOT` are empty (CMK-DEP-21). On 4.3+ each prefix also probes `cps/` |

```sh
# CMK-DEP-07 consumer probe. SRC = the library source (absolute), DEP_PREFIX = the
# dependency installed. Use a new build directory, so _deps starts empty.
GATE=-Werror=dev   # -Werror=author on a leg that runs CMake 4.4 or newer only
mkdir -p probe07
printf '%s\n' 'cmake_minimum_required(VERSION 3.25...4.4)' 'project(consumer LANGUAGES C)' \
  "add_subdirectory($SRC lib)" > probe07/CMakeLists.txt
cmake -S probe07 -B probe07/build "$GATE" -DCMAKE_PREFIX_PATH="$DEP_PREFIX" \
  -DFETCHCONTENT_FULLY_DISCONNECTED=ON -DCMAKE_POLICY_DEFAULT_CMP0170=NEW
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-DEP-07 | An installable library resolves its dependencies with `find_package` and never forces acquisition. Outside test, example, benchmark, docs, tool and binding code, `FetchContent_MakeAvailable` or `CPMAddPackage` runs only under a top-level guard (`PROJECT_IS_TOP_LEVEL`, shimmed below 3.21), on a declare carrying `FIND_PACKAGE_ARGS`, or as the fallback of a `find_package` that ran first behind a switch the consumer can flip. | A library that always fetches takes steps 2 and 3 away from every consumer, so the consumer's installed copy, lock and manager are ignored. A hand-written try-find-then-fetch (protobuf's `cmake/abseil-cpp.cmake`) passes, so never flag it for lacking the 3.24 keyword. The `FIND_PACKAGE_ARGS` try-find searches the declare's name, so a declare spelled differently from the package's Config file, case included, needs `NAMES <Package>` or it fetches silently. The probe catches it (exit 1 on 3.31.12 and 4.3.4 for `FetchContent_Declare(cjson …)` against an installed `cJSONConfig.cmake`, exit 0 with `NAMES cJSON`, 2026-09-26). Floor: 3.24 for `FIND_PACKAGE_ARGS`, any for try-find-then-fetch. | The probe above on each CI binary: exit 0 = pass (the installed copy was found), non-zero = finding. To locate candidates, `grep -rn --include='*.cmake' --include='CMakeLists.txt' -e 'FetchContent_MakeAvailable' -e 'CPMAddPackage' .` Empty = not applicable. A hit under a test, example, docs, tool or binding directory, or behind `PROJECT_IS_TOP_LEVEL`, `NOT dep_FOUND` or `NOT TARGET`, is not a finding. | MUST |
| CMK-DEP-08 | When a dependency can arrive either fetched or found, link only the namespaced name the installed package exports (`dep::dep`). A project that may itself be fetched defines matching `ALIAS` targets. | When `find_package` satisfies a `FIND_PACKAGE_ARGS` declare, only `dep::dep` exists and `TARGET dep` is false, so a consumer linking the bare `dep` breaks the day an installed copy appears. Floor: 3.24. | For each name declared with `FIND_PACKAGE_ARGS`: `NAME=dep; grep -rlzE --include='*.cmake' --include='CMakeLists.txt' -e "target_link_libraries\([^)]*[[:space:]]${NAME}[[:space:])]" .` A listed file = finding, empty = pass. `-z` reads each file as one record, so a call split across lines is caught and `dep::dep` is not. | MUST |
| CMK-DEP-09 | Never rely on a `find_package` version check against a fetched dependency: a name declared with `OVERRIDE_FIND_PACKAGE`, or with `FIND_PACKAGE_ARGS` when the installed copy was missing. A version in `FIND_PACKAGE_ARGS` (`FIND_PACKAGE_ARGS 2.0`) gates only the installed copy. Check the fetched version explicitly, and never put both keywords on one declare. | The redirect stub reports every version compatible and exact, so `find_package(dep 3.0 EXACT REQUIRED)` exits 0 against a fetched 1.0 with a blank `dep_VERSION`. Both keywords on one declare is a `FATAL_ERROR`. Floor: 3.24. | `grep -rn -A12 --include='*.cmake' --include='CMakeLists.txt' -e 'OVERRIDE_FIND_PACKAGE' -e 'FIND_PACKAGE_ARGS' .` Empty = not applicable. For each declared name, a later versioned `find_package` with no explicit check of the fetched version = finding. On a configured tree, `grep -rl -e 'Version not available' build/CMakeFiles/pkgRedirects` lists the stubs, empty = none written. | MUST |
| CMK-DEP-10 | Declare every dependency shared by several subprojects in the top-level project, before any `add_subdirectory` or `FetchContent_MakeAvailable` that might declare it again. | The first declaration of a name controls how it is made available, and CPM resolves a diamond as first-version-wins, so a newer pin added in a subdirectory is silently ignored. A `CPMUsePackageLock` file's `CPMDeclarePackage` is a first declaration too: a lock at 12.0.0 beat `CPMAddPackage("gh:fmtlib/fmt#12.1.0")` with one ungated warning and exit 0 (CPM.cmake 0.43.2, 3.31.12 to 4.4.2, 2026-09-26), so a bump goes in the lock. Floor: 3.14. | Reading heuristic: `grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'FetchContent_Declare\(' -e 'CPMAddPackage\(' -e 'CPMDeclarePackage\(' .` and group the hits by name. A name declared in more than one file whose top-level declaration is missing or comes later = finding. One declaration per name = pass. | SHOULD |

```cmake
# wrong: in a library's own CMakeLists.txt, the consumer's installed copy is never asked
FetchContent_MakeAvailable(dep)

# right: an installed copy wins, and the fetch is the fallback
FetchContent_Declare(
    dep
    GIT_REPOSITORY https://example.com/dep.git
    GIT_TAG 3f1c2a9e0b7d4c6f8a5e2d1b0c9f8e7d6a5b4c3d # v1.4.2
    FIND_PACKAGE_ARGS 1.4 CONFIG
)
FetchContent_MakeAvailable(dep)
```

## Caught by Reading the Cache First

```sh
# The first read, before any debug flag. NAME = the find_package name. Output is expected.
NAME=dep
grep -rn --include='CMakeCache.txt' -e "^${NAME}_DIR" -e "^${NAME}_ROOT" -e '^VCPKG_INSTALLED_DIR' build
# CMK-DEP-13 modules: a _ROOT cache write in a file that never unsets a _DIR cache entry.
grep -rlzE --include='*.cmake' -e '_ROOT[^)]*CACHE' . | xargs -r grep -L -e '_DIR CACHE'
# Then, and only then, a fresh reconfigure with the search printed.
cmake -S . -B build --fresh "$GATE" --debug-find-pkg="$NAME"
# On 4.1 and newer: find_package events in the configure log.
grep -rc --include='CMakeConfigureLog.yaml' -e 'kind: "find_package-v1"' build
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-DEP-13 | Treat `<Pkg>_DIR` as the sticky record of which copy was found. Switch copies with a fresh build tree, `--fresh` or `-U <Pkg>_DIR`, and only a fresh tree or `--fresh` when the switch adds or changes the toolchain (CMK-TC-03). A module that re-points `<Pkg>_ROOT` on reconfigure runs `unset(<Pkg>_DIR CACHE)` whenever the hint's value changes. Re-pointing a manager's tree (`VCPKG_INSTALLED_DIR`, a triplet, a Conan output folder) on a reused build tree is the same trap. | A cached valid compatible `_DIR` is used as is: re-pointing `_ROOT`, even `CACHE PATH … FORCE`, prints the new hint and keeps the old copy (also measured through vcpkg on 2026-09-26). The `unset` fixes it only while the hint can win the search at all (CMK-DEP-21). `-U <Pkg>_DIR` on a tree just given a toolchain finds the old copy again, because the toolchain was never loaded (measured 2026-09-26 on 3.31.12 and 4.4.2, vcpkg-tool 2026-07-27). Floor: any, upper-case `<PKG>_ROOT` 3.27 (CMP0144). | Behaviour: configure with the hint at prefix A, reconfigure the same tree with it at B, then the first cache grep above. A `_DIR` still under A = finding. Modules: the DEP-13 line above. A listed file writes a `_ROOT` cache entry and never unsets a `_DIR` cache entry, and a `FORCE` in that call, often on the next line, = finding. Empty = pass. | MUST |
| CMK-DEP-14 | Hand a provisioned tool or library to `find_program` or `find_library` through `HINTS`, `CMAKE_PROGRAM_PATH`, `CMAKE_LIBRARY_PATH` or an imported target. `<Pkg>_ROOT` is read only by `find_package(<Pkg>)` and by the `find_*` calls in the Find module or Config file that call loads. | A top-level `find_program` returns `NOTFOUND` with `dep_ROOT` at a prefix that holds `bin/depprog`, as `find_program`'s docs say. Docs that promise otherwise leave the consumer with a system copy or nothing. Floor: CMP0074 (3.12). | Reading heuristic. A doc or comment saying `<X>_ROOT` makes a following bare `find_program` or `find_library` search a prefix = finding. For code, `grep -rn --include='*.cmake' --include='CMakeLists.txt' -e 'find_program(' -e 'find_library(' .` and read each hit that relies on a `_ROOT` set nearby. Empty = pass. | MUST |
| CMK-DEP-17 | Answer "which copy was used" from the configure's own records, in the block's order: `<name>_DIR` and `<name>_ROOT` in `CMakeCache.txt` first, where a `_DIR` under `CMakeFiles/pkgRedirects` means a FetchContent declare answered. Then `--debug-find-pkg` on a `--fresh` reconfigure only. Then, on 4.1+, `found.path` of the last `find_package-v1` event whose `mode` is not `provider`. Never `cmake -L`, `--graphviz`, the call site or a manager's trace. | On a reused tree `--debug-find-pkg` lists only the cached candidate and prints the old answer with confidence. `cmake -L` omits `UNINITIALIZED` entries such as a plain `-D<Pkg>_ROOT`, `--graphviz` draws targets only, and `VCPKG_TRACE_FIND_PACKAGE` logs calls, not answers. Floor: configure-log events 4.1. | The last line above, on a `--fresh` 4.1+ tree: 0 after a `find_package` ran = finding, unless step 1 shows the `_DIR` under `CMakeFiles/pkgRedirects` (a redirect logs no event without `--debug-find-pkg`, and one event with a blank found `version` under it: 4.3.4 and 4.4.2, FetchContent and CPM) or a cmake-conan provider answered without `--debug-find-pkg`, and 0 on 3.x is expected. A cmake-conan provider logs events only under `--debug-find-pkg`: one `mode: "config"` event per `find_package` it ran, then one `mode: "provider"` event whose `path` is `dependency_provider::conan_provide_dependency`. The copy is the `config` event before it, never the provider event (cmake-conan `b1593849`, 4.3.4 and 4.4.2). Match `find_package-v1` exactly, because `'kind: "find'` also counts CMake's own `find-v1` probes and never reads 0. | SHOULD |
| CMK-DEP-32 | When a CI leg depends on a specific copy of a dependency (installed rather than fetched, or a given manager's tree), assert it after configure from `<Pkg>_DIR` in `CMakeCache.txt`. | With the installed copy on `CMAKE_PREFIX_PATH`, an `OVERRIDE_FIND_PACKAGE` declare still wins with no diagnostic, and `--debug-find-pkg` never names the installed prefix. The redirect path in `_DIR` is the one reliable tell. Floor: redirects directory 3.24. | `NAME=dep; grep -rn --include='CMakeCache.txt' -e "^${NAME}_DIR" build` A path under `CMakeFiles/pkgRedirects` = fetched, one under the expected prefix = installed, empty = never looked up. The leg fails unless the path matches its expectation. Under a cmake-conan provider with `CMakeConfigDeps`, the provider sets `<Pkg>_DIR` as a normal variable, so a Conan-supplied package has no cache line. Any `<Pkg>_DIR` cache line for a package the conanfile lists means the provider's fallback found another copy. | SHOULD |
| CMK-DEP-33 | Link one copy of each library. When a consumed package can bundle a dependency that the project, or another package in the same link, also uses, consume the package's build that uses the external copy (spdlog: `SPDLOG_FMT_EXTERNAL=ON`), whose exported targets then list the dependency on `INTERFACE_LINK_LIBRARIES`. | The bundled copy never passes through `find_package`, so no cache line, debug output or configure event names it, and `ldd` shows nothing for a static library. The copies share include guards, so the first include per source file wins. Measured 2026-09-26 on 3.31.12, 4.3.4 and 4.4.2 with spdlog 1.17.0 (bundled fmt 12.1.0) beside fmt 11.1.4: one include order fails the link on a `fmt::v11` signature, with "did you mean" naming the `fmt::v12` one, and the other exits 0 and runs fmt 12.1.0 while fmt 11.1.4 sits on its link line. The external build fixed both orders. Floor: any. | `grep -rho --include='build.ninja' --include='link.txt' -e '[^ ]*/libfmt[.][^ ]*' build`, naming the library's file name: paths from one directory = pass, two directories = finding (a second lookup), empty = wrong name. Then `grep -rn --include='*.h' --include='*.hpp' -e 'define FMT_VERSION ' /usr/local/include /opt/spdlog/include`, naming the library's version macro and each `-I` or `-isystem` directory on the artifact's compile lines. One hit per macro = pass, a second hit = finding, empty = wrong macro or directory. Measured 2026-09-26 on 3.31.12 and 4.4.2 with zstd 1.5.6 from pkg-config beside 1.5.7 from `find_package`: two link directories and two `-isystem` directories, one of each after the fix. | MUST |
| CMK-DEP-34 | Forward a list-valued search variable (`CMAKE_PREFIX_PATH`, `CMAKE_MODULE_PATH`, `CMAKE_FIND_ROOT_PATH`) to an `ExternalProject_Add` configure through `CMAKE_CACHE_ARGS` with a `:STRING` type, never as `-D<VAR>=${list}` in `CMAKE_ARGS`. | `CMAKE_ARGS` splits a list at `;`, so the inner configure gets the first entry, prints `Ignoring extra path from command line` only when its configure step runs, and falls back to the environment with exit 0. Measured 2026-09-26 on 3.31.12, 4.3.4 and 4.4.2 with json-c 0.17 and 0.18: the `CMAKE_ARGS` form built 0.17, `CMAKE_CACHE_ARGS` built 0.18. An outer `--fresh` never resets the inner cache. Floor: any. | `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'CMAKE_PREFIX_PATH=\${' -e 'CMAKE_MODULE_PATH=\${' -e 'CMAKE_FIND_ROOT_PATH=\${' .`: a hit inside an `ExternalProject_Add` `CMAKE_ARGS` = finding, empty = pass. | MUST |

```cmake
# wrong: a second configure with a new root keeps the old dep_DIR, so the old copy
set(dep_ROOT "${new_root}" CACHE PATH "dep prefix" FORCE)

# right: drop the stale record when the hint moves
if(DEFINED CACHE{dep_ROOT} AND NOT dep_ROOT STREQUAL new_root)
    unset(dep_DIR CACHE)
endif()
set(dep_ROOT "${new_root}" CACHE PATH "dep prefix" FORCE)
```

## Caught by Grepping for Policy and Warning Knobs

```sh
# CMK-DEP-15: every write of either knob. Each hit must be one of the four scoped shapes.
grep -rn --include='*.cmake' --include='CMakeLists.txt' --include='CMakePresets.json' --include='*.yml' --include='*.yaml' -e 'CMAKE_POLICY_VERSION_MINIMUM' -e 'CMAKE_POLICY_DEFAULT_CMP' .
# CMK-DEP-30: warning switches, then the CI and presets forms of -Wno-deprecated.
grep -rnE --include='CMakeLists.txt' --include='*.cmake' --include='CMakePresets.json' --include='CMakeUserPresets.json' --include='*.yml' --include='*.yaml' -e 'CMAKE_WARN_DEPRECATED' -e 'Wno-dev' -e 'Wno-error=deprecated[^-a-z]' -e 'Wno-error=deprecated$' .
grep -rnE --include='CMakePresets.json' --include='CMakeUserPresets.json' --include='*.yml' --include='*.yaml' -e '[[:space:]"]-Wno-deprecated[^-a-z]' -e '[[:space:]"]-Wno-deprecated$' -e '"deprecated"[[:space:]]*:[[:space:]]*false' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-DEP-15 | On CMake 4.x, set a third-party dependency's policy knobs with set and restore around the one `add_subdirectory`, `FetchContent_MakeAvailable` or `find_package` that loads it: `CMAKE_POLICY_VERSION_MINIMUM` for a floor below 3.10, and `CMAKE_POLICY_DEFAULT_CMP<NNNN>` (CMP0077 for a floor below 3.13 whose `option()` would discard the parent's variable). Scoped means an explicit save, set and restore, a `set()` inside a `function()` (or a `macro()` called only from functions), one `ExternalProject_Add`'s `CMAKE_ARGS`, or a port tool's per-port arguments. Never a project-wide `set()`, a committed preset `cacheVariables` entry or a CI environment variable. A dependency configured in a child process (a manager's bootstrap such as HunterGate, or `execute_process` of `cmake`) never sees the value or a `-D`: re-pin or patch the file that writes its floor, as CMK-DEP-30 does on 3.x. **pinned**: the value is 3.10, and 3.5 only inside a vcpkg port build. | Set and restore scopes both knobs, so a second old dependency still fails after the restore. The `-D` and environment forms mask every dependency added later, and the environment form persists in `CMakeCache.txt` after it is unset. 3.5 clears only the hard error and leaves "Compatibility with CMake < 3.10 will be removed", which the gate turns into an error. Both variables' 4.4.2 docs sanction exactly this shape. `-DCMAKE_WARN_DEPRECATED=OFF` does survive `-Werror=dev` on 3.31.12, but it silences deprecations for the whole project, so it is never the fix. Measured 2026-09-26 with cpp-pm/gate v0.9.2 and Hunter v0.26.12 on an empty `HUNTER_ROOT`: the set and restore around `HunterGate(` and `-DCMAKE_POLICY_VERSION_MINIMUM=3.10` both exit 1 on 4.4.2, and gate `9205073` exits 0 on 3.31.12, 4.3.4 and 4.4.2. Floor: 4.0 for the escape hatch, 3.13 for `CMAKE_POLICY_DEFAULT_CMP0077`. | DEP-15 line above: empty = pass. Every hit must be a scoped shape around one call. A preset hit, a workflow hit, a file-scope hit with no enclosing function and no restore, or a literal `3.5` outside a port build = finding. On a configured tree, a `CMAKE_POLICY_VERSION_MINIMUM` entry in `CMakeCache.txt` that no documented command passes = leaked environment. | MUST |
| CMK-DEP-30 | On CMake 3.x, clear a fetched or vendored dependency whose floor is 3.5 to 3.9 by re-pinning to a version that declares 3.10 or newer, or with a `PATCH_COMMAND` that rewrites that one `cmake_minimum_required` line (raise it, or add `...<max>`). Never use `-DCMAKE_WARN_DEPRECATED=OFF`, `-Wno-dev`, `-Wno-deprecated`, `-Wno-error=deprecated` or a preset's `"warnings": {"deprecated": false}` as the remedy. | `CMAKE_POLICY_VERSION_MINIMUM` does not exist on 3.31.12: it is accepted and ignored ("Manually-specified variables were not used"). Under `-Werror=dev` on 3.31.12 the re-pin and the patch configure clean, `-Wno-error=deprecated` still fails, and the other switches can pass only by also silencing the project's own deprecations, which turns the gate off. A dependency range such as `3.7...4.0` configures clean under the gate. Floor: any 3.x, `PATCH_COMMAND` in FetchContent 3.11. On 4.0 and newer, CMK-DEP-15 applies instead. | Both DEP-30 lines above: empty = pass, a hit that exists to get a dependency past the gate = finding. The second covers presets and CI only, because in listfiles `-Wno-deprecated` is almost always the compiler flag. Behaviour: configure under the gate on every CI line, output in `logs/`, then `grep -rc --include='*.log' -e 'Deprecation' -e '(deprecated)' logs`. Every count 0 = pass (grep exits 1, so read the counts), any non-zero count = finding. | MUST |

```cmake
# wrong: every dependency added after this line inherits it, and 3.5 still fails the gate
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
FetchContent_MakeAvailable(oldlib)

# right: one call, the gate-clearing value, then gone
set(CMAKE_POLICY_VERSION_MINIMUM 3.10)
FetchContent_MakeAvailable(oldlib)
unset(CMAKE_POLICY_VERSION_MINIMUM)
```

## Caught by a Configure With the Network Removed

```sh
# CMK-DEP-16: every configure-time network touch. Empty = no network surface.
grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'FetchContent_MakeAvailable' -e 'CPMAddPackage' -e 'HunterGate' -e 'file\(DOWNLOAD' -e 'SET_DEPENDENCY_PROVIDER' .
# Then a pre-populated tree with no network: one source dir per fetched dependency.
GATE=-Werror=dev   # -Werror=author on a leg that runs CMake 4.4 or newer only
unshare -rn cmake -S . -B build-offline "$GATE" -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
  -DCMAKE_POLICY_DEFAULT_CMP0170=NEW -DFETCHCONTENT_SOURCE_DIR_ZLIB="$PWD/vendor/zlib"
# CMK-DEP-31: patched dependencies, then every override of a source directory.
grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'PATCH_COMMAND' .
grep -rn --include='CMakeLists.txt' --include='*.cmake' --include='CMakePresets.json' --include='CMakeUserPresets.json' --include='*.yml' --include='*.yaml' --include='*.sh' -e 'FETCHCONTENT_SOURCE_DIR_' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-DEP-16 | Make every configure-time network touch satisfiable offline: FetchContent, CPM, `HunterGate`, `file(DOWNLOAD)` in configure scope, and a provider that runs a manager. A configure with `FETCHCONTENT_FULLY_DISCONNECTED=ON`, `FETCHCONTENT_SOURCE_DIR_<X>` per dependency and `CPM_SOURCE_CACHE` succeeds with no network. | vcpkg forces `FETCHCONTENT_FULLY_DISCONNECTED=ON` on every port configure and a Bazel wrap has no network, so a configure that reaches out fails the day it is packaged. A text grep over-reports (a `cmake -P` download at build time is not a configure touch), so the offline configure is the check. A Find module that fetches on a miss is CMK-MOD's. Floor: 3.11, strict failure CMP0170 (3.30). | The DEP-16 probe above: exit 0 = pass, non-zero = finding. Without `-DCMAKE_POLICY_DEFAULT_CMP0170=NEW` a tree with a bare `VERSION 3.25` floor, no `...<max>`, missing one source directory still exits 0 under `unshare -rn`, the false pass this rule exists to catch. On a hosted `ubuntu-24.04` runner, run it in a `--network none` container (CMK-CI-05, `presets-and-ci.md`). | MUST |
| CMK-DEP-31 | Point an offline or override configure (`FETCHCONTENT_SOURCE_DIR_<X>`, the CMK-DEP-16 probe included) only at source that already carries the declare's `PATCH_COMMAND` result. Prefer a re-pin to a patch when the dependency must also build from an override. | An override skips the patch step: a `GIT_REPOSITORY` declare whose `PATCH_COMMAND` fixes the floor exits 0, and the same configure with the override at a pristine copy exits 1. A patch that fixes code instead fails silently, and the build is simply different. A `SOURCE_DIR` declare does run the patch, in place, so one inside the repository makes a configure rewrite tracked files. Floor: 3.11. | The two DEP-31 lines above: the first empty = rule vacuous. An override naming a patched dependency whose directory lacks the patched line = finding, read with `OVERRIDE_DIR=vendor/oldlib; grep -rn --include='CMakeLists.txt' -e 'cmake_minimum_required' "$OVERRIDE_DIR"` Behaviour: the DEP-16 probe under the gate exits 0. | MUST |

## Caught by Grepping the find_package Calls

```sh
# CMK-DEP-19: policy-removed Find modules. Empty = pass.
grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'find_package\([[:space:]]*CUDA[[:space:])]' -e 'find_package\([[:space:]]*PythonInterp' -e 'find_package\([[:space:]]*PythonLibs' -e 'find_package\([[:space:]]*GCCXML' -e 'find_package\([[:space:]]*CABLE' .
# CMK-DEP-11: CPS knobs CMake never reads, and the retired import gate. Empty = pass.
grep -rn --include='*.cmake' --include='CMakeLists.txt' --include='CMakePresets.json' --include='*.yml' -e 'CPS_PATH' -e 'CPS_PREFIX_PATH' -e 'CMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES' .
# CMK-DEP-12: calls with a bare keyword right after the name, so no version. Read each.
grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'find_package\([A-Za-z0-9_]+[[:space:]]+CONFIG' -e 'find_package\([A-Za-z0-9_]+[[:space:]]+REQUIRED' -e 'find_package\([A-Za-z0-9_]+[[:space:]]+COMPONENTS' -e 'find_package\([A-Za-z0-9_]+[[:space:]]+QUIET' .
# CMK-DEP-20: calls naming no mode on their first line. Read multi-line calls in full.
grep -rn --include='*.cmake' --include='CMakeLists.txt' -e 'find_package(' . | grep -v -e 'CONFIG' -e 'MODULE'
# CMK-DEP-18: CI pins the optional dependencies.
grep -rn --include='CMakePresets.json' --include='*.yml' -e 'CMAKE_DISABLE_FIND_PACKAGE_' -e 'CMAKE_REQUIRE_FIND_PACKAGE_' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-DEP-19 | Never call a policy-removed Find module where its removal policy is `NEW`. Migrate `find_package(CUDA)` to `enable_language(CUDA)` plus `find_package(CUDAToolkit)`, and `PythonInterp` or `PythonLibs` to `find_package(Python3)`. `GCCXML` (use CastXML) and `CABLE` (no replacement) are the same. Read the policy version from the `...<max>` end of the governing `cmake_minimum_required`, capped at the running CMake, never from the floor. | CMP0146 (`FindCUDA`) and CMP0148 (`FindPythonInterp`, `FindPythonLibs`) are 3.27, CMP0167 (`FindBoost`) 3.30, CMP0188 and CMP0191 (`FindGCCXML`, `FindCABLE`) 4.1. Under `3.25...4.4` the three 3.x policies are `NEW` on 3.31.12 and 4.4.2: a plain call warns and exits 0, a `QUIET` call is silent, and the feature vanishes. A bare `find_package(Boost)` falls through to the `BoostConfig.cmake` Boost ships from 1.70, a finding only when the supported Boost reaches below 1.70 or the code reads `FindBoost`-only results. Floor: `FindPython3` 3.12, `FindCUDAToolkit` 3.17. | DEP-19 line above: empty = pass. For each hit, a governing `...<max>` of 3.27 or later (4.1 or later for `GCCXML` and `CABLE`), or a bare floor at or past it, = finding. A legacy call behind `if(CMAKE_VERSION VERSION_LESS …)` with the modern call live beside it passes. | MUST |
| CMK-DEP-11 | On CMake 4.3 or newer, expect `find_package(X)` to load a valid `X.cps` over an `XConfig.cmake` in the same prefix, and a rejected `.cps` to fall through to `XConfig.cmake` without a diagnostic. State the intent: `CONFIGS` for script-only, `X_DIR` at the `cps/` directory for CPS. Never set the retired `CMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES`, and never set `CPS_PATH` or `CPS_PREFIX_PATH` expecting CMake to read them. | Measured on 4.3.4 and 4.4.2 under `lib/cps/`, `lib/cps/X/` and `lib64/cps/X/`: the valid `.cps` wins. A `.cps` whose version schema is not `simple` is rejected for any versioned request that is not the exact string, and the search falls through to Config, which is how "Config wins" gets reported. The 4.0 to 4.2 import gate is ignored from 4.3: set on 4.3.4 and 4.4.2 under the gate, it draws only the unused-variable warning, exits 0, and the `.cps` still wins (measured 2026-09-26). Exporting CPS is CMK-INST-14 and CMK-INST-16 (`install-and-export.md`). Floor: 4.3. | DEP-11 line above: empty = pass. A hit is the finding on every leg: the Config package CPS ships beside serves 4.0 to 4.2. Confirm which file won with `--debug-find-pkg=X` on a `--fresh` configure. | SHOULD |
| CMK-DEP-12 | Give `find_package` a minimum version for any dependency with a known breaking major. Rely on a range's upper bound only when the package's version file handles ranges: CPS with the `simple` schema (or none) does, `write_basic_package_version_file()` does, a hand-written `*ConfigVersion.cmake` may not. | A version request makes CMake discard a cached `_DIR` whose package is incompatible, which partly defends against CMK-DEP-13, and it turns a silent API break into a configure error. Floor: any, ranges 3.19. | Reading heuristic, DEP-12 line above. Each hit names a package with no version, and one with a documented breaking major = finding. Empty = pass. | SHOULD |
| CMK-DEP-20 | State `CONFIG` or `MODULE` on a `find_package` whose package ships only one of the two. | An explicit mode makes the not-found message name the file that was expected, and keeps a stray `Find<X>.cmake` on `CMAKE_MODULE_PATH` from answering a Config-only package. Diagnostics, not correctness. Floor: any. | Reading heuristic, DEP-20 line above: each line is a call with no mode on its first line. Empty = pass. | SHOULD |
| CMK-DEP-18 | Make optional dependencies deterministic in CI: give every non-`REQUIRED` `find_package` a `CMAKE_DISABLE_FIND_PACKAGE_<Pkg>` or `CMAKE_REQUIRE_FIND_PACKAGE_<Pkg>` in the CI preset. | Otherwise the runner image decides the feature set, and an image update drops a feature silently. Unmeasured, hence CONSIDER. Floor: `CMAKE_REQUIRE_FIND_PACKAGE_<Pkg>` 3.22. | DEP-18 line above: empty while the tree has a non-`REQUIRED` `find_package` = finding. | CONSIDER |

## Caught by a Fresh Configure Under a Root Path

```sh
# CMK-DEP-21: is any configure rooted? Empty = not applicable.
grep -rn --include='*.cmake' --include='CMakeLists.txt' --include='CMakePresets.json' -e 'CMAKE_FIND_ROOT_PATH' -e 'CMAKE_SYSROOT' -e 'vcpkg.cmake' .
# CMK-DEP-22: LANGUAGES NONE projects that call find_package. Empty = pass.
grep -rlE --include='CMakeLists.txt' -e 'LANGUAGES[[:space:]]+NONE' . | xargs -r grep -l -e 'find_package('
# CMK-DEP-23: pkg-config consumers, then each sysroot variable on its own.
grep -rln --include='*.cmake' --include='CMakeLists.txt' -e 'pkg_check_modules' -e 'pkg_search_module' -e 'cmake_pkg_config' .
grep -rn --include='*.cmake' --include='CMakePresets.json' --include='*.yml' -e 'PKG_CONFIG_SYSROOT_DIR' .
grep -rn --include='*.cmake' --include='CMakePresets.json' --include='*.yml' -e 'PKG_CONFIG_LIBDIR' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-DEP-21 | When `CMAKE_FIND_ROOT_PATH` or `CMAKE_SYSROOT` is non-empty, never rely on `<Pkg>_ROOT` or `CMAKE_PREFIX_PATH` to choose between copies of a package. Pin the copy with `<Pkg>_DIR`, or put the hint inside a root, and confirm the result with `--debug-find-pkg`. | Unless the package mode is `NEVER`, CMake searches every category re-rooted before any unrooted one, so a manager's `CMAKE_FIND_ROOT_PATH` entry or the sysroot's own `/usr` beats a `CACHE … FORCE` hint, even in a native build. vcpkg's toolchain appends its installed triplet there. `NEVER` restores the hint but un-sandboxes every other `find_package`. A `<Pkg>_DIR` at the wanted config directory wins under every mode. The modes a toolchain sets are CMK-TC's. Floor: any, `<Pkg>_ROOT` 3.12. | DEP-21 line above: empty = not applicable. With a hit, run `cmake -S . -B build --fresh "$GATE" --debug-find-pkg=dep` for each package the code selects through a hint. A path after `The file was found at` outside the hinted prefix = finding, a `<Pkg>_DIR` pin = pass. | MUST |
| CMK-DEP-22 | Enable a compiled language before any `find_package(… CONFIG)` whose package may install under `lib64/` or `lib32/`, because `project(… LANGUAGES NONE)` does not search those layouts. Never write `CMAKE_FIND_LIBRARY_USE_LIB64_PATHS`, which does not exist. | `LANGUAGES NONE` leaves `CMAKE_SIZEOF_VOID_P` empty, and `find_package` adds `lib64` only when it is 8. The same prefix resolved to its `share/` copy under `NONE` and its `lib64/` copy under `C`. Silent only when another layout also holds a copy, hence SHOULD. The `lib/<tuple>` layout is unmeasured. Floor: any. | DEP-22 line above: empty = pass. For each listed file, a Config-mode `find_package` before any `enable_language` = finding. A Find-module call is not affected. | SHOULD |
| CMK-DEP-23 | A cross build that consumes pkg-config sets `PKG_CONFIG_SYSROOT_DIR` and `PKG_CONFIG_LIBDIR` itself, in the toolchain (`set(ENV{…})`) or the documented environment. Neither `CMAKE_SYSROOT` nor any manager's toolchain does it. | `FindPkgConfig.cmake` at 4.4.2 never reads `CMAKE_SYSROOT` and never sets either variable, and neither `vcpkg.cmake` nor Conan 2.32.0's cross `conan_toolchain.cmake` sets both. With pkgconf 2.3.0 a sysroot `.pc` found through `PKG_CONFIG_PATH` or `PKG_CONFIG_LIBDIR` alone reports found with the host's `/usr/include`. Floor: any. | The DEP-23 lines above: the first empty = not applicable. With a hit in a tree that has a cross toolchain, either of the other two empty = finding, both non-empty = pass. | MUST |

## What Agents Get Wrong Here

1. **Pinning to a branch or a tag, or calling a `${VAR}` pin "opaque".** Resolve
   the variable, then apply CMK-DEP-01 and CMK-DEP-02. Scorecard does not scan
   CMake, so "CI would catch it" is false.
2. **Fixing the CMake 4 floor error globally.** A preset, CI or environment
   `CMAKE_POLICY_VERSION_MINIMUM`, the value 3.5, or a warning switch. The fix is
   CMK-DEP-15 on 4.x and CMK-DEP-30 on 3.x, chosen by `cmake --version`, because
   3.x accepts and ignores the variable.
3. **Reading `--debug-find-pkg` or a green reconfigure as "which copy".** Grep
   the cache first (CMK-DEP-17), and never re-point `_ROOT` expecting the copy to
   move (CMK-DEP-13).
4. **Writing an unconditional `FetchContent_MakeAvailable` into a library.** The
   shape training data emits most. CMK-DEP-07's probe fails it.
5. **Linking the bare `dep` after a `FIND_PACKAGE_ARGS` declare.** It works
   until an installed copy appears (CMK-DEP-08).
6. **CPS confusion.** Setting the retired gate, exporting `CPS_PREFIX_PATH`, or
   asserting that CPS or Config always wins (CMK-DEP-11).
7. **Emitting the one-argument `FetchContent_Populate(name)`, or flagging the
   multi-argument form as deprecated.** CMK-DEP-04 matches only the bare name.
8. **Claiming `<X>_ROOT` feeds a following `find_program`.** It does not
   (CMK-DEP-14). A vendored bootstrap module that documents this sends consumers
   to the wrong copy.
9. **Not knowing `include(CPM.cmake)` changes policy defaults for every later
   subproject** (CMK-DEP-05).
10. **Passing `FETCHCONTENT_SOURCE_DIR_<X>` for a patched dependency.** The
    patch is dropped (CMK-DEP-31).
11. **Expecting a hint to beat a manager's or sysroot's copy, or `CMAKE_SYSROOT`
    to wire up pkg-config.** CMK-DEP-21, CMK-DEP-23.
12. **Suggesting `find_package(CUDA)` or `PythonInterp`, or judging a removed
    module by the floor.** CMK-DEP-19 reads the `...<max>` end.
13. **Inventing `CMAKE_FIND_LIBRARY_USE_LIB64_PATHS`** to fix a `LANGUAGES NONE`
    miss (CMK-DEP-22).
14. **Grepping for "deprecated" and hitting `-Wno-error=deprecated-declarations`.**
    That is a compiler flag. CMK-DEP-30's patterns exclude it.

## Re-check

- D1: on each CMake minor after 4.4, the gate spelling in every probe here, and
  the CMP0170 default the offline probes pass.
- D4: Conan and vcpkg-tool release tags, for CMK-DEP-13's manager-tree case and
  CMK-DEP-23's toolchain reads (Conan 2.32.0, vcpkg-tool 2026-07-27).
- D7: the CPS UUID rotation, for CMK-DEP-11's 4.0 to 4.2 gate.
- CPM.cmake after v0.43.2 (CMK-DEP-05) and Hunter after v0.26.12 and cpp-pm/gate after `9205073` (CMK-DEP-06).
