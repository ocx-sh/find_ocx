---
title: Toolchains, Top-Level Includes and Dependency Providers
summary: The CMK-TC family. One toolchain source per configure, what must be set before the first project(), who owns the dependency-provider slot and what a provider never sees, and the find-root modes a cross toolchain must state
---

# Toolchains, Top-Level Includes and Dependency Providers

Owns everything that enters a configure before the first `project()` runs: the
one `CMAKE_TOOLCHAIN_FILE` and how package managers compose into it,
`CMAKE_PROJECT_TOP_LEVEL_INCLUDES` and the dependency-provider slot, the
toolchain file's own hygiene, and the find-root modes of a cross toolchain. It
does not own how `find_package` then picks a copy, the `<Pkg>_DIR` pin, a hint
losing to a rooted copy, or pkg-config in a cross build, which are `CMK-DEP` in
`dependencies.md`. Choosing the package manager of record is `CMK-PKG` in the
separate `cpp-packaging` rule set, which cites `CMK-TC-02` for the ban. The vcpkg
triggers of these rows and the two meanings of `VCPKG_CHAINLOAD_TOOLCHAIN_FILE`
are `CMK-VCPKG` in `cpp-packaging/vcpkg.md`, and Conan's `user_toolchain` over
`toolchain_file` is `CMK-CONAN` in `cpp-packaging/conan.md`. A caller-supplied
toolchain under Bazel's `rules_foreign_cc` has its probe in `CMK-BZL-02`
(`bazel-seam.md`). The configure gate is `CMK-CORE-01` in the index.

Rules assume `cmake_minimum_required(VERSION 3.25...4.4)`. Every measurement
below ran on CMake 3.31.12 and 4.4.2 (4.3.4 where named) on 2026-09-26. Commands
run from the repository root.

Contents: [One Toolchain per Configure Leg](#one-toolchain-per-configure-leg) ·
[What the First project() Reads](#what-the-first-project-reads) ·
[The Provider Slot](#the-provider-slot) ·
[Reading a Toolchain File](#reading-a-toolchain-file) ·
[Find-Root Modes in a Cross Toolchain](#find-root-modes-in-a-cross-toolchain) ·
[What Agents Get Wrong Here](#what-agents-get-wrong-here)

## One Toolchain per Configure Leg

A1 lists every toolchain source for a per-leg read. A2 and A3 go red on their
own. Read the output of A2 and A3, not their exit codes.

```sh
# A1: every toolchain source. Read per leg.
grep -rn --include='CMakePresets.json' --include='CMakeUserPresets.json' --include='*.yml' --include='*.yaml' --include='CMakeLists.txt' -e 'CMAKE_TOOLCHAIN_FILE' -e 'toolchainFile' -e '--toolchain' .
# A2: project code that sets the variable with no guard and no chainload. Empty = pass.
grep -rliE --include='CMakeLists.txt' --include='*.cmake' -e 'set[[:space:]]*\([[:space:]]*CMAKE_TOOLCHAIN_FILE' . | xargs -r grep -L -e 'NOT DEFINED CMAKE_TOOLCHAIN_FILE' -e 'VCPKG_CHAINLOAD_TOOLCHAIN_FILE'
# A3: one file naming both managers' toolchains. Empty = pass.
grep -rl --include='CMakePresets.json' --include='CMakeUserPresets.json' --include='*.yml' --include='*.yaml' --include='*.cmake' -e 'vcpkg.cmake' . | xargs -r grep -l -e 'conan_toolchain.cmake'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TC-01 | Give each configure leg one `CMAKE_TOOLCHAIN_FILE` from one source of record: a preset's `toolchainFile` or `cacheVariables`, `-D` or `--toolchain`, or the environment variable. Project code never sets it, except inside `if(NOT DEFINED CMAKE_TOOLCHAIN_FILE)` or after chainloading the caller's value (for example into `VCPKG_CHAINLOAD_TOOLCHAIN_FILE`). Compose toolchains only through the wrapping claimant's hook: `VCPKG_CHAINLOAD_TOOLCHAIN_FILE`, or Conan's `tools.cmake.cmaketoolchain:user_toolchain`. | The variable holds one path, and the losing file is never read, with no diagnostic. Measured on 3.31.12, 4.3.4 and 4.4.2: a preset's `toolchainFile` beats the same preset's `cacheVariables` entry, and `-D` beats the preset. Measured on 3.31.12 and 4.4.2: an unguarded `set()` before `project()` beats the caller's `-D`. The environment variable applies only when a build tree is first created, so a CI job that reuses the tree ignores it. Floor: any. Preset `toolchainFile`, `--toolchain` and the environment variable need 3.21. | A1: read per leg. More than one distinct value reaching one leg, or a `;` in a value, is the finding. Zero or one per leg is the pass. A2: empty output is the pass. A listed file is the finding. A file that passes still gets a read that the guard encloses the `set()`. The wrapped-build probe is `CMK-BZL-02`'s. | MUST |
| CMK-TC-02 | Never let vcpkg's `vcpkg.cmake` and Conan's `conan_toolchain.cmake` reach one configure, directly or chained through either one's hook. | The slot holds one path, and neither project documents chaining the other's generated file. conan-io/conan#12341 (open as of 2026-09-26) asks Conan to adopt vcpkg's chainload model, not to combine the two managers. No public repository in the measured corpus chains them. Floor: any. Conan 2.x, vcpkg any. | A3: empty output is the pass. A listed file names both toolchains (finding). Managers that meet across files, such as a preset naming one and a CI step passing the other, need the per-leg read of A1's output. | MUST |

How each claimant composes (Conan 2.32.0 and vcpkg 2026.07.29, read
2026-09-26):

| Claimant | Enters through | Takes another toolchain through | Must precede the first `project()` |
|---|---|---|---|
| vcpkg | `CMAKE_TOOLCHAIN_FILE` set to `scripts/buildsystems/vcpkg.cmake` | `VCPKG_CHAINLOAD_TOOLCHAIN_FILE`, included before vcpkg's own re-entry guard, so the chained file runs on every read | the toolchain path and every `VCPKG_*` input |
| Conan 2, explicit flow | `conan install` writes `conan_toolchain.cmake` and presets, then `cmake --preset conan-<config>` | `user_toolchain`, included as the first lines of the generated file | the one toolchain path. `conan install` already ran |
| cmake-conan provider | `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` naming `conan_provider.cmake` | nothing: it never reads or sets `CMAKE_TOOLCHAIN_FILE` | the include list itself |
| Hand-written cross toolchain | `-D`, a preset, or chained by one of the above | being `include()`d, so it must stay idempotent (`CMK-TC-06`) | `CMAKE_SYSTEM_NAME`, `CMAKE_SYSROOT`, the four find-root modes |

## What the First project() Reads

B1 reads the top-level `CMakeLists.txt`. B2 reads every other `CMakeLists.txt`,
all of which run after the first `project()`. Both are case-insensitive, because
`SET(` is legal CMake.

```sh
# B1: a toolchain or vcpkg write after the first project(). Empty = pass.
awk 'tolower($0) ~ /^[[:space:]]*project[[:space:]]*\(/ { seen = 1 } seen && tolower($0) ~ /^[[:space:]]*(set|list)[[:space:]]*\([[:space:]]*(append[[:space:]]+)?(cmake_toolchain_file|vcpkg_)/ { print FILENAME ":" FNR ": " $0 }' CMakeLists.txt
# B2: the same writes below the top level. Empty = pass.
find . -mindepth 2 -name 'CMakeLists.txt' | xargs -r grep -HniE -e 'set[[:space:]]*\([[:space:]]*VCPKG_' -e 'list[[:space:]]*\([[:space:]]*APPEND[[:space:]]+VCPKG_' -e 'set[[:space:]]*\([[:space:]]*CMAKE_TOOLCHAIN_FILE'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TC-03 | Set everything the first `project()` reads before it runs, preferably in the configure preset's `cacheVariables`: `CMAKE_TOOLCHAIN_FILE` (under `CMK-TC-01`'s guard when it is in code), `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` (preset or command line only, `CMK-TC-04`), and every `VCPKG_*` input (triplet, manifest mode and features, overlays, chainload). Give a build tree its toolchain on its first configure: to add or change `CMAKE_TOOLCHAIN_FILE` (a preset's `toolchainFile` included), configure a new tree or pass `--fresh`. Load a toolchain file only as the toolchain, never through `include()` after `project()`. | A later write is a silent no-op. `set(CMAKE_TOOLCHAIN_FILE … CACHE … FORCE)` after `project()` prints the new value while the file is never read (measured on 3.31.12). vcpkg's own docs say every vcpkg-affecting variable must be defined "before the first `project()` directive". A triplet set after it silently resolved the host triplet's package, and the configure exited 0 (measured for `CMK-VCPKG-04` on 3.31.12, 4.3.4 and 4.4.2). A toolchain given to an existing tree is recorded in the cache and never loaded, because `CMakeSystem.cmake` is written once: one `unused-cli` warning, exit 0 under `-Werror=dev` (3.31.12) and `-Werror=author` (4.4.2), silent on every later reconfigure, and `-U <Pkg>_DIR` finds the old copy again (measured 2026-09-26 with vcpkg-tool 2026-07-27). A `conan_toolchain.cmake` loaded by `include()` after `project()` compiled with the profile's clang while `CMAKE_C_COMPILER_ID` stayed `GNU`, exit 0 under the gate (measured 2026-09-26 on Conan 2.32.0 with 3.31.12 and 4.4.2). Floor: any. Preset `cacheVariables` 3.19, `toolchainFile` 3.21. | B1: empty output is the pass. Every printed line is a write after the first `project()` (finding). B2: empty output is the pass, any line is the finding. Reads such as `if(VCPKG_TARGET_TRIPLET MATCHES …)` are not matched. Printing the variable after the write proves nothing. Tree check: `grep -rn --include='CMakeSystem.cmake' -e 'include(' build/CMakeFiles` and `grep -rn --include='CMakeCache.txt' -e '^CMAKE_TOOLCHAIN_FILE:' build`. Empty output from both means not applicable. Empty output from the first while the second prints a line is the finding. Two different files is a finding by reading. For an `include()` of a generated toolchain, `CMK-CONAN-07`'s second grep: empty output = pass. | MUST |

## The Provider Slot

A provider has one real implementation, cmake-conan. vcpkg ships none. Treat it
as one user-owned slot, never as a general hook every manager plugs into.
**Pinned default**: for Conan, the explicit flow (`conan install`, then
`cmake --preset`) is recommended. The provider is legal within `CMK-TC-05`'s
limits. An adopter that standardises on the provider overrides this once,
repository-wide.

```sh
# C1: project or module code writing the include list. Empty = pass.
grep -rniE --include='CMakeLists.txt' --include='*.cmake' -e 'set[[:space:]]*\([[:space:]]*CMAKE_PROJECT_TOP_LEVEL_INCLUDES' -e 'list[[:space:]]*\([[:space:]]*APPEND[[:space:]]+CMAKE_PROJECT_TOP_LEVEL_INCLUDES' .
# C2: every registration. Empty = pass. Read each hit's file.
grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'SET_DEPENDENCY_PROVIDER' .
# C3: the user's own provider must be the one called. MARKER holds the file shown below,
# outside the source tree. Gate per CMK-CORE-01: -Werror=dev serves 3.31 and 4.4 on one
# command line. A 4.4-only leg may use -Werror=author. Count 0 = finding.
MARKER="$HOME/cmake-probes/user-marker.cmake"
mkdir -p logs
cmake -S . -B build-marker --fresh -Werror=dev -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES="$MARKER" > logs/marker.log 2>&1
grep -rc --include='marker.log' -e 'USER_PROVIDER_CALLED' logs
# C4: does any committed preset or CI file load cmake-conan? Empty = CMK-TC-05 not applicable.
grep -rn --include='CMakePresets.json' --include='CMakeUserPresets.json' --include='*.yml' --include='*.yaml' -e 'conan_provider' .
# C5: find_* or add_subdirectory before the first find_package. Empty = pass.
awk 'tolower($0) ~ /^[[:space:]]*find_package[[:space:]]*\(/ { exit } tolower($0) ~ /^[[:space:]]*(find_program|find_library|find_path|add_subdirectory)[[:space:]]*\(/ { print FILENAME ":" FNR ": " $0 }' CMakeLists.txt
# C6: which generator the provider ran, from the saved configure console. Empty = CMakeDeps.
grep -rn --include='*.log' -e 'Loading conan_cmakedeps_paths.cmake' logs
```

```cmake
function(marker_provide method name)
    message(STATUS "USER_PROVIDER_CALLED ${name}")
endfunction()
cmake_language(
    SET_DEPENDENCY_PROVIDER marker_provide
    SUPPORTED_METHODS FIND_PACKAGE
)
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TC-04 | Leave the dependency provider to the user. Call `cmake_language(SET_DEPENDENCY_PROVIDER)` only in a shipped, opt-in file that users list in `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` themselves. Never `set()` or `list(APPEND)` that variable from project or module code, and list at most one provider-registering file per configure. | The `cmake_language` docs (4.4.2) say the choice "should always be under the user's control". Registering from a `CMakeLists.txt` is a hard error, and a second registration silently replaces the first. Measured on 3.31.12 and 4.4.2: a project `set()` before `project()` hides the user's file entirely, and `list(APPEND)` runs the user's file and then displaces its provider. Both configures exit 0 under the gate. Floor: 3.24. Module-name entries 3.29. | C1: empty output is the pass, any line is the finding. C2: empty output is the pass. A hit in a `CMakeLists.txt`, or in a `.cmake` file any project file `include()`s, is the finding. A hit in a provider file the project never includes is the shipped opt-in (pass). C3, when the project calls `find_package`: a count of 0 is the finding, 1 or more is the pass. | MUST |
| CMK-TC-05 | Never design on a provider seeing `find_program`, `find_library` or `find_path`: providers intercept only `find_package` and `FetchContent_MakeAvailable`. With cmake-conan, those three calls see Conan content only under the `CMakeConfigDeps` generator, only after the first intercepted `find_package`, and only in that call's directory scope and the subdirectories added after it. Under `CMakeDeps` they never see it, and `CMAKE_PREFIX_PATH` stays empty under both. Put the first `find_package` of a Conan package in the top-level `CMakeLists.txt`, before any `add_subdirectory`. `cmake_language(DEFER)` runs the call at the end of the directory and is never the fix. **pinned**, see above. | `SUPPORTED_METHODS` is a closed set: `FIND_LIBRARY` is an "Unknown dependency provider method" on 3.31.12 and 4.4.2. cmake-conan includes `conan_cmakedeps_paths.cmake` once, in the first-run branch of its provider macro, and that file sets `CMAKE_PROGRAM_PATH` and `CMAKE_LIBRARY_PATH` in the calling directory's scope. Measured with Conan 2.32.0 and cmake-conan `develop2` on 4.4.2: with the first `find_package` in a subdirectory, a top-level `find_program` stays NOTFOUND even after its own later `find_package`. Not demonstrated: multi-config generators and build-context `tool_requires` binaries. Floor: providers 3.24. cmake-conan needs Conan 2.0.5. | C4 decides applicability. C5: empty output is the pass. A printed line before the first `find_package` is the finding, and a `DEFER`-ed call does not clear it. C6: empty output means `CMakeDeps` or no provider run, so any `find_program`, `find_library` or `find_path` that expects a Conan package's files is the finding. `CMakeConfigureLog.yaml` never carries this line. | MUST |

## Reading a Toolchain File

The name glob misses toolchains with other names. Repeat D1 for each file that a
`VCPKG_CHAINLOAD_TOOLCHAIN_FILE` value or a `user_toolchain` entry names, binding
its name first: `NAME=aarch64.cmake; grep -rniE --include="$NAME" -e 'execute_process' -e 'message[[:space:]]*\(FATAL_ERROR' -e 'project[[:space:]]*\(' -e 'enable_language' .`. Empty output = pass.

```sh
# D1: project-level commands in a toolchain file. Empty = pass.
grep -rniE --include='*toolchain*.cmake' -e 'execute_process' -e 'message[[:space:]]*\(FATAL_ERROR' -e 'project[[:space:]]*\(' -e 'enable_language' .
# D2: emulator use. Empty = pass.
grep -rn --include='*.cmake' --include='CMakeLists.txt' -e 'CROSSCOMPILING_EMULATOR' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TC-06 | Keep a toolchain file that a manager may chainload idempotent and free of project-level commands: no `project()`, `enable_language()`, unguarded `execute_process()` or `message(FATAL_ERROR)`. | The file is re-read inside every `try_compile`. Measured on 3.31.12 and 4.4.2: a `LANGUAGES C` configure reads it 2 + L + N times, where L is the compiled languages (measured for C only) and N the `try_compile` calls of either signature, each `check_*` macro included. vcpkg's early return does not protect a chained file, which runs on every read. A `project()` in a chained file is a hard "Recursive call not allowed" error and reports itself. `execute_process` and file writes do not. Floor: any. CMP0137 (3.24) only governs which platform variables reach a project-mode `try_compile`. | D1: empty output is the pass. A hit outside a first-run guard is the finding. Count reads with a `file(APPEND)` sink, never `message()`, whose nested output `try_compile` captures. | SHOULD |
| CMK-TC-07 | In a cross build, get code generators for the build host, and run target binaries only through `CMAKE_CROSSCOMPILING_EMULATOR`. Host tools come from vcpkg `"host": true`, a Conan `tool_requires` in the build context, or `find_program(… NO_CMAKE_FIND_ROOT_PATH)`. The emulator wraps only a command that names an executable target, so never expect `set_tests_properties(… CROSSCOMPILING_EMULATOR …)` to wrap a script path. | Measured on 3.31.12, 4.3.4 and 4.4.2: with the `PROGRAM` mode unset, a plain `find_program` returns the sysroot's binary over a host copy earlier on `PATH`. `NO_CMAKE_FIND_ROOT_PATH` returns the host copy. `CROSSCOMPILING_EMULATOR` is a target property baked in at generate time, and the same name on a test is accepted and never acted on. The vcpkg and Conan host-context semantics are read from their docs, not measured. Floor: emulator 3.3, list form 3.15. | Reading heuristic. A generator found by a plain `find_program` while the `PROGRAM` mode is unset, `ONLY` or `BOTH` (a Conan cross build counts) is the finding, and so is a manifest dependency run at build time without `"host": true`. D2: empty output is the pass. A `set_tests_properties` hit whose `add_test` names a literal path instead of a target is the finding. | SHOULD |

## Find-Root Modes in a Cross Toolchain

Run on the source tree. The excludes keep a generated `conan_toolchain.cmake` out
of E1 to E6, where it is expected to match (`CMK-TC-10`). Read the output of the
`xargs` pipelines, not their exit codes.

```sh
# E1-E4: a cross toolchain that leaves a mode unset. Empty = pass for each.
grep -rliE --include='*.cmake' --exclude='conan_toolchain.cmake' -e 'set[[:space:]]*\([[:space:]]*CMAKE_SYSROOT' -e 'set[[:space:]]*\([[:space:]]*CMAKE_SYSTEM_NAME' . | xargs -r grep -L -e 'CMAKE_FIND_ROOT_PATH_MODE_LIBRARY'
grep -rliE --include='*.cmake' --exclude='conan_toolchain.cmake' -e 'set[[:space:]]*\([[:space:]]*CMAKE_SYSROOT' -e 'set[[:space:]]*\([[:space:]]*CMAKE_SYSTEM_NAME' . | xargs -r grep -L -e 'CMAKE_FIND_ROOT_PATH_MODE_INCLUDE'
grep -rliE --include='*.cmake' --exclude='conan_toolchain.cmake' -e 'set[[:space:]]*\([[:space:]]*CMAKE_SYSROOT' -e 'set[[:space:]]*\([[:space:]]*CMAKE_SYSTEM_NAME' . | xargs -r grep -L -e 'CMAKE_FIND_ROOT_PATH_MODE_PACKAGE'
grep -rliE --include='*.cmake' --exclude='conan_toolchain.cmake' -e 'set[[:space:]]*\([[:space:]]*CMAKE_SYSROOT' -e 'set[[:space:]]*\([[:space:]]*CMAKE_SYSTEM_NAME' . | xargs -r grep -L -e 'CMAKE_FIND_ROOT_PATH_MODE_PROGRAM'
# E5: a library, include or package mode set to anything but ONLY. Empty = pass.
grep -rnE --include='*.cmake' --exclude='conan_toolchain.cmake' -e 'MODE_LIBRARY[[:space:]"]+BOTH' -e 'MODE_LIBRARY[[:space:]"]+NEVER' -e 'MODE_INCLUDE[[:space:]"]+BOTH' -e 'MODE_INCLUDE[[:space:]"]+NEVER' -e 'MODE_PACKAGE[[:space:]"]+BOTH' -e 'MODE_PACKAGE[[:space:]"]+NEVER' .
# E6: the program mode set to ONLY or BOTH. Empty = pass.
grep -rnE --include='*.cmake' --exclude='conan_toolchain.cmake' -e 'MODE_PROGRAM[[:space:]"]+ONLY' -e 'MODE_PROGRAM[[:space:]"]+BOTH' .
# E7: a Conan cross build in the build tree. Empty = CMK-TC-10 not applicable.
grep -rn --include='conan_toolchain.cmake' -e 'CMAKE_FIND_ROOT_PATH_MODE_PACKAGE "BOTH"' build
# E8: a sysroot toolchain that never names the multiarch triplet. Empty = pass.
grep -rliE --include='*.cmake' --exclude='conan_toolchain.cmake' -e 'set[[:space:]]*\([[:space:]]*CMAKE_SYSROOT' . | xargs -r grep -L -e 'CMAKE_LIBRARY_ARCHITECTURE'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TC-08 | A project-owned cross toolchain sets `CMAKE_FIND_ROOT_PATH_MODE_LIBRARY`, `_INCLUDE` and `_PACKAGE` to `ONLY` explicitly. Never rely on the unset default. | Unset, all three behave as `BOTH` outside the Android and Apple-device platforms named in the Verification: rooted paths first, then the host's (`find_package` docs, 4.4.2). Measured on 3.31.12, 4.3.4 and 4.4.2: a toolchain that sets only `CMAKE_SYSTEM_NAME` and `CMAKE_SYSROOT` finds a package that exists only on the host, and the cross build links it. `NEVER` is worse and prefers the host copy even when the sysroot has one. The `ONLY` lines everyone copies come from the `cmake-toolchains(7)` example, not from the defaults. `ONLY` keeps vcpkg working, because vcpkg adds its installed tree to `CMAKE_FIND_ROOT_PATH`. Floor: any. | E1, E2, E3: empty output is the pass for each, and a listed file is the finding. A listed file that sets `CMAKE_SYSTEM_NAME Android` with a `CMAKE_SYSTEM_VERSION` other than 1 passes E1 to E4 when the NDK has the unified `toolchains/llvm/prebuilt/<host>/sysroot`, because CMake's `Platform/Android-Initialize.cmake` then sets the four modes to `NEVER`, `ONLY`, `ONLY`, `ONLY` when they are undefined. Measured 2026-09-26 on 3.31.12 and 4.4.2 with a stub NDK: all four printed, and all four were empty with the unified sysroot removed and for a `Linux` toolchain. KDE/extra-cmake-modules' `toolchain/Android.cmake` at `b4c4ec99` is this case. `iOS`, `tvOS`, `visionOS` and `watchOS` get the three `ONLY` modes from `Platform/Darwin.cmake` (read at 4.4.2, not run), so they pass E1 to E3. E5: empty output is the pass, any line is the finding. | MUST |
| CMK-TC-09 | Set `CMAKE_FIND_ROOT_PATH_MODE_PROGRAM` to `NEVER` explicitly in a project-owned toolchain. Never set it to `ONLY`, and never leave it unset. Reach a target-side tool through an explicit path or a per-call `ONLY_CMAKE_FIND_ROOT_PATH`. | Unset behaves as `BOTH`, not `NEVER`: with the same program in the sysroot and on the host `PATH`, unset and `BOTH` return the sysroot's target-arch binary. `ONLY` hides every host generator and also sandboxes CMake's own build-program search, so a Makefiles configure without `CMAKE_MAKE_PROGRAM` fails with "CMake was unable to find a build program". Both measured on 3.31.12, 4.3.4 and 4.4.2. A target binary run at build time usually fails loudly with an exec-format error, which is why the unset and `BOTH` half is SHOULD. Floor: any. | E6: empty output is the pass. An `ONLY` line is the MUST finding, a `BOTH` line the SHOULD finding. E4: empty output is the pass, and a listed file (mode unset) is the SHOULD finding, except the Android case CMK-TC-08 names. | MUST (`ONLY`) / SHOULD (`BOTH` or unset) |
| CMK-TC-10 | In a Conan 2 cross build, assume every `CMAKE_FIND_ROOT_PATH_MODE_*` is `BOTH`. Pin each Conan-supplied package's `<Pkg>_DIR` (`CMK-DEP-21`), or show that the sysroot holds no same-named package config. | Conan 2.32.0's `CMakeToolchain` `FindFiles` block rewrites an unset or `ONLY` mode to `BOTH` whenever it cross-builds, and never sets `CMAKE_FIND_ROOT_PATH`. Its explicit `ONLY` branch overrides a `user_toolchain`'s value, so `CMK-TC-08` does not survive under Conan (read in source at 2.32.0, not measured). Measured on 4.4.2 with a real Conan 2.32.0 cross profile: a config under `<sysroot>/usr/lib/cmake` beat both a `_ROOT` hint and Conan's generators folder, with no warning. Conan has no setting that keeps `ONLY`. Floor: Conan 2.x. | E7 decides applicability. With a hit, bind the host profile's sysroot and each Conan-supplied package name, then `SYSROOT=/opt/sysroots/aarch64; NAME=libfoo; find "$SYSROOT/usr" -ipath '*cmake*' -iname "${NAME}*config.cmake"`. Empty output is the pass. A listed file without a `<Pkg>_DIR` pin is the finding. `--debug-find-pkg=libfoo` shows the path that won. | SHOULD |
| CMK-TC-11 | A project-owned cross toolchain whose sysroot has a multiarch `usr/lib/<triplet>` directory sets `CMAKE_LIBRARY_ARCHITECTURE` to that triplet. | CMake searches `lib/<triplet>` under a prefix only when `CMAKE_LIBRARY_ARCHITECTURE` is set, and a compiler that reports no implicit link directories leaves it empty (zig cc 0.16.0-dev writes `set(CMAKE_C_LIBRARY_ARCHITECTURE "")` to `CMakeCCompiler.cmake`). Measured 2026-09-26 on 3.31.12, 4.3.4 and 4.4.2 with expat 2.8.5 in a Debian-multiarch sysroot: under `BOTH` the host copy on `CMAKE_PREFIX_PATH` won and the link failed with "incompatible with aarch64linux", CMK-TC-08's `ONLY` modes alone gave "Could not find" for Config and Find-module consumers, and adding the triplet found the sysroot copy. Not measured with a GNU cross compiler, which may detect the triplet itself. Floor: any. | E8: empty output is the pass. A listed file is the finding when `SYSROOT=/opt/sysroots/aarch64; find "$SYSROOT/usr/lib" -maxdepth 1 -type d -name '*-linux-gnu*'` prints a directory, and empty `find` output means not applicable. | SHOULD |

```cmake
# wrong: every mode behaves as BOTH, so host packages and programs leak in
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSROOT /opt/sysroots/aarch64)

# right: state all four modes after the two lines above
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
```

## What Agents Get Wrong Here

1. **Setting `CMAKE_TOOLCHAIN_FILE` or a `VCPKG_*` input after `project()`, then
   "verifying" by printing it.** The print shows the new value while nothing
   reads it. B1 and B2 are the check (`CMK-TC-03`).
2. **Registering a provider from `CMakeLists.txt`, or appending
   `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` "for convenience".** Both configure green
   and take the slot from the user. C1 and the C3 marker probe (`CMK-TC-04`).
3. **Describing providers as a hook every package manager plugs into, or
   assuming a provider widens search paths like a toolchain.** One real
   implementation exists and vcpkg has none. `find_program` is not a provider
   method, and `DEFER` makes a call run later, never earlier (`CMK-TC-05`).
4. **Setting two toolchain files, or a `;`-list, "one per manager".** One path
   is read and the other is dropped in silence (`CMK-TC-01`, `CMK-TC-02`).
5. **"The cross toolchain is sandboxed by default."** All four modes default to
   `BOTH`, `PROGRAM` included. E1 to E4 (`CMK-TC-08`, `CMK-TC-09`).
6. **Expecting an `ONLY` in a `user_toolchain`, or a `_ROOT` hint, to beat the
   sysroot's copy under Conan.** Conan forces `BOTH`. Pin `<Pkg>_DIR` and read
   `--debug-find-pkg` (`CMK-TC-10`).
7. **Counting toolchain reads from `message()` output, or assuming a `check_*`
   macro does not re-read the toolchain.** Use a `file(APPEND)` sink (`CMK-TC-06`).
8. **Setting `CROSSCOMPILING_EMULATOR` on a test that runs a script.** It is
   accepted and inert (`CMK-TC-07`).

Re-check: D1 (CMake 4.5 and the `-Werror=dev` spelling in C3), D2 (the
`CMakeConfigDeps` recommendation, which decides what `CMK-TC-05` users meet), D4
(Conan 2.32.0, cmake-conan `develop2`, the vcpkg tag, and the open states of
conan-io/conan#12341 and microsoft/vcpkg#36244).
