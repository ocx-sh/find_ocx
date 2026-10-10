---
title: Presets and CI Pipelines
summary: The CMK-CI family. Which presets schema a committed file may declare, why the user presets file never enters git, how CI legs map to presets, where a compiler launcher is set, and how an offline probe runs on a hosted runner
---

# Presets and CI Pipelines

Owns the two presets files and the pipeline around them: the schema a committed
`CMakePresets.json` declares, keeping `CMakeUserPresets.json` out of git, the
mapping from CI legs to presets, where a compiler launcher is set, and the
container form of an offline probe on a hosted runner. It does not own the ctest
line a pipeline runs (`--no-tests=error`, `--timeout`, `-C`) or the
as-subproject smoke job, which are `CMK-TEST` in `testing.md`. Pinning the CMake
a pipeline runs is CMK-VER-03 in `versions-and-policies.md`, and a CMake pinned
by a committed tool lock counts as pinned there. The configure gate, its
per-binary spelling and a preset that switches it off are CMK-CORE-01, and the
`dev` to `author` rename at schema 12 is CMK-CORE-02, both in the `cmake-build`
index. What an offline probe must prove is CMK-DEP-16 in `dependencies.md` and
CMK-BZL-01 in `bazel-seam.md`. The install round trip as a CI job is CMK-INST-18
in `install-and-export.md`. Conan's generated user presets file is CMK-CONAN-08
and a package manager's CI cache key is CMK-PKG-04, both in the `cpp-packaging`
rule.

Measured on CMake 3.31.12, 4.3.4 and 4.4.2 on 2026-09-26. Rules assume the
pinned 3.25 floor. `CI_DIR` names one directory of CI definitions or scripts,
default `.github`. Run each command once per such directory (`CI_DIR=ci`, then
`CI_DIR=.gitlab`), because one quoted variable holding two names is one missing
path and grep exits 2. Run every command from the repository root.

Contents: [Caught by the Oldest CI CMake and by Git](#caught-by-the-oldest-ci-cmake-and-by-git) ·
[Caught by Matching CI Steps Against Preset Names](#caught-by-matching-ci-steps-against-preset-names) ·
[Caught by One Grep for the Launcher](#caught-by-one-grep-for-the-launcher) ·
[Caught by Reading the Offline Job](#caught-by-reading-the-offline-job) ·
[What Agents Get Wrong Here](#what-agents-get-wrong-here) · [Re-check](#re-check)

## Caught by the Oldest CI CMake and by Git

Run `cmake --list-presets` from the repository root with the lowest CMake any CI
leg runs: its pin, or the runner image default where the leg pins nothing
(3.31.6 on hosted `ubuntu-24.04` and `windows-2025` as of 2026-09-26). That
binary parses the root file and every include against its own schema ceiling,
so it is the whole check for `CMK-CI-01`. Then two `git` commands for
`CMK-CI-02`. Presets need CMake 3.19, below the 3.25 floor, so neither row needs
a version gate.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CI-01 | Keep a committed presets file's `"version"`, and the `"version"` of every file it includes, at or below the schema ceiling of the oldest CMake any CI leg runs (table below). Under the pinned 3.25 floor, a floor leg that configures through a preset caps every file at schema 6. | 3.31.12 rejects schema 12 with `Unrecognized "version" 12: must be >=1 and <=10`, rc 1, and rejects a schema-11 include under a schema-10 root the same way. The author's newer local CMake accepts both, so the break shows only on the runner. 4.4.2 also rejects `errors.dev` at schema 12 (`File version must be 11 or lower`). Measured on 3.31.12, 4.3.4 and 4.4.2, 2026-09-26. Floor: CMake 3.19. | `cmake --list-presets` with the oldest CI leg's binary. Exit 0 is the pass. A nonzero exit reporting `Unrecognized "version"` or `File version must be` is the finding. `File not found` means no presets file, and the rule does not apply. With no such binary at hand, run the `jq` listing below and compare every number, includes too, against the table. | MUST |
| CMK-CI-02 | Never commit `CMakeUserPresets.json`. List it in `.gitignore`. | `cmake-presets(7)` at v4.4.2 says the file "should NOT be checked in": it holds one machine's paths and toolchains. 0 of 6 real corpus projects track one. Conan writes its own copy and silently skips a hand-written one, which is the Conan consequence CMK-CONAN-08 keeps. The user file includes `CMakePresets.json` implicitly at every schema, so it never needs an `include`. Floor: CMake 3.19. | `git ls-files -- '*CMakeUserPresets.json'`: empty output is the pass, any path printed is the finding. Then `git check-ignore --no-index CMakeUserPresets.json`: the name printed is the pass, empty output is the finding. | MUST |

| Schema | Needs CMake | Schema | Needs CMake |
|---|---|---|---|
| 6 | 3.25 | 10 | 3.31 |
| 7 | 3.27 | 11 | 4.3 |
| 8 | 3.28 | 12 | 4.4 |
| 9 | 3.30 | 13 | not released (4.5, as of 2026-09-26) |

The table is `cmake-presets(7)` at v4.4.2, confirmed by 3.31.12 and 4.0.7 to 4.2.7
accepting up to 10, 4.3.4 up to 11 and 4.4.2 up to 12 (measured 2026-09-26). The static fallback prints each root
file's schema and the files it includes. Run the same `jq` on each included
file, whose path is relative to the file that includes it. Empty output means
no presets file. A `jq: parse error` means the file is not JSON as committed,
such as a Jinja template in a project generator (friendlyanon/cmake-init,
2026-09-26). CMake never reads it, so the rule binds the generated file instead.

```sh
find . -name CMakePresets.json -not -path '*/_deps/*' -print0 | xargs -0 -r -n1 jq -r '(input_filename) + " " + (.version | tostring), (.include[]? | "  includes " + .)'
```

`cmake --presets-file` (CMake ≥ 4.4) reads a presets file under any name. The
rule's glob does not load for such a file, so treat it as a `CMakePresets.json`
for `CMK-CI-01` and add it to the listing. 3.31.12 and 4.3.4 stop on the flag
with `Unknown argument --presets-file`, rc 1, so every leg that passes it runs
4.4 or later (measured 2026-09-26).

## Caught by Matching CI Steps Against Preset Names

Two commands, then a read: the first lists the non-hidden configure presets, the
second lists the CI steps that call a preset. `condition` needs schema 3 (CMake
3.21) and `include` schema 4 (3.23), both below the 3.25 floor.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CI-03 | Configure each CI leg with `cmake --preset <name>`, and pass the matrix axes as `-D` or `-G` on top of it. Ship no CI-named preset that CI does not call. Compose OS, compiler and configuration from hidden bases with `inherits` and `condition`, never one flat preset per combination. | Presets that CI never calls drift from the matrix CI really runs, and nothing reports it: cpp-best-practices/cmake_template defines `ci-*` presets and then rebuilds the same matrix with raw flags. One preset plus the axes is the cheap conforming shape. Hidden ingredient presets (all of LLVM's are hidden) and developer presets are legal. The cross-product problem is open upstream as CMake issue 22538 (as of 2026-04-27). Floor: CMake 3.21 for `condition`. | Reading heuristic over the two commands below. Every non-hidden preset CI is meant to use must appear in the second command's hits. Presets present and empty second output is the finding: the presets are decorative. Empty output from the first command means no root presets file or no visible preset, and the rule does not apply. A hidden preset, or a plainly local developer preset, missing from CI is not a finding. | SHOULD |

```sh
find . -maxdepth 1 -name CMakePresets.json -print0 | xargs -0 -r jq -r '.configurePresets[] | select(.hidden != true) | .name'
grep -rn -e 'cmake --preset' -e 'ctest --preset' -e '--preset=' "${CI_DIR:-.github}"
```

## Caught by One Grep for the Launcher

One grep over CMake files, presets and workflow YAML, then a read of each `set`
hit for its guard. The cache variable needs CMake 3.4 and the environment
variable 3.17, both below the 3.25 floor.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CI-04 | Set a compiler launcher only as the cache entry `CMAKE_<LANG>_COMPILER_LAUNCHER`, from one place: a preset's `cacheVariables`, a `-D`, or the environment variable of that name. Project code that offers a default wraps it in `if(NOT DEFINED CMAKE_<LANG>_COMPILER_LAUNCHER)`, or writes it as `set(... CACHE FILEPATH ...)` without `FORCE`, and picks one tool with `find_program(NAMES sccache ccache)`. Never use `RULE_LAUNCH_COMPILE`, and never set a chained list. | An unconditional `set()` in project code shadows the caller's `-D` and nothing reports it: `build.ninja` carries the project's launcher (measured on 3.31.12 and 4.4.2). A list that prepends the project's launcher to the caller's overrides their choice the same way. apache/arrow's guard is the reference shape. A `CACHE` write without `FORCE` is the same guard: a caller's `-D` and the environment variable both survive it into `CMakeCache.txt` and the build files (measured 2026-09-26 on 3.31.12 and 4.4.2, the shape of cpp-best-practices/cmake_template's `cmake/Cache.cmake`). Floor: CMake 3.4. | `grep -rn --include='CMakeLists.txt' --include='*.cmake' --include='CMakePresets.json' --include='*.yml' --include='*.yaml' -e 'COMPILER_LAUNCHER' -e 'RULE_LAUNCH_COMPILE' .` Every `RULE_LAUNCH_COMPILE` hit is a finding. A `set(CMAKE_<LANG>_COMPILER_LAUNCHER ...)` outside an `if(NOT DEFINED ...)` or `if(NOT CMAKE_<LANG>_COMPILER_LAUNCHER)` guard is a finding, unless it is a `CACHE` write without `FORCE`. A plain `set()` or a `CACHE ... FORCE` write outside the guard stays a finding. Empty output means no launcher, and the rule does not apply. | SHOULD |

```cmake
# wrong: shadows the caller's -DCMAKE_CXX_COMPILER_LAUNCHER=sccache
set(CMAKE_CXX_COMPILER_LAUNCHER ccache)

# right: a default only when the caller chose nothing
if(NOT DEFINED CMAKE_CXX_COMPILER_LAUNCHER)
    find_program(PROJ_LAUNCHER NAMES sccache ccache)
    if(PROJ_LAUNCHER)
        set(CMAKE_CXX_COMPILER_LAUNCHER "${PROJ_LAUNCHER}")
    endif()
endif()
```

## Caught by Reading the Offline Job

Two greps over the CI directory, then a read of each container step. The wiring
has no CMake floor. `CMAKE_POLICY_DEFAULT_CMP0170` needs CMake 3.30, and below
that it is an unused variable, not an error.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CI-05 | On a hosted `ubuntu-24.04` runner, run the offline probes of CMK-DEP-16 and CMK-BZL-01 inside a `--network none` container, never under bare `unshare -rn`. Mount the checkout, use an image that carries the pinned CMake and generator, keep `-DCMAKE_POLICY_DEFAULT_CMP0170=NEW` on the probe, and never discard its exit status. | Ubuntu 24.04 restricts unprivileged user namespaces (`kernel.apparmor_restrict_unprivileged_userns=1`), and `unshare` fails on the stock image ([actions/runner-images#10443](https://github.com/actions/runner-images/issues/10443)). The fix PR, actions/runner-images#11489, closed unmerged. A `--network none` container passes a clean tree and fails a fetch with `Could not resolve hostname` (4.4.2, 2026-09-26), and fails outright when the image lacks the generator. macOS runners ship no Docker, so the probe stays Linux-only there. SHOULD because no hosted runner was measured. Floor: none. | `grep -rn -e 'unshare -rn' -e 'unshare --net' "${CI_DIR:-.github}"`: empty output is the pass, and a hit in a job on `ubuntu-24.04` or `ubuntu-latest` is the finding. Then `grep -rn -e '--network none' -e '--network=none' "${CI_DIR:-.github}"` and read each hit: a step ending in `\|\| true` is the finding. Empty output from this second command means no container probe, which is a finding only for a project that owes one of the two probes. | SHOULD |

The probe below runs the CMK-DEP-16 form. For the CMK-BZL-01 probe, drop
`-DFETCHCONTENT_FULLY_DISCONNECTED=ON`, because the wrapper passes none. The
gate is spelled for the image's CMake line (CMK-CORE-01).

```sh
IMAGE=registry.example/ci-cmake:4.4.2 # carries the pinned CMake and ninja
docker run --rm --network none -v "$PWD:/src" -w /src "$IMAGE" \
  cmake -S . -B build-offline -G Ninja -Werror=author \
  -DFETCHCONTENT_FULLY_DISCONNECTED=ON -DCMAKE_POLICY_DEFAULT_CMP0170=NEW
# an image with CMake 4.3 or older spells the gate -Werror=dev
```

## What Agents Get Wrong Here

1. **Hard-coding a launcher** with `set(CMAKE_CXX_COMPILER_LAUNCHER ccache)` or
   `RULE_LAUNCH_COMPILE`, copied from old tutorials. It silently overrides the
   user's `-D`. `CMK-CI-04` is the check.
2. **Bumping presets to the newest schema.** The agent's newest local CMake
   accepts it and the runner's 3.31.6 rejects it. The same happens when only an
   included file is bumped. Run `CMK-CI-01`'s `cmake --list-presets` with the
   oldest leg's binary before committing.
3. **Committing `CMakeUserPresets.json` "so the team shares a setup".** A shared
   setup belongs in a named preset in `CMakePresets.json`. `CMK-CI-02` is the
   check.
4. **Writing CI-named presets and then a hand-rolled matrix beside them.** The
   presets rot unseen because nothing runs them. `CMK-CI-03` matches the names.
5. **Emitting `unshare -rn` in a GitHub workflow**, then silencing
   `Operation not permitted` with `|| true`. The probe then proves nothing.
   `CMK-CI-05` is the check.
6. **Prescribing `cmake --workflow` and workflow presets as "the modern
   way".** 0 of 46 corpus repositories use them, so no rule here asks for one.
7. **Switching the gate off from a preset.** A preset's
   `"warnings": {"deprecated": false}` beats a command-line `-Werror=dev` on
   3.31.12. CMK-CORE-01 owns the grep, and the canary runs through the leg's
   own `--preset`.
8. **Passing `-DCMAKE_BUILD_TYPE` on a multi-config leg** and believing it
   selects the configuration. The `-C` clause of CMK-TEST-06 in `testing.md`
   catches the mismatch.
9. **Relaxing the gate for an informational `message(AUTHOR_WARNING)`.** Every
   `AUTHOR_WARNING` fails the gate, a "Building Tests" note included, and the
   agent reaches for `-Wno-error` or a preset switch. Downgrade the note to
   `message(STATUS)`. CMK-CORE-01 owns the measurement.

## Re-check

- D1: the CMake 4.5 release adds schema 13 to the `CMK-CI-01` table and
  re-checks the gate spelling in the probe (CMK-CORE-01).
- The runner image default CMake (3.31.6 on `ubuntu-24.04` and `windows-2025`
  as of 2026-09-26), on each runner-images release, because it sets the
  `CMK-CI-01` ceiling for legs that pin nothing.
- `CMK-CI-05` on a real hosted runner: `unshare -rn` failing and the container
  probe passing raises it to MUST, and `unshare` passing retires it.
