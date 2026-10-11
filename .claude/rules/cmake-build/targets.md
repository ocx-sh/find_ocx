---
title: Targets, Linkage and ABI
summary: The CMK-TGT family, which owns every target a CMake project defines, covering link keywords, global flags, the guarded standard, runtime and build-type defaults, library type and PIC, symbol visibility, and C++20 module scanning
---

# Targets, Linkage and ABI

Owns what a target is and what it passes on: the keyword on every link, where a flag lives, which defaults a project may
write and under which guard, whether a library is static, shared or position-independent, which symbols it exports, and
when C++20 scanning switches on. It does not own installing or exporting a target, which is `CMK-INST` in
`install-and-export.md`, nor the policy knobs around a sub-built dependency (`CMAKE_POLICY_DEFAULT_CMP0077`, the policy
version minimum), which are `CMK-DEP` in `dependencies.md`. Setting a policy `OLD` and the experimental-gate UUIDs are
`CMK-VER` in `versions-and-policies.md`. Flags a toolchain file seeds are `CMK-TC` in `toolchains-and-providers.md`. The
Conan profile and vcpkg triplet sides of the standard and runtime are `CMK-CONAN` and `CMK-VCPKG` in the `cpp-packaging`
rule. Modules and sanitizers under Bazel are `BZL-CC-27` and `BZL-CC-18` in `bazel-quality`.

**Pinned floor**, a default the adopter overrides once: every snippet reads
`cmake_minimum_required(VERSION 3.25...4.4)`, and any newer mechanism carries its `(CMake ≥ X.Y)` gate. Rows were measured on CMake 3.31.12 and 4.4.2 on
2026-09-26 unless the row says otherwise. Commands run from the project root with the build tree in `build`. Configure
probes pass `-Werror=dev`, the one spelling that serves both lines (on 4.4 alone, `-Werror=author`).

Contents: [Link Keywords, Aliases and Directory Scope](#link-keywords-aliases-and-directory-scope) · [Global Flags, Warnings and Sanitizers](#global-flags-warnings-and-sanitizers) · [Guarded Defaults: Standard, Runtime, Build Type](#guarded-defaults-standard-runtime-build-type) ·
[Library Type and PIC](#library-type-and-pic) · [Symbols, Link Items and Embedded Paths](#symbols-link-items-and-embedded-paths) · [C++20 Modules and Scanning](#c20-modules-and-scanning) · [What Agents Get Wrong Here](#what-agents-get-wrong-here)

## Link Keywords, Aliases and Directory Scope

Scope: a library's own non-test CMake files. Line (1) prints single-line calls
whose second token is not a keyword. Line (2) is the read for calls that wrap.

```sh
# (1) CMK-TGT-01. Empty output = pass. Each line printed is a finding.
grep -rnE --include='CMakeLists.txt' --include='*.cmake' -e 'target_link_libraries[[:space:]]*[(][[:space:]]*[^[:space:])]+[[:space:]]+[^[:space:])]' . | grep -vE -e 'target_link_libraries[[:space:]]*[(][[:space:]]*[^[:space:])]+[[:space:]]+(PUBLIC|PRIVATE|INTERFACE)([[:space:]]|[)]|$)'
# (2) CMK-TGT-01, calls split across lines. Read the first token after the target.
grep -rn -A2 --include='CMakeLists.txt' --include='*.cmake' -e 'target_link_libraries[[:space:]]*(' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TGT-01 | In every `target_link_libraries` call, name `PUBLIC`, `PRIVATE` or `INTERFACE`. Default to `PRIVATE` unless the dependency's types appear in the library's installed headers. | The plain signature is "transitive by default" (`target_link_libraries` doc at 4.4.2), so every private dependency lands in the exported `INTERFACE_LINK_LIBRARIES` and then needs a `find_dependency` (CMK-INST-03). CMake accepts the bare form silently. | Gate lines (1) and (2). Measured red on a planted `target_link_libraries(core m)` and green on keyworded single-line and wrapped calls. | MUST for library targets, SHOULD for test and example targets. Floor: 2.8.12 |
| CMK-TGT-02 | Give every installable library target a namespaced `ALIAS` matching its exported name (`add_library(Pkg::lib ALIAS lib)`) and link through the alias inside the build. | Build-tree consumers (`add_subdirectory`, FetchContent) then spell the name install-tree consumers spell, and CMP0028 turns a typo into an error instead of a bare `-llib`. | Reading heuristic: each `NAMESPACE X::` in an `install(EXPORT)` has a matching `add_library(X::… ALIAS …)`. | SHOULD. Floor: any |
| CMK-TGT-03 | In a library you author or modernise, use the `target_*` command instead of `include_directories`, `add_definitions`, `add_compile_definitions`, `add_compile_options`, `link_directories` or `link_libraries`. A compile definition that an installed header reads is `PUBLIC` on the library target, or baked into a configured installed header, and never `PRIVATE` or directory-scoped. In an untouched legacy tree, flag them and never auto-rewrite. | Directory scope leaks into sibling targets and into code pulled in with `add_subdirectory`. It never reaches install-tree consumers, because only `INTERFACE_*` properties export. On open-source-parsers/jsoncpp at `3347a4b8` with `-DJSONCPP_USE_SECURE_MEMORY=ON`, both the `PRIVATE` form and upstream's directory-scoped form fail with `undefined symbol: Json::Value::operator[]`, and `PUBLIC` exits 0 (measured 2026-09-26 on 3.31.12 and 4.4.2). | `grep -rnE --include='CMakeLists.txt' --include='*.cmake' -e '^[[:space:]]*include_directories\(' -e '^[[:space:]]*add_definitions\(' -e '^[[:space:]]*add_compile_definitions\(' -e '^[[:space:]]*add_compile_options\(' -e '^[[:space:]]*link_directories\(' -e '^[[:space:]]*link_libraries\(' .` Empty output = pass. Per definition, with `NAME=JSONCPP_USE_SECURE_MEMORY` as the example and the installed include directory as the operand, `grep -rn -e "$NAME" include`: empty output = `PRIVATE` is right, a line = `PUBLIC`. Then run the round trip once with each option that adds such a definition switched on. | MUST (a definition an installed header reads), SHOULD (the rest). Floor: any |
| CMK-TGT-21 | A library others consume never builds its usage requirements (include directories, interface sources) or its generated files and output directories on `CMAKE_SOURCE_DIR` or `CMAKE_BINARY_DIR`. Use `CMAKE_CURRENT_SOURCE_DIR`, `CMAKE_CURRENT_BINARY_DIR` or `PROJECT_*`. | Under `add_subdirectory` or FetchContent, both variables name the parent's roots. The round trip reads only `INSTALL_INTERFACE`, so it passes. c42f/tinyformat with `$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}>` configures with exit 0 and fails a compiled subproject consumer with `'tinyformat.h' file not found`, and its `file(WRITE ${CMAKE_BINARY_DIR}/_empty.cpp)` lands in the parent's build root (measured 2026-09-26 on 3.31.12 and 4.4.2). | `grep -rnE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' -e 'CMAKE_SOURCE_DIR' -e 'CMAKE_BINARY_DIR' .` Empty output = pass. The output is a list to read: a hit outside a top-level-only guard on a consumable target is the finding. The decisive check is a compiled consumer through `add_subdirectory` (the cmake-modernize smoke's third pass), where exit 0 = pass. | MUST (usage requirements), SHOULD (generated files and output directories). Floor: any |
| CMK-TGT-08 | List target sources explicitly. `file(GLOB)` or `GLOB_RECURSE` feeding `add_library`, `add_executable` or `target_sources` is a finding, and `CONFIGURE_DEPENDS` mitigates it without fixing it. | A new file is missed until someone reconfigures. `file.rst` at 4.4.2: "We do not recommend using GLOB to collect a list of source files", and `CONFIGURE_DEPENDS` "may not work reliably on all generators". | `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'file(GLOB' .` Empty output = pass. Read each hit: one that feeds a target is the finding. | SHOULD. Floor: `CONFIGURE_DEPENDS` 3.12 |

## Global Flags, Warnings and Sanitizers

Line (1) is the MUST half of CMK-TGT-04 and prints only overwrites. Line (2)
prints appends, the SHOULD half. `-i` catches `SET(`, and a `*_FLAGS_INIT` in a
toolchain file is the correct channel, so both lines drop it. Both also drop
`CMAKE_REQUIRED_FLAGS`, a `check_*` probe input that is set and restored around
one check. A value that reads any `CMAKE_*_FLAGS` variable, wherever it sits,
moves from (1) to (2), so a prefix such as `"-Wl,--as-needed ${CMAKE_SHARED_LINKER_FLAGS}"`
is an append. A line in (2) whose value reads a different variable than it sets
(`set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS} -O3")`) is still an overwrite.
A line in (1) whose whole value is a variable the same file saved from that
same flags variable earlier is a restore: find the save with `grep -n` on the
name it reads. abseil/abseil-cpp at `583556e9` saves `CMAKE_CXX_FLAGS` at
`CMake/Googletest/DownloadGTest.cmake:11` and restores it at `:33`, and a
restore keeps the `_INIT` seed on the compile line, so it passes on read
(measured 2026-09-26 on 3.31.12 and 4.4.2).
On ccache/ccache at `b471bbde`, KDE/extra-cmake-modules at `b4c4ec99` and
catchorg/Catch2 at `222e2339`, the earlier line (1) printed 10 probe setups and
9 prefix appends. These lines print none of them in (1), keep ccache's two `_CI`
definitions (read in the row), and keep planted overwrites red (measured 2026-09-26).

```sh
# (1) CMK-TGT-04 overwrite. Empty output = pass. Each line printed is a finding unless it is a restore.
grep -rniE --include='CMakeLists.txt' --include='*.cmake' -e 'set[[:space:]]*[(][[:space:]]*CMAKE_[A-Z]+_(LINKER_)?FLAGS(_[A-Z]+)?([[:space:]]|[)]|$)' . | grep -viE -e 'FLAGS_INIT' -e '[(][[:space:]]*CMAKE_REQUIRED_FLAGS' -e '[$][{]CMAKE_[A-Z]+_(LINKER_)?FLAGS(_[A-Z]+)?[}]'
# (2) CMK-TGT-04 append. Empty output = pass. Each line printed is a SHOULD finding.
grep -rniE --include='CMakeLists.txt' --include='*.cmake' -e 'string[[:space:]]*[(][[:space:]]*APPEND[[:space:]]+CMAKE_[A-Z]+_(LINKER_)?FLAGS' -e 'set[[:space:]]*[(][[:space:]]*CMAKE_[A-Z]+_(LINKER_)?FLAGS(_[A-Z]+)?[[:space:]].*[$][{]CMAKE_[A-Z]+_(LINKER_)?FLAGS' . | grep -viE -e '[(][[:space:]]*(APPEND[[:space:]]+)?CMAKE_REQUIRED_FLAGS' -e '[(][[:space:]]*(APPEND[[:space:]]+)?CMAKE_[A-Z]+_(LINKER_)?FLAGS_INIT'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TGT-04 | Never overwrite `CMAKE_<LANG>_FLAGS`, `CMAKE_<LANG>_FLAGS_<CONFIG>` or `CMAKE_<KIND>_LINKER_FLAGS` (`EXE`, `SHARED`, `STATIC`, `MODULE`) in project code. Do not append to them either. Put flags on targets with `target_compile_options`, and global flags in a toolchain file, a preset or a manager profile. | An overwrite drops the toolchain's `_INIT` value, including an injected `-fPIC`, and the shared link fails with `recompile with -fPIC` (measured). An append survives but still leaks into every subdirectory and fetched dependency. | Gate line (1) for the overwrite, measured red on `set(CMAKE_C_FLAGS "-O2")` and `SET(CMAKE_SHARED_LINKER_FLAGS …)`, green on `target_compile_options` and `_INIT`. Gate line (2) for the append. A `set(` whose value continues on the next line prints in (1): read it. A hit that defines `_<CONFIG>` flags for a configuration the project adds itself (`CMAKE_C_FLAGS_CI`) drops no `_INIT` value. Without `FORCE` it passes. With `CACHE … FORCE` it is a SHOULD finding, because it replaces the user's `-DCMAKE_C_FLAGS_CI=…` on every configure (measured 2026-09-26 on 3.31.12 and 4.4.2). | MUST (overwrite), SHOULD (append). Floor: any |
| CMK-TGT-09 | Never put an unconditional literal `-Werror` or `/WX` in an installable library. Warnings-as-errors comes from `CMAKE_COMPILE_WARNING_AS_ERROR` in a preset or CI, or from a developer option that defaults `OFF`. | `cmake --compile-no-warning-as-error` lets a packager switch the property off, but it cannot remove a literal flag, so the next compiler's new warning breaks every consumer's build (measured: property build exit 0, literal build exit 2). | `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e '-Werror' -e '/WX' .` Empty output = pass. A hit outside a default-`OFF` option is the finding. Report `-Werror=` with a category separately. | MUST. Floor: 3.24 |
| CMK-TGT-20 | Select sanitizers with cache options, apply each one as both `target_compile_options` and `target_link_options` on an `INTERFACE` options target, and let each CI leg pick its combination in a preset. On Windows, pair clang sanitizers with a non-debug runtime and standalone UBSan with a static one. | A compile-only `-fsanitize=` fails at link time, and one in the global flags reaches every dependency. The Windows runtime pairings are codified by the two maintained sanitizer modules (aminya/project_options, cpp-best-practices/cmake_template), read-only on Windows. | `grep -rn --include='CMakeLists.txt' --include='*.cmake' --include='CMakePresets.json' -e '-fsanitize=' .` Empty output = nothing to check. A hit in `CMAKE_*_FLAGS` or `add_compile_options` is a finding (CMK-TGT-04, CMK-TGT-03), and so is a compile hit with no matching link option. | CONSIDER. Floor: `target_link_options` 3.13 |

## Guarded Defaults: Standard, Runtime, Build Type

A manager toolchain writes these variables during `project()`. Conan 2.32.0's
`CppStdBlock` and `VSRuntimeBlock` do so with a plain `set()`, so a project's
own later unguarded `set()` silently wins over the profile. `guard_scan`
prints every setter that no enclosing `if()` guards. Empty output = pass.

```sh
guard_scan() { # $1 setter ERE, $2 guard ERE, both lower-case
  grep -rliE --include='CMakeLists.txt' --include='*.cmake' -e "$1" . | xargs -r awk -v s="$1" -v g="$2" '
    FNR == 1 { n = 0 }
    { l = tolower($0) }
    l ~ /^[[:space:]]*if[[:space:]]*[(]/ { n++; ok[n] = (l ~ g) }
    l ~ /^[[:space:]]*endif[[:space:]]*[(]/ { if (n) n-- }
    l ~ s { c = 0; for (i = 1; i <= n; i++) if (ok[i]) c = 1; if (!c) print FILENAME ":" FNR ": " $0 }'
}
# (1) CMK-TGT-05, -06, -07
guard_scan 'set[[:space:]]*[(][[:space:]]*cmake_c_(standard|standard_required|extensions)[[:space:])]' 'not[[:space:]]+(defined[[:space:]]+)?cmake_c_standard[[:space:]]*([)]|and[[:space:]]|$)'
guard_scan 'set[[:space:]]*[(][[:space:]]*cmake_cxx_(standard|standard_required|extensions)[[:space:])]' 'not[[:space:]]+(defined[[:space:]]+)?cmake_cxx_standard[[:space:]]*([)]|and[[:space:]]|$)'
# (2) CMK-TGT-06 pairing. Each file listed is a finding.
grep -rlE --include='CMakeLists.txt' --include='*.cmake' -e 'set[[:space:]]*\(CMAKE_CXX_STANDARD[[:space:]]' . | xargs -r grep -L -e 'CMAKE_CXX_STANDARD_REQUIRED'
# (3) CMK-TGT-16, the variable and then the flags
guard_scan 'set[[:space:]]*[(][[:space:]]*cmake_msvc_runtime_library[[:space:])]' 'not[[:space:]]+defined[[:space:]]+cmake_msvc_runtime_library'
grep -rnE --include='CMakeLists.txt' --include='*.cmake' -e '[/-]M[TD]d?([^A-Za-z]|$)' .
# (4) CMK-TGT-17, the top-level guard and then a CACHE default without FORCE
guard_scan 'set[[:space:]]*[(][[:space:]]*cmake_build_type[[:space:])]' '_is_top_level'
grep -rniE --include='CMakeLists.txt' --include='*.cmake' -e 'set[[:space:]]*[(][[:space:]]*CMAKE_BUILD_TYPE[^)]*CACHE' . | grep -vi -e 'FORCE'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TGT-05 | State an installable library's minimum standard as `target_compile_features(<t> PUBLIC cxx_std_NN)`. Set `CMAKE_<LANG>_STANDARD` (`CMAKE_C_STANDARD` as `CMAKE_CXX_STANDARD`) only inside `if(NOT DEFINED CMAKE_<LANG>_STANDARD)`. `if(NOT CMAKE_<LANG>_STANDARD)` is the same guard. A `CACHE` default without `FORCE` counts as one only at a policy version of 3.21 or later (CMP0126 `NEW`). `PROJECT_IS_TOP_LEVEL` may be added with `AND` and never replaces the guard. When converting an explicit `-std=` flag, in C as in C++, also set the target's `<LANG>_STANDARD` to that level inside `if(NOT DEFINED CMAKE_<LANG>_STANDARD)` (with `<LANG>_EXTENSIONS ON` for a `gnu` spelling). The compile feature is a floor and adds no flag when the compiler's default is newer. | The compile feature exports and propagates, the variable does not. An `if(PROJECT_IS_TOP_LEVEL)` set after `project()` overrides the Conan profile in exactly the top-level consumer, with one STATUS line as the only trace (Conan 2.7.0 and later, silent on 2.6.0). gcc 15.2.1 defaults to C 23: `c_std_99` alone emits no `-std`, while `C_STANDARD 99` emits `-std=gnu99`. Set outside the guard, the property also overrides a consumer's `-DCMAKE_C_STANDARD=11`. Inside it the consumer's 11 wins and the feature raises a 90 to 99 (measured 2026-09-26 on 3.31.12 and 4.4.2). | Gate line (1). Empty output = pass. Measured red on an unguarded and a `PROJECT_IS_TOP_LEVEL`-only setter and on a C setter guarded by `CMAKE_CXX_STANDARD`, green inside the `NOT DEFINED` guard (cmark 0.30.3, 3.31.12 and 4.4.2: unguarded `set(CMAKE_C_STANDARD 99)` builds `-std=c99` against a consumer's `-DCMAKE_C_STANDARD=11`). Green inside `if(NOT CMAKE_CXX_STANDARD)` (CTK a5c2e4d1 keeps a consumer's `-DCMAKE_CXX_STANDARD=14`), red on `if(NOT CMAKE_CXX_STANDARD VERSION_GREATER_EQUAL 17)`, which turns that 14 into 17. A hit on a `CACHE` setter without `FORCE` passes on reading when the tree's policy version (the `<max>` of a `cmake_minimum_required` range, else its `<min>`) is 3.21 or later, or `cmake_policy(SET CMP0126 NEW)` precedes it. Below that it is a finding: under libgit2 0551dfd4's `VERSION 3.5.1`, its `set(CMAKE_C_STANDARD "90" CACHE STRING …)` replaces a toolchain file's `set(CMAKE_C_STANDARD 11)` with 90, and under `3.25...4.4` the 11 survives. A consumer's `-D` survives both (measured 2026-09-26 on 3.31.12 and 4.4.2). For a converted `-std=` flag, configure with `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`, then `grep -rho --include='compile_commands.json' -e '-std=[a-z0-9+]*' build` prints the same token before and after the diff. Empty after a non-empty before = finding. | MUST. Floor: `cxx_std_17` 3.8, `cxx_std_20` 3.12, `cxx_std_23` 3.20, `cxx_std_26` 3.30 (gate it under the 3.25 floor), `c_std_99` 3.8, `C_STANDARD` 3.1 |
| CMK-TGT-06 | Wherever `CMAKE_CXX_STANDARD` is set (a top level, a preset), also set `CMAKE_CXX_STANDARD_REQUIRED ON`, inside the same `NOT DEFINED` guard. | Without it the standard "may 'decay' to a previous standard" (`CXX_STANDARD_REQUIRED` doc at 4.4.2), and the compile succeeds at the wrong level. Conan's `CppStdBlock` writes the variable too. | Gate lines (1) and (2). Empty output from both = pass. `[[:space:]]*` admits `set (CMAKE_CXX_STANDARD …)`. | MUST. Floor: 3.1 |
| CMK-TGT-07 | Set `CMAKE_CXX_EXTENSIONS OFF` inside the same guard. The variable is `CMAKE_CXX_EXTENSIONS`, and `CMAKE_CXX_STANDARD_EXTENSIONS` does not exist. | Extensions default to `ON` (`-std=gnu++NN`). Conan sets them from the profile and watches only the standard, so an unguarded later set flips them with no message (measured). A wrong name is a silent no-op. | Gate line (1). Then `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'CMAKE_CXX_STANDARD_EXTENSIONS' .` Empty output = pass. | SHOULD. Floor: 3.1 |
| CMK-TGT-16 | Choose the MSVC runtime only through `CMAKE_MSVC_RUNTIME_LIBRARY` or the `MSVC_RUNTIME_LIBRARY` property, never with `/MD`, `/MT`, `-MD` or `-MT` flags. Put the value in a preset's `cacheVariables`, before the first `project()`, inside `if(NOT DEFINED CMAKE_MSVC_RUNTIME_LIBRARY)`, or behind a default-`OFF` option. Never let a `set()` run by default after `project()`. On a static-CRT vcpkg leg, `CMK-VCPKG-06` narrows the placements to the first two. | Conan's `VSRuntimeBlock` sets the variable with no watch, so a later `set()` overrides `compiler.runtime` with no message at all, and the link fails with LNK2038. vcpkg never sets it, so a static triplet needs the project to (CMK-VCPKG-06). Read-only on Windows, grounded on Conan's source and CMake's docs. | Gate line (3). Empty output = pass. A variable hit above the top-level `project()` or behind a default-`OFF` option passes on reading. A flag hit is a finding. Ignore GCC depfile flags (`-MD -MT` with a target). | MUST, **pinned** (owner default: kept MUST without a Windows measurement). Floor: 3.15 (CMP0091) |
| CMK-TGT-17 | Only the top-level project defaults `CMAKE_BUILD_TYPE`, and only on a single-config generator tested with `GENERATOR_IS_MULTI_CONFIG`. A library never writes it. After `project()` the default needs `FORCE`: `get_property(_is_multi GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)`, then `if(PROJECT_IS_TOP_LEVEL AND NOT _is_multi AND NOT CMAKE_BUILD_TYPE)` around `set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Build type" FORCE)`. | A subproject's forced default compiles its parent's own target with `-O3 -DNDEBUG`. A plain `CACHE` set after `project()` is a no-op, because the empty entry exists. Before `project()`, `CMAKE_CONFIGURATION_TYPES` is empty even on Ninja Multi-Config. A normal `set()` after `project()` takes effect but leaves the cache empty. | Gate line (4). Empty output from both = pass. A hit above the top-level `project()` passes on reading only if its multi-config test is `GENERATOR_IS_MULTI_CONFIG`. For a normal-variable default, read `compile_commands.json`, not `CMakeCache.txt`. | MUST (library write, no-op default), SHOULD (multi-config test). Floor: 3.9, `PROJECT_IS_TOP_LEVEL` 3.21 |

```cmake
# wrong: the top-level consumer is where Conan's cppstd is overridden
project(app LANGUAGES CXX)
if(PROJECT_IS_TOP_LEVEL)
    set(CMAKE_CXX_STANDARD 17)
endif()

# right: a default that yields to a profile, a preset or a -D
if(NOT DEFINED CMAKE_CXX_STANDARD)
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    set(CMAKE_CXX_EXTENSIONS OFF)
endif()
```

## Library Type and PIC

A configure probe, then a build. After the add, print the dependency's type
with `get_target_property(_dep_type dep TYPE)` and `message(STATUS "dep TYPE=${_dep_type}")`.
`guard_scan` is defined in the section above.

```sh
cmake -S . -B build -G Ninja -Werror=dev -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build
# CMK-TGT-12: compile lines without -fPIC. Empty output = pass.
grep -rn --include='compile_commands.json' -e '"command"' build | grep -v -e '-fPIC'
# CMK-TGT-10, -11: a FORCE write outside a NOT DEFINED guard. Empty output = pass.
guard_scan 'set[[:space:]]*[(][[:space:]]*build_shared_libs[^)]*force' 'not[[:space:]]+defined[[:space:]]+build_shared_libs'
# CMK-TGT-11: a hard-coded type. Read each hit.
grep -rniE --include='CMakeLists.txt' --include='*.cmake' -e 'add_library[[:space:]]*[(][[:space:]]*[^[:space:])]+[[:space:]]+(STATIC|SHARED)' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TGT-10 | Let the user choose a sub-built dependency's library type through a cache entry (`-DBUILD_SHARED_LIBS=…`, a preset's `cacheVariables`). When project code must choose, set `BUILD_SHARED_LIBS` as a normal variable, restore it around the one `add_subdirectory` or `FetchContent_MakeAvailable`, and set `CMAKE_POLICY_DEFAULT_CMP0077 NEW` with it (CMK-DEP-15 owns that knob). Never write it with `CACHE … FORCE`. | A normal variable is lost on a dependency whose floor is below 3.13, with only a CMP0077 warning. `CACHE … FORCE` turns the user's `-DBUILD_SHARED_LIBS=OFF` into a shared build. | The `TYPE` message: a type other than the intended one is a finding. Measured red (`STATIC_LIBRARY`, and the gate exits 1 on the CMP0077 warning) for a plain set before a floor-3.12 dependency, green (`SHARED_LIBRARY`) for the scoped form. The `guard_scan` line lists unguarded FORCE writes. | MUST. Floor: 3.13 for CMP0077, any for the cache entry |
| CMK-TGT-11 | In a library, never write `BUILD_SHARED_LIBS` with a `FORCE` outside `if(NOT DEFINED BUILD_SHARED_LIBS)`, and never hard-code `STATIC` or `SHARED` on an exported target. Declare `option(BUILD_SHARED_LIBS "…" <default>)` or a documented per-kind option, and let the consumer decide. When that default is `ON`, first set it as a normal variable under `if(NOT PROJECT_IS_TOP_LEVEL AND NOT DEFINED BUILD_SHARED_LIBS)` (CMP0077 NEW), so the option never creates the parent's cache entry. Outside `PROJECT_IS_TOP_LEVEL`, never create a cache entry for another variable CMake reads (`EXECUTABLE_OUTPUT_PATH`, `LIBRARY_OUTPUT_PATH`, `CMAKE_<KIND>_OUTPUT_DIRECTORY`). | An unguarded FORCE overrides the consumer's `-D`, and a hard-coded type ignores both channels. qtbase's FORCE under `NOT DEFINED` is guarded and is not a finding. An unguarded `option(BUILD_SHARED_LIBS … ON)` in a subproject creates the parent's cache entry, and every `add_library()` the parent adds afterwards builds `SHARED_LIBRARY` (open-source-parsers/jsoncpp at `3347a4b8`, measured 2026-09-26 on 3.31.12 and 4.4.2). A cached `EXECUTABLE_OUTPUT_PATH` in a subproject puts every executable the parent adds later into the subproject's `bin/` (uclouvain/openjpeg at `8314119b`, measured 2026-09-26 on 3.31.12 and 4.4.2). | The `guard_scan` line (empty output = pass) and the `add_library` read: a hit on an exported target that no option or cache variable selects is a finding. Read `add_library(` calls whose type sits on the next line by hand. Under a parent that never sets it, `message(STATUS "bsl=[${BUILD_SHARED_LIBS}]")` after the `add_subdirectory` prints `bsl=[]`. A printed `bsl=[ON]` is the finding. For the cached output variables, the same parent adds an executable after the `add_subdirectory`: built in the parent's build directory is the pass, built under the subproject's `bin/` is the finding. | MUST (FORCE, and the non-top-level `ON` default), SHOULD (hard-coded type, and other cached variables CMake reads). Floor: any |
| CMK-TGT-12 | Make every static library that ends up in a `SHARED` or `MODULE` target position-independent before it is created. A library sets `POSITION_INDEPENDENT_CODE ON` on its own static targets. A top level linking other people's static targets into a shared object sets `CMAKE_POSITION_INDEPENDENT_CODE ON` before the add that creates them. Never claim the variable guarantees PIC. | Without PIC the shared link fails with `relocation R_X86_64_32S … recompile with -fPIC`. The variable seeds only targets created after it and never overrides a target's own property. Whether the link fails depends on codegen, so "it links here" proves nothing. | The compile-line grep: a printed line for a source of a static target feeding a shared object is a finding (an executable's source is not). Measured red on a property-less static member (link fails too), green with the property. Second check: `readelf -rW` on the member object shows no `R_X86_64_32` or `R_X86_64_32S`. | MUST. Floor: 2.8.9 |

```cmake
# wrong: lost on a dependency older than 3.13, and FORCE beats the user's -D
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(dep)

# right: scoped to the one add, with the policy default
set(_saved_bsl "${BUILD_SHARED_LIBS}")
set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
set(BUILD_SHARED_LIBS ON)
FetchContent_MakeAvailable(dep)
set(BUILD_SHARED_LIBS "${_saved_bsl}")
unset(CMAKE_POLICY_DEFAULT_CMP0077)
```

## Symbols, Link Items and Embedded Paths

Read the built artefact, not the configure log. `nm`, `readelf` and
`-ffile-prefix-map` are GCC and Clang on ELF, and the Windows halves are
read-only (documented, not measured).

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TGT-13 | Give an installable shared library `C_VISIBILITY_PRESET hidden`, `CXX_VISIBILITY_PRESET hidden` and `VISIBILITY_INLINES_HIDDEN ON`, and mark its API with `generate_export_header`'s macro. Never offer `WINDOWS_EXPORT_ALL_SYMBOLS` as a portable fix, and never add it in a recipe or port. | ELF exports every symbol by default, internal helpers and header inlines included (measured with `nm -D`). Export-all works only on MS toolchains and skips global data. vcpkg's maintainer guide forbids adding it unless upstream already does, which abseil, protobuf, grpc and re2 do (not a finding). | `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'VISIBILITY_PRESET' -e 'generate_export_header' .` Empty output in a project that builds a SHARED library is the finding. Then `nm -D --defined-only` on the built `.so`: a symbol missing from the public headers is a finding. | SHOULD. Floor: any, CMP0063 (3.3) for every target type |
| CMK-TGT-14 | Before enabling `CMAKE_LINK_LIBRARIES_ONLY_TARGETS`, replace every bare `m`, `pthread`, `dl` or `rt` link item with an imported target (`Threads::Threads`) or an absolute path, and judge the result by the exit code. | A misspelling, a bare `m` and a bare `pthread` all fail with "which is not a target" and exit 1, but the error arrives in the generate step after `Configuring done`, so a log read looks green. | `grep -rn -A3 --include='CMakeLists.txt' --include='*.cmake' -e 'target_link_libraries[[:space:]]*(' .` and read the items: a bare system name is a finding. Empty output = nothing to check. Then `cmake -S . -B build -Werror=dev -DCMAKE_LINK_LIBRARIES_ONLY_TARGETS=ON` must exit 0. | SHOULD. Enabling it is CONSIDER. Floor: 3.23 |
| CMK-TGT-15 | When a build must not embed its checkout or build path, pass `-ffile-prefix-map=` for the source dir and the binary dir yourself, through a compiler-guarded `target_compile_options` or a toolchain's `CMAKE_<LANG>_FLAGS_INIT`. CMake has no native variable, and `CMAKE_DEBUG_PREFIX_MAP` does not exist. | Objects built from two directories differ and embed both paths. With either channel they are byte-identical (measured, GCC and Clang). An invented variable is a silent no-op. | Build from two checkouts and `cmp` the objects. Then `SRC_DIR="$PWD"; grep -rlF --include='*.o' -e "$SRC_DIR" build` Empty output = pass. | SHOULD, when the project promises reproducible builds. Floor: any |

## C++20 Modules and Scanning

Configure only. `rules.ninja` defines the scan rules whenever any target could
scan, so it is excluded, and Ninja Multi-Config writes the statements to
`CMakeFiles/impl-<Config>.ninja`, which the `*.ninja` include covers.

```sh
cmake -S . -B build -G Ninja -Werror=dev
# CMK-TGT-18. Empty output = pass. A listed file, with no FILE_SET CXX_MODULES in the project, is a finding.
grep -rl --include='*.ninja' --exclude='rules.ninja' -e 'CXX_SCAN__' -e 'CXX_DYNDEP__' build
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TGT-18 | When a target's standard rises to C++20 or later and the project has no named-module sources, set `CMAKE_CXX_SCAN_FOR_MODULES OFF` as a normal variable (never a cache entry) or set the target property. The remedy is the variable. `cmake_policy(SET CMP0155 OLD)` violates CMK-VER-07. | A `3.25...4.4` range makes CMP0155 `NEW`, so C++20 scans every source. On Ninja with a Clang that ships no `clang-scan-deps`, the configure exits 0 and the build fails with exit 127. A library cannot know its consumer's Clang. `cmake-cxxmodules(7)` says the variable "should not be in the cache", because a cache entry leaks into FetchContent consumers. | The gate grep. Measured on Ninja and Ninja Multi-Config: red at C++20, green at C++17 and at C++20 with the variable `OFF`. Unix Makefiles emits no scan step (nothing to check). | MUST. Floor: 3.28 |
| CMK-TGT-19 | Ship a C++20 named-module interface only as an extra, opt-in target beside the classic one, with `target_compile_features(<t> PUBLIC cxx_std_20)`, gated on CMake ≥ 3.28, Ninja ≥ 1.11 or Visual Studio ≥ 17.4, and GCC 14+, Clang 16+ or MSVC 14.34+. Keep `import std` behind `CMAKE_EXPERIMENTAL_CXX_IMPORT_STD` with the exact binary's UUID (CMK-VER-09), on Ninja only, gated on Clang 18.1.2+, MSVC 14.36+ or GCC 15+. | The gates are `cmake-cxxmodules(7)` at 4.4.2. Kitware's "the experiment is over" covers named modules, not `import std`, and the UUID rotates per CMake release. fmt and nlohmann/json ship modules as extra targets. | `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'CXX_MODULES' -e 'CMAKE_EXPERIMENTAL_CXX_IMPORT_STD' .` Empty output = nothing to check. A module target that is the only target or that no option or `CMAKE_VERSION` test gates is a finding. A configure printing `CMAKE_EXPERIMENTAL_CXX_IMPORT_STD is set to incorrect value` is a finding. | SHOULD. Floor: 3.28, `import std` experimental through 4.4 |

## What Agents Get Wrong Here

1. **Writing `set(BUILD_SHARED_LIBS ON)` before a fetch and assuming it took, or "fixing" it with `CACHE … FORCE`.** The first is silent on an old dependency, the second overrides the user. `CMK-TGT-10`'s `TYPE` message.
2. **Putting `set(CMAKE_CXX_STANDARD …)` or `set(CMAKE_MSVC_RUNTIME_LIBRARY …)` inside `if(PROJECT_IS_TOP_LEVEL)` after `project()` and calling it Conan-safe, or reading a `CACHE` default without `FORCE` as a guard below policy version 3.21.** The top level is where the override fires, and the runtime one prints nothing. To debug an LNK2038, read the generated `conan_toolchain.cmake`, not the log (`CMK-TGT-05`, `CMK-TGT-16`).
3. **Writing bare `target_link_libraries(t a b)`.** It is still the dominant tutorial form and CMake accepts it silently (`CMK-TGT-01`).
4. **Copying the build-type idiom without `FORCE` after `project()`, or putting it in a library.** The first is a no-op, the second changes the parent's build (`CMK-TGT-17`).
5. **Treating `CMAKE_POSITION_INDEPENDENT_CODE` as a global guarantee, or "it links on my machine" as proof.** Read the compile line (`CMK-TGT-12`).
6. **Raising the standard to C++20 without noticing that scanning switched on**, then reaching for `CMP0155 OLD`. The `*.ninja` grep (`CMK-TGT-18`).
7. **Citing "the experiment is over" for `import std`, or copying a gate UUID from another CMake version** (`CMK-TGT-19`, CMK-VER-09).
8. **Believing visibility is a Windows-only problem, or offering `CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS` as the portable fix.** `nm -D` on the real `.so` (`CMK-TGT-13`).
9. **Inventing a variable: `CMAKE_DEBUG_PREFIX_MAP`, `CMAKE_CXX_STANDARD_EXTENSIONS`.** `cmake --help-variable NAME` must exit 0 for every `CMAKE_` name you write (`CMK-TGT-15`, `CMK-TGT-07`).
10. **Enabling `CMAKE_LINK_LIBRARIES_ONLY_TARGETS` as free hardening, or reading `Configuring done` as success** (`CMK-TGT-14`).
11. **Putting `-fsanitize=` in the global flags or in compile options only, or porting a Linux sanitizer job to Windows unchanged** (`CMK-TGT-20`).
12. **Moving a definition that an installed header reads onto the target as `PRIVATE`**, because `PRIVATE` is the default for links. The build passes until the option that sets it is switched on (`CMK-TGT-03`).
13. **Keeping a library's `option(BUILD_SHARED_LIBS … ON)` as prescribed.** Under a parent that never set it, the parent's later libraries turn `SHARED` (`CMK-TGT-11`).
14. **Keeping a legacy tree's `${CMAKE_SOURCE_DIR}` in an include directory.** Only a compiled `add_subdirectory` consumer shows it (`CMK-TGT-21`).

Re-check:
- D4, each Conan release tag: `CppStdBlock` and `VSRuntimeBlock` in `conan/tools/cmake/toolchain/blocks.py` (as of Conan 2.32.0), for CMK-TGT-05, -06, -07 and -16.
- Each CMake release: the `CXX_IMPORT_STD` UUID (CMK-VER-09) and whether `import std` leaves experimental (CMK-TGT-19).
- Host-bound, read-only as of 2026-09-26: Windows (CMK-TGT-13, -16, -20) and default-PIE toolchains (CMK-TGT-12).
