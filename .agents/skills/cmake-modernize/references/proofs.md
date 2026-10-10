# The proofs

Read this when running steps 5 to 9: the scripts whose exit codes close them,
and step 8's CI greps. Each ran against a planted passing and a planted failing
project on CMake 3.31.12, 4.3.4 and 4.4.2, gcc 15.2.1, Ninja 1.13.2
(2026-09-26), with the range `3.25...4.4` and the gate in `GATE` (`CMK-CORE-01`).

Contents: [The gate canary](#the-gate-canary) · [The as-subproject smoke](#the-as-subproject-smoke) ·
[The offline subproject probe](#the-offline-subproject-probe) · [The gated round trip](#the-gated-round-trip) ·
[The pkg-config check](#the-pkg-config-check) · [CI checks](#ci-checks) · [CPS and pkg-config](#cps-and-pkg-config)

## The gate canary

A three-line project. Configure it with a leg's exact binary and flags: exit 1
means the gate is live, exit 0 is the finding.

```cmake
cmake_minimum_required(VERSION 3.25...4.4)
project(gate_canary LANGUAGES NONE)
message(AUTHOR_WARNING "gate canary")
```

```sh
# W = scratch dir holding canary/CMakeLists.txt. Exit 1 = pass.
cmake -S "$W/canary" -B "$W/canary-build" "$GATE"
```

Measured: `-Werror=dev` exits 1 on all three lines, `-Werror=author` exits 1 on
4.4.2 and **0** on 3.31.12 and 4.3.4. A CI leg that takes its gate from a preset
runs the leg's preset beside a copy of `CMakePresets.json`. Exit 1 = pass.
`"errors": {"dev": true}` exits 1, `"warnings": {"dev": false}` exits 0.

```sh
LEG=ci
cp CMakePresets.json "$W/canary/"
cmake -S "$W/canary" -B "$W/canary-build" --preset "$LEG" --fresh
```

## The as-subproject smoke

Step 7's exit check, and step 5's. Dropped in with `add_subdirectory` under a
parent that defines none of its option names, the tree defines no test and no
developer-only target. The parent includes `CTest` on purpose, which turns
`BUILD_TESTING` on. Pass the plan file's configure options to each `cmake -S`.

```sh
# SRC = absolute library source, W = an empty scratch dir, GATE per binary.
mkdir -p "$W/asub"
printf '%s\n' 'cmake_minimum_required(VERSION 3.25...4.4)' 'project(asub LANGUAGES C)' \
  'include(CTest)' "add_subdirectory($SRC lib-build)" 'message(STATUS "asub_bsl=[${BUILD_SHARED_LIBS}]")' > "$W/asub/CMakeLists.txt"
cmake -S "$W/asub" -B "$W/asub-build" -G Ninja "$GATE" > "$W/asub-configure.txt"
grep -r --include='asub-configure.txt' -e 'asub_bsl=\[ON\]' "$W"
ctest --test-dir "$W/asub-build" -N > "$W/asub-tests.txt"
grep -r --include='asub-tests.txt' -e 'Total Tests: 0' "$W"
cmake --build "$W/asub-build" --target help > "$W/asub-targets.txt"
NAME=mylib_unit_tests
grep -r --include='asub-targets.txt' -e "^$NAME: " "$W"
```

The configure must exit 0: after a failed one, `ctest -N` still prints
`Total Tests: 0` and every target grep is empty (tinyformat). The `asub_bsl`
grep: empty output = pass, and a line means the library's
`option(BUILD_SHARED_LIBS ... ON)` made every later parent library `SHARED`
(jsoncpp). The tests `grep` must print a line, and empty output = tests leaked.
Run the last `grep` once per developer-only target name of a top-level
configure. Empty output = pass. Planted: guarded prints `Total Tests: 0` and no
`mylib_unit_tests: phony`, unguarded `Total Tests: 1` and that line. It is
anchored because a bare `ssh2` also matches `libssh2_static`. Never use a
`--directory` flag or an `|| echo OK` ending. Declare the library's language.

Then compare the parent's state with and without the library (`C2`), which
needs no name in advance: the typed cache entries without the library's prefix,
and the two build roots' top-level files.

```sh
# PREFIX = the library's option prefix, W and GATE as above. Two lists to read, see below.
PREFIX=LIBSSH2_
mkdir -p "$W/asub0"
printf '%s\n' 'cmake_minimum_required(VERSION 3.25...4.4)' 'project(asub LANGUAGES C)' 'include(CTest)' > "$W/asub0/CMakeLists.txt"
cmake -S "$W/asub0" -B "$W/asub0-build" -G Ninja "$GATE"
for d in asub0 asub; do grep -E -e '^[A-Za-z_][A-Za-z0-9_]*:(BOOL|STRING|PATH|FILEPATH)=' "$W/$d-build/CMakeCache.txt" | grep -v -i -e "^$PREFIX" | sort > "$W/$d-cache.txt"; ls "$W/$d-build" > "$W/$d-root.txt"; done
diff "$W/asub0-cache.txt" "$W/asub-cache.txt"
diff "$W/asub0-root.txt" "$W/asub-root.txt"
```

Each `>` cache line is an entry the library wrote into the parent's cache: a
`BOOL` or `STRING` is a second-pass name. `CMAKE_INSTALL_*`, a language's
`CMAKE_<LANG>_*` and a Find module's results are expected. A `CPACK_*` line, or
a `>` root line other than `lib-build`, is a write into the parent's build
root, the finding: libssh2's `include(CPack)` rewrote a packaging parent's
version to `1.11.1_DEV`, exit 0.

The second pass runs the same smoke under a parent that owns an option name the
library also declares. List the library's options first:

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e '^[[:space:]]*option[[:space:]]*\(' -e 'CACHE[[:space:]]+(BOOL|STRING|PATH|FILEPATH)' -e 'CACHE[[:space:]]*$' "$SRC"
```

Empty output = no second pass. The `CACHE` patterns list openjpeg's
`WITH_ASTYLE` and libssh2's split `set(CRYPTO_BACKEND "" CACHE`, which a parent
owning `CRYPTO_BACKEND=mbedTLS` broke with `Could NOT find MbedTLS`. A hit `I6`
or `I3` settles is no option. Run once per unprefixed name:

```sh
# NAME as in the first pass, once per developer-only target name.
OPT=BUILD_EXAMPLES
mkdir -p "$W/asub2"
printf '%s\n' 'cmake_minimum_required(VERSION 3.25...4.4)' 'project(asub2 LANGUAGES C)' \
  'include(CTest)' "option($OPT \"parent option\" ON)" "add_subdirectory($SRC lib-build)" > "$W/asub2/CMakeLists.txt"
cmake -S "$W/asub2" -B "$W/asub2-build" -G Ninja "$GATE"
cmake --build "$W/asub2-build" --target help > "$W/asub2-targets.txt"
grep -r --include='asub2-targets.txt' -e "^$NAME: " "$W"
```

A non-zero configure exit or any grep line is a finding. Empty output = pass.
`option()` never overrides a parent's name, so Chipmunk2D's unprefixed
`BUILD_DEMOS` took the parent's `ON` and failed with `Could NOT find OpenGL`.

The third pass compiles a consumer through `add_subdirectory`, because a usage
requirement on `CMAKE_SOURCE_DIR` passes the first pass and the round trip.

```sh
# TARGETS, SYM_DECL and SYM_CALL as in the round trip. Exit 0 from both commands = pass.
mkdir -p "$W/asub3"
printf '%s\n' "$SYM_DECL" "int main(void) { return $SYM_CALL; }" > "$W/asub3/main.c"
printf '%s\n' 'cmake_minimum_required(VERSION 3.25...4.4)' 'project(asub3 LANGUAGES C)' \
  "add_subdirectory($SRC lib-build)" 'add_executable(app main.c)' "target_link_libraries(app PRIVATE $TARGETS)" > "$W/asub3/CMakeLists.txt"
cmake -S "$W/asub3" -B "$W/asub3-build" -G Ninja "$GATE"
cmake --build "$W/asub3-build"
```

For a C++ library, declare `LANGUAGES CXX` and write `main.cpp`. On tinyformat
`$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}>` failed with `'tinyformat.h' file not
found`, and `${CMAKE_CURRENT_SOURCE_DIR}` built with exit 0.

## The offline subproject probe

When `I7` listed an unguarded fetch, this is `CMK-DEP-07`'s check: the dependency
installed, the network off (`FETCHCONTENT_FULLY_DISCONNECTED`), a forced fetch fails.

```sh
# SRC = absolute library source, DEP_PREFIX = an install prefix holding the dependency. Exit 0 = pass.
mkdir -p "$W/dep07"
printf '%s\n' 'cmake_minimum_required(VERSION 3.25...4.4)' 'project(dep07 LANGUAGES C)' \
  "add_subdirectory($SRC lib-build)" > "$W/dep07/CMakeLists.txt"
cmake -S "$W/dep07" -B "$W/dep07-build" "$GATE" -DCMAKE_PREFIX_PATH="$DEP_PREFIX" \
  -DFETCHCONTENT_FULLY_DISCONNECTED=ON -DCMAKE_POLICY_DEFAULT_CMP0170=NEW
```

A non-zero exit is the finding. Without the CMP0170 default, a range below 3.30
fetches into an empty source directory and exits 0. An unconditional declare
exits 1, and with `FIND_PACKAGE_ARGS CONFIG` exits 0 against the installed copy.

## The gated round trip

Step 6's exit check (`CMK-INST-01`). It installs, greps the prefix for leaked
paths, moves it, then builds and links a separate compiled consumer, because a
missing `find_dependency` stays green for a `LANGUAGES NONE` consumer.

```sh
# Run from an empty scratch dir, once per CMake line CI runs. Export first: PKG (find_package name),
# VER (a version it satisfies), TARGETS (its imported targets), SRC (absolute source dir), GATE (per binary),
# SYM_DECL and SYM_CALL (an include and a call of one exported function per target in TARGETS), for example:
#   export PKG=mylib VER=1.0 TARGETS=mylib::mylib SRC=/abs/path/to/project GATE=-Werror=dev
#   export SYM_DECL='#include <mylib/mylib.h>' SYM_CALL='mylib_version() != 0'
# CFG_ARGS (optional): the plan file's -D options. A dependency outside system paths: export CMAKE_PREFIX_PATH=/abs/dep/prefix
set -eu
: "${PKG:?}" "${VER:?}" "${TARGETS:?}" "${SRC:?}" "${GATE:?}" "${SYM_DECL:?}" "${SYM_CALL:?}"
W="$PWD"
cmake -S "$SRC" -B "$W/build" "$GATE" ${CFG_ARGS:-}
cmake --build "$W/build"
cmake --install "$W/build" --prefix "$W/prefix"
# (a) Text files in the prefix naming the source, build or install tree. Empty = pass.
grep -rIl --exclude='*.pc' -e "$SRC" -e "$W/build" -e "$W/prefix" "$W/prefix" > "$W/leaks.txt" || true
test ! -s "$W/leaks.txt"
# (b) An export file with a baked absolute import prefix. Empty = pass.
grep -rn --include='*.cmake' -e 'set(_IMPORT_PREFIX "/' "$W/prefix" > "$W/abs-import.txt" || true
test ! -s "$W/abs-import.txt"
# (c) Move the prefix, then configure, build and link a separate compiled consumer.
mv "$W/prefix" "$W/moved"
mkdir -p "$W/consumer"
printf '%s\n' "$SYM_DECL" "int main(void) { return $SYM_CALL; }" > "$W/consumer/main.c"
printf '%s\n' 'cmake_minimum_required(VERSION 3.25...4.4)' 'project(rt LANGUAGES C)' 'set(_mp "${CMAKE_MODULE_PATH}")' \
  "find_package($PKG $VER CONFIG REQUIRED)" 'if(NOT "${CMAKE_MODULE_PATH}" STREQUAL "${_mp}")' \
  'message(FATAL_ERROR "find_package changed CMAKE_MODULE_PATH")' 'endif()' 'add_executable(rt main.c)' \
  "target_link_libraries(rt PRIVATE $TARGETS)" > "$W/consumer/CMakeLists.txt"
cmake -S "$W/consumer" -B "$W/consumer-build" "$GATE" -DCMAKE_PREFIX_PATH="$W/moved" -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF
cmake --build "$W/consumer-build"
grep -e "^${PKG}_DIR:PATH=$W/moved/" "$W/consumer-build/CMakeCache.txt"
```

The script stops at the first failure, and any non-zero exit is a finding. The
last line proves the consumer resolved the moved prefix
(`mylib_DIR:PATH=.../moved/lib64/cmake/mylib`, `C8`). A tree's own
`export(PACKAGE)` below a 3.15 floor (`CMK-INST-24`) writes a registry entry
that resolves an old build tree instead: libssh2 with no version file exited 0
through its entry-check build tree, and with the registry switch and the
anchored grep exits 1, `version: unknown` (`CMK-INST-04`, 3.31.12 and 4.4.2).
The `CMAKE_MODULE_PATH` guard stops a Config that shadows the consumer's Find
modules with its own directory (`C2`).

The consumer calls a function because an empty `main` pulls no archive member:
Chipmunk2D's static target, which never linked `m`, failed with
``undefined reference to `sincos'`` only under `SYM_CALL`. When two targets
export the same symbols (a shared and a static build of one library), the call
resolves from whichever the linker reads first, so run once per target: cmark's
`libcmark.a` supplied nothing beside `libcmark.so`. Multi-config defects need
`CMK-INST-22`'s leg. A C++ consumer writes `main.cpp` under `LANGUAGES CXX`. Run
once more per option that adds a `PUBLIC` definition in `CFG_ARGS` (jsoncpp).

### The pkg-config check

The round trip never reads a `.pc`. A tree that ships one compares pkg-config's
output against a step-0 install staged with `DESTDIR` (absolute destinations
ignore `--prefix`), from the round trip's dir.

```sh
# PC = the .pc name, STEP0_DESTDIR = the DESTDIR of a step-0 install with the default prefix,
# PCDIR = the directory each install wrote the .pc to, under its prefix. Empty output = pass.
PC=zlib
PCDIR=share/pkgconfig
PKG_CONFIG_PATH="$STEP0_DESTDIR/usr/local/$PCDIR" pkg-config --cflags --libs "$PC" > pc-before.txt
PKG_CONFIG_PATH="$PWD/moved/$PCDIR" pkg-config --cflags --libs "$PC" > pc-after.txt
diff pc-before.txt pc-after.txt
```

A printed directory change the plan file names (`lib` to `lib64`) passes. An
empty `-I` or `-L`, or a path that lost its prefix, is the finding: zlib
1.3.1's literal step 6 printed `> -I -L -lz` while the round trip exited 0.

## CI checks

Step 8. CI carries each leg under its own gate, checked by the canary through
that leg's binary and preset, `gersemi --check`, and the round trip as its own
job (`CMK-INST-18`). A module project running gersemi commits a `.gersemirc`
(`CMK-MOD-15`), and a `.cmake-format*` file is migrated, never extended.

```sh
# CMK-CORE-01: a gate exists in the workflows. Empty output = no gate (finding), unless the leg's preset carries "errors": {"dev": true} and the preset canary exits 1.
# A Werror=author hit on a leg that can resolve CMake below 4.4 is also a finding.
# CI_SCRIPTS (optional) = a directory or script the workflows configure or install through (openjpeg: tools/ctest_scripts, a ctest -S script).
grep -rn -e 'Werror=author' -e 'Werror=dev' .github/workflows ${CI_SCRIPTS:+"$CI_SCRIPTS"}
# A preset that switches the gate off ("deprecated": false beat a command-line -Werror=dev on 3.31.12). Empty output = pass.
grep -rn --include='CMakePresets.json' --include='CMakeUserPresets.json' -e '"dev"[[:space:]]*:[[:space:]]*false' -e '"deprecated"[[:space:]]*:[[:space:]]*false' .
# CMK-CORE-05: an early-exiting reader in a script. Empty output = pass. A hit in
# a file that also sets pipefail is the finding. Name only operands that exist:
# a missing scripts exits 2, and -s hides the message while the hits still print.
grep -rsnE -e '[|] *grep( +-[a-zA-Z]+)* +-[a-zA-Z]*[qm]' -e '[|] *rg( +-[a-zA-Z]+)* +-[a-zA-Z]*[qm]' -e '[|] *head' scripts .github
# CMK-CORE-04: a dead formatter. Empty output = pass. Any hit means migrate.
grep -rn --include='*.yml' --include='*.yaml' --include='*.txt' --include='*.toml' \
  -e 'cmake-format' -e 'cmake_format' -e 'cmake-lint' -e 'cmakelang' .
# CMK-CORE-02: schema 12 still carrying dev. "true" is the finding, "false" or no output passes.
find . -name CMakePresets.json -not -path '*/_deps/*' -print0 \
  | xargs -0 -r -n1 jq -e '.version >= 12 and ([.configurePresets[]? | (.warnings // {}), (.errors // {}) | has("dev")] | any)'
# CMK-INST-18: the install steps, a list to read, then a consumer configure after each. Hits from the first with empty output from the second is the finding.
grep -rn -e 'cmake --install' -e '--target install' -e 'make .* install' .github/workflows ${CI_SCRIPTS:+"$CI_SCRIPTS"}
grep -rn -e 'CMAKE_PREFIX_PATH' .github/workflows ${CI_SCRIPTS:+"$CI_SCRIPTS"}
```

The formatting gate is the index's gate line,
`git ls-files -z -- '*CMakeLists.txt' '*.cmake' | xargs -0 -r gersemi --check`
(gersemi 0.29.1). gersemi exits 1 on an unformatted file, which `xargs` reports
as 123: any non-zero exit is the finding. Append one `':!:thirdparty/**'`
pathspec per vendored directory the plan file records (openjpeg: 8 of 39). Never
`gersemi --check .`, which descends into build trees, and never
`gersemi --diff`, which exited 0 on both (2026-09-26, `CMK-CORE-04`).

With no `.github/workflows` directory, the greps that name it exit 2, neither a
pass nor a hit: step 8 is not applicable, and SKILL.md says what to report.
libssh2 installs and consumes only in `tests/cmake/test.sh`, which the
`CMK-INST-18` greps read only when `CI_SCRIPTS` names it.

## CPS and pkg-config

Step 9, optional, only after the round trip is green without it. Add
`install(PACKAGE_INFO <pkg> EXPORT <set> VERSION ... COMPAT_VERSION ...)` inside
`if(CMAKE_VERSION VERSION_GREATER_EQUAL 4.3)`. Re-run the round trip on a 3.31
line and a 4.3 or later line. Both exit 0, and the `_DIR` line ends in
`/cmake/<pkg>` on 3.31 and `/cps/<pkg>` on 4.3 and later, because a `.cps` in
the same prefix wins from 4.3. Before that run, three greps. For each, empty
output = pass.

```sh
# CMK-INST-13: retired experimental gates and the distributor-only switch.
grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'CMAKE_EXPERIMENTAL_EXPORT_PACKAGE_INFO' \
  -e 'CMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES' -e 'CMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO' .
# CMK-INST-16: any schema other than simple. A hit is the finding.
grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'VERSION_SCHEMA' . | grep -v -e 'VERSION_SCHEMA simple'
```

`CMK-INST-15` is a list to read:
`grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'install(PACKAGE_INFO' -e 'NAMESPACE' .`
A `PACKAGE_INFO` name that differs in any character from its export's `NAMESPACE` prefix is the finding.
`CMK-INST-17` is the configure exit code with CPS enabled: non-zero is the
finding (a log grep misses the wrapped message). A pkg-config file writes
`prefix=${pcfiledir}/<rel>` from `file(RELATIVE_PATH)`, never `../..`
(`CMK-INST-12`, SHOULD): `grep -rnF --include='*.pc.in' -e 'prefix=@CMAKE_INSTALL_PREFIX@' .`
prints nothing for new files.
