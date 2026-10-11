# The inventory commands

Read this when running step 0, or when re-running one command as the exit check
of steps 1 to 4. Every command runs from the repository root and was run
against a planted violating and a planted compliant tree on CMake 3.31.12 and
4.4.2 (2026-09-26). Each `I` command is a `grep -r` with an explicit directory
operand and no early-exiting reader (`CMK-CORE-05`).

Contents: [How to read the output](#how-to-read-the-output) · [Links, scope and flags](#links-scope-and-flags) ·
[Parses and reserved names](#parses-and-reserved-names) ·
[Build type, fetches and policy knobs](#build-type-fetches-and-policy-knobs) ·
[Floors and hand-off tokens](#floors-and-hand-off-tokens) ·
[Standards and warnings-as-errors](#standards-and-warnings-as-errors) · [The flag-set check](#the-flag-set-check) ·
[The configured-file check](#the-configured-file-check) · [The variable-existence check](#the-variable-existence-check)

## How to read the output

Own-code commands exclude `_deps` and `build*` trees, not a vendored directory
such as `third_party/`: a hit there is recorded `flagged-not-converted` and
never edited. Each command says whether empty output is the pass or the output
is a list to read. The commands match upper-case spellings and a space before
the paren, because CMake command names are case-insensitive. A call whose name
and paren sit on different lines is not seen, so read those by hand.

## Links, scope and flags

`I1`, bare links (`CMK-TGT-01`). A list to read: a call whose token after the
target name is not `PUBLIC`, `PRIVATE` or `INTERFACE` is the finding (`-A2`
shows a split call's continuation).

```sh
grep -rni -A2 --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'target_link_libraries[[:space:]]*(' .
```

`I2`, directory scope (`CMK-TGT-03`, SHOULD, never auto-rewrite). Empty output
= pass. Each hit is a step-2 row. A call inside `if(CMAKE_VERSION VERSION_LESS ...)`
is usually a dead twin of a live call, so record both (jsoncpp, three pairs).

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e '^[[:space:]]*include_directories[[:space:]]*\(' -e '^[[:space:]]*add_definitions[[:space:]]*\(' \
  -e '^[[:space:]]*add_compile_options[[:space:]]*\(' -e '^[[:space:]]*link_directories[[:space:]]*\(' \
  -e '^[[:space:]]*link_libraries[[:space:]]*\(' -e '^[[:space:]]*add_compile_definitions[[:space:]]*\(' .
```

`I2b`, definitions set as a target, source or directory property
(`CMK-TGT-03`). A list to read: each `-D` in a hit is a step-2 row and gets the
reader grep of SKILL.md steps 2 to 4 (cmark's `COMPILE_FLAGS -DCMARK_STATIC_DEFINE`).

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e '(^|[[:space:]])COMPILE_FLAGS([[:space:]]|$)' -e '(^|[[:space:]])COMPILE_DEFINITIONS([[:space:]]|$)' .
```

`I3`, global flag writes (`CMK-TGT-04`). Empty output = pass. A value that does
not start with the variable's own `${...}` is an overwrite, MUST, because it
drops a toolchain's `_INIT` `-fPIC` and the shared link fails. A
`string(APPEND ...)` or a `set()` starting with its own value is an append,
SHOULD. A `..._FLAGS_INIT` hit inside a toolchain file is no finding.

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'set[[:space:]]*\([[:space:]]*CMAKE_C_FLAGS' -e 'set[[:space:]]*\([[:space:]]*CMAKE_CXX_FLAGS' \
  -e 'set[[:space:]]*\([[:space:]]*CMAKE_EXE_LINKER_FLAGS' -e 'set[[:space:]]*\([[:space:]]*CMAKE_SHARED_LINKER_FLAGS' \
  -e 'set[[:space:]]*\([[:space:]]*CMAKE_STATIC_LINKER_FLAGS' -e 'set[[:space:]]*\([[:space:]]*CMAKE_MODULE_LINKER_FLAGS' \
  -e 'string[[:space:]]*\([[:space:]]*APPEND[[:space:]]+CMAKE_C_FLAGS' \
  -e 'string[[:space:]]*\([[:space:]]*APPEND[[:space:]]+CMAKE_CXX_FLAGS' .
```

## Parses and reserved names

`I4`, legacy parses (`CMK-LANG-04`). Empty output = pass. Each line is a parse
that forwards `${ARGN}`: a finding inside a `function()`, `CMK-LANG-08`'s
inside a `macro()`. A call with `PARSE_ARGV` on its next line also prints. Each
hit's row names the command, public (another project calls it) or private, and
each multi-value keyword that takes lists of files, targets or paths.

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'cmake_parse_arguments[[:space:]]*\(' . | grep -v -e 'PARSE_ARGV' -e 'PARSE_ARGN'
```

### Migrating a parse

Migrating a public command to `PARSE_ARGV` changes what callers get (3.31.12, 4.3.4, 4.4.2):

| Call | `${ARGN}` legacy | `PARSE_ARGV` |
|---|---|---|
| `MULTI "${L}" z`, with `L` = `x;y` | 3 elements | 2 elements, the first `x;y` |
| `ONE "a;b"` | `ONE` = `a`, `b` unparsed | `ONE` = `a;b` |

So the fix for each multi-value keyword whose values are lists of files,
targets or paths carries the flatten line, directly after the parse:

```cmake
function(mylib_add NAME)
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "DEST" "SOURCES")
    set(arg_SOURCES ${arg_SOURCES})
endfunction()
```

With it, `SOURCES "${L}" z` gives 3 elements again. The one-value change is a
fix. A public command's parse is never rewritten without the flatten line or a
changelog entry naming the behaviour change, and a private helper is SHOULD.
After the parse, read `<prefix>_UNPARSED_ARGUMENTS` and stop with `FATAL_ERROR`
(`CMK-LANG-06`).

`I5`, reserved option names (`CMK-LANG-11`). Empty output = pass. A hit is the
finding: it does not override a consumer's `-D`, it leaks into the parent. For
a `set(<name> ... CACHE ...)` named `CMAKE_*`, run
[the variable-existence check](#the-variable-existence-check).

```sh
grep -rnE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e '^[[:space:]]*option[[:space:]]*\([[:space:]]*"?[Cc][Mm][Aa][Kk][Ee]_' \
  -e '^[[:space:]]*option[[:space:]]*\([[:space:]]*"?_[Cc][Mm][Aa][Kk][Ee]_' .
```

## Build type, fetches and policy knobs

`I6`, build-type writes (`CMK-TGT-17`). Empty output = nothing to check. A hit
in a library's files outside a `PROJECT_IS_TOP_LEVEL` guard, a `CACHE` hit after
`project()` without `FORCE` (a no-op), and a hit before `project()` whose only
multi-config test is `CMAKE_CONFIGURATION_TYPES` are findings.

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'set[[:space:]]*\([[:space:]]*CMAKE_BUILD_TYPE' .
```

`I7`, forced acquisition (`CMK-DEP-07`). Empty output = not applicable. A hit
under a test, example, benchmark, docs or tool directory, or behind
`PROJECT_IS_TOP_LEVEL`, `NOT <dep>_FOUND` or `NOT TARGET`, is no finding. Any
other hit is a step-5 row, settled by the offline subproject probe.

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'FetchContent_MakeAvailable' -e 'CPMAddPackage' .
```

`I8`, policy knobs (`CMK-DEP-15`). Empty output = pass. A hit in a preset's
`cacheVariables`, a workflow `env`, or at file scope with no restore after
exactly one add is the finding, and so is 3.5 in an application build.

```sh
grep -rn --include='CMakeLists.txt' --include='*.cmake' --include='CMakePresets.json' --include='*.yml' --include='*.yaml' \
  -e 'CMAKE_POLICY_VERSION_MINIMUM' -e 'CMAKE_POLICY_DEFAULT_CMP' .
```

## Floors and hand-off tokens

`I9`, dependency floors (`CMK-VER-05`), over the fetched and vendored trees
that exist (a missing operand exits 2, not a pass), else `vacuous`. Empty
output = pass. A live line with no `...<max>` of 3.10 or above is the finding:
below 3.5 a hard error on 4.x, 3.5 to 3.9 a gate failure on 3.31 and 4.4.

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' \
  -e 'cmake_minimum_required[[:space:]]*\([[:space:]]*VERSION[[:space:]]+(2\.|3\.[0-9]([^0-9]|$))' \
  -e 'cmake_policy[[:space:]]*\([[:space:]]*VERSION[[:space:]]+(2\.|3\.[0-9]([^0-9]|$))' build/_deps third_party
```

`I10`, Conan 1 tokens. Empty output = continue. Any hit stops the skill and
hands off to `cpp-packaging` for a manager migration.

```sh
grep -rni --include='CMakeLists.txt' --include='*.cmake' -e 'conan_basic_setup' -e 'conanbuildinfo' .
```

`I13`, policy-removed Find modules (`CMK-DEP-19`), a step-1 row: a finding once
the raised `<max>` reaches 3.27 (4.1 for `GCCXML`, `CABLE`), migrated in the
floor's second diff (cmark's `PythonInterp`). `I14`, `export(PACKAGE)`
(`CMK-INST-24`), a step-6 row: below a 3.15 floor each configure writes a
registry entry a later `find_package` can resolve (libssh2). Empty = pass.

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'find_package[[:space:]]*\([[:space:]]*CUDA([[:space:])]|$)' -e 'find_package[[:space:]]*\([[:space:]]*PythonInterp' \
  -e 'find_package[[:space:]]*\([[:space:]]*PythonLibs' -e 'find_package[[:space:]]*\([[:space:]]*GCCXML' -e 'find_package[[:space:]]*\([[:space:]]*CABLE' .
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'export[[:space:]]*\([[:space:]]*package([[:space:])]|$)' .
```

`F1`, the own-code floor, and `F1b`, every variable floor, policy pin and range.
SKILL.md step 1 settles each `F1b` line. Empty `F1b` output = nothing to check.

```sh
# F1: every own-code floor carries a three-dot max. Empty output = pass. Lists a bare floor (3.10, 3.10 FATAL_ERROR,
# upper case, a space before the paren) and a two-dot 3.15..4.3. A split or variable floor is not seen: F1b lists those.
grep -rniE --include='CMakeLists.txt' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'cmake_minimum_required[[:space:]]*\([[:space:]]*VERSION[[:space:]]+[0-9]+(\.[0-9]+)*[[:space:]]*(FATAL_ERROR)?[[:space:]]*\)' \
  -e 'cmake_minimum_required[[:space:]]*\([[:space:]]*VERSION[[:space:]]+[0-9]+(\.[0-9]+)*\.\.[0-9]' .
# F1b: floors through a variable, own-code policy pins, and every existing range. A list to read, never a pass.
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'cmake_minimum_required[[:space:]]*\([[:space:]]*VERSION[[:space:]]+[$]' \
  -e 'cmake_policy[[:space:]]*\([[:space:]]*VERSION' \
  -e 'cmake_minimum_required[[:space:]]*\([[:space:]]*VERSION[[:space:]]+[0-9.]+\.\.\.[0-9]' .
```

## Standards and warnings-as-errors

`I11`, standard setters (`CMK-TGT-05`). Empty output = nothing to check. A hit whose
enclosing `if()` lacks `NOT DEFINED CMAKE_<LANG>_STANDARD` or `NOT CMAKE_<LANG>_STANDARD`
(closed by `)` or `AND`) is the finding. A `CACHE` setter without `FORCE` passes only at
policy version 3.21 or later (cmark's bare `set(CMAKE_C_STANDARD 99)` ignored
`-DCMAKE_C_STANDARD=11`, exit 0). The guard also holds `CMAKE_<LANG>_STANDARD_REQUIRED ON`
(`CMK-TGT-06`) and `CMAKE_<LANG>_EXTENSIONS OFF` (`CMK-TGT-07`).

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'set[[:space:]]*\([[:space:]]*CMAKE_CXX_STANDARD[[:space:]]' -e 'set[[:space:]]*\([[:space:]]*CMAKE_C_STANDARD[[:space:]]' .
```

`I12`, literal warnings-as-errors (`CMK-TGT-09`). Empty output = pass. A hit
outside a developer option that defaults OFF is the finding. One that sets
`CMAKE_REQUIRED_FLAGS` feeds a try-compile probe, never a target, and `/WX-`
turns the error off: both are `vacuous`. A `-Werror=<category>` hit is
`flagged-not-converted` with a `CMK-TGT-09` note, and does not hold step 4.

```sh
grep -rn --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' -e '-Werror' -e '/WX' .
```

## The flag-set check

The second half of the exit check of steps 2 and 4: a deleted
`include_directories` with nothing added passes `I2`. Record the flag set of
one source per target at the step-1 commit and after each diff, with the plan
file's configure options.

```sh
# SRCFILE = one source of target TGT. Writes flags-after.txt, and flags-before.txt the same way at the step-1 commit.
SRCFILE=src/core.c
TGT=core
cmake -S . -B build-flags --fresh "$GATE" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
jq -r --arg f "$SRCFILE" --arg t "$TGT" '[.[] | select(.file | endswith($f)) | select(.output | contains("/" + $t + ".dir/")) | .command | split(" ")[] | select(startswith("-"))] | sort | unique | .[]' \
  build-flags/compile_commands.json > flags-after.txt
diff flags-before.txt flags-after.txt
```

Empty `diff` output = pass. A `<` line is a lost flag, the finding, and a `>`
line an added one the plan file names. Run once per target when two compile one
source (a union hid openjpeg's lost `-DMUTEX_pthread`). Two `-I` spellings of
one directory are no loss once `realpath` agrees (jsoncpp).

Run it once per configuration the tree names (`-DCMAKE_BUILD_TYPE=<value>`):
the default and each value the list below prints. A dropped Debug-only
definition passed cmark's Release diff and printed `< -DCMARK_DEBUG_NODES` in Debug.

```sh
# A list to read: each configuration name is one more flag-set run.
grep -rnoiE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' \
  -e 'CONFIG:[A-Za-z]+' -e 'CMAKE_BUILD_TYPE[[:space:]]+(STREQUAL|MATCHES)[[:space:]]+"?[A-Za-z]+' -e 'CMAKE_[A-Z]+_FLAGS_[A-Z]+' .
```

A diff that moves a linker flag (an `I3` `_LINKER_FLAGS` hit, `LINK_FLAGS`,
`target_link_options`) also compares the target's link line. A `<` line the
plan file does not name as compile-only is the finding: cmark's Asan link line
lost `-fsanitize=address` while the flag-set diff printed nothing.

```sh
# Ninja, TGT as above. Writes link-after.txt, link-before.txt the same way at the step-1 commit. Empty output = pass.
ninja -C build-flags -t commands "$TGT" | tail -1 | tr ' ' '\n' | grep -e '^-' | sort -u > link-after.txt
diff link-before.txt link-after.txt
```

## The configured-file check

The last part of step 1's exit check. Raising `<max>` sets newer policies
`NEW`, which can change what `configure_file()` writes or which tests exist.
Configure the step-0 commit and the floor diff on the newest CI line, ungated,
into two build directories. List the configured outputs first:

```sh
# The configure_file() calls, any case. A list to read: each output path goes into CONFIGURED.
grep -rni --include='CMakeLists.txt' --include='*.cmake' --exclude-dir='_deps' --exclude-dir='build*' -e 'configure_file' .
```

```sh
# CONFIGURED = the configured outputs, relative to the build dir. Empty output = pass.
CONFIGURED='libopenjp2.pc src/lib/openjp2/opj_config.h'
for f in $CONFIGURED; do diff "build-step0/$f" "build-step1/$f"; done
# The test names of the same two build dirs. Empty output = pass. A lost test is the finding.
ctest --test-dir build-step0 -N | grep -e 'Test *#' > tests-step0.txt
ctest --test-dir build-step1 -N | grep -e 'Test *#' > tests-step1.txt
diff tests-step0.txt tests-step1.txt
```

A printed line is the finding, repaired in the floor's second diff: openjpeg's
CMP0219 `.pc` wrote `libdir=\/lib64` (4.4.2), and cmark's CMP0148 dropped 9 tests
to 2 (`CMK-DEP-19`, both lines). Raw `ctest -N` names each build directory, so
only the test names are compared.

## The variable-existence check

Run the `CMK-LANG-11` lookup block in `cmake-build/language.md` with the pinned
binary for every `CMAKE_*` name a diff introduces. It expands `<LANG>` and
`<CONFIG>` first. A count of 0 is an invented name, the finding, and 1 is a
documented name: `CMAKE_CXX_STANDARD_EXTENSIONS` reads 0 and `CMAKE_CXX_FLAGS`
reads 1 (3.31.12 and 4.4.2).
