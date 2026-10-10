---
title: Versions, Floors and Policies
summary: The CMK-VER family. How a project declares its CMake floor and range, how it settles a policy, which features the floor allows, how it finds a dependency whose floor breaks CMake 4, and how it pins an experimental gate
---

# Versions, Floors and Policies

Owns the version contract of a CMake project: the `cmake_minimum_required`
floor and range, policy settings, the features the floor allows, the floors of
fetched and vendored dependencies, and `CMAKE_EXPERIMENTAL_*` gates. It does not
own the configure gate or its per-binary spelling, which is CMK-CORE-01 in the
`cmake-build` index. The scoped `CMAKE_POLICY_VERSION_MINIMUM` fix is CMK-DEP-15
and the CMake 3.x remedy for an old dependency floor is CMK-DEP-30, both in
`dependencies.md`, which also owns migrating off a removed Find module
(CMK-DEP-19). The presets schema ceiling is CMK-CI-01 in `presets-and-ci.md`.
A shipped module's floor leg is CMK-TEST-01 in `testing.md`. The module-scanning
remedy behind CMP0155 is CMK-TGT-18 in `targets.md`. A Bazel-wrapped build runs
the wrapper's CMake (3.31.12 under rules_foreign_cc 0.16.0), and CMK-BZL-08 in
`bazel-seam.md` owns that floor.

**Pinned, overridable once:** rules are written for a CMake 3.25 floor, and
every `cmake_minimum_required` in this file reads `VERSION 3.25...4.4`. An
adopter with another floor or a newer top CI leg changes both numbers once,
repository-wide. Measured on CMake 3.31.12, 4.3.4 and 4.4.2 on 2026-09-26.
Three passes in this family look green and are not: a two-dot range (CMK-VER-01),
an explicit policy OLD (CMK-VER-07) and a stale experimental UUID (CMK-VER-09).
None of them trips the configure gate. Run every command from the repository root.

Contents: [Caught by Greps Over Your Own Listfiles](#caught-by-greps-over-your-own-listfiles) ·
[Caught by the Dependency-Floor Scan](#caught-by-the-dependency-floor-scan) ·
[Caught by the Pinned Binary](#caught-by-the-pinned-binary) ·
[Caught by Reading the CI Matrix and the Bump Diff](#caught-by-reading-the-ci-matrix-and-the-bump-diff) ·
[What Agents Get Wrong Here](#what-agents-get-wrong-here) · [Re-check](#re-check)

## Caught by Greps Over Your Own Listfiles

One pass over `CMakeLists.txt` and `*.cmake`, every command with a directory
operand. These are own-code checks, so they exclude `_deps` and build trees
(CMK-CORE-05 sets that scope). Add each vendor directory of yours as one more
`--exclude-dir`. Empty output is the pass for all three.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-VER-01 | Write a version range with exactly three literal dots: `cmake_minimum_required(VERSION 3.25...4.4)`. Two dots are never a range. Floor: CMake 3.12. | `3.15..4.3` is one literal that collapses to `VERSION 3.15`. CMP0126 and CMP0140 stay unset with no diagnostic, even under the configure gate (measured 2026-09-26 on 3.31.12, 4.3.4 and 4.4.2). The manual says "the `...` is literal". Real repositories ship the two-dot form (yaml-cpp), so it gets copied. | `grep -rnE --include='CMakeLists.txt' --include='CMakeLists.txt.in' --include='*.cmake' --exclude-dir=_deps --exclude-dir='build*' -e 'VERSION[[:space:]]+[0-9]+(\.[0-9]+)*\.\.[0-9]' .` Empty output is the pass. Any hit is the finding. The pattern does not match the three-dot form. | MUST |
| CMK-VER-02 | Declare the floor as `<min>...<max>`, where `<max>` is the newest CMake the project's CI runs, never simply the newest release. **pinned**: `3.25...4.4`, overridable once. Floor: CMake 3.12. | A bare floor leaves every later policy unset on a newer binary. Bare `3.25` gives empty CMP0143 through CMP0219 on 4.4.2, while `3.25...4.4` sets all of them NEW. The range sets NEW up to the lower of `<max>` and the running version, and the manual reads `<max>` as "updated to work with policies introduced by" it, which is a claim of testing. The rule is argued, so it is SHOULD. Raising an existing `<max>` flips every policy up to it: on 4.4.2, CMP0219 stopped re-escaping `macro()` arguments and uclouvain/openjpeg's `.pc` macro wrote `libdir=\/lib64` while the canary and the gated configure passed (measured 2026-09-26, 3.31.12 and 4.3.4 unaffected). | `grep -rnE --include='CMakeLists.txt' --exclude-dir=_deps --exclude-dir='build*' --exclude-dir=third_party -e 'cmake_minimum_required\([[:space:]]*VERSION[[:space:]]+[0-9]+(\.[0-9]+)*[[:space:]]*(FATAL_ERROR)?[[:space:]]*\)' .` Empty output is the pass. Any hit is a bare floor (finding). Then read `<max>` against the newest CI leg: a `<max>` above or below it is the finding, and after a raise every `configure_file()` output on the newest line is compared with the one before it. | SHOULD |
| CMK-VER-07 | Resolve a gate error "Policy CMPxxxx is not set" by adopting NEW: migrate the code, then raise `<max>` or write `cmake_policy(SET CMPxxxx NEW)`. Never resolve it with `SET … OLD`. A temporary OLD sits behind `if(POLICY CMPxxxx)` with a comment giving the reason and the exit condition. Once a leg's binary reports that OLD as deprecated, the guarded OLD fails that leg's gate too, so its exit has arrived: migrate. Migrate off the removed Find modules (CMP0146 `FindCUDA`, CMP0148 `FindPythonInterp` and `FindPythonLibs`, CMP0167 `FindBoost`, CMP0188 `FindGCCXML`, CMP0191 `FindCABLE`), whose replacements CMK-DEP-19 owns. Floor: any CMake. Those removals landed at 3.27, 3.30 and 4.1. | An unset policy is a gate error. An explicit OLD passes the gate silently until the running binary deprecates that policy's OLD, which depends on the policy: CMP0177 OLD passes on 3.31.12 through 4.4.2, CMP0155 OLD passes through 4.3.4 and fails the 4.4.2 gate even inside `if(POLICY)`, and CMP0126 OLD fails the gate on every binary from 3.31.12 (measured 2026-09-26 on 3.31.12, 4.0.7, 4.2.7, 4.3.4 and 4.4.2). Ungated, each is only a warning with exit 0. So the gate misses exactly the newest OLDs. OLD is "deprecated by definition and may be removed" (`cmake-policies(7)`, 4.4.2). A starter template that sets CMP0155 OLD "at the moment", with no guard and no exit, propagates it into every project generated from it. | `grep -rniE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir=_deps --exclude-dir='build*' -e 'cmake_policy\([[:space:]]*SET[[:space:]]+CMP[0-9]+[[:space:]]+OLD' .` Empty output is the pass. A hit with no `if(POLICY …)` guard and no adjacent reason-and-exit comment is the finding. | MUST |

```cmake
# wrong: two dots collapse to VERSION 3.15, and an unguarded OLD with no exit
cmake_minimum_required(VERSION 3.15..4.3)
cmake_policy(SET CMP0155 OLD)

# right: a real range, and module scanning switched off by its own variable
cmake_minimum_required(VERSION 3.25...4.4)
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)
```

## Caught by the Dependency-Floor Scan

Run it before a CMake bump and whenever a dependency is added or re-pinned. It
is the one scan that must include `_deps`. Name your build's `_deps` directory
and every vendor directory (`third_party`, `contrib`, a vendored subdirectory)
as operands.

```sh
grep -rniE --include='CMakeLists.txt' --include='*.cmake' \
  -e '^[[:space:]]*cmake_minimum_required[[:space:]]*\([[:space:]]*VERSION[[:space:]]+2\.[0-9]+(\.[0-9]+)*[^0-9.]' \
  -e '^[[:space:]]*cmake_minimum_required[[:space:]]*\([[:space:]]*VERSION[[:space:]]+3\.[0-9](\.[0-9]+)*[^0-9.]' \
  -e '^[[:space:]]*cmake_minimum_required[[:space:]]*\([^)]*\.\.\.[[:space:]]*3\.[0-9](\.[0-9]+)*[^0-9.]' \
  -e '^[[:space:]]*cmake_policy[[:space:]]*\([[:space:]]*VERSION[[:space:]]+2\.[0-9]+(\.[0-9]+)*[^0-9.]' \
  -e '^[[:space:]]*cmake_policy[[:space:]]*\([[:space:]]*VERSION[[:space:]]+3\.[0-9](\.[0-9]+)*[^0-9.]' \
  -e '^[[:space:]]*cmake_minimum_required[[:space:]]*\([[:space:]]*$' \
  build/_deps third_party
```

Empty output is the pass, and every hit is the finding. A hit is a bare floor
below 3.10, a range whose `<max>` is below 3.10, or a `cmake_policy(VERSION)`
below 3.10. A range whose `<max>` is 3.10 or higher does not match, and it
passes: `2.8.12...3.10` and `3.5...3.10` configure clean under `-Werror=dev` on
3.31.12 and `-Werror=author` on 4.4.2 (measured 2026-09-26). Commented lines do
not match. A hit that ends in `cmake_minimum_required(` is a call split across
lines, so read its next line. A `No such file or directory` on stderr means that operand was never
scanned, which is not a pass. A two-dot range in a dependency collapses to its
floor and escapes this scan, so run the CMK-VER-01 pattern over the same
operands.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-VER-05 | Before a CMake bump, and whenever a dependency is added or re-pinned, scan the fetched and vendored trees for an effective policy version below 3.10. Floor: CMake 4.0 for the hard error below 3.5, and CMake 3.31 for the gate error from 3.5 through 3.9. | Below 3.5, CMake 4.x stops with "Compatibility with CMake < 3.5 has been removed", gate or no gate. From 3.5 through 3.9, the dependency's deprecation becomes a gate error in *your* build on 3.31.12 and 4.4.2. A dependency that declares 3.10 and then calls `cmake_policy(VERSION 3.5)` fails the same way (measured 2026-09-26). Real projects' root floors are clean, and the old lines sit in recipe, port and example trees, which is what a fetch pulls in. | The scan above. Empty output is the pass. Any hit is the finding. | MUST |
| CMK-VER-06 | Citation only. A stale dependency floor is CMK-DEP-15's on CMake 4.x and CMK-DEP-30's on CMake 3.x, both in `dependencies.md`. Floor: `CMAKE_POLICY_VERSION_MINIMUM` is CMake 4.0. | Both rows in `dependencies.md` keep the text, because they cover both policy knobs and all three calls that load a dependency. | CMK-DEP-15's grep and CMK-DEP-30's greps, in `dependencies.md`. This row adds no command. | MUST (cited) |

## Caught by the Pinned Binary

Ask the binary the leg runs, never `master` or the "latest" docs. Read the
`versionadded` line of `cmake --help-command block`,
`cmake --help-variable CMAKE_POLICY_VERSION_MINIMUM`,
`cmake --help-policy CMP0155` or `cmake --help-manual cmake-presets`, or the
same file at the matching Git tag. For an experimental gate, the binary's own
bytes are the authority.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-VER-04 | Before using a command, keyword, variable, generator or preset field, check its `versionadded` against the declared floor on the pinned binary or at the matching Git tag. Guard anything newer than the floor with `if(CMAKE_VERSION VERSION_GREATER_EQUAL X.Y)` and a fallback, and guard a policy with `if(POLICY CMPxxxx)`. Setting a variable that an older CMake never reads, such as `CMAKE_CXX_SCAN_FOR_MODULES`, needs no guard. Floor: per the table below. | These are hard floors with no OLD or NEW fallback. Features on `master` do not exist in 4.4.3: presets schema 13, `CMD_STRICT`, `CMD_NON_TARGET_DIRECTIVE` and `cmake_language(PRINT_TARGETS)` (read 2026-09-26). `-DCMAKE_POLICY_VERSION_MINIMUM=3.10` on 3.31.12 exits 0 with only "Manually-specified variables were not used". | `grep -rnE --include='CMakeLists.txt' --include='*.cmake' --exclude-dir=_deps --exclude-dir='build*' -e 'CXX_MODULES' -e 'PACKAGE_INFO' -e 'SCOPE_FOR[^)]*DIAGNOSTICS' -e 'cmake_diagnostic' -e 'cmake_pkg_config' .` finds features above a 3.25 floor. Empty output is the pass. A hit outside a version guard is the finding. A lower floor adds each table row above it as one more `-e`. Then `grep -rn --include='CMakePresets.json' --include='*.yml' --include='*.yaml' -e 'Visual Studio 9' -e 'Visual Studio 10' -e 'Visual Studio 11' -e 'Visual Studio 12' -e 'Visual Studio 18' -e 'FASTBuild' .` Empty output is the pass. Settle each hit with `cmake --help` on that leg's binary. | MUST |
| CMK-VER-09 | Copy a `CMAKE_EXPERIMENTAL_*` UUID only from `Help/dev/experimental.rst` at the tag of the pinned binary. Re-check it on every CMake bump, and prove activation by building something that uses the feature, never by a configure exit code. On a 4.3 or newer floor, delete the gates retired at 4.3.0 (`EXPORT_PACKAGE_INFO`, `FIND_CPS_PACKAGES`): `install(PACKAGE_INFO)` needs no gate from 4.3, and only `CMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO` still needs `MAPPED_PACKAGE_INFO`. An activated gate emits an `experimental` warning that the configure gate fails. On 4.4, exempt it on that leg with `-Wno-error=experimental`. On 4.3 or older no such child exists, so build the feature on an ungated leg of its own. Floor: the UUID can change at any minor. | `CXX_IMPORT_STD` is `d0edc3af…` on 3.31.12 (unchanged through 4.2.7, read at each tag), `451f2fe2…` on 4.3.4 and `f35a9ac6…` on 4.4.2. Four of six gates rotated between 4.3.4 and 4.4.2, and `master` carries UUIDs no release has. A stale UUID is silent on 3.31.12 and under the Makefiles generator, and with Ninja on 4.3.4 and 4.4.2 it only warns "is set to incorrect value" and exits 0 (measured 2026-09-26). | `grep -rn --include='CMakeLists.txt' --include='*.cmake' --include='CMakePresets.json' --include='*.yml' --include='*.yaml' -e 'CMAKE_EXPERIMENTAL_' .` Empty output is the pass. For each hit, set `CMAKE_BIN` to the pinned binary's path, bind the literal, and count it in the binary: `UUID=451f2fe2-a8a2-47c3-bc32-94786d8fc91b; grep -c -a -F -e "$UUID" "$CMAKE_BIN"` A count of `0` is a stale gate (finding). `1` or more passes. On 4.4.2, `451f2fe2…` counts 0 and `f35a9ac6…` counts 1. | MUST |

| Feature | `versionadded` (read on 4.4.2) |
|---|---|
| `string(JSON)` | 3.19 |
| `PROJECT_IS_TOP_LEVEL` | 3.21. Below it, compare `CMAKE_SOURCE_DIR` with `PROJECT_SOURCE_DIR` |
| `target_sources(FILE_SET)` | 3.23 |
| dependency providers, `FIND_PACKAGE_ARGS`, `OVERRIDE_FIND_PACKAGE`, `CMAKE_COMPILE_WARNING_AS_ERROR` | 3.24 |
| `block()`, `return(PROPAGATE)`, FetchContent `SYSTEM`, presets schema 6 | 3.25 |
| `FILE_SET TYPE CXX_MODULES`, `CMAKE_CXX_SCAN_FOR_MODULES` | 3.28 |
| `cmake_pkg_config`, presets schema 10 | 3.31 |
| `CMAKE_POLICY_VERSION_MINIMUM` | 4.0. Unknown to 3.31.12 |
| `Visual Studio 18 2026` and `FASTBuild` generators | 4.2 |
| `install(PACKAGE_INFO)` ungated, presets schema 11 | 4.3 |
| `-Werror=author`, `block(SCOPE_FOR DIAGNOSTICS)`, `cmake_diagnostic`, presets schema 12 | 4.4 |
| Removed generators: VS 10 2010 at 3.25, VS 11 2012 at 3.28, VS 9 2008 at 3.30, VS 12 2013 at 3.31 | removal |

## Caught by Reading the CI Matrix and the Bump Diff

Both rows are read, not run. CMK-VER-03 starts from one grep over the workflow
directory, and CMK-VER-08 reads the diff that moves a version.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-VER-03 | Install a pinned CMake explicitly on every CI leg, with one leg at the declared floor and one at `<max>`. Never rely on the runner image or the distro package. A CMake version pinned by a committed tool lock counts as pinned. A shipped module's floor leg is CMK-TEST-01's, and this row does not restate it. Floor: any CMake. | Image defaults differ by OS on the same day: 3.31.6 on `ubuntu-24.04` and `windows-2025`, 4.4.2 on `macos-15`, and Ubuntu 22.04's apt ships 3.22.1 (as of 2026-09-26). A floor that no leg runs is a claim, not a contract. Lowering the floor would not rescue 22.04, so provision a CMake instead. | `grep -rn -e 'get-cmake' -e 'setup-cmake' -e 'cmake==' .github/workflows` Empty output is the finding, unless a leg installs from a committed tool lock that pins CMake: confirm the lock with `git ls-files` and read its CMake entry. With a pin found, read the matrix for a leg whose version equals the declared `<min>`. None is the finding. | SHOULD |
| CMK-VER-08 | Treat raising `<max>` or the floor as a behaviour change. List the policies the new version adds (`cmake --help-policy-list` on the new binary, each read with `cmake --help-policy`) and review the DECIDE set before merging: CMP0155 (C++20 sources scanned for modules, 3.28), CMP0168 to CMP0170 (FetchContent steps, `FetchContent_Populate`, `FETCHCONTENT_FULLY_DISCONNECTED`, 3.30), CMP0176 (`execute_process` output decoded as UTF-8, 3.31) and CMP0177 (`install` DESTINATION normalisation, 3.31). Floor: 77 policies arrived after 3.25, as of 4.4.2. | The range's upper bound flips every covered policy to NEW with no diagnostic. The other policies past 3.25 are removals that fail loudly or platform plumbing, so these six are the ones that change a build quietly. | Reading heuristic. A diff that changes a `cmake_minimum_required` bound and names none of the DECIDE policies it crosses is the finding. | SHOULD |

## What Agents Get Wrong Here

1. **Writing an old floor from training data** (`VERSION 3.5`, `3.8`,
   `2.8.12`), or adding a dependency that has one. On 3.31 and newer that is a
   gate error, and below 3.5 it is a hard error on 4.x. The dependency-floor
   scan (CMK-VER-05) and CMK-VER-02 catch it.
2. **Assuming a bare floor gives NEW behaviour up to the running CMake.** It
   leaves every later policy unset. To see it, add `cmake_policy(GET CMP0180 v)`
   after `project()` in a scratch copy and configure with the leg's binary
   under its gate spelling (`-Werror=author` on 4.4, `-Werror=dev` on 4.3 or
   older). An empty `v` means unset (CMK-VER-02).
3. **"Fixing" CMake-4 breakage with a global `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`**
   in a preset or a CI environment, or emitting that variable for a 3.x build
   where it does nothing. CMK-DEP-15 and CMK-DEP-30 own the fix (CMK-VER-06).
4. **Silencing a policy gate error with `SET … OLD`**, which the gate reports
   only once the binary deprecates that OLD (CMP0155 from 4.4.2, CMP0177 not
   yet). The CMK-VER-07 grep is the only check that sees every one.
5. **Copying an experimental UUID from cmake.org or `master`.** Count it in the
   pinned binary (CMK-VER-09).
6. **Copying a two-dot range from a real repository** (yaml-cpp ships one). The
   CMK-VER-01 grep catches it.
7. **Citing a 4.5 or `master` feature as current** (presets schema 13,
   `CMD_STRICT`, `PRINT_TARGETS`). Read `cmake --help-manual` on the pinned
   binary (CMK-VER-04).

## Re-check

- D1: on the CMake 4.5 release, re-measure `-Werror=dev`, which the gate
  spellings in this file assume (CMK-CORE-01), and add 4.5's rows to the
  CMK-VER-04 table.
- D7: on every CMake release, re-read `Help/dev/experimental.rst` at the new
  tag, because the CMK-VER-09 UUIDs rotate.
- The count of policies past 3.25 (77 as of 4.4.2, 2026-09-26) grows with each
  minor, so re-list the DECIDE set for CMK-VER-08.
