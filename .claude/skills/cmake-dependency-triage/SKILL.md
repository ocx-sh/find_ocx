---
name: cmake-dependency-triage
description: Symptom-first triage for a CMake dependency that resolved to the wrong copy, version or mechanism, with the exact cache, configure-log, Conan, vcpkg and CPM reads and what each output means. Use when find_package picked the wrong installed copy, a re-pointed _ROOT, CMAKE_PREFIX_PATH or toolchain had no effect, a cross build linked a host library, a fetched or CPM copy was built instead of the expected one, two copies of one library meet in one link, a provider or cmake-conan never supplied a package or find_program cannot see it, a binary loads a different copy than the one configured, a consumer fails with "link interface of target ... not found", CMake 4 reports "Compatibility with CMake < 3.5 has been removed" or the gate stops on "< 3.10 will be removed" or install-absolute-destination in a dependency, an offline or FETCHCONTENT_SOURCE_DIR configure fails where the online one passed, or someone asks which version Conan or vcpkg picked. Not for choosing a package manager or writing build files.
license: Apache-2.0
metadata:
  summary: Ordered triage for "which copy, which version and which mechanism resolved this dependency", read from the configure's own records before any debug flag
  keywords: cmake,dependency,triage,find_package,CMakeCache,_DIR,_ROOT,debug-find-pkg,fresh,CMakeConfigureLog,FetchContent,OVERRIDE_FIND_PACKAGE,pkgRedirects,FETCHCONTENT_SOURCE_DIR,dependency-provider,cmake-conan,CMakeConfigDeps,conan-graph-info,conan-graph-explain,conan.lock,vcpkg,VCPKG_INSTALLED_DIR,toolchain,CMAKE_FIND_ROOT_PATH,find_dependency,CMAKE_POLICY_VERSION_MINIMUM,cmake_minimum_required,CPM,CPMUsePackageLock,CPM_USE_LOCAL_PACKAGES,CPM_SOURCE_CACHE,bundled,CMAKE_SYSROOT,CMAKE_LIBRARY_ARCHITECTURE,pkg_check_modules,ExternalProject
---

# cmake-dependency-triage

Answer one question with evidence: which copy, which version and which
mechanism resolved this dependency, and why not the one you expected. Then hand
the fix to the rule that owns it.

It assumes the `cmake-build` and `cpp-packaging` rule sets and repeats the MUST
rows it leans on at the end. Everything below ran on CMake 3.31.12, 4.3.4 and
4.4.2 against real trees (2026-09-26). The references name each tree and tool.

Contents: [Stop condition](#stop-condition) · [The evidence rule](#the-evidence-rule) · [Before you start](#before-you-start) · [The read order](#the-read-order) · [Check the classes](#4-check-the-eight-classes-before-you-name-the-copy) · [Pick the entry point](#pick-the-entry-point) ·
[T1 to T15](#t1-and-t13-wrong-copy-or-a-re-pointed-hint-had-no-effect) · [Pinned defaults](#pinned-defaults) · [MUST rows this procedure enforces](#must-rows-this-procedure-enforces) · [References](#references)

## Stop condition

Stop when the triage names all three. Any one missing and it is a guess.

- **Which copy.** On a `--fresh` configure, `<Pkg>_DIR` (or a Find module's
  library cache line, or the provider that answered) names the copy you intended,
  and step 4's C3 and C8 reads find no other copy in the artifact.
- **Which mechanism put it there.** A stale cache entry, a FetchContent or
  CPM redirect, a provider, a toolchain-injected root, a Find module, a bundled
  copy, a second lookup, or the manager's resolution. "It found X" is not one.
- **The rule that fixes it, and its check passing.** Applied at the file and
  line that decided, never at a layer that did not.

Out of scope, because each turns a diagnosis into a defect: a global floor
switch, wiping the tree before step 1, a hand-edited lockfile (CMK-CONAN-09),
and `cmake_language(DEFER)` as an ordering fix (CMK-TC-05).

## The evidence rule

Provenance comes only from the configure's own records (class C1):
`CMakeCache.txt` read by `grep` (never `cmake -L`, which omits the
`UNINITIALIZED` type of a plain `-Ddep_ROOT=...`), `CMakeFiles/pkgRedirects/`,
`CMakeConfigureLog.yaml` events on 4.1 and newer, and `--debug-find-pkg=NAME`
output from a `--fresh` configure only. Never from the call site, a green
configure, a manager's trace (`VCPKG_TRACE_FIND_PACKAGE`, `vcpkg depend-info`),
`conan graph info`, or `cmake --graphviz`. A bundled copy's record is its
version macro (T14), and each lookup of a library has its own record (C8).

## Before you start

```sh
cmake --version
```

The binary line decides the gate spelling and which floor rule applies. Every
configure in this skill passes the gate for its line and, because a fetch may
be involved, `-DCMAKE_POLICY_DEFAULT_CMP0170=NEW` (floor pinned below).

| Binary line | `GATE` | A dependency floor of 3.5 to 3.9 | A floor below 3.5 |
|---|---|---|---|
| 3.x (3.31.12) | `-Werror=dev` | T6, fixed by CMK-DEP-30 | T6 as well: 3.31.12 prints the same deprecation for it |
| 4.0 to 4.3 (4.3.4) | `-Werror=dev` | T6, fixed by CMK-DEP-15 | T5, fixed by CMK-DEP-15 |
| 4.4 and newer (4.4.2) | `-Werror=author` | T6, fixed by CMK-DEP-15 | T5, fixed by CMK-DEP-15 |

`-Werror=author` below 4.4 is ignored silently, so one command line serving
both sides uses `-Werror=dev`, which 4.4.2 still honours (CMK-CORE-01).

## The read order

Run the four steps in order, on the tree that showed the symptom. `build` and
`dep` stand for the leg's build directory and the name as the call spells it.

### 1. Grep the cache, before any flag

```sh
NAME=dep
grep -rn --include='CMakeCache.txt' -e "^${NAME}_DIR" -e "^${NAME}_ROOT" -e '^CMAKE_PREFIX_PATH' -e '^VCPKG_INSTALLED_DIR' -e '^CMAKE_TOOLCHAIN_FILE' -e '^CMAKE_PROJECT_TOP_LEVEL_INCLUDES' -e '^CPM_PACKAGE_' -e '^CPM_USE_LOCAL_PACKAGES' -e '^CPM_SOURCE_CACHE' -e '^HUNTER_CACHED_ROOT' build
```

The patterns are a union, so read each line, and the first row below that
matches decides. Empty output means `build` is not the leg's tree, or no call,
hint or manager reached this cache: check both before the last-but-one row.
Save the output before step 2, because `--fresh` deletes the cache it came
from. Lines from a second `CMakeCache.txt` are a nested configure's (C8).

| What the output shows | Reading | Go to |
|---|---|---|
| `CMAKE_TOOLCHAIN_FILE` names `vcpkg.cmake`, and no `VCPKG_INSTALLED_DIR` line | vcpkg's toolchain never ran. A toolchain given to an existing build tree is cached and never loaded: `grep -rn --include='CMakeSystem.cmake' -e 'include(' build/CMakeFiles` prints nothing (3.31.12 and 4.4.2) | T1 |
| A `dep_DIR` line while `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` names cmake-conan with `CMakeConfigDeps` | The provider's own search failed, and its fallback `find_package` found a copy outside Conan | T13 |
| `dep_DIR` is a Conan `generators` folder | That folder is the copy of record, whatever version it now describes. Read the version there, never from `conan graph info` | T8 |
| `CPM_USE_LOCAL_PACKAGES:BOOL=ON` | CPM ran `find_package` before fetching. The option is read from the environment on the first configure and then cached, so unsetting the variable or `-U dep_DIR` keeps the local copy (4.4.2) | T15 |
| `CPM_PACKAGE_dep_VERSION` other than the version the `CPMAddPackage` call names | Another declaration of the name came first, a `CPMUsePackageLock` file included | T15 |
| `CPM_PACKAGE_dep_SOURCE_DIR` outside the build tree | A shared `CPM_SOURCE_CACHE` copy, which every tree reuses, `--fresh` included | T15 |
| `HUNTER_CACHED_ROOT` | A Hunter root outside the tree decides what runs, and a step that runs only while it lacks something passes on a populated one. Compare it with CI's, and reproduce on a new, empty `HUNTER_ROOT` | C2 |
| `dep_DIR` not under the current `dep_ROOT`, `CMAKE_PREFIX_PATH` entry or `VCPKG_INSTALLED_DIR` | A stale cache entry, or a rooted copy. Step 2 tells them apart | T1, T9 |
| `dep_DIR:PATH=<build>/CMakeFiles/pkgRedirects` | A FetchContent or CPM redirect answered, and step 2 prints its candidates with no `The file was found at` line. An installed copy was never consulted | T2 |
| No `dep_DIR` line, with `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` naming a provider | Expected under cmake-conan with `CMakeConfigDeps`: the provider sets `dep_DIR` as a normal variable (measured 3.31.12 and 4.4.2) | T3 |
| No `dep_DIR` line and no provider | A Find module answered, or the call never ran. A module's copy is its `<NAME>_LIBRARY*` and `<NAME>_INCLUDE_DIR` cache lines, grepped with `NAME` as the call spells it | [references](references/reading-the-answers.md#module-mode-find_package) |
| `dep_DIR` under the expected prefix, and no row above matches | The configured copy is right for this lookup. A binary that reports another version at run time is a second lookup (C8), the loader (T11), or, with no `ldd` line for the library, a bundled copy compiled in (T14). One that loads another file of the same package is the imported configuration (C3). Otherwise a wrong version is the manager's | C8, T11, T14, C3, T8, T9 |

### 2. Reconfigure fresh, with the search printed

```sh
GATE=-Werror=dev
GEN=Ninja
cmake -S . -B build -G "$GEN" --fresh "$GATE" -DCMAKE_POLICY_DEFAULT_CMP0170=NEW --debug-find-pkg="$NAME"
```

Pass the same `-G`, `-D` hints and `--toolchain` the leg passes. `--fresh`
drops the cached generator, and a superbuild's next build then stops on its
inner tree's generator (exit 2 on 3.31.12, 4.3.4 and 4.4.2). A preset leg runs
`cmake --preset "$PRESET" --fresh "$GATE" -DCMAKE_POLICY_DEFAULT_CMP0170=NEW
--debug-find-pkg="$NAME"` with its configure preset, so its cache variables
and `warnings` block apply exactly as in CI.

- `The file was found at` followed by a path names the file that answered.
  `The item was found at` is a `find_library` or `find_path` answer: for a Find
  module those lines are the copy, and `The file was found at` names the module.
- `Package was found by the dependency provider` means the provider returned,
  not that it supplied the copy. cmake-conan prints it after its fallback
  search too, so read the path above it (C1, T13).
- On a reused tree the same flag lists only the cached candidate and prints
  the old answer with no warning (measured, both lines). That is why it never
  runs before step 1, and never without `--fresh`.
- A gated configure that stops at a floor error first is T5 or T6.

Then re-run the step 1 grep beside the saved output (C2), comparing values,
not line numbers, which `--fresh` shifts. A moved `dep_DIR` is a stale cache,
and step 4's C4 question reads one that stayed (T1, CMK-DEP-21).

### 3. On CMake 4.1 and newer, read the configure log

```sh
grep -rc --include='CMakeConfigureLog.yaml' -e 'kind: "find_package-v1"' build
grep -rn --include='CMakeConfigureLog.yaml' -e '^    name: ' -e '^      path: ' -e '^      mode: ' -e '^      version: ' build
```

Run both only after step 2's `--fresh` configure, because the log appends on a
reused tree. Empty output from the count means no configure log (not
applicable), and 0 on 3.x is expected. 0 on 4.1 or newer after a
`find_package` ran is a finding (CMK-DEP-17), but a FetchContent or CPM
redirect logs an event only under `--debug-find-pkg`, with its `path:` in
`pkgRedirects` and a blank found `version:` (4.3.4 and 4.4.2). A blank found
`version:` beside any other path means the package ships no version file
(json-c 0.17 and 0.18): read its version macro (step 4's C3). The second
command pairs each `name:` with its `path:`, `mode:` and `version:` lines, the
request's version first. A found version other than the manager's is the
finding. A Find module reports the version it parsed, usually the header's
(C8). Empty output means no `find_package` resolved. On 3.x, read the version
file beside step 1's `_DIR` ([references](references/reading-the-answers.md#config-mode-find_package)).
cmake-conan's events: [references](references/reading-the-answers.md#dependency-providers).

### 4. Check the eight classes before you name the copy

Every failure this read order has shown on a real tree is one of eight
mechanisms, and so is a symptom no entry row names. Ask each question and follow
the first that fails ([measured cases](references/failure-modes.md)).

| Class | Ask | Read | A failing answer goes to |
|---|---|---|---|
| C1 Proxy record | Is each path and version you cite a record of what this tree consumed? | The evidence rule's list | The consumption record: the generators folder (T8), vcpkg's `status` (T9), the `CPM_PACKAGE_` lines (T15), `CMakeSystem.cmake` (T1), the `The file was found at` path (step 2) |
| C2 Sticky state | Did a cached or once-written input outlive the change? | Step 1's saved output beside the re-grep after step 2 | Name the line that moved. A reset that clears the symptom with no moved line names no mechanism. `-U` never reloads a toolchain or a cached `CPM_USE_LOCAL_PACKAGES` (T1, T15), and `--fresh` resets only the tree it names, never a nested configure's (C8) |
| C3 Substitution after resolution | Does the artifact carry the copy the records name? | The reads below | C8 when its reads show a second copy, else T11, T14, T7, T15 or the imported configuration, by the read that differs |
| C4 Absent or rejected candidate | Where is the expected copy in step 2's candidate list? | Step 2's output, searched for the expected path | Never listed: the search space (T1, T3), or a nested configure's forwarded arguments (C8). `considered but not accepted`: the request (T13). Listed and beaten: precedence (T1) |
| C5 Record shape | Does the read fit the mechanism that answered? | Step 1's table, re-run with `NAME` spelled as each declare spells it | An empty or zero result is absence only for a mechanism that writes that record (step 3, T2, the module row) |
| C6 Gate stop in third-party code | Does the remedy change the dependency's input, with the gate on, on every CI line? | The T5 and T6 writes grep, the T12 grep | A warning switch, a scoped diagnostic, `CMAKE_SKIP_INSTALL_RULES`, a knob the line ignores, or a variable that never reaches a child configure (T5, T6, T12) |
| C7 Narrow proof | Does the proof run the consumer kind that failed? | The CMK-INST-01 round trip | A compiled consumer that calls one exported function, once per consumer kind that failed (T4) |
| C8 Several lookups | Is every lookup that fed the artifact accounted for? | The C8 reads below | Two copies: resolve the library once (CMK-DEP-33). A nested configure: steps 1 to 3 on its tree |

The C3 reads of the artifact and its source, whatever the entry row:

```sh
BIN=build/app
ldd "$BIN"
readelf -d "$BIN"
grep -rho --include='build.ninja' --include='flags.make' -e '-isystem [^ ]*' -e ' -I[^ ]*' build | sort -u
grep -rn --include='*.h' --include='*.hpp' -e 'define FMT_VERSION ' /usr/local/include /opt/spdlog/include
DIR=build/_deps/dep-src
git -C "$DIR" status --porcelain
grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'PATCH_COMMAND' .
grep -rn --include='CMakeLists.txt' --include='*.cmake' --include='CMakePresets.json' --include='CMakeUserPresets.json' --include='*.yml' --include='*.yaml' --include='*.sh' -e 'FETCHCONTENT_SOURCE_DIR_' .
PKGDIR=/usr/local/lib/cmake/dep
grep -rn --include='*.cmake' -e 'IMPORTED_CONFIGURATIONS' "$PKGDIR"
grep -rn --include='CMakeCache.txt' -e '^CMAKE_BUILD_TYPE' -e '^CMAKE_CONFIGURATION_TYPES' -e '^CMAKE_MAP_IMPORTED_CONFIG_' build
```

- **T11, `ldd` and `readelf -d`** on the binary and its build-tree twin. The
  `ldd` line naming the library is the copy that loads. Another file name of
  the recorded package (a postfix such as `d`) is another build of it (the
  imported configuration). None, or `not a dynamic executable`, means not
  applicable. An installed binary with no `RUNPATH` or `RPATH` line, whose twin
  has one, lost it at install, so a same-SONAME copy on the loader's path wins
  with exit 0. Fix with CMK-INST-11 (`$ORIGIN`) for the same prefix,
  `INSTALL_RPATH_USE_LINK_PATH ON` for another, never `LD_LIBRARY_PATH`. A
  `RUNPATH` naming two directories that both hold the SONAME is C8, not T11.
- **T14, the macro grep**, over each directory the include grep prints (empty:
  another generator, so step 1's prefixes). One hit passes, and empty output
  means a wrong macro or directory. A second hit under the same package's other
  prefix is a second lookup (C8). One under another package's tree is a bundled
  copy: consume the package's build that uses the external copy, never an
  include order (CMK-DEP-33, [references](references/reading-the-answers.md#bundled-copies)).
- **T15, `git`.** Set `DIR` to step 1's `_SOURCE_DIR` value. Empty output
  passes, `not a git repository` means a URL download (not applicable), and a
  line means another project edited the shared checkout (CMK-DEP-16).
- **T7, the last two greps.** `FETCHCONTENT_SOURCE_DIR_<X>` skips the
  declare's `PATCH_COMMAND` (3.31.12, 4.3.4 and 4.4.2). Empty first output
  means no dependency is patched, so the cause is elsewhere in the offline
  probe (CMK-DEP-16). Empty second output means no override (not applicable).
  A name in both whose override directory lacks the patched line is the
  finding (CMK-DEP-31). The probe always carries
  `-DCMAKE_POLICY_DEFAULT_CMP0170=NEW`, or a missing source directory exits 0.
- **The imported configuration, the last two greps,** with `PKGDIR` from step
  1's `dep_DIR`. Empty first output: not applicable. Empty second output:
  `build` is not a configured tree. A leg configuration that
  no `IMPORTED_CONFIGURATIONS` line lists and no map line maps links the first
  listed, `DEBUG` by file order, with exit 0 and no warning ([lz4](references/failure-modes.md#c3-substitution-after-resolution)).
  Map it in the leg's preset or toolchain, `CMAKE_MAP_IMPORTED_CONFIG_RELWITHDEBINFO`
  as `RelWithDebInfo;Release` as vcpkg's toolchain does, never empty (CMK-INST-22).

The C8 reads, from the artifact's side, with `LIB` as the library's file name:

```sh
LIB=libzstd
grep -rho --include='build.ninja' --include='link.txt' -e "[^ ]*/${LIB}[.][^ ]*" build | sort -u
grep -rn --include='CMakeConfigureLog.yaml' -e "^    found: \"[^\"]*/${LIB}[.]" build
grep -rl --include='CMakeCache.txt' -e '^CMAKE_HOME_DIRECTORY' build
```

- **Link lines.** One directory passes. Empty output means a wrong `LIB`, or a
  link line naming another build: re-run with the `ldd` line's file name. Two
  directories are two lookups on two copies: resolve the library once and
  link that target everywhere (CMK-DEP-33). The ungated `Cannot generate a safe
  runtime search path` warning with `cycle` is the same finding.
- **`found:` lines** (4.1 and newer) are `find_library` answers, pkg-config's
  included. A prefix that steps 1 and 3 do not name is a second lookup, and
  empty output passes.
- **Caches.** One file passes. More than one is a nested configure: run steps
  1 to 3 on the tree that holds the artifact, with the arguments in its
  `<name>-prefix/tmp/<name>-cfgcmd.txt`. A list forwarded through `CMAKE_ARGS`
  arrives cut to its first entry (CMK-DEP-34,
  [forwarding](references/failure-modes.md#c8-one-dependency-several-lookups)).
  Count also under each `-B` the console names and a manager's root, where
  HunterGate's bootstrap keeps its cache (C8).

## Pick the entry point

| # | Symptom | First read | Reading | Fixing rule |
|---|---|---|---|---|
| T1 | Wrong copy or version found. A re-pointed hint had no effect | Step 1, then step 2 | `_DIR` moves under `--fresh`: stale cache. It does not move: a rooted copy wins, or the expected copy was never a candidate | CMK-DEP-13, CMK-DEP-21, CMK-TC-08 |
| T2 | Installed copy ignored, fetched copy built | Step 1 | `_DIR` under `pkgRedirects` | CMK-DEP-07, CMK-DEP-09, CMK-DEP-32 |
| T3 | cmake-conan active, `find_program` or `find_library` NOTFOUND | Configure console output | `Loading conan_cmakedeps_paths.cmake` absent: `CMakeDeps`. Present: check the call's directory | CMK-TC-05, CMK-TC-04 |
| T4 | Consumer fails right after `Configuring done` with "The link interface of target ... not found" | The installed Config file | No `find_dependency` for a package on the link interface | CMK-INST-03, CMK-INST-01 |
| T5 | 4.x: "Compatibility with CMake < 3.5 has been removed" | The error's file:line | A dependency's floor | CMK-DEP-15 |
| T6 | Gate error: "Compatibility with CMake < 3.10 will be removed" | The error's file:line and `cmake --version` | 4.x: CMK-DEP-15. 3.x: CMK-DEP-30 | CMK-DEP-15, CMK-DEP-30 |
| T7 | Online configure passes, offline or override configure fails | Step 4's patch and override greps | An override of a patched dependency | CMK-DEP-31, CMK-DEP-16 |
| T8 | "Which version did Conan pick?" | `conan graph info`, then the generators folder | graph info: what the conanfile resolves to now. The folder: what this tree consumes | CMK-CONAN-07, CMK-CONAN-09 |
| T9 | vcpkg: wrong tree or wrong version | Step 1 | `_DIR` not under the current `VCPKG_INSTALLED_DIR`: T1 through vcpkg. A version above a `version>=` floor: the baseline won | CMK-DEP-13, CMK-VCPKG-01, CMK-VCPKG-02 |
| T10 | A provider registered, never called | Step 1, then the TC-04 grep | The project set or appended `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` | CMK-TC-04 |
| T11 | The configured copy is right, but the built or installed binary loads another | Step 4's `ldd` and `readelf -d` | No `RUNPATH` on the installed binary while the build-tree binary has one: install stripped it and a same-SONAME copy on the loader path wins. Another file of the same package: step 4's imported configuration | CMK-INST-11, CMK-INST-22 |
| T12 | 4.4 and newer: the gate stops on `install-absolute-destination` inside a fetched or vendored dependency | The error's file:line | The dependency installs to an absolute `DESTINATION` (`CMAKE_INSTALL_FULL_*`) | CMK-DEP-30, CMK-DEP-31 |
| T13 | cmake-conan ran, and the consumer got a copy or version Conan did not install | Step 1, then step 2 | A `dep_DIR` cache line under `CMakeConfigDeps`, and `considered but not accepted` naming the generators copy | CMK-DEP-32, CMK-CONAN-07 |
| T14 | A link error names two versions of one library ("did you mean" another inline namespace), or a static binary runs another version than `<dep>_DIR` names | Step 4's include and version-macro greps | Another package bundles a copy in its headers and library | CMK-DEP-33 |
| T15 | A CPM project builds another version or source than its `CPMAddPackage` call names | Step 1's `CPM_` lines | A lock declaration, a cached `CPM_USE_LOCAL_PACKAGES`, or a shared source cache | CMK-DEP-10, CMK-DEP-16, CMK-DEP-32 |

## T1 and T13 Wrong copy, or a re-pointed hint had no effect

A resolved `find_package` keeps `<Pkg>_DIR` in the cache, so re-pointing
`<Pkg>_ROOT`, `CMAKE_PREFIX_PATH`, `VCPKG_INSTALLED_DIR` or a Conan output
folder keeps the old copy while the hint prints the new value (both lines).
Step 4's C4 answer picks the branch:

- **Listed, and `_DIR` moves under `--fresh`.** Stale cache (C2): `--fresh`
  or a new tree, and `-U <Pkg>_DIR` only when the toolchain did not change
  (CMK-TC-03). A module that writes a `_ROOT` cache entry on every configure
  needs CMK-DEP-13's guarded `unset(<Pkg>_DIR CACHE)` ([the module grep](references/failure-modes.md#c2-sticky-state-outlives-its-input)).
- **Listed, and `_DIR` stays put under `--fresh` and starts with a root.**
  `CMAKE_FIND_ROOT_PATH` or `CMAKE_SYSROOT` is non-empty (step 2 prints both),
  and every rooted candidate beats an unrooted `_ROOT` hint. Pin the copy with
  `<Pkg>_DIR` (CMK-DEP-21, and CMK-TC-10 under a Conan cross build).
- **T13, `considered but not accepted` names the generators copy, or both
  roots are empty while step 1 names cmake-conan.** cmake-conan re-runs a
  failed generators search with CMake's default search, so a request that
  rejects Conan's copy, or a conanfile without the package, lets another copy
  win with exit 0 ([references](references/reading-the-answers.md#dependency-providers)).
  Fix the request or the conanfile, never with a `_DIR` pin. A leg that must
  use Conan's copy asserts that step 1 prints no `<Pkg>_DIR` line for it
  (CMK-DEP-32).
- **Never listed, and `_DIR` stays put outside every root in a cross build.**
  The target's copy was never a candidate, and the toolchain leaves the
  find-root modes at `BOTH` (CMK-TC-08). A sysroot's `usr/lib/<triplet>` is
  searched only when `CMAKE_LIBRARY_ARCHITECTURE` is set, which a compiler with
  no implicit link directories leaves empty, so the toolchain also sets the
  triplet (CMK-TC-11, [references](references/reading-the-answers.md#toolchain-injected-paths)).

## T2 Installed copy ignored, fetched copy built

`dep_DIR` under `CMakeFiles/pkgRedirects` means an `OVERRIDE_FIND_PACKAGE`
declare, or a `FIND_PACKAGE_ARGS` declare that fell through to a fetch, won,
and `--debug-find-pkg` never names the installed prefix (both lines). Name the
declaring line with a grep, never a trace:

```sh
grep -rn --include='*.cmake' --include='CMakeLists.txt' -e 'OVERRIDE_FIND_PACKAGE' .
```

Empty output, or a hit only inside `CPM.cmake` (CPM writes the redirect for
every package it fetches: T15), means no override declare. Then a
`FIND_PACKAGE_ARGS` try-find missed on a name spelled unlike the Config file:
re-run step 1 with that spelling (C5, [references](references/reading-the-answers.md#fetchcontent-redirects)). A hit
in an installable library outside a top-level guard is a CMK-DEP-07 finding.
A later `find_package(dep 2.0 ...)` against the redirect passes with a blank
version (CMK-DEP-09). A CI leg on the installed copy asserts step 1's path (CMK-DEP-32).

## T3 and T10 A provider that never supplies the package

Providers intercept only `find_package` and `FetchContent_MakeAvailable`. T3's
tell is in the console output, never in `CMakeConfigureLog.yaml`, and the
second grep is T10's:

```sh
PRESET=default
mkdir -p logs
cmake --preset "$PRESET" --fresh "$GATE" -DCMAKE_POLICY_DEFAULT_CMP0170=NEW > logs/configure.log 2>&1
grep -rn --include='configure.log' -e 'conan_cmakedeps_paths' logs
grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'SET_DEPENDENCY_PROVIDER' -e 'CMAKE_PROJECT_TOP_LEVEL_INCLUDES' .
```

A leg without presets captures the step 2 command the same way. Empty output
from the first grep means `CMakeDeps`, whose content no `find_*` call sees. A
`Loading` line means `CMakeConfigDeps`, whose paths exist after the first
intercepted `find_package`, in that directory scope (4.4.2). The fix is
CMK-TC-05, and `DEFER` never helps ([references](references/reading-the-answers.md#dependency-providers)).

T10: step 1 shows the user's file in `CMAKE_PROJECT_TOP_LEVEL_INCLUDES`, and
step 2 never credits the provider. A project `set()` hides the user's file, and
a `list(APPEND)` registers the project's provider last, which wins. Empty output
from the second grep passes, and any project hit is the finding (CMK-TC-04).

## T4 Consumer fails after Configuring done

The error names the installed `*Targets.cmake`: the exporter never redeclared
a dependency on its link interface. Only a compiled consumer fails (class C7).

```sh
NAME=dep2
PREFIX=/usr/local
grep -rn --include="${NAME}Config.cmake" --include="${NAME}-config.cmake" -e 'find_dependency' "$PREFIX"
grep -rn --include="${NAME}*argets.cmake" -e 'INTERFACE_LINK_LIBRARIES' "$PREFIX"
```

Empty output from the first while the second names another package's target
is the finding (CMK-INST-03). Empty output from the second means no exported
target links another package (not applicable). The proof is the CMK-INST-01
round trip with a compiled consumer.

## T5, T6 and T12 The gate stops inside a dependency

Each is class C6: the remedy changes the dependency's input, never the gate.
T5 is 4.x's "Compatibility with CMake < 3.5 has been removed". T6 is the gate
on "< 3.10 will be removed" (`CMake Deprecation Error` on 3.31.12 and 4.3.4,
`CMake Error (deprecated)` on 4.4.2). Both name the dependency's
`cmake_minimum_required` line, relative to the configure that printed it: if
the project's line holds no such call, the tree is the console's reproduce
line's `-H` and `-B` (C8). On 4.x the fix is CMK-DEP-15, value 3.10 (never
3.5), scoped to the one call that adds the dependency. On 3.x it is
CMK-DEP-30, a re-pin or a one-line `PATCH_COMMAND`, because 3.31.12 ignores
`CMAKE_POLICY_VERSION_MINIMUM`. A child configure (a manager's bootstrap,
`execute_process` of `cmake`) sees neither the scoped value nor a `-D`, nor the
gate on 3.x: on every line re-pin or patch the file that writes its floor (the
third grep, [FM](references/failure-modes.md#c6-a-gate-stop-in-third-party-code-cleared-at-the-wrong-knob), CMK-DEP-06). T12 is 4.4's `install-absolute-destination`
inside a dependency: only one `PATCH_COMMAND` over every absolute destination
clears it on 4.4.2 ([FM11](references/failure-modes.md#c6-a-gate-stop-in-third-party-code-cleared-at-the-wrong-knob)).
List the floor writes, then the absolute destinations:

```sh
grep -rn --include='*.cmake' --include='CMakeLists.txt' --include='CMakePresets.json' --include='*.yml' --include='*.yaml' -e 'CMAKE_POLICY_VERSION_MINIMUM' -e 'CMAKE_POLICY_DEFAULT_CMP' .
grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'CMAKE_INSTALL_FULL_' build/_deps
grep -rn --include='CMakeLists.txt' --include='*.cmake' -e '"cmake_minimum_required(VERSION' .
```

Empty first output passes. Each hit must be a set/restore around one call that
adds the dependency, a `set()` inside a function, or a vcpkg port's own
arguments, and a preset, workflow or file-scope hit is the finding. Empty
second output means a literal absolute path, so read the error's file:line.
The third lists floors written into a generated project, and empty output
means none (not applicable). The gate never drops (CMK-CORE-01).

## T8 and T9 Which version the manager put in this tree

Both are class C1. Conan's graph info (with the build's `conan install` flags)
prints what the conanfile resolves to now. The grep reads the generators folder
the tree builds against:

```sh
conan graph info . --profile:host=default --profile:build=default
grep -rn --include='*ConfigVersion.cmake' --include='*-config-version.cmake' --include='*-data.cmake' -e 'set(PACKAGE_VERSION ' -e '_PACKAGE_FOLDER_[A-Z]* "' build
```

Hits under `generators` are this tree's version and package folder, and empty
output means no generators folder (not applicable). Another version than graph
info's means `conan install` did not run after a change (CMK-CONAN-07,
CMK-CONAN-09, [references](references/reading-the-answers.md#the-conan-graph)).
For vcpkg, step 1's lines answer "which tree" (a `_DIR` outside
`VCPKG_INSTALLED_DIR` is T1), and `status` answers the version:

```sh
grep -rn --include='status' -e '^Package: ' -e '^Version: ' -e '^Status: ' build/vcpkg_installed/vcpkg
```

Only an `install ok installed` entry counts, and empty output means no manifest
install ran into this tree. A version above a `version>=` floor is the baseline
winning (CMK-VCPKG-02, [references](references/reading-the-answers.md#vcpkg)).

## T15 CPM chose another copy

Step 1's `CPM_PACKAGE_<name>_VERSION` and `_SOURCE_DIR` lines are CPM's record.
List the declarations, the lock included:

```sh
grep -rn --include='CMakeLists.txt' --include='*.cmake' --exclude='CPM.cmake' --exclude='cpm-package-lock.cmake' --exclude-dir='_deps' -e 'CPMUsePackageLock' -e 'CPMDeclarePackage' -e 'CPMAddPackage' .
```

Empty output means no CPM (not applicable). A `CPMDeclarePackage` beats every
`CPMAddPackage` of the name with one ungated warning, so a bump goes in the
lock (CMK-DEP-10). Step 2's `Debug Log at cmake/CPM.cmake` is the cached local
search: pass `-DCPM_USE_LOCAL_PACKAGES=OFF`, and a CI leg asserts the copy
(CMK-DEP-32). A `_SOURCE_DIR` under `CPM_SOURCE_CACHE` gets step 4's `git`
read (CMK-DEP-16, [references](references/reading-the-answers.md#cpm)).

## Pinned defaults

Agreed once, never re-litigated during a triage. Every shipped probe's floor is
`cmake_minimum_required(VERSION 3.25...4.4)`. The gate and floor value are as
in [Before you start](#before-you-start) and T5 and T6, with
`CMAKE_POLICY_VERSION_MINIMUM` 3.5 only inside a vcpkg port build. Conan runs
an explicit `conan install`, then `cmake --preset`, and the cmake-conan
provider is legal within CMK-TC-05's limits, never with `DEFER` as a fix. One
manager of record per configure (CMK-PKG-01, CMK-TC-02).

## MUST rows this procedure enforces

Duplicated as a hedge against the scoped rule set not being loaded. The full
rows live in the `cmake-build` and `cpp-packaging` rule sets, which settle a dispute.

| # | Finding | Rule |
|---|---|---|
| 1 | An application whose `requires` or `tool_requires` use a version range commits `conan.lock`. CI passes `--lockfile=conan.lock` explicitly and never `--lockfile-partial`. The lock is regenerated with `--lockfile-out` (plus `--lockfile-clean`), never edited by hand | CMK-CONAN-09 |
| 2 | An installable library resolves its dependencies with `find_package` and never forces acquisition | CMK-DEP-07 |
| 3 | Treat `<Pkg>_DIR` as the sticky record of which copy was found. To switch copies use a fresh build tree, `--fresh` or `-U <Pkg>_DIR`, and only a fresh tree or `--fresh` when the switch adds or changes the toolchain. A module that re-points `<Pkg>_ROOT` on reconfigure must `unset(<Pkg>_DIR CACHE)` whenever the hint's value changes | CMK-DEP-13 |
| 4 | On CMake 4.x, set a third-party dependency's policy knobs with set/restore around the one `add_subdirectory`, `FetchContent_MakeAvailable` or `find_package` that loads it, with `CMAKE_POLICY_VERSION_MINIMUM` at 3.10. Never use a project-wide `set()`, a committed preset `cacheVariables` entry, or a CI environment variable. A dependency configured in a child process (a manager's bootstrap such as HunterGate, or `execute_process` of `cmake`) never sees the value or a `-D`: re-pin or patch the file that writes its floor, as CMK-DEP-30 does on 3.x | CMK-DEP-15 |
| 5 | Make every configure-time network touch satisfiable offline | CMK-DEP-16 |
| 6 | On CMake 3.x, clear a fetched or vendored dependency whose floor is 3.5 to 3.9 by re-pinning to a version that declares 3.10 or newer, or with a `PATCH_COMMAND` that rewrites that one `cmake_minimum_required` line. Never use `-DCMAKE_WARN_DEPRECATED=OFF`, `-Wno-dev`, `-Wno-deprecated`, `-Wno-error=deprecated` or a preset's `"warnings": {"deprecated": false}` as the remedy | CMK-DEP-30 |
| 7 | Point an offline or override configure (`FETCHCONTENT_SOURCE_DIR_<X>`, including the CMK-DEP-16 probe) only at source that already carries the declare's `PATCH_COMMAND` result | CMK-DEP-31 |
| 8 | Whenever install, export, Config-template or dependency wiring changes, prove the package can be consumed with the round-trip script. Never treat a green build and install as proof | CMK-INST-01 |
| 9 | In the Config template, redeclare every imported dependency that sits on an exported target's PUBLIC or INTERFACE link line with `find_dependency()`, under the same condition the build used to add it. Never use a raw `find_package()` there | CMK-INST-03 |
| 10 | Leave the dependency provider to the user. Never `set()` or `list(APPEND)` `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` from project or module code, and list at most one provider-registering file per configure | CMK-TC-04 |
| 11 | Never design on a provider seeing `find_program`, `find_library` or `find_path`. With cmake-conan they see Conan content only under `CMakeConfigDeps`, only after the first intercepted `find_package`, and only in that directory scope, so the first `find_package` of a Conan package goes in the top-level `CMakeLists.txt` before any `add_subdirectory`. `DEFER` is not an ordering fix | CMK-TC-05 |
| 12 | Link one copy of each library. When a consumed package can bundle a dependency that the project, or another package in the same link, also uses, consume the package's build that uses the external copy (spdlog: `SPDLOG_FMT_EXTERNAL=ON`) | CMK-DEP-33 |
| 13 | Forward a list-valued search variable to an `ExternalProject_Add` configure through `CMAKE_CACHE_ARGS` with a `:STRING` type, never as `-D<VAR>=${list}` in `CMAKE_ARGS` | CMK-DEP-34 |

## References

Read one level down, on demand.

| File | Read it when |
|---|---|
| [references/reading-the-answers.md](references/reading-the-answers.md) | An output does not match a row above. Holds, per mechanism, what each writes into the cache, the redirects directory and the configure log: Config and Module mode, FetchContent redirects, providers, toolchain-injected paths, bundled copies, CPM, the Conan graph and vcpkg |
| [references/failure-modes.md](references/failure-modes.md) | A step 4 question fails, or a symptom resembles a measured case. Holds each class's instances (the old failure modes 1 to 19 and the misled, stalled and wrong steps of the real-tree runs) with version, exit code and output, and the re-check list for each tool bump |
