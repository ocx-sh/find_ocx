---
title: Testing a CMake Project and Its Modules
summary: The CMK-TEST family. What a green CTest step in CI must prove, how a consumed library keeps its tests out of a consumer's tree, how a negative test pins exit status and diagnostic together, and how a CMake module is tested on every CMake line it claims
---

# Testing a CMake Project and Its Modules

Owns the test side of a CMake build: the ctest line CI runs, the gate around a
library's test tree, what a negative test asserts, how a CMake module's own
harness is driven, and test discovery on a cross leg. It does not own the
configure gate's spelling or the silent-pass list, which are `CMK-CORE` in the
`cmake-build` index, nor pinning the CMake a pipeline runs, which is `CMK-VER-03`
in `versions-and-policies.md`. Test presets and the offline job are
`CMK-CI` in `presets-and-ci.md`. The install round trip is `CMK-INST-01`, and
its CI job is `CMK-INST-18`, both in `install-and-export.md`. Flipping a dependency's own
test toggle from the parent is `CMK-DEP-15` in `dependencies.md`, and the
contract a shipped module keeps is `CMK-MOD` in `module-authoring.md`.

Conventions. Rules assume a CMake 3.25 floor written as
`cmake_minimum_required(VERSION 3.25...4.4)` (pinned) and were measured on
3.31.12, 4.3.4 and 4.4.2 on 2026-09-26. "The gate" is `CMK-CORE-01`'s pinned
spelling: `-Werror=author` on CMake 4.4 and later, `-Werror=dev` on 4.3 and
older, and `-Werror=dev` when one command line serves both. Commands read
variables, never placeholders: `CI_DIR` is one directory of CI definitions or
scripts (run once per directory, for example `.github` and then `ci`),
`TEST_DIR` is the test tree (`.` for a whole-project review) and `MODULE_DIR`
a module's source directory. Run every command from the repository root.

Contents: [The CI CTest Line](#the-ci-ctest-line) · [Every Negative Test](#every-negative-test) ·
[A Consumed Library's Test Tree](#a-consumed-librarys-test-tree) · [Testing a CMake Module](#testing-a-cmake-module) ·
[Discovery on a Cross Leg](#discovery-on-a-cross-leg) · [What Agents Get Wrong Here](#what-agents-get-wrong-here) · [Re-check](#re-check)

## The CI CTest Line

Binds every project that runs `ctest` in CI. Read the CI line, not the local
one: a green step must prove that tests ran and that none of them hung.
Commands 1 and 2 skip Markdown, because a `CONTRIBUTING.md` under `.github`
shows a local `ctest` line that no CI job runs (nlohmann/json, 2026-09-26). They
still read shell scripts, so never narrow them to YAML.

```sh
CI_DIR=.github
# 1. CMK-TEST-06: files that run tests with no zero-test guard. Empty output passes.
grep -rlw --exclude='*.md' -e 'ctest' -e '--target test' "$CI_DIR" | xargs -r grep -L -e 'no-tests=error' -e 'CTEST_NO_TESTS_ACTION' -e 'CMAKE_CTEST_ARGUMENTS' -e 'noTestsAction'
# 2. CMK-TEST-07: files that run tests with no suite bound. Empty output passes.
grep -rlw --exclude='*.md' -e 'ctest' -e '--target test' "$CI_DIR" | xargs -r grep -L -e '--timeout' -e '"timeout"'
# 3. CMK-TEST-07 fallback, only for a file command 2 printed. Empty output is the finding.
grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'TIMEOUT' -e 'include(CTest)' .
# 4. CMK-TEST-08: retry-until-green on a gate. Empty output passes.
grep -rn -e 'until-pass' -e 'after-timeout' "$CI_DIR"
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TEST-06 | Run CTest in CI as `ctest --test-dir "$BUILD_DIR" -C "$CONFIG" --output-on-failure --no-tests=error`. When CI runs tests through the build's `test` target, put the same flags in `CMAKE_CTEST_ARGUMENTS`. Match `-C` to the build step's `--config` on a multi-config leg and to `CMAKE_BUILD_TYPE` on a single-config leg, and pass it unconditionally. A `ctest --preset` run passes when its test preset sets `"execution": {"noTestsAction": "error"}`. | A zero-test tree, a `-R` or `-L` filter that matches nothing, a `--test-dir` naming a directory with no `CTestTestfile.cmake`, and the `test` target all exit 0. `--no-tests=error` turns each into exit 8 (measured 2026-09-26 on 3.31.12, 4.3.4 and 4.4.2). Multi-config without `-C` fails every test, and a single-config tree silently drops a test restricted by `add_test(... CONFIGURATIONS ...)` under a wrong or missing `-C`. Floor: `--no-tests` and `CMAKE_CTEST_ARGUMENTS` 3.17, `--test-dir` 3.20, `CTEST_NO_TESTS_ACTION` 3.26. | Command 1. Empty output passes. Each file printed is a finding, unless its only run is `ctest --preset` and that test preset sets `execution.noTestsAction` to `error`. Then read every invocation in the files it did not print: one file can hold a guarded line and a bare one, a call can span lines, and a `CMAKE_CTEST_ARGUMENTS` without `--no-tests=error` does not count. | MUST |
| CMK-TEST-07 | Bound every test's run time in CI: `--timeout` with a number of seconds on the ctest line, in `CMAKE_CTEST_ARGUMENTS` or in the test preset's `execution.timeout`, plus a per-test `TIMEOUT` for the few tests that need longer. `enable_testing()` alone sets no bound, `include(CTest)`'s 1500 s is a bound nobody chose, and `CTEST_TEST_TIMEOUT` in the environment does nothing. | Without a bound a hung test holds the whole job until the runner's own job timeout. `enable_testing()` alone computes an effectively unbounded timeout, `--timeout 1` fails a 3 s test, and the environment variable is ignored (measured 2026-09-26 on 3.31.12, 4.3.4 and 4.4.2). `--timeout` applies only to tests without their own `TIMEOUT` (`ctest.1.rst` at v4.4.2). Floor: any version. | Command 2. Empty output passes. A file whose only run is `ctest --preset` passes when that test preset sets `execution.timeout`. For any other file printed, run command 3: empty output is the finding, and a hit passes only if every `add_test` carries its own `TIMEOUT`. An `include(CTest)` hit alone is the 1500 s default, so it is still the finding. | MUST |
| CMK-TEST-08 | Never put `--repeat until-pass` or `--repeat after-timeout` on a gating ctest line. Keep either one only for a named, temporary flake-hunt job that cites an issue. `--repeat until-fail` with a count finds flakes and may run anywhere. | `ctest.1.rst` at v4.4.2 calls both modes a way of tolerating sporadic failures, so on a gate every future flaky test turns green on retry. Apache Arrow's test script runs `until-pass:3` on every job that calls it. Floor: `--repeat` 3.17. | Command 4. Empty output passes. A hit in a job that runs on every push or pull request is the finding. | SHOULD |

## Every Negative Test

Binds every test suite, not only module harnesses: a negative test is any test
that passes because something failed or printed a diagnostic. The `cmake-build`
index cites `CMK-TEST-03` as a non-negotiable.

```sh
TEST_DIR=.
# 1. Every hit is a finding. Empty output passes.
grep -rn --include='*.cmake' --include='CMakeLists.txt' -e 'WILL_FAIL' "$TEST_DIR"
# 2. Regexes with no severity header, across line breaks. Empty output passes.
grep -rPzo --include='*.cmake' --include='CMakeLists.txt' 'PASS_REGULAR_EXPRESSION\s+"(?![^"]*CMake Error)[^"]*"' "$TEST_DIR" | tr '\0' '\n'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TEST-03 | A negative test asserts the exit status and the diagnostic together. Use a `PASS_REGULAR_EXPRESSION` that includes the severity header, for example `"CMake Error at [^\n]*\\(message\\):\n  mymodule: ..."`, or a driver in the RunCMake style that checks the result code and stderr separately. Never `WILL_FAIL` alone, never `WILL_FAIL` combined with a regex, and never a regex matching only the message. | Measured 2026-09-26 on 3.31.12 and 4.4.2: `PASS_REGULAR_EXPRESSION` ignores the exit code, `WILL_FAIL` passes on any failure (a missing file included), and the two combined invert each other so the test fails whether the command exits 0 or 1. A regex carrying the `CMake Error at` header passes a `FATAL_ERROR` and fails a `WARNING` with the same text. CMake's own RunCMake harness checks `-result.txt` and `-stderr.txt` together. Floor: any version. | Both commands above. Empty output from both passes. Every `WILL_FAIL` hit is a finding. Every regex command 2 prints is a finding unless its command is a driver that checks the exit code (read it). A regex held in a variable prints too, so read what the variable holds. | MUST |

```cmake
# wrong: passes on any failure, or when the module prints the text and carries on
set_tests_properties(rejects_bad PROPERTIES WILL_FAIL TRUE)
set_tests_properties(
    rejects_msg
    PROPERTIES PASS_REGULAR_EXPRESSION "mymodule: VERSION is required"
)
# right: the severity header and the message in one regex
set_tests_properties(
    rejects_msg
    PROPERTIES
        PASS_REGULAR_EXPRESSION
            "CMake Error at [^\n]*\\(message\\):\n  mymodule: VERSION is required"
)
```

## A Consumed Library's Test Tree

Binds a library shipping a package, or a library meant to be vendored or
fetched. A pure top-level application is exempt. The static grep finds each test
subtree, the smoke build proves the gate.

```sh
# 1. Each hit must sit inside a project-prefixed gate. Empty output means there is no test, example, demo or benchmark tree to gate.
grep -rn --include='CMakeLists.txt' -e 'add_subdirectory(test' -e 'add_subdirectory (test' -e 'add_subdirectory(unittest' -e 'add_subdirectory(example' -e 'add_subdirectory(demo' -e 'add_subdirectory(bench' .
# 2. The as-subproject smoke. SRC: the library's absolute source directory. W: a fresh, empty scratch
#    directory outside the tree. GATE: -Werror=author on CMake 4.4 and later, -Werror=dev
#    on 4.3 and older (CMK-CORE-01).
mkdir -p "$W/asub"
printf '%s\n' 'cmake_minimum_required(VERSION 3.25...4.4)' 'project(asub LANGUAGES C)' \
  'include(CTest)' "add_subdirectory($SRC lib-build)" > "$W/asub/CMakeLists.txt"
cmake -S "$W/asub" -B "$W/asub-build" -G Ninja "$GATE" && ctest --test-dir "$W/asub-build" -N > "$W/asub-tests.txt"
# Must print the line. Empty output means the library's tests leaked, or the consumer failed to configure: both are findings.
grep -e 'Total Tests: 0' "$W/asub-tests.txt"
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TEST-09 | Gate the test tree of a library that others consume on a project-prefixed option whose default is `PROJECT_IS_TOP_LEVEL` (or `OFF`). Never gate it on `BUILD_TESTING` alone. Call `include(CTest)` inside the gate. Run the smoke build above as a named CI job. Gate examples, demos and benchmarks the same way, on project-prefixed options. Renaming an existing unprefixed option keeps the old spelling as the top-level default (`if(PROJECT_IS_TOP_LEVEL AND DEFINED BUILD_TESTING)`), or ships a changelog entry naming the rename. | A consumer's `include(CTest)` turns `BUILD_TESTING` on for the whole tree, so a `BUILD_TESTING`-guarded dependency lands its tests in the consumer's `ctest -N`. The prefixed option keeps them out, and the standalone build still has them (measured 2026-09-26 on 3.31.12, 4.3.4 and 4.4.2). fmt and spdlog gate this way, and curl runs the as-subproject job in CI. Floor: `PROJECT_IS_TOP_LEVEL` 3.21. Below that, compare `CMAKE_SOURCE_DIR` with `PROJECT_SOURCE_DIR`. A plain rename drops `-DBUILD_TESTING=ON` with only a "not used" warning, 0 tests and exit 0, and uclouvain/openjpeg at `8314119b` seeds that entry from its CI script (measured 2026-09-26 on 3.31.12 and 4.4.2). | Command 1 first. A hit under a `BUILD_TESTING`-only guard, or under an unprefixed option whatever its default, is the finding: `option()` never overrides a parent's entry of the same name, so a parent's `BUILD_EXAMPLES=ON` switches the library's on (measured 2026-09-26 on 3.31.12 and 4.4.2). Then the smoke block on the leg's CMake with that line's gate (3.31.x: `-Werror=dev`, 4.4.x: `-Werror=author`): the final grep printing `Total Tests: 0` passes, and empty output is the finding. After a rename, `-D<old>=ON` at top level must change the `ctest -N` count. | MUST |

```cmake
# wrong: the consumer's include(CTest) turns BUILD_TESTING on and pulls these in
include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
# right
option(MYLIB_BUILD_TESTS "Build MyLib's tests" ${PROJECT_IS_TOP_LEVEL})
if(MYLIB_BUILD_TESTS)
    include(CTest)
    add_subdirectory(tests)
endif()
```

## Testing a CMake Module

Binds a CMake module author (a Find module, a helper module, a copy-and-own
bootstrapper, a dependency-provider file) and any project that tests its own
CMake diagnostics. Read the CI matrix and the test driver.

```sh
CI_DIR=.github
TEST_DIR=tests
# 1. CMK-TEST-01: the CMake lines CI provisions. Empty output is the finding.
grep -rn --include='*.yml' --include='*.yaml' -e 'cmake_version' -e 'cmake-version' -e 'cmakeVersion' "$CI_DIR"
# 2. CMK-TEST-02: configure-mode inner configures with no gate on the line. Empty output passes.
grep -rn --include='*.cmake' --include='CMakeLists.txt' -e 'build-and-test' -e ' -S ' "$TEST_DIR" | grep -v -e '-Werror='
# 3. CMK-TEST-02: script-mode cases and their substitutes, for reading.
grep -rn --include='*.cmake' --include='CMakeLists.txt' -e ' -P ' -e 'FAIL_REGULAR_EXPRESSION' "$TEST_DIR"
# 4. CMK-TEST-05: tests that load one shipped file. Empty output is the finding.
SHIPPED=MyTool
grep -rn --include='*.cmake' --include='CMakeLists.txt' -e "$SHIPPED" "$TEST_DIR"
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TEST-01 | Run the module's tests on a real binary of every CMake line it claims: at least the declared floor and the newest release. Call each binary by an explicit provisioned path, as a CI matrix axis (CPM.cmake's shape) or as one `ctest --build-and-test` per provisioned binary. A floor that no leg can provision is raised or labelled untested, never left standing as a claim. | Behaviour differs between lines: `-Werror=author` does nothing on 4.3 and older, no gate spelling works under `cmake -P` on 4.3 and older, and the `TLS_VERIFY` default flips at 3.31 (measured 2026-09-26 on 3.31.12, 4.3.4 and 4.4.2). A copy-and-own bootstrap module claimed a 3.19 floor and tested only 3.31 and 4.x. `CMK-VER-03` pins CI's CMake for every project and cites this row for modules. Floor: any version. | Command 1, compared with every `cmake_minimum_required` and `CMAKE_VERSION VERSION_LESS` floor under `MODULE_DIR`. Empty output is the finding unless the harness drives per-line binaries through `--build-and-test` (read it). A claimed floor with no matching leg is the finding, and so is a bare `cmake` or `${CMAKE_COMMAND}` in an `add_test` that claims a version-specific run. | MUST |
| CMK-TEST-02 | Put the gate, spelled for that line (pinned by `CMK-CORE-01`), on every inner configure the harness drives, including `execute_process`-driven reconfigures. For each `cmake -P` case on 4.3 or older, which the gate cannot reach, add `FAIL_REGULAR_EXPRESSION "CMake Warning;CMake Deprecation Warning"`. | Under `cmake -P` every gate spelling exits 0 on a warning script on 3.31.12 and 4.3.4 and exits 1 on 4.4.2 (4.4 still accepts `-Werror=dev`, with a deprecation notice). The `FAIL_REGULAR_EXPRESSION` substitute fails on the warning and passes a clean script on every line (measured 2026-09-26). A bootstrap module drove half its test families ungated, one of them a plain configure with no reason to skip. Floor: the gate under `-P` 4.4, the substitute any version. | Command 2: empty output passes, and each line printed is a finding unless the gate reaches it through a variable on that line. Command 3: each `-P` case on a 4.3-or-older leg needs a `FAIL_REGULAR_EXPRESSION` on the same test. A case with neither the gate (4.4 and later) nor the substitute is the finding. | MUST |
| CMK-TEST-04 | A memoization or reconfigure test runs three configures: a baseline, a repeat with nothing changed (expect a hit), then one changed input (expect invalidation and a correct re-store). | A two-configure test proves only the hit. When a module's cache memo was suspected of a defect, its own suite could neither confirm nor refute it, and settling it took an external three-run reproduction. Floor: any version. | Reading heuristic: count the configures in the test file and look for a mutated input between two of them. A file with two identical configures is the finding. | SHOULD |
| CMK-TEST-05 | Exercise every shipped file through the entry point a consumer uses: `find_package` for a `Find<Pkg>.cmake`, `include()` for a helper, `cmake -P` for a script entry point. | A shipped Find module that no test loads through `find_package` breaks unseen when the only test copies the file and checks its hash. Running each entry point also catches `CMK-MOD-20`'s wrong-mode `cmake_language` calls, which fail loudly only when reached. Floor: any version. | Command 4, once per shipped file, with `SHIPPED` set to the name a consumer writes: the package name for a Find module (`MyTool` for `FindMyTool.cmake`), the module name for a helper, the file name for a script. Empty output is the finding. A hit counts only if it is a real call (`find_package`, `include`, `-P`), never a `file(COPY)` of the module. | SHOULD |

```cmake
# wrong on 4.3 and older: the gate does nothing under -P, so a warning passes
add_test(NAME script COMMAND ${CMAKE_COMMAND} -Werror=dev -P ${SCRIPT})
# right on every line
add_test(NAME script COMMAND ${CMAKE_COMMAND} -P ${SCRIPT})
set_tests_properties(
    script
    PROPERTIES FAIL_REGULAR_EXPRESSION "CMake Warning;CMake Deprecation Warning"
)
```

## Discovery on a Cross Leg

Binds a project with a cross-compiling CI leg. Plain `add_test` per test binary
stays an acceptable default: googletest and Catch2 use it for their own suites.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-TEST-10 | On a cross-compiling leg, give every `gtest_discover_tests` or `catch_discover_tests` a `CROSSCOMPILING_EMULATOR` on the test target, or use `DISCOVERY_MODE PRE_TEST` with ctest running in the target environment. Call 4.4's generic `discover_tests()` only under `CMAKE_VERSION VERSION_GREATER_EQUAL 4.4`. | The default `POST_BUILD` discovery runs the built binary on the build host, and the GoogleTest module (4.4.2) says discovery requires a properly set `CROSSCOMPILING_EMULATOR` when cross-compiling. The failure is loud, hence SHOULD. `discover_tests()` has no adopters outside Kitware (as of 2026-09-26). Floor: `gtest_discover_tests`' `DISCOVERY_MODE` 3.18, `catch_discover_tests`' `DISCOVERY_MODE` Catch2 3.4.0, `discover_tests()` 4.4. | `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'gtest_discover_tests' -e 'catch_discover_tests' -e 'discover_tests(' .` Empty output means the rule does not apply. On a tree with a cross leg, a hit with neither an emulator nor `PRE_TEST` is the finding. | SHOULD |

## What Agents Get Wrong Here

1. **Copying a bare `ctest` line from a README.** A typo in `add_test`, an empty
   filter or a missing `-C` then reads as green. 14 of 18 corpus projects that
   run ctest from a workflow have no zero-test guard (2026-09-26). `CMK-TEST-06`.
2. **Leaving tests unbounded**, or trusting `CTEST_TEST_TIMEOUT` under `env:`. `CMK-TEST-07`.
3. **A negative test as `WILL_FAIL TRUE`, a message-only regex, or both.** A test
   that must just fail needs no inversion: `${CMAKE_COMMAND} -E false`. `CMK-TEST-03`.
4. **Guarding a library's tests with `if(BUILD_TESTING)`.** `CMK-TEST-09`.
5. **`-Werror=dev` on a `cmake -P` test on 4.3 or older**, where it does nothing. `CMK-TEST-02`.
6. **"Tested against CMake X" from one `ctest --build-and-test`** running whatever
   `cmake` is on `PATH`. `CMK-TEST-01`.
7. **`--repeat until-pass:3` to fix flaky CI.** `CMK-TEST-08`.
8. **Claiming `CMAKE_CTEST_ARGUMENTS` does not exist.** It is 3.17. Check
   `cmake --help-variable CMAKE_CTEST_ARGUMENTS` on the pinned binary.
9. **`-DCMAKE_BUILD_TYPE` on a multi-config leg** as if it chose the
   configuration. Only `-C` does (`CMK-TEST-06`).
10. **4.4's `discover_tests()` as "the modern way"** without the version gate. `CMK-TEST-10`.
11. **A memo test with two identical configures**, which never proves invalidation. `CMK-TEST-04`.

## Re-check

- D1: on the first CMake 4.5 release, re-run the `-P` gate measurement behind
  `CMK-TEST-02` and the smoke gate spelling behind `CMK-TEST-09` (both follow
  `CMK-CORE-01`).
- The corpus census of consumed-library test gates and of CI scripts outside
  `.github` (as of 2026-09-26) adds exemplars only. No row's text depends on it.
