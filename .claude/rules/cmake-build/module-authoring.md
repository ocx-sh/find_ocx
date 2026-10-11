---
title: Shipping a Reusable CMake Module
summary: The CMK-MOD family, the contract a .cmake file that other projects include keeps. Downloads and processes that fail loudly and are bounded, policies pinned around every definition, the Find-module contract, configure-time state and secrets, the find_package hand-off, script mode, and gersemi setup for the module's own commands
---

# Shipping a Reusable CMake Module

CMK-MOD owns what a `.cmake` file that other projects include must guarantee: a
Find module, a helper module, a copy-and-own bootstrap module, a dependency-provider
file, and anything that downloads or runs a process at configure time. It does not
own testing that module (negative tests, the gate on inner configures, a CI leg per
claimed CMake line), which is `CMK-TEST` in `testing.md`. The function signature and
`PARSE_ARGV` correctness are `CMK-LANG` in `language.md`. Consuming a helper such as
CPM from the caller's side, `<Pkg>_DIR` stickiness and hint precedence under a root
path are `CMK-DEP` in `dependencies.md`. Find-root modes in a toolchain are `CMK-TC`
in `toolchains-and-providers.md`. The configure gate, the `gersemi --check` gate line
and the `pipefail` trap are `CMK-CORE` in the index.

Every command reads a variable with a stated default instead of a placeholder:
`MODULE_DIR` (the module sources, default `.`), `CI_DIR` (default `.github`),
`DOC_DIR` (default `.`), `ROOT` (the consuming build, default `.`). The default
`.` fits the download and process rows (CMK-MOD-01 to -04 and -17 to -19), which bind
any configure-time file. For every other row, `MODULE_DIR` is the subtree the project
installs or documents for others to `include()`. A project that ships none, such as
cpp-best-practices/cmake_template with its own `cmake/*.cmake` helpers, owes none of
them: its 20 CMK-MOD-05 lines at `.` were all internal (2026-09-26). Every grep
excludes `build*` directories, because configured test fixtures carry copies of the
module. **pinned**: rules are written for a CMake 3.25 floor
(`cmake_minimum_required(VERSION 3.25...4.4)`), which is what makes CMK-MOD-03 and
CMK-MOD-19 apply. An adopter whose floor and every policy pin are 3.31 or later
overrides that once, repository-wide. Measured on 3.31.12, 4.3.4 and 4.4.2 on
2026-09-26 unless a row says otherwise.

Contents: [Calls That Fail Open](#calls-that-fail-open-downloads-and-processes) · [How the Module Loads](#how-the-module-loads-policies-and-duplicate-copies) · [Find Modules](#find-modules) ·
[Configure-Time State and the Hand-off](#configure-time-state-secrets-and-the-find_package-hand-off) · [Script Mode](#script-mode-and-the-public-surface) ·
[gersemi](#gersemi-on-the-modules-own-commands) · [What Agents Get Wrong Here](#what-agents-get-wrong-here)

## Calls That Fail Open: Downloads and Processes

Every check here is a `grep -rPzo` lookahead. `-z` reads each file as one record, so
a call spread over lines is one match, and the negative lookahead prints a call that
lacks the keyword. **Empty output passes. Each printed block is a finding.** The
patterns assume a call's arguments contain no `)`, which holds for `${}` and `$<>`.
The command name matches in any case (`FILE (DOWNLOAD` is caught), keywords only in
upper case, as CMake reads them. `file(DOWNLOAD)` and `execute_process` never stop a
configure on their own.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-MOD-01 | Check `STATUS` after every `file(DOWNLOAD)`, and stop with a module-prefixed `FATAL_ERROR` when the code is not 0. | A failed download exits 0 and, without `STATUS`, prints nothing at all. Floor: any version. | `grep -rPzo --include='*.cmake' --exclude-dir='build*' -e '(?i:file)\s*\(DOWNLOAD(?:(?!STATUS)[^)])*\)' "${MODULE_DIR:-.}"`. Empty passes. Then read that each `STATUS` capture is compared with 0. | MUST |
| CMK-MOD-02 | Give every downloaded artifact that will be executed, extracted, linked or swapped in over a live copy an `EXPECTED_HASH`, verified before it becomes active. The one exception is a documented trust root (a manifest or `SHA256SUMS` file carrying the hashes), named as such in the module header. | `EXPECTED_HASH` is the only integrity check CMake runs inside the download, and before 3.31 TLS was not verified by default. Floor: any version. | `grep -rPzo --include='*.cmake' --exclude-dir='build*' -e '(?i:file)\s*\(DOWNLOAD(?:(?!EXPECTED_HASH)(?!EXPECTED_MD5)[^)])*\)' "${MODULE_DIR:-.}"`. Empty passes. Each printed block must be a named trust root. Then trace every self-update path from its download to its `file(RENAME)`: the hash check sits between the two. | MUST |
| CMK-MOD-03 | Pass `TLS_VERIFY ON` to every `file(DOWNLOAD)` while the declared floor is below 3.31. | Verification was off by default before 3.31 and flipped without a policy. The `CMAKE_TLS_VERIFY=0` environment variable (read since 3.30) still turns it off for any download that omits the option, while an explicit `TLS_VERIFY ON` fails a bad certificate even then. Floor: any version. | Read the floor from `cmake_minimum_required` or the module's `CMAKE_VERSION` guard. Below 3.31: `grep -rPzo --include='*.cmake' --exclude-dir='build*' -e '(?i:file)\s*\(DOWNLOAD(?:(?!TLS_VERIFY)[^)])*\)' "${MODULE_DIR:-.}"`. Empty passes. | MUST below a 3.31 floor (the pinned floor is 3.25). At 3.31 or later, keep it as defence against the environment override |
| CMK-MOD-04 | Make every `execute_process` fail loudly: test its `RESULT_VARIABLE` or `RESULTS_VARIABLE`, or pass `COMMAND_ERROR_IS_FATAL ANY`. A probe whose failure is a valid answer still captures `RESULT_VARIABLE` and says it is a probe in a comment. | An unchecked `execute_process(COMMAND false)` lets the configure run to the end. On 4.0 and later an includer's `CMAKE_EXECUTE_PROCESS_COMMAND_ERROR_IS_FATAL ANY` halts a probe that captures no result (measured on 4.3.4 and 4.4.2). Floor: `COMMAND_ERROR_IS_FATAL` needs 3.19, `RESULT_VARIABLE` any version. | `grep -rPzo --include='*.cmake' --exclude-dir='build*' -e '(?i:execute_process)\s*\((?:(?!RESULTS?_VARIABLE)(?!COMMAND_ERROR_IS_FATAL)[^)])*\)' "${MODULE_DIR:-.}"`. Empty passes, probes included. Then read that each captured result is tested or carries the probe comment. | MUST |
| CMK-MOD-17 | Give every network download a finite `TIMEOUT` or `INACTIVITY_TIMEOUT`: each `file(DOWNLOAD)`, and each `FetchContent_Declare` or `ExternalProject_Add` that fetches by `URL`. Size it for the retries: through FetchContent or ExternalProject a timed-out download is attempted six times, about 6 × T + 85 s in the worst case. Prefer `INACTIVITY_TIMEOUT` for a large artifact. | With neither option a server that accepts and never answers holds the configure until it is killed. A timeout returns status 28 and the configure carries on, so CMK-MOD-01 is still what stops it. The `URL_HASH` on a declare is CMK-DEP-03 in `dependencies.md`. Floor: any version for `file(DOWNLOAD)`, 3.19 for `ExternalProject_Add`'s `INACTIVITY_TIMEOUT`. | Three commands, each empty on a pass: `grep -rPzo --include='*.cmake' --exclude-dir='build*' -e '(?i:file)\s*\(DOWNLOAD(?:(?!TIMEOUT)[^)])*\)' "${MODULE_DIR:-.}"`, `grep -rPzo --include='*.cmake' --exclude-dir='build*' -e '(?i:FetchContent_Declare)\s*\((?=[^)]*\sURL\s)(?:(?!TIMEOUT)[^)])*\)' "${MODULE_DIR:-.}"`, `grep -rPzo --include='*.cmake' --exclude-dir='build*' -e '(?i:ExternalProject_Add)\s*\((?=[^)]*\sURL\s)(?:(?!TIMEOUT)[^)])*\)' "${MODULE_DIR:-.}"`. The lookahead accepts `INACTIVITY_TIMEOUT`, and `\sURL\s` skips `GIT_REPOSITORY ${URL}`. | MUST |
| CMK-MOD-18 | Never count on `TIMEOUT` or `INACTIVITY_TIMEOUT` to bound a `GIT_REPOSITORY` fetch. Bound git with `GIT_HTTP_LOW_SPEED_LIMIT` and `GIT_HTTP_LOW_SPEED_TIME` in CI, or fetch a hashed `URL` archive. A module that sets them itself does so only when `ENV{GIT_HTTP_LOW_SPEED_LIMIT}` is undefined, and says so in its header. | `gitclone.cmake.in` reads neither keyword, so a git fetch carrying both still hangs, and the git variables end it after three 5 s attempts. They bound HTTP(S) only. 4.4 adds `CMAKE_EP_GIT_CLONE_RETRY_COUNT` (default 2 retries, still 3 attempts). Floor: any version. | `grep -rPzo --include='*.cmake' --exclude-dir='build*' -e '\((?=[^)]*GIT_REPOSITORY)(?=[^)]*TIMEOUT)[^)]*\)' "${MODULE_DIR:-.}"`: empty passes, each block is a finding. Then `grep -rn --exclude-dir='build*' -e 'GIT_REPOSITORY' -e 'GIT_HTTP_LOW_SPEED' "${MODULE_DIR:-.}" "${CI_DIR:-.github}"`: the two patterns are a union, so `GIT_REPOSITORY` hits with no `GIT_HTTP_LOW_SPEED` hit anywhere are the finding. | SHOULD |
| CMK-MOD-19 | Pass `ENCODING UTF-8` to every `execute_process` that captures `OUTPUT_VARIABLE` or `ERROR_VARIABLE` while the floor or the policy pin is below 3.31. | Below policy version 3.31, CMP0176 decodes captured output as `AUTO` (the Windows console or ANSI code page) and never warns. A CMK-MOD-05 pin at 3.25 puts every pinned function on that default even under 4.4.2. `ENCODING` is ignored off Windows, so it costs nothing there. Read-only on Windows: the mis-decoding is documented (CMP0176, CMake issue 26262), not measured. Floor: `ENCODING` needs 3.8, its `UTF-8` value 3.11. | Read the floor and the pin. At 3.31 or later the rule does not apply. Otherwise `grep -rPzo --include='*.cmake' --exclude-dir='build*' -e '(?i:execute_process)\s*\((?=[^)]*(?<!RESULT)(?<!RESULTS)_VARIABLE)(?:(?!ENCODING)[^)])*\)' "${MODULE_DIR:-.}"`. Empty passes. `RESULT_VARIABLE` alone does not trigger it. | MUST below a 3.31 floor or pin |

```cmake
# wrong: fails open, unhashed, unverified TLS before 3.31, no bound on a stall
file(DOWNLOAD "${url}" "${dest}")

# right
file(
    DOWNLOAD "${url}"
    "${dest}"
    EXPECTED_HASH SHA256=${sha256}
    TLS_VERIFY ON
    INACTIVITY_TIMEOUT 60
    STATUS status
)
list(GET status 0 code)
if(NOT code EQUAL 0)
    message(FATAL_ERROR "mymodule: download of ${url} failed: ${status}")
endif()
```

## How the Module Loads: Policies and Duplicate Copies

The awk command below checks CMK-MOD-05 on every module file. **Empty output passes.**
It accepts either pin form, indented or upper-case definitions, and reports a
definition before the pin opens, after it closes, or with no pin at all.

```sh
find "${MODULE_DIR:-.}" -name '*.cmake' -not -path '*/build*/*' -print0 | xargs -0 -r -n1 awk '{l=tolower($0)} l~/cmake_policy\(push\)/{if(!open)open=NR} l~/^[[:space:]]*block\(scope_for[^)]*policies/{if(!open)open=NR} l~/^[[:space:]]*block\(\)/{if(!open)open=NR} l~/cmake_policy\(pop\)/{shut=NR} l~/^[[:space:]]*endblock\(/{shut=NR} l~/^[[:space:]]*function\(/{if(!first)first=NR; last=NR} l~/^[[:space:]]*macro\(/{if(!first)first=NR; last=NR} END{if(first && !open) print FILENAME": definition at "first" with no policy pin"; else if(first && first<open) print FILENAME": definition at "first" before the pin opens at "open; else if(last>shut) print FILENAME": definition at "last" after the pin closes at "shut}'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-MOD-05 | Put every `function()` and `macro()` a module defines inside its policy pin: `cmake_policy(PUSH)` and `cmake_policy(VERSION 3.25)` before the first definition and `cmake_policy(POP)` after the last, or `block(SCOPE_FOR POLICIES)` … `endblock()` (CMake ≥ 3.25). The one exception is a helper that runs the caller's own code (`cmake_language(EVAL)`, a forwarded `find_package`) under the caller's policies. It sits after the pin with a comment saying why, as Kitware's `FetchContent.cmake` does. | A function captures policies where it is defined, so one defined after the `POP` follows the includer's policy version. `block(SCOPE_FOR POLICIES)` pins the same way, but variables set inside it still leak. Floor: PUSH/POP any version, `block` 3.25. | The awk command above. Empty passes. A printed line is the finding unless it is the commented caller-code exception. A later variables-only `block()` can hide a late definition, so read any `endblock()` the check trusts. | MUST |
| CMK-MOD-06 | Never change the includer's policy state from a module's file scope: no `set(CMAKE_POLICY_DEFAULT_CMP…)` and no `cmake_policy(SET …)` outside the pin. A module that must (CPM.cmake does, for four policies) says so in its header, and so does one that sets `ENV{GIT_HTTP_LOW_SPEED_*}` for CMK-MOD-18. | `CMAKE_POLICY_DEFAULT_CMP<NNNN>` is a plain variable, so it reaches every later `project()` and subdirectory, and no `POP` undoes it. Floor: any version. | `grep -rn --include='*.cmake' --exclude-dir='build*' -e 'CMAKE_POLICY_DEFAULT_CMP' "${MODULE_DIR:-.}"`. Empty passes. Each hit needs a header note. Then read every `cmake_policy(SET` for whether it sits inside the pin. | SHOULD |
| CMK-MOD-07 | Give a copy-and-own module one version variable, record it in a GLOBAL property on first load, and `FATAL_ERROR` when a second copy at a different path loads with a different version. | `include_guard(GLOBAL)` is keyed on the file path, so two vendored copies both run in full, the last one wins, and the log says nothing. The same variable lets a consumer check it holds the pinned copy. Floor: any version. | `grep -rl --include="${MODULE_NAME:-mymodule.cmake}" --exclude-dir='build*' -e 'include_guard' "${ROOT:-.}"`. One path or none passes. More than one means the module is vendored twice: read each copy for the version check. A bare `include_guard` is the finding. | SHOULD |

## Find Modules

Three commands check CMK-MOD-08. **Each prints nothing on a pass**, and nothing in a
tree with no `Find*.cmake` (not applicable).

```sh
# 1. Find modules that never call FPHSA: each file printed is a finding
grep -rL --include='Find*.cmake' --exclude-dir='build*' -e 'find_package_handle_standard_args' "${MODULE_DIR:-.}"
# 2. include_guard in a Find module: each hit is a finding
grep -rn --include='Find*.cmake' --exclude-dir='build*' -e 'include_guard' "${MODULE_DIR:-.}"
# 3. IMPORTED targets in a file with no NOT TARGET guard: each file printed is a finding
grep -rlZ --include='Find*.cmake' --exclude-dir='build*' -e 'IMPORTED' "${MODULE_DIR:-.}" | xargs -0 -r grep -L -e 'NOT TARGET'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-MOD-08 | In a `Find<Pkg>.cmake`, set `<Pkg>_FOUND` through `find_package_handle_standard_args`, create each imported target as `<Pkg>::<Component>` (`<Pkg>::<Pkg>` for a single library) under `if(<Pkg>_FOUND AND NOT TARGET <Pkg>::<Component>)`, and add no `include_guard`. | FPHSA is what honours QUIET, REQUIRED and version requests (the `cmake-developer(7)` contract). `find_package` reruns the module from every directory that calls it, and with `include_guard(GLOBAL)` a second `find_package(Foo REQUIRED)` from a sibling directory leaves `Foo_FOUND` empty and `Foo::Foo` invisible while the configure exits 0. Floor: any version. | The three commands above. Then read each `IMPORTED` target for its own guard, since command 3 checks the file. | MUST |
| CMK-MOD-09 | Keep a Find module off the network by default. A fetch on a miss (`FetchContent`, `ExternalProject`, `file(DOWNLOAD)`) runs only behind an option declared in the same file, defaulting to OFF and documented in its header. | Module mode is expected to search locally. ccache's `FindZstd.cmake` downloads when a `DEPS` variable declared in another file is `AUTO`, its default, so a copied file fetches by default. SHOULD because one corpus instance cannot carry a MUST. Floor: any version. | `grep -rn --include='Find*.cmake' --exclude-dir='build*' -e 'FetchContent' -e 'ExternalProject' -e 'file(DOWNLOAD' "${MODULE_DIR:-.}"`. Empty passes. A hit passes only when the same file declares the default-OFF option gating it. | SHOULD |

## Configure-Time State, Secrets and the find_package Hand-off

CMK-MOD-11 is a configure experiment. The gate on its configure is `-Werror=author`
on CMake ≥ 4.4 and `-Werror=dev` on ≤ 4.3 (or run it through the leg's `--preset`).
Name the dummy under every credential variable the module reads.

```sh
# CMK-MOD-11: empty grep output passes, a hit is the finding
DUMMY_SECRET=sk-dummy-4b1d
BUILD_DIR=build-secret
GATE=-Werror=author # -Werror=dev on CMake 4.3 or older (CMK-CORE-01)
MYMOD_AUTH_TOKEN="$DUMMY_SECRET" cmake -S . -B "$BUILD_DIR" "$GATE"
grep -rn --include='CMakeCache.txt' -e "$DUMMY_SECRET" "$BUILD_DIR"
# CMK-MOD-12: a _ROOT write without FORCE, each block printed is a finding
grep -rPzo --include='*.cmake' --exclude-dir='build*' -e '\b(?i:set)\(\s*[^\s)]*_ROOT\s(?:(?!FORCE)[^)])*\)' "${MODULE_DIR:-.}"
# CMK-MOD-12: a file that caches a _ROOT but never unsets a _DIR, each file printed is a finding
grep -rlZzP --include='*.cmake' --exclude-dir='build*' -e '\b(?i:set)\(\s*[^\s)]*_ROOT\s[^)]*CACHE' "${MODULE_DIR:-.}" | xargs -0 -r grep -L -e '_DIR CACHE'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-MOD-10 | Register every project file the module reads at configure time with `set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS …)`, never with a variable of that name, and document that a watched file created after the first configure needs a manual reconfigure. | An unregistered file is never reread. `list(APPEND CMAKE_CONFIGURE_DEPENDS …)` sets a plain variable that does nothing and warns about nothing. A watched path that did not exist at configure time triggers no rerun when it appears (measured under Ninja on 3.31.12 and 4.4.2). Floor: any version. | `grep -rni --include='*.cmake' --exclude-dir='build*' -e 'list(APPEND CMAKE_CONFIGURE_DEPENDS' -e 'set(CMAKE_CONFIGURE_DEPENDS' "${MODULE_DIR:-.}"`. Empty passes, each hit is a finding. Then read that every `file(READ`, `file(STRINGS` or `string(JSON` on a project file has a matching property append. | MUST |
| CMK-MOD-11 | Take environment variables into the cache from an allow-list, never by copying a whole namespace. Read credentials live and forward them through the child process's environment, never through `CACHE`. | A loop over a whole namespace wrote a planted `*_AUTH_TOKEN` into `CMakeCache.txt` in plain text. Floor: any version. | The configure experiment above: empty grep output passes. | MUST |
| CMK-MOD-12 | Hand off to `find_package` by setting the case-preserved `<Name>_ROOT` as `CACHE PATH … FORCE`, and `unset(<Name>_DIR CACHE)` when the value changes. Never also emit the upper-case `<NAME>_ROOT`, which is the consumer's CMP0144 opt-in. | `Foo_ROOT` alone is honoured under CMP0074, and it outranks `CMAKE_PREFIX_PATH` only while `CMAKE_FIND_ROOT_PATH` and `CMAKE_SYSROOT` are empty (CMK-DEP-21 in `dependencies.md`, CMK-TC-08 in `toolchains-and-providers.md`). A write without `FORCE` does not replace a cached entry, and a re-pointed root leaves the old `<Name>_DIR`, and the copy it found, in force (CMK-DEP-13 owns that stickiness). Floor: CMP0074 needs 3.12. | The two CMK-MOD-12 commands above, each empty on a pass. Then read each `_ROOT` write for its case: an upper-case-only root is the finding. | MUST for a module that provisions tools or packages |
| CMK-MOD-13 | Choose which binary a tool-provisioning module fetches from the host: `CMAKE_HOST_SYSTEM_NAME` for the OS and `cmake_host_system_information(RESULT … QUERY OS_PLATFORM)` for the CPU, never `CMAKE_SYSTEM_*`. | The plain variables describe the build target, so a cross build fetches a tool that cannot run. Under `cmake -P`, `CMAKE_HOST_SYSTEM_PROCESSOR` is empty while the host name and the `OS_PLATFORM` query are set. Floor: any version. | `grep -rn --include='*.cmake' --exclude-dir='build*' -e 'CMAKE_SYSTEM_NAME' -e 'CMAKE_SYSTEM_PROCESSOR' "${MODULE_DIR:-.}"`: a hit in the code that picks a binary is the finding. `grep -rn --include='*.cmake' --exclude-dir='build*' -e 'CMAKE_HOST_SYSTEM_PROCESSOR' "${MODULE_DIR:-.}"`: a hit reachable from a `cmake -P` entry point is the finding. Empty passes for both. | MUST |

```cmake
# wrong: the root moves, but find_package keeps the Foo_DIR it cached, and the old copy
set(Foo_ROOT "${prefix}" CACHE PATH "Foo prefix" FORCE)

# right
if(NOT "${prefix}" STREQUAL "${Foo_ROOT}")
    unset(Foo_DIR CACHE)
endif()
set(Foo_ROOT "${prefix}" CACHE PATH "Foo prefix" FORCE)
```

## Script Mode and the Public Surface

Both rows are greps plus a read. Running each entry point for real is CMK-TEST-05 in
`testing.md`.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-MOD-14 | For any entry point documented to run as `cmake -P`, guard on `CMAKE_SCRIPT_MODE_FILE` before calling anything that needs a project, and give it a public name, not the module's private `__` prefix. | `set_property(DIRECTORY …)` is accepted under `-P` and silently does nothing, which is the case the guard exists for. Project commands fail loudly (`add_library command is not scriptable`). A consumer-invoked function with a private-looking name hides the public surface from review. Floor: any version. | `grep -rn --include='*.md' --include='*.rst' -e 'cmake -P' "${DOC_DIR:-.}"` lists the documented entry points: check each name against the private prefix. `grep -rn --include='*.cmake' --exclude-dir='build*' -e 'CMAKE_SCRIPT_MODE_FILE' "${MODULE_DIR:-.}"` must print at least one line whenever the first did. Both empty passes. | SHOULD |
| CMK-MOD-20 | Keep `cmake_language(DEFER)` out of every path a `cmake -P` entry point can reach, and `cmake_language(EXIT)` out of every path a project configure can reach, each behind a `CMAKE_SCRIPT_MODE_FILE` guard. | `DEFER` needs a project directory and fails under `-P`, even in a file the script `include()`s. `EXIT` fails anywhere except `-P`. Both failures are loud, so the rule is about a module that works in both documented modes. Floor: `DEFER` needs 3.19, `EXIT` 3.29. | `grep -rn --include='*.cmake' --exclude-dir='build*' -e 'cmake_language(DEFER' -e 'cmake_language(EXIT' "${MODULE_DIR:-.}"`. Empty passes. Each hit must sit under a guard that excludes the wrong mode. | SHOULD |

## gersemi on the Module's Own Commands

The gate is the index's tracked-files form, `git ls-files -z -- '*CMakeLists.txt' '*.cmake' | xargs -0 -r gersemi --check` (gersemi 0.29.1, released
2026-09-14). **pinned**: gersemi is SHOULD, never MUST, and binds only a module project
that runs it, a default the adopter overrides once. The awk command below checks
CMK-MOD-16. **Empty output passes. Each printed line is a parse nested in a control
block.**

```sh
find "${MODULE_DIR:-.}" -name '*.cmake' -not -path '*/build*/*' -print0 | xargs -0 -r -n1 awk '{l=tolower($0)} l~/^[[:space:]]*function\(/{d=0} l~/^[[:space:]]*if\(/{d++} l~/^[[:space:]]*foreach\(/{d++} l~/^[[:space:]]*while\(/{d++} l~/^[[:space:]]*endif\(/{d--} l~/^[[:space:]]*endforeach\(/{d--} l~/^[[:space:]]*endwhile\(/{d--} l~/cmake_parse_arguments\(/{if(d>0) print FILENAME":"FNR": parse nested in a control block"}'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-MOD-15 | A module project that runs gersemi commits a `.gersemirc` whose `definitions` key lists every file or directory defining the project's own commands, and gates with `gersemi --check`, never `--diff`. | Without definitions gersemi leaves custom calls unformatted and prints `unknown command` warnings, and `--diff` exits 0 even when it would reformat. `.gersemirc` is the only file name gersemi discovers, so it is what makes the editor and CI format alike. Floor: gersemi 0.29.1. | The gersemi gate above. Exit 0 passes. Any `Warning: unknown command` on stderr means the `definitions` list is incomplete. | SHOULD |
| CMK-MOD-16 | Parse each command's keywords with one top-level `cmake_parse_arguments(PARSE_ARGV 0 …)` per function, split a multi-verb dispatch function into one function per verb, and put `# gersemi: hints { KEYWORD: command_line }` above the parse for each keyword that forwards argv. | gersemi 0.29.1 reads any top-level parse and none nested in an `if()`, `foreach()` or `while()`, with no warning: every token lands on its own line. Without the hint a forwarded command line is split one token per line too. The signature and the correctness case for `PARSE_ARGV` are CMK-LANG-04 in `language.md`. Floor: `PARSE_ARGV` needs 3.7, gersemi 0.29.1. | The awk command above: empty passes. Then `grep -rn --include='*.cmake' --exclude-dir='build*' -e 'gersemi: hints' "${MODULE_DIR:-.}"` lists the hints: a keyword that forwards argv with no hint is the finding. | SHOULD |

## What Agents Get Wrong Here

1. **Assuming `file(DOWNLOAD)` or `execute_process` fails the configure.** The bare
   call goes in, and `if(EXISTS …)` stands in as proof of success. CMK-MOD-01, -04.
2. **A download with no timeout.** Nearly every corpus call is a bare
   `file(DOWNLOAD … STATUS st)` or `FetchContent_Declare(… URL …)`, and a stalled
   server then holds the configure forever. CMK-MOD-17.
3. **`list(APPEND CMAKE_CONFIGURE_DEPENDS …)`.** It reads like registration and does
   nothing, with no warning. CMK-MOD-10.
4. **Believing `TLS_VERIFY` is always on, or always off.** Each belief is right for
   one side of 3.31. Read the floor, then CMK-MOD-03.
5. **Re-pointing `<Name>_ROOT` and expecting `find_package` to follow**, or emitting
   `FOO_ROOT` beside or instead of `Foo_ROOT`. The cached `_DIR` wins. CMK-MOD-12.
6. **`cmake_policy(POP)` placed before a late-added function**, often a script-mode
   helper appended at the end of the file. CMK-MOD-05.
7. **`gersemi --diff` as the CI gate, or `--check` without definitions.** The first
   exits 0, and the second's warnings get filed as "gersemi does not support this".
   CMK-MOD-15.
8. **Treating `include(CPM.cmake)` as free of side effects.** It sets policy
   defaults for the rest of the build. CMK-MOD-06, after adding any helper.
9. **Adding `TIMEOUT` to a `GIT_REPOSITORY` fetch and calling it bounded.** The
   keyword is accepted and ignored. CMK-MOD-18.
10. **Assuming `execute_process` output is UTF-8 everywhere.** True off Windows and
    under CMP0176 NEW, false inside a function pinned below 3.31, even on 4.4.2.
    CMK-MOD-19.
11. **Treating `cmake_language` as one scope rule**, or reading `command is not
    scriptable` as a typo after porting project code into `-P`. CMK-MOD-20.

Re-check: D8, gersemi releases after 0.29.1 (the `--diff` exit code and nested-parse
detection behind CMK-MOD-15 and -16). D1, CMake 4.5 and the gate spelling on the
CMK-MOD-11 configure. CMK-MOD-19's Windows half stays read-only until a Windows host
can measure it (as of 2026-09-26).
