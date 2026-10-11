---
title: Quoting, Parsing, Scopes and the Cache
summary: The CMK-LANG family. How if() reads an operand, how a list survives a loop or a call, how a command parses its arguments, which scope a returned value lands in, and how a cache entry, an option() and a -D interact
---

# Quoting, Parsing, Scopes and the Cache

Owns the CMake language itself: how `if()` reads an operand, how a list survives
`foreach()` or a call, how `cmake_parse_arguments` is spelled, which scope a
returned value lands in, and how a cache entry, an `option()` and a `-D` interact.
The floor, `cmake_policy(SET … OLD)` and the configure gate are `CMK-VER` and
`CMK-CORE`, in `versions-and-policies.md` and the index. A module's single
top-level parse, policy pin and `<Name>_ROOT` hand-off are `CMK-MOD`, in
`module-authoring.md`. Injecting a policy default into a third-party dependency
is `CMK-DEP`, in `dependencies.md`.

Written for a 3.25 floor, `cmake_minimum_required(VERSION 3.25...4.4)`
(**pinned**, an adopter overrides it once). Measured 2026-09-26 on CMake 3.31.12,
4.3.4 and 4.4.2. Every command runs from the repository root. In a tree that
holds build directories or copied modules, add `--exclude-dir='build*'
--exclude-dir='_deps'` to each `grep -r`, or every copy repeats every hit.
Severity cells name who is bound: **all** (anyone writing `CMakeLists.txt` or
`*.cmake`), **MOD** (a module author) or **LIB** (a library whose commands other
projects call).

Contents: [Greps Over if() and foreach()](#greps-over-if-and-foreach) · [Reading Each cmake_parse_arguments](#reading-each-cmake_parse_arguments) ·
[Reading Each macro()](#reading-each-macro) · [Reading a return() Hand-off](#reading-a-return-hand-off) ·
[Options and Cache Writes](#options-and-cache-writes) · [What Agents Get Wrong Here](#what-agents-get-wrong-here)

## Greps Over if() and foreach()

Run the LANG-01 and LANG-02 blocks on every change. Empty output from both is the
pass. No configure catches either defect: both configure cleanly on every line.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-LANG-01 | Quote every `${…}` operand of an `if()`, `elseif()` or `while()` comparison: `if("${X}" STREQUAL "y")`. For truthiness, name the variable bare: `if(X)`. | `if()` looks an unquoted operand's value up again as a variable name, on either side of the operator and for the numeric operators too. After `set(A B)` and `set(B x)`, `if(${A} STREQUAL "x")` is TRUE. An empty value turns into a hard syntax error. CMP0054, removed in 4.0, only ever covered quoted operands, so "CMP0054 made this safe" is false on 4.4.2. | The LANG-01 block below. Empty output passes. It reads single lines, so a condition split across lines needs a read. A composed name such as `if(${pkg}_FOUND)` does not match, by design. | **MUST** (all). Floor: any CMake |
| CMK-LANG-02 | Iterate with `foreach(x IN LISTS var)` or `foreach(x IN ITEMS …)`, never bare `foreach(x ${var})`. In a macro, copy first: `set(args "${ARGN}")`, then `foreach(x IN LISTS args)`. | An unquoted list expansion drops empty elements. `a;;b` iterates twice, not three times, and a macro called as `mac(a "" b)` sees two arguments. | The LANG-02 block below, over the files the change touches, untracked files included and deleted files skipped. Set `BASE_REF` to the branch the change merges into. Empty output passes. | **MUST** (all) on lines written or touched. Untouched legacy loops are a `cmake-modernize` step, never a gate failure. Floor: 3.0 |
| CMK-LANG-03 | Pass configuration-dependent text only to a consumer that evaluates generator expressions: target properties, `add_custom_command`, `install()` or `file(GENERATE)`. Never to `message()`, `if()`, `string()` or `file(WRITE)`. | `$<…>` is evaluated at generate time. At configure time it is still literal text: `message(STATUS "$<CONFIG>")` prints `$<CONFIG>`. | `grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'message[[:space:]]*\(.*\$<' -e 'string[[:space:]]*\(.*\$<' -e 'file[[:space:]]*\([[:space:]]*WRITE.*\$<' -e '^[[:space:]]*(else)?if[[:space:]]*\(.*\$<' .` A hit is the finding unless the text is meant to reach a later `file(GENERATE)` input. Empty output passes. | SHOULD (all). Floor: any |

```sh
# CMK-LANG-01: V is a bare left operand, W a bare right operand of EQUAL, LESS or GREATER
V='\$\{[A-Za-z_][A-Za-z0-9_]*\}[[:space:]]+'
W='[[:space:]]+\$\{[A-Za-z_][A-Za-z0-9_]*\}[[:space:])]'
grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e "[( ]${V}STREQUAL" -e "[( ]${V}MATCHES" -e "[( ]${V}EQUAL" -e "[( ]${V}VERSION_" -e "[( ]${V}IN_LIST" -e "[( ]${V}LESS" -e "[( ]${V}GREATER" -e "[( ]${V}STRLESS" -e "[( ]${V}STRGREATER" -e "[( ]${V}PATH_EQUAL" -e "EQUAL${W}" -e "LESS${W}" -e "GREATER${W}" . | grep -e 'if[[:space:]]*(' -e 'while[[:space:]]*('

# CMK-LANG-02: bare list expansions in the loops this change touches
{ git diff --name-only --diff-filter=d "${BASE_REF:-origin/main}" -- '*.cmake' '*CMakeLists.txt'; git ls-files --others --exclude-standard -- '*.cmake' '*CMakeLists.txt'; } | xargs -r grep -nE -e 'foreach[[:space:]]*\([[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]+\$\{'
```

## Reading Each cmake_parse_arguments

`grep -rn --include='*.cmake' --include='CMakeLists.txt' -e 'cmake_parse_arguments' .`
lists every parse. Read each against the four rows, narrowed by the LANG-04 grep
and the LANG-06 awk below. A parse inside a `macro()` belongs to LANG-08.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-LANG-04 | In a `function()`, parse with `cmake_parse_arguments(PARSE_ARGV N prefix …)`, where `N` is the number of named parameters. Never forward an unquoted `${ARGN}` into the parse. When migrating an existing public command, apply the migration clause below (**pinned**). | Through unquoted `${ARGN}`, `VALUE "a;b;c"` splits into `a` plus an unparsed `b;c`, and `VALUE ""` reads exactly like a bare `VALUE`. `PARSE_ARGV` keeps the list whole. The empty value stays distinct only where CMP0174 is NEW, which is LANG-07's case. CMake's own `find_dependency()` forwards `${ARGN}` unquoted, so training text shows the lossy form. | The LANG-04 block below. Each printed line is a legacy-form parse, and one inside a `function()` is the finding. A call with `PARSE_ARGV` on its next line prints too, so read it. Empty output passes. | **MUST** for a new public command (LIB, MOD). Migrating an existing public command: **MUST** with the flatten line, or with a changelog entry naming the behaviour change. SHOULD for a private helper. Floor: CMake 3.7 |
| CMK-LANG-05 | Never write `cmake_parse_arguments(PARSE_ARGN …)` unless `cmake_minimum_required` is 4.4 or higher. Below 4.4, write `PARSE_ARGV <number of named parameters>`. | On 3.31.12 and 4.3.4 the call is read as the legacy form with the prefix `PARSE_ARGN`. It exits 0, leaves every keyword variable unset and prints nothing. The current docs mark it 4.4, but an agent copying the signature never sees an error, only an empty parse. | `grep -rn --include='*.cmake' --include='CMakeLists.txt' -e 'PARSE_ARGN' .` then `grep -rn --include='CMakeLists.txt' -e 'cmake_minimum_required' .` A `PARSE_ARGN` hit in a tree whose floor is below 4.4 is the finding. Empty first output passes. | **MUST** (all). Floor: the rule exists because of CMake 4.4 |
| CMK-LANG-06 | After a full parse in a public command, read `<prefix>_UNPARSED_ARGUMENTS` and stop with `FATAL_ERROR` naming them. Use the same prefix in the parse, the condition and the message. | A misspelled keyword, or a value the `${ARGN}` form split, is absorbed without a word. Qt and Hunter each ship a module that parses one prefix and prints another's `_UNPARSED_ARGUMENTS`, so the guard fires and the message comes out empty. | The LANG-06 awk below. Empty output passes. A "never read" line is the finding unless the function deliberately parses one keyword and forwards the rest to another parser. A "message reads" line is the finding unless it is a nested sub-parse. | **MUST** for a public command (LIB, MOD), SHOULD for a private helper. Floor: any |
| CMK-LANG-07 | When an optional one-value keyword may legitimately be empty, test it with `if(DEFINED <prefix>_<KW>)` only where CMP0174 is NEW, and there also check that `<prefix>_KEYWORDS_MISSING_VALUES` does not name the keyword. Below that, treat an empty value as absent. | Without CMP0174 NEW, `VALUE ""` and an omitted `VALUE` both leave the variable unset with an empty `KEYWORDS_MISSING_VALUES`, so nothing tells them apart. Under NEW a bare `VALUE` is also defined and empty, and only the missing-values list rejects it. The 3.25 floor predates CMP0174. Example, not a rule: a module may opt in with `if(POLICY CMP0174)` and `cmake_policy(SET CMP0174 NEW)` inside its pin. | Reading heuristic. For each `grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'DEFINED[[:space:]]+[A-Za-z_]+_[A-Z][A-Z0-9_]*[[:space:]]*\)' .` hit that tests a parse result, confirm the floor is 3.31 or later, or that CMP0174 is set NEW in the pin. Empty output passes. | SHOULD (MOD, LIB). Floor: CMP0174 needs 3.31, `KEYWORDS_MISSING_VALUES` 3.15 |

**CMK-LANG-04 migration clause (pinned).** Migrating an existing public command
from `${ARGN}` changes what its callers get (measured identically on 3.31.12,
4.3.4 and 4.4.2). A quoted list (`"${SRCS}"`, `"a;b"`) given to a multi-value
keyword arrives as one element with an escaped `;`, and an unquoted forward
passes it on as one argument. A quoted list given to a one-value keyword now
arrives whole. For each multi-value keyword whose values are lists of files,
targets or paths, add the flatten line `set(arg_SOURCES ${arg_SOURCES})` (your
prefix and keyword) directly after the parse. That keeps the old splitting.

```sh
# CMK-LANG-04: legacy-form parses
grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'cmake_parse_arguments[[:space:]]*\(' . | grep -v -e 'PARSE_ARGV' -e 'PARSE_ARGN'

# CMK-LANG-06: parses whose _UNPARSED_ARGUMENTS is never read, or read under another prefix
grep -rl --include='*.cmake' --include='CMakeLists.txt' -e 'cmake_parse_arguments' . | xargs -r awk '
function flush() { if (p != "") print f ":" ln ": " p "_UNPARSED_ARGUMENTS never read"; p = "" }
function prefix(s,   t) { split(s, t, /[[:space:]()"]+/); if (t[1] == "") return ""; if (t[1] == "PARSE_ARGV") return t[3]; if (t[1] == "PARSE_ARGN") return t[2]; return t[1] }
FNR == 1 { flush(); q = ""; want = 0 }
/^[[:space:]]*(end)?(function|macro)[[:space:]]*\(/ { flush(); q = ""; want = 0 }
want && NF { p = prefix($0); q = p; want = 0; next }
/cmake_parse_arguments[[:space:]]*\(/ { flush(); s = $0; sub(/.*cmake_parse_arguments[[:space:]]*\([[:space:]]*/, "", s); f = FILENAME; ln = FNR; p = prefix(s); q = p; if (p == "") want = 1; next }
p != "" && (index($0, p "_UNPARSED_ARGUMENTS") || index($0, "(" p ")")) { p = "" }
q != "" && match($0, /\$\{[A-Za-z0-9_]+_UNPARSED_ARGUMENTS\}/) { u = substr($0, RSTART + 2, RLENGTH - 3); if (u != q "_UNPARSED_ARGUMENTS") print FILENAME ":" FNR ": message reads " u ", parse prefix is " q }
END { flush() }'
```

```cmake
# wrong: "a;b" splits, and a misspelled keyword is absorbed silently
function(mylib_add name)
    cmake_parse_arguments(arg "" "DEST" "SOURCES" ${ARGN})
endfunction()

# right
function(mylib_add name)
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "DEST" "SOURCES")
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "unknown arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif()
    set(arg_SOURCES ${arg_SOURCES}) # only when migrating an existing public command
endfunction()
```

## Reading Each macro()

`grep -rnE -B1 --include='*.cmake' --include='CMakeLists.txt' -e '^[[:space:]]*macro[[:space:]]*\(' .`
prints every macro with the line above it. Read each against both rows.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-LANG-08 | Define commands with `function()`. Use `macro()` only when the body must act in the caller's scope, either `return()` from the including file (the `find_dependency()` idiom) or writing a caller-named variable, and put a comment above the `macro(` line that says which. | A macro cannot use `PARSE_ARGV` (hard error: `ARGC='' that is not an unsigned integer`), so it is stuck with the lossy `${ARGN}` parse. Its `foreach(${ARGN})` drops empty arguments, and its `return()` leaves the caller. | Reading heuristic. Every line the section's grep prints needs a comment on the line above naming the caller-scope need. Empty output passes. | SHOULD (all). Floor: any |
| CMK-LANG-09 | Write `set(… PARENT_SCOPE)` inside a `macro()` only in a private macro whose every call site sits inside a function, where it writes that function's outputs. Never call such a macro from directory scope and from a function both. | A macro has no scope of its own, so `PARENT_SCOPE` lands one scope above whatever contains the call. Inside a function it skips that function and lands in its caller. At directory scope it lands in the parent directory. CMake's `CheckIPOSupported` module is the sanctioned shape. | The LANG-09 awk below prints each macro line that writes `PARENT_SCOPE`. Read every call site of that macro. Mixed depths are the finding. Empty output passes. | SHOULD (MOD). Floor: any |

```sh
# CMK-LANG-09: PARENT_SCOPE writes inside a macro body
grep -rl --include='*.cmake' --include='CMakeLists.txt' -e 'PARENT_SCOPE' . | xargs -r awk 'FNR==1{m=0} /^[[:space:]]*macro[[:space:]]*\(/{m=1} /^[[:space:]]*endmacro[[:space:]]*\(/{m=0} m && /PARENT_SCOPE/{print FILENAME":"FNR}'
```

## Reading a return() Hand-off

Run the LANG-10 awk on the top-level `CMakeLists.txt`. An `include()`d file
shares its includer's scope, so read it the same way.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-LANG-10 | Call `return(PROPAGATE …)` only inside a `function()`, or in a listfile that has a parent scope. Never call it inside a bare `block()` in a project's top-level `CMakeLists.txt`. In a chain of helpers, each function relays its own hop. | In a top-level `block()` the propagate fails with only a warning ("current scope has no parent", `(dev)` on 3.31.12 and 4.3.4, `(author)` on 4.4.2), configure exits 0, and the `return()` still exits the file, so the rest of the top-level listfile is silently skipped. `PARENT_SCOPE` and `return(PROPAGATE)` each move a value one hop only. | `awk '/^[[:space:]]*function[[:space:]]*\(/{d++} /^[[:space:]]*endfunction[[:space:]]*\(/{d--} d==0 && /return[[:space:]]*\([[:space:]]*PROPAGATE/{print FILENAME":"FNR}' CMakeLists.txt` Each line printed is the finding, except a commented-out call. Empty output passes. `cannot open file` means no top-level `CMakeLists.txt`, as in a project generator whose listfiles are templates, and the rule does not apply there. | **MUST** (all). Floor: CMake 3.25 (`block()`, `return(PROPAGATE)`, CMP0140) |

## Options and Cache Writes

Chasing "my `-D` did not take"? Read LANG-14 first, then LANG-13, then LANG-15.
Each grep runs over the whole tree. Empty output passes each one.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-LANG-11 | Never declare an option, cache entry or variable of your own whose name begins with `CMAKE_` or `_CMAKE_` (in any case), or with `_` followed by a CMake command name. Setting a variable CMake documents (`CMAKE_CXX_STANDARD`) is fine. Inventing one in that namespace is not. | `cmake-language(7)` reserves these names. A subproject's `option(CMAKE_UNITY_BUILD … ON)` does not override a consumer's `-D`. It leaks instead: the cache entry is global, so the setting switches on for the parent project that pulled the subproject in. | `grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e '^[[:space:]]*option[[:space:]]*\([[:space:]]*"?[Cc][Mm][Aa][Kk][Ee]_' -e '^[[:space:]]*option[[:space:]]*\([[:space:]]*"?_[Cc][Mm][Aa][Kk][Ee]_' .` Empty output passes. For each `CMAKE_` name a change sets or caches, run the LANG-11 lookup below with the binary the project builds with. A count of 0 is an invented name (the finding). CMake's own repository is the one exception. | **MUST** (all). Floor: any |
| CMK-LANG-12 | Prefix every `option()` and user-facing cache entry with the project's name. In a monorepo, use each sub-project's own prefix, and check per sub-project. | The cache is global. An unprefixed `BUILD_TESTS` collides with every project that pulls this one in with `add_subdirectory()` or FetchContent. A repo-wide single-prefix check misfires on legitimate sub-project prefixes. | Reading heuristic, once per sub-project: `SUBPROJECT_DIR=libs/core; grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e '^[[:space:]]*option[[:space:]]*\(' "$SUBPROJECT_DIR"` A name without that sub-project's prefix is the finding, and a verb prefix such as `ENABLE_` counts as unprefixed. Empty output passes. | SHOULD (LIB, and any project consumed as a subproject). Floor: any |
| CMK-LANG-13 | Never add `FORCE` to a cache entry a user is meant to set (an `option()`, a documented knob). Write computed results as `CACHE INTERNAL`, which already implies `FORCE`, or as normal variables. To make a changed default reach an existing build tree, say "reconfigure with `--fresh`". | Without `FORCE`, a cache write never updates an existing entry, and `CACHE INTERNAL` overwrites on every configure. A `FORCE` on a knob discards the user's `-D` on every configure. The one sanctioned `FORCE` hand-off is CMK-MOD-12's `<Name>_ROOT` (module-authoring). `CMAKE_TOOLCHAIN_FILE` is never forced (CMK-TC-01, toolchains-and-providers). | `grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'CACHE[[:space:]]+[A-Z]+[^)]*FORCE' .` Reading heuristic: a hit whose name is a documented option or knob is the finding. Single-line. Empty output passes. | SHOULD (all). Floor: any |
| CMK-LANG-14 | In the project that declares an `option()` or cache knob, never `set()` a normal variable of the same name. Read the cache explicitly with `$CACHE{X}` where a normal variable may shadow it. | A later plain `set()` wins every read in that scope and leaves the cache entry untouched: the classic "my `-D` did not take". Under CMP0126 NEW a normal variable also survives a `set(… CACHE)` of the same name. The one sanctioned exception is a parent pre-seeding a child's option before `add_subdirectory` under CMP0077, with set/restore (CMK-DEP-15, dependencies). | The LANG-14 loop below. Each printed line is the finding unless it is that parent-to-child pre-seed. Empty output passes. | SHOULD (all). Floor: `$CACHE{}` 3.13, CMP0126 3.21 |
| CMK-LANG-15 | Test an `option()` variable by truthiness, `if(X)`. Never compare it to `"ON"` or `"OFF"`. | `option()` claims the `BOOL` type but never coerces the value. After `-DX=yes` the cache holds `yes`, so `STREQUAL "ON"` misreads a true value. | `grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e 'STREQUAL[[:space:]]*"ON"' -e 'STREQUAL[[:space:]]*"OFF"' -e 'STREQUAL[[:space:]]+ON[[:space:])]' -e 'STREQUAL[[:space:]]+OFF[[:space:])]' .` A hit on an `option()`-declared name is the finding. Empty output passes. | SHOULD (all). Floor: any |

```sh
# CMK-LANG-11 lookup: expand <LANG> and <CONFIG> first, or CMAKE_CXX_FLAGS reads as invented. Keep only patterns that start with CMAKE_, or <PROJECT-NAME>_VERSION reads CMAKE_MYLIB_VERSION as documented.
# Count 0 = invented, 1 = documented. Another language needs its own sed line.
NAME=CMAKE_MY_KNOB
D=build/varcheck
mkdir -p "$D"
cmake --help-variable-list > "$D/vars.txt"
sed -e 's/<LANG>/C/g' "$D/vars.txt" > "$D/c.txt"
sed -e 's/<LANG>/CXX/g' "$D/vars.txt" > "$D/cxx.txt"
sed -e 's/<CONFIG>/[A-Z]+/g' -e 's/<[^>]*>/[A-Za-z0-9_]+/g' "$D/c.txt" "$D/cxx.txt" > "$D/all.txt"
grep -e '^CMAKE_' -e '^_CMAKE_' "$D/all.txt" > "$D/patterns.txt"
printf '%s\n' "$NAME" > "$D/name.txt"
grep -rcxE --include='name.txt' -f "$D/patterns.txt" "$D"

# CMK-LANG-14: a plain set() of a name the tree declares with option()
grep -rhoE --include='*.cmake' --include='CMakeLists.txt' -e '^[[:space:]]*option[[:space:]]*\([[:space:]]*[A-Za-z0-9_]+' . | sed -E 's/.*\([[:space:]]*//' | sort -u | while read -r NAME; do grep -rnE --include='*.cmake' --include='CMakeLists.txt' -e "^[[:space:]]*set[[:space:]]*\([[:space:]]*${NAME}[[:space:]]" . | grep -v -e 'CACHE' -e 'PARENT_SCOPE'; done
```

```cmake
# wrong: FORCE discards -D every configure, the plain set() shadows the cache, "yes" is not "ON"
option(MYLIB_TESTS "Build the tests" ON)
set(MYLIB_TESTS ON CACHE BOOL "Build the tests" FORCE)
set(MYLIB_TESTS OFF)
if(MYLIB_TESTS STREQUAL "ON")
endif()

# right: declare once, read by truthiness, write computed results INTERNAL
option(MYLIB_TESTS "Build the tests" ON)
if(MYLIB_TESTS)
endif()
set(MYLIB_HAVE_FOO 1 CACHE INTERNAL "computed by a configure check")
```

## What Agents Get Wrong Here

1. **Writing `if(${X} STREQUAL "y")` because "CMP0054 made this safe".** It
   covered quoted operands only. `CMK-LANG-01`.
2. **Writing bare `foreach(x ${list})`**, the majority idiom in large legacy
   trees and so in training text. It drops empty elements. `CMK-LANG-02`.
3. **Copying the `${ARGN}` parse** that CMake's own `find_dependency()` uses, or
   migrating to `PARSE_ARGV` without the flatten line, which silently changes
   every caller that passed a quoted list. `CMK-LANG-04`.
4. **Writing `PARSE_ARGN` from the current docs below a 4.4 floor.** It parses
   nothing on 3.31 and 4.3, silently. `CMK-LANG-05`.
5. **"The cache write needs `FORCE`."** Either `FORCE` lands on a user knob and
   breaks `-D`, or a missing `FORCE` is reported against `CACHE INTERNAL`, which
   already implies it. `CMK-LANG-13`.
6. **Skipping the `_UNPARSED_ARGUMENTS` check, or printing another prefix's
   variable in it.** `CMK-LANG-06`.
7. **Printing or comparing `$<CONFIG>` at configure time.** `CMK-LANG-03`.
8. **Putting `PARENT_SCOPE` in a macro "to return a value"** and calling it from
   a function, so the value skips that function. `CMK-LANG-09`.
9. **Using `return(PROPAGATE)` as a clean early exit at the top level**, which
   truncates the rest of the file with only a warning. `CMK-LANG-10`.
10. **Writing `cmake_policy(SET CMP0054 OLD)`.** A hard error from 4.0 on
    (measured on 4.3.4 and 4.4.2), a warning on 3.31.12. CMK-VER-07 owns it.
11. **Inventing a `CMAKE_*` option, or comparing an option to `"ON"`.**
    `CMK-LANG-11`, `CMK-LANG-15`.

Re-check: on each CMake minor release after 4.4 (D1), re-run the `PARSE_ARGN`,
CMP0174 and top-level `return(PROPAGATE)` behaviour behind LANG-05, LANG-07 and
LANG-10, and the placeholder forms behind the LANG-11 lookup.
