# Reading the answers, mechanism by mechanism

Read this when the step 1 to 3 output in `SKILL.md` does not match a row of its
symptom table, or when a symptom row sends you here. It holds what each
resolution mechanism writes into the configure's records, and the output shape
that identifies it. It states no standard: every fix is a rule ID owned by the
`cmake-build` or `cpp-packaging` rule sets.

Measured 2026-09-26 on CMake 3.31.12, 4.3.4 and 4.4.2, Conan 2.32.0 with
cmake-conan `develop2` (`b1593849`, as of 2026-09-26), and vcpkg-tool
2026-09-26, unless a row says otherwise. Rows that name vcpkg-tool 2026-07-27
used the tool that registry commit `11ace808` (2026-09-26) bootstraps. CPM rows
used CPM.cmake 0.43.2, and cross rows zig cc 0.16.0-dev (2026-09-26).

Contents: [Config mode](#config-mode-find_package) ·
[Module mode](#module-mode-find_package) ·
[FetchContent redirects](#fetchcontent-redirects) ·
[Dependency providers](#dependency-providers) ·
[Toolchain-injected paths](#toolchain-injected-paths) · [Bundled copies](#bundled-copies) ·
[CPM](#cpm) · [The Conan graph](#the-conan-graph) · [vcpkg](#vcpkg)

## Config mode `find_package`

The resolution order a plain `find_package(<X>)` follows, first match wins:

| Order | Source | Where it shows |
|---|---|---|
| 1 | A registered provider (`FIND_PACKAGE` method) | `--debug-find-pkg` prints `Package was found by the dependency provider` |
| 2 | `CMAKE_FIND_PACKAGE_REDIRECTS_DIR` (a FetchContent redirect) | `<X>_DIR` ends in `CMakeFiles/pkgRedirects` |
| 3 | A cached, valid, version-compatible `<X>_DIR`, used as is | The cache line itself. `--debug-find-pkg` lists only this one candidate |
| 4 | `<X>_ROOT`, then `CMAKE_PREFIX_PATH` (variable, then environment), then system paths | `--debug-find-pkg` on a `--fresh` configure lists every candidate |

Order 4 holds only while `CMAKE_FIND_ROOT_PATH` and `CMAKE_SYSROOT` are both
empty. Otherwise every category runs re-rooted first, so any rooted copy beats
a `_ROOT` hint (see [Toolchain-injected paths](#toolchain-injected-paths)).

- A version request makes CMake discard a cached `_DIR` whose package is
  incompatible. A bare `find_package(<X> CONFIG)` never does, which is why a
  stale `_DIR` survives (CMK-DEP-12, CMK-DEP-13).
- On CMake 4.3 and newer, each prefix also probes `cps/` locations. A valid
  `<X>.cps` beside `<X>Config.cmake` wins, and `<X>_DIR` then ends in
  `/cps/<x>` or `/cps`. A `.cps` that `find_package` rejects (any version
  schema but `simple` on an inexact request) falls through to the Config file
  with no diagnostic (CMK-DEP-11, CMK-INST-16). The `cps/` candidates in
  `--debug-find-pkg` output on 4.4.2 are noise, not misconfiguration.
- On 4.4.2 each `find_package-v1` event carries a `settings` block. Its
  `CMAKE_FIND_ROOT_PATH_MODE` line shows the package mode that was in force
  for that call.
- On 4.1 and newer an event holds `version_request.version` (when the call
  names one) and `found.version`, both matched by `^      version: `. On 3.x,
  read the version file beside the step 1 `_DIR`:

```sh
DIR=build/vcpkg_installed/x64-linux/share/dep
grep -rn --include='*ConfigVersion.cmake' --include='*-config-version.cmake' -e 'set(PACKAGE_VERSION ' "$DIR"
```

Empty output means the package ships no version file, so CMake knows no
version for it (cJSON 1.7.19 through vcpkg printed its version on 3.31.12,
4.3.4 and 4.4.2).

## Module mode `find_package`

A Find module writes no `<X>_DIR` cache entry, so the step 1 grep prints
nothing for it on both lines. That is not "never looked up".

- `--debug-find-pkg=NAME` prints `find_package considered the following paths
  for Find<X>.cmake`, then `The file was found at` and the module's path.
- On 4.1 and newer the `find_package-v1` event shows the module's path, then
  `mode: "module"` on the next line.
- A stray `Find<X>.cmake` on `CMAKE_MODULE_PATH` answers a Config-only package
  before Config mode is tried. Stating `CONFIG` on the call removes that
  path (CMK-DEP-20).
- A removed module (`FindCUDA`, `FindPythonInterp`, `FindPythonLibs`) under a
  `...4.4` range is policy `NEW`. A `QUIET` call is then silent and
  `<X>_FOUND` stays empty (CMK-DEP-19). A bare `find_package(Boost)` instead
  falls through to the `BoostConfig.cmake` that Boost ships from 1.70.
- A module's copy is its `<X>_LIBRARY*` and `<X>_INCLUDE_DIR` cache lines,
  printed by `--debug-find-pkg` as `The item was found at`. They can come from
  two copies (class C8), and the module reports the version it parsed, usually
  the header's: FindEXPAT in a cross build took `expat.h` 2.8.5 from the
  sysroot and `libexpat.so` 2.7.3 from the host, and `found suitable version`
  and 4.4.2's `found.version` both said 2.8.5 (3.31.12, 4.3.4 and 4.4.2).

## FetchContent redirects

| Output | Meaning | Rule |
|---|---|---|
| `<X>_DIR` = `<build>/CMakeFiles/pkgRedirects` | `OVERRIDE_FIND_PACKAGE`, or a `FIND_PACKAGE_ARGS` declare that fell through to a fetch, satisfied the call. The installed copy was never consulted, whatever `CMAKE_PREFIX_PATH` held | CMK-DEP-07, CMK-DEP-32 |
| `<declared>_DIR:INTERNAL=<build>/CMakeFiles/pkgRedirects` under the declare's spelling, with the installed copy on the path | A `FIND_PACKAGE_ARGS` try-find searched the declare's name (`cjson`) and missed a package that ships `cJSONConfig.cmake`, then fetched. `FIND_PACKAGE_ARGS NAMES cJSON ...` finds it (3.31.12 and 4.4.2) | CMK-DEP-07, CMK-DEP-09 |
| No `find_package-v1` event on 4.1 and newer while `<X>_DIR` is under `pkgRedirects` | Expected without `--debug-find-pkg`, so a zero count is not a CMK-DEP-17 finding. With the flag the call logs one event whose `path` is `pkgRedirects/<x>-config.cmake` and whose found `version` is blank (4.3.4 and 4.4.2, FetchContent and CPM alike) | CMK-DEP-17 |
| `pkgRedirects/<x>-config-version.cmake` containing `Version not available` | The version-less stub. Every later `find_package(<X> <ver> EXACT)` succeeds with a blank `<X>_VERSION` | CMK-DEP-09 |
| A `FETCHCONTENT_SOURCE_DIR_<X>` cache entry | Resolution step 1: that directory is added directly. No provider and no `find_package` run, and the declare's `PATCH_COMMAND` is skipped | CMK-DEP-31 |
| Two `FetchContent_Declare` of one name in different files | The first declare processed wins. A newer pin in a subdirectory is ignored silently | CMK-DEP-10 |

To find which declare fired, grep the tree for the keyword, never trace by
file name. `--trace-source=CMakeLists.txt` traces only files of that name and
printed 0 lines for a declare kept in a `.cmake` module (4.4.2).

```sh
grep -rn -A2 --include='*.cmake' --include='CMakeLists.txt' -e 'FetchContent_Declare' -e 'CPMAddPackage' -e 'CPMDeclarePackage' -e 'CPMUsePackageLock' .
```

Empty output means the tree declares nothing through FetchContent or CPM, so
the copy came from elsewhere. Otherwise read the name in each hit (the `-A2`
lines cover a name split onto the next line). One name declared in more than
one file, or a `CPMDeclarePackage` from a lock, is a first-declare-wins
question (CMK-DEP-10, [CPM](#cpm)).

## Bundled copies

spdlog 1.17.0 with its default `SPDLOG_FMT_EXTERNAL=OFF` carries fmt 12.1.0
in `include/spdlog/fmt/bundled/`, its Config file reads
`set(SPDLOG_FMT_EXTERNAL OFF)`, and its targets list no `fmt::fmt`. Beside an
installed fmt 11.1.4 (guards `FMT_BASE_H_`, `FMT_FORMAT_H_` in both), with
configure exit 0 on 3.31.12, 4.3.4 and 4.4.2: `<fmt/format.h>` first fails the
link on `fmt::v11::basic_string_view` with `did you mean` `fmt::v12::`, and
`<spdlog/spdlog.h>` first runs `FMT_VERSION 120100` with exit 0, 242
`fmt::v12::` symbols and none from the fmt 11.1.4 on its link line. spdlog
built with `SPDLOG_FMT_EXTERNAL=ON` gave exit 0 and only `fmt::v11::` symbols
for either order (4.4.2, CMK-DEP-33). With Ninja, `ninja -C build -t deps
CMakeFiles/app.dir/main.cpp.o` lists the one header copy that object used.

## CPM

| Output | Meaning |
|---|---|
| `CPM_PACKAGE_<name>_VERSION:INTERNAL=` and `_SOURCE_DIR:INTERNAL=` | What CPM added: the version and the source it built |
| `<name>_DIR` under `pkgRedirects`, no `OVERRIDE_FIND_PACKAGE` in the tree | CPM wrote the redirect for a fetched package. Its version file holds only `set(PACKAGE_VERSION_COMPATIBLE TRUE)` and `set(PACKAGE_VERSION_EXACT TRUE)`, so `find_package(fmt 12.1 CONFIG REQUIRED)` passed against 12.0.0 (CMK-DEP-09) |
| `CPM: Adding package fmt@12.0.0`, then `Requires a newer version of fmt (12.1.0) than currently included (12.0.0)` | A `CPMDeclarePackage` came first. A lock the `cpm-update-package-lock` target wrote at 12.0.0 beat `CPMAddPackage("gh:fmtlib/fmt#12.1.0")` with exit 0 on 3.31.12, 4.3.4 and 4.4.2, and the gate never promotes the warning. Change the lock (CMK-DEP-10) |
| `CPM: Using local package fmt@12.1.0`, `CPM_USE_LOCAL_PACKAGES:BOOL=ON` | CPM ran `find_package(fmt 12.0.0 QUIET)`, and fmt's `AnyNewerVersion` file accepted 12.1.0. The option is seeded from the environment and cached: unsetting the variable and `-U fmt_DIR` both kept 12.1.0, `-DCPM_USE_LOCAL_PACKAGES=OFF` fetched 12.0.0 (4.4.2) |
| `Cache for fmt (<CPM_SOURCE_CACHE>/fmt/061b) is dirty` | The shared checkout was edited. A brand-new tree built the edit with exit 0 (3.31.12 and 4.4.2) |

## Dependency providers

| Output | Meaning |
|---|---|
| `CMAKE_PROJECT_TOP_LEVEL_INCLUDES:UNINITIALIZED=...` in the step 1 grep | The user passed a top-level include. It is the provider of record only if nothing in the project sets or appends the variable (CMK-TC-04) |
| `Package was found by the dependency provider` in `--debug-find-pkg` output | The provider's macro returned (both `CMakeDeps` and `CMakeConfigDeps`, 4.4.2). Under cmake-conan that includes its fallback search, so read the `The file was found at` path and any `considered but not accepted` line above it |
| cmake-conan under `CMakeDeps`: `<X>_DIR:PATH=<build>/conan` in the cache | The provider installed with Conan and answered the call. No `find_program`, `find_library` or `find_path` sees Conan content |
| cmake-conan under `CMakeConfigDeps`: no `<X>_DIR` cache line, and no `find_package-v1` event for the package without `--debug-find-pkg` | Expected. The provider sets `<X>_DIR` as a normal variable from `conan_cmakedeps_paths.cmake` (measured 4.4.2 and 3.31.12). With `--debug-find-pkg` the log holds a `mode: "config"` event naming the generators copy, then a `mode: "provider"` event whose `path` is `dependency_provider::conan_provide_dependency` (4.3.4 and 4.4.2) |
| cmake-conan under `CMakeConfigDeps` with a `<X>_DIR:PATH=` cache line | The fallback search answered, from outside Conan (SKILL T13) |
| Console line `CMake-Conan: Loading conan_cmakedeps_paths.cmake file`, or the file `<build>/conan/conan_cmakedeps_paths.cmake` | `CMakeConfigDeps` is in use. From that call on, and in that directory scope and subdirectories added later, `CMAKE_PROGRAM_PATH`, `CMAKE_LIBRARY_PATH` and `CMAKE_INCLUDE_PATH` carry the package's `bin`, `lib` and `include`. `CMakeConfigureLog.yaml` never carries this line |
| `CMake-Conan: find_package(<X>) found, 'conan install' already ran` in a directory whose `find_program` is NOTFOUND | The first intercepted call ran in a subdirectory. The paths were set in that scope only (CMK-TC-05) |

cmake-conan's `conan_provide_dependency` (`conan_provider.cmake` at
`b1593849`, line 665) first runs `find_package(<X> ... BYPASS_PROVIDER PATHS
<generators> NO_DEFAULT_PATH)`. When that fails, line 678 re-runs
`find_package(<X> ${ARGN} BYPASS_PROVIDER)` with CMake's full default search.
Measured with cjson 1.7.19 in the conanfile and 1.7.15 on the environment's
`CMAKE_PREFIX_PATH` (3.31.12 and 4.4.2, exit 0, the binary printed 1.7.15):

- `find_package(cJSON 1.7.15 EXACT CONFIG REQUIRED)`: step 2 printed
  `considered but not accepted: .../generators/cJSONConfig.cmake, version:
  1.7.19`, then the host path, then `Package was found by the dependency
  provider`. The log held 3 events: the generators search rejected with
  `reason: "insufficient_version"`, the host copy, then the provider event.
- cjson missing from the conanfile: the same console lines without the
  not-accepted one (4.4.2).
- The passing control (no version request) logged 0 events without
  `--debug-find-pkg`, 2 with it, and had no `cJSON_DIR` cache line.

`CMAKE_PREFIX_PATH` stays empty before and after the intercepted call under
both generators, so printing it proves nothing. `cmake_language(DEFER CALL
find_package ...)` runs at the end of the current directory, after every
non-deferred command in it, so it never makes an earlier `find_program` see
Conan. `cmake --help-command cmake_language` on the pinned binary lists the
closed method set a provider can intercept: `FIND_PACKAGE` and
`FETCHCONTENT_MAKEAVAILABLE_SERIAL`.

Per docs, not measured: `CMakeConfigDeps` under a multi-config generator, and
whether a build-context `tool_requires` binary reaches `CMAKE_PROGRAM_PATH`
through the same file.

## Toolchain-injected paths

The step 1 grep's `CMAKE_TOOLCHAIN_FILE` line names the toolchain the cache was
last given, not the one the tree loaded. `CMakeFiles/<version>/CMakeSystem.cmake`
is written on the first configure only, and its `include(` line is the loaded
toolchain:

```sh
grep -rn --include='CMakeSystem.cmake' -e 'include(' build/CMakeFiles
```

Empty output while the cache names a toolchain means the toolchain was given
to an existing tree and never read. Empty output and no cache line means no
toolchain, so this does not apply. Measured with a preset `toolchainFile`
naming `vcpkg.cmake` added to a tree first configured without it: one
`CMake Warning (unused-cli)` naming `CMAKE_TOOLCHAIN_FILE`, exit 0 under
`-Werror=dev` (3.31.12) and `-Werror=author` (4.4.2), no `VCPKG_INSTALLED_DIR`
cache line, and the host copy kept. `-U <X>_DIR` found the host copy again.
`--fresh` wrote the `include(` line and vcpkg installed its copy (vcpkg-tool
2026-07-27). The fix is a new tree or `--fresh` (CMK-TC-03, CMK-DEP-13).

A preset's `toolchainFile` beats its own
`cacheVariables.CMAKE_TOOLCHAIN_FILE`, and a command-line `-D` beats both. The
losing file is never read (CMK-TC-01).

| Output | Meaning | Rule |
|---|---|---|
| `<X>_DIR` under a manager's tree or a sysroot, while `<X>_ROOT` names another prefix, and the same after `--fresh` | A rooted copy won. vcpkg appends its installed triplet to `CMAKE_FIND_ROOT_PATH`, and any rooted candidate beats an unrooted `_ROOT` hint, cross build or not (measured with a one-line toolchain, 3.31.12 and 4.4.2). Pin the copy with `<X>_DIR` | CMK-DEP-21 |
| `<X>_DIR` or `<X>_LIBRARY` on a host path in a cross build, the same after `--fresh`, and no candidate under `<sysroot>/usr/lib/<triplet>` in `--debug-find-pkg` | The target's copy was never searched. The compiler reported no implicit link directories (zig cc 0.16.0-dev), so `CMakeCCompiler.cmake` holds `CMAKE_C_LIBRARY_ARCHITECTURE ""` and the multiarch directory is skipped, while the unset modes (`BOTH`) let the environment's `CMAKE_PREFIX_PATH` win. `ONLY` alone gives "Could not find". Adding `set(CMAKE_LIBRARY_ARCHITECTURE aarch64-linux-gnu)` found the sysroot copy (3.31.12, 4.3.4 and 4.4.2) | CMK-TC-08, CMK-TC-11 |
| A Conan cross build finds a sysroot copy over Conan's package | Conan 2.32.0's `CMakeToolchain` rewrites every `CMAKE_FIND_ROOT_PATH_MODE_*` to `BOTH` in cross builds | CMK-TC-10 |
| A `VCPKG_*` or `CMAKE_TOOLCHAIN_FILE` value printed correctly, the other triplet's package found | The variable was set after the first `project()`. The printed value changed, the loaded file did not, and configure exits 0 | CMK-TC-03, CMK-VCPKG-04 |
| `vcpkg.cmake` and `conan_toolchain.cmake` both reach one configure leg | Two managers of record. The variable holds one path | CMK-TC-02 |

A `_ROOT` hint also never reaches a top-level `find_program` or
`find_library`. It reaches only `find_package(<X>)` and the `find_*` calls in
the Find module or Config file that call loads (CMK-DEP-14).

## The Conan graph

Run from the directory holding the consumer's `conanfile`, with the same
profiles, `-s`, `-o` and lockfile the build's `conan install` line uses.

```sh
conan graph info . --profile:host=default --profile:build=default
```

| Output line | Meaning |
|---|---|
| `gamma/1.0#<rrev> - Cache` under `Requirements` | The resolved reference and recipe revision, served from the local cache |
| `gamma/1.0#<rrev>:<package_id>#<prev> - Cache` | The binary that matches this profile exists |
| `... - Missing` | No binary matches this profile. `conan graph explain` names the closest one and the setting that differs |

`conan graph explain` answers "why does no existing binary match", not "what
resolved":

| Graph state | Exit | Output |
|---|---|---|
| Every binary present | 1 | `ERROR: There is no missing binary` |
| A binary missing | 0 | `Missing binary: <ref>`, the wanted `conaninfo.txt`, then `Closest binaries` with a `diff` block listing `expected:` and `existing:` settings |

The missing-binary run queried every configured remote before it reported
the local closest match (Conan 2.32.0).

A `conan.lock` in the working directory is picked up implicitly and pins
every ranged requirement it lists, with no flag. An empty `--lockfile=`
switches it off, and `--lockfile-partial` lets an unlisted requirement
resolve (CMK-CONAN-09). A version that "should have floated" and did not,
or floated in CI but not locally, starts there:

```sh
grep -rn --include='conanfile.py' --include='conanfile.txt' -e '/\[' .
grep -rn -e 'conan install' .github
grep -rn -e '--lockfile[= ]' -e ' -l ' .github
grep -rn -e '--lockfile=""' -e "--lockfile=''" -e '--lockfile= ' -e '--lockfile=$' -e '--lockfile-partial' .github
```

A hit from the first means ranges exist, and `git ls-files conan.lock` must then
be non-empty. Empty output from the first means no ranges, so the rule is not
applicable. Empty output from the second means CI runs no `conan install` (not
applicable). An install line from the second that is missing from the third is
the finding. The fourth must be empty: an empty `--lockfile=` switches the lock
off.

`conan graph info` never describes a build tree. After a requirement bump to
cjson 1.7.19 without `conan install`, it printed `cjson/1.7.19#bb87c8e7...`
while `cmake --preset conan-release` reconfigured with exit 0, the generators
folder's `cJSONConfigVersion.cmake` still read 1.7.17 and the binary printed
1.7.17 (Conan 2.32.0, `CMakeDeps`, 4.4.2). SKILL T8's generators-folder grep
is the tree's record.

## vcpkg

vcpkg has no lockfile, no dependency provider and no CPS support
(CMK-VCPKG-11). Its version record is the manifest's `builtin-baseline` (or
a registry `baseline`) plus the vcpkg root commit CI checks out (CMK-VCPKG-01,
CMK-PKG-02). The installed version is the highest of the baseline's version
and every `version>=` in the graph, and only an `overrides` entry in the
top-level manifest pins one below the baseline (CMK-VCPKG-02). Measured with
vcpkg-tool 2026-07-27 on baseline `11ace808`: `version>=` 1.7.15 installed
cjson 1.7.19 with exit 0 on 3.31.12, 4.3.4 and 4.4.2, and
`"overrides": [{ "name": "cjson", "version": "1.7.15", "port-version": 2 }]`
installed 1.7.15 (4.4.2). The baseline's entry for a port:

```sh
BASELINE=11ace808cc8a3a941f386e33726b992b22ba9e5a
git -C "${VCPKG_ROOT:-vcpkg}" show "$BASELINE:versions/baseline.json" | jq -c '.default.cjson'
```

Set `BASELINE` to the manifest's `builtin-baseline` and `cjson` to the port.
It printed `{"baseline":"1.7.19","port-version":0}`, and `null` means the
baseline has no entry for the port.

| Tool | What it answers | What it does not |
|---|---|---|
| The step 1 grep's `VCPKG_INSTALLED_DIR` and `<X>_DIR` lines | Which installed tree this build tree resolved | Nothing else is needed for "which tree" |
| `VCPKG_TRACE_FIND_PACKAGE=ON` | That a `find_package` call happened. It is a macro override of `find_package` inside `vcpkg.cmake` | Which prefix answered. It logs every call, whoever satisfies it |
| `vcpkg depend-info` | What the manifest declares | Anything about a configure |
| The `Version:` lines of `build/vcpkg_installed/vcpkg/status`, or the `<port>:<triplet>@<version>` lines of `vcpkg-manifest-install.log` | The version installed into this tree. Only an `install ok installed` entry counts | Why that version: read the baseline's entry |
| `vcpkg install --dry-run` in the manifest directory | What the manifest resolves to now | What an existing build tree consumed |
| `vcpkg x-update-baseline` | Nothing. It moves the baseline (`--add-initial-baseline` the first time), and the `x-` prefix marks it experimental | It is the only way to move a baseline, never a hand edit (CMK-VCPKG-01) |

Re-pointing `VCPKG_INSTALLED_DIR`, the triplet or the manifest root on a
reused build tree leaves `<X>_DIR` on the old tree, exactly like the plain
CMake case (measured 2026-09-26 with vcpkg-tool 2026-09-26 and two
overlay-port builds). The fix is CMK-DEP-13's: a fresh tree, `--fresh`, or
`-U <X>_DIR`.
