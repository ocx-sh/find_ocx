---
paths:
  - "**/CMakeLists.txt"
  - "**/*.cmake"
  - "**/*.cmake.in"
  - "**/CMakeLists.txt.in"
  - "**/CMakePresets.json"
  - "**/CMakeUserPresets.json"
  - "**/*.pc.in"
  - "**/.gersemirc"
  - "**/.cmake-format*"
summary: "The CMake build index: the configure gate, the non-negotiables, and where the depth lives for listfiles, modules, Config and pkg-config templates, presets and the Bazel seam"
keywords: cmake,cmakelists,cmake-presets,ctest,cmake_minimum_required,policies,find_package,fetchcontent,cpm,hunter,toolchain,dependency-provider,cps,install,export,gnuinstalldirs,pkg-config,cross-compiling,gersemi,rules_foreign_cc,cpp,c++
license: Apache-2.0
repository: https://github.com/ocx-sh/grimoire-lore
---

# CMake Build

Contents: [The Gate](#the-gate) · [Non-Negotiables](#non-negotiables) ·
[Rules This File Owns](#rules-this-file-owns) ·
[Where the Depth Is](#where-the-depth-is) · [Severity](#severity) ·
[Siblings](#siblings)

**Before trusting any rule below, know what a green configure does not
prove.** It does not prove the gate ran: `-Werror=author` exits 0 on 3.31 and
4.3, and on 3.31.12 a preset's `"warnings": {"deprecated": false}` beats a
command-line `-Werror=dev` (`CMK-CORE-01`). It does not prove the floor you
wrote: `VERSION 3.15..4.3` is one literal that collapses to 3.15
(`CMK-VER-01`), an explicit policy `OLD` passes the gate (`CMK-VER-07`), and a
stale experimental UUID only warns, or says nothing (`CMK-VER-09`). It does not
prove which copy of a dependency won: a FetchContent redirect answers every
later `find_package` as compatible with any version (`CMK-DEP-09`), and a
re-pointed `<Pkg>_ROOT` keeps the old `<Pkg>_DIR` (`CMK-DEP-13`). It does not
prove the user's dependency provider ran, because a project `set()` of
`CMAKE_PROJECT_TOP_LEVEL_INCLUDES` hides it (`CMK-TC-04`). It does not prove the
package can be consumed, because a missing `find_dependency` fails only in the
consumer (`CMK-INST-01`). And uninitialized variables stay ignored under either
gate spelling (`CMK-CORE-03`). All of these look exactly like a pass.

## The Gate

Run it after every change, narrowest first. Verified 2026-09-26 on CMake
3.31.12, 4.3.4 and 4.4.2, with gersemi 0.29.1.

```sh
BIN=/opt/cmake-4.4.2/bin   # the pinned CMake this leg provisions (CMK-VER-03), never a cmake on PATH
GATE=-Werror=author        # CMake 4.4 or newer only. 4.3 or older, or one command line serving both: -Werror=dev
PRESET=ci                  # the leg's own configure preset
BUILD_DIR=build            # that preset's binaryDir
CONFIG=Release
# 1. The canary: the gate is live on this binary through this preset. Exit 1 is the pass, exit 0 the finding.
printf 'message(AUTHOR_WARNING "gate canary")\n' > canary.cmake
"$BIN/cmake" --preset "$PRESET" --fresh -B build-canary "$GATE" -DCMAKE_PROJECT_INCLUDE="$PWD/canary.cmake"
# 1b. The deprecation canary. A preset that sets deprecated to false still passes canary 1 and fails this one on 4.3 or older. Exit 1 is the pass.
printf 'message(DEPRECATION "gate canary")\n' > canary-dep.cmake
"$BIN/cmake" --preset "$PRESET" --fresh -B build-canary-dep "$GATE" -DCMAKE_PROJECT_INCLUDE="$PWD/canary-dep.cmake"
# 2. Formatting, SHOULD (CMK-CORE-04). Tracked listfiles only: a build tree that .gitignore does not exclude fails it.
git ls-files -z -- '*CMakeLists.txt' '*.cmake' | xargs -0 -r gersemi --check
# 3. Configure, build and test. Each exit 0 is the pass.
"$BIN/cmake" --preset "$PRESET" --fresh "$GATE"
"$BIN/cmake" --build "$BUILD_DIR" --config "$CONFIG"
"$BIN/ctest" --test-dir "$BUILD_DIR" -C "$CONFIG" --output-on-failure --no-tests=error --timeout 300
```

The gate is spelled per binary and pinned: `-Werror=author` on CMake ≥ 4.4,
`-Werror=dev` on ≤ 4.3, and `-Werror=dev` whenever one command line serves
legs on both sides, which 4.4.2 still honours with a one-line deprecation
notice. The canary measured exit 1 under `-Werror=dev` on all three binaries,
and exit 0 under `-Werror=author` on 3.31.12 and 4.3.4. `$BIN`, never a `cmake`
off `PATH`: on 2026-09-26 the hosted `ubuntu-24.04` and `windows-2025` images
ship 3.31.6 and `macos-15` ships 4.4.2, so one unpinned workflow runs two gates.

Add the checks the change reaches. Before a CMake bump or a dependency add or
re-pin, run the dependency-floor scan (`CMK-VER-05`). A library that installs
runs the round trip (`CMK-INST-01`), a consumed library the as-subproject smoke
(`CMK-TEST-09`), anything that fetches the offline configure (`CMK-DEP-16`),
and a wrappable library the wrap simulation (`CMK-BZL-01`). A task is done when
a command, its exit code, and the tree it ran against are all named.

## Non-Negotiables

Every line below blocks a merge. IDs resolve to the depth files in
[Where the Depth Is](#where-the-depth-is), where each rule carries its
rationale and verification, or to this file's own table.

| # | Rule | ID |
|---|---|---|
| 1 | Every CI configure leg runs under the gate spelled for its binary, proven by the canary through the leg's own preset. Never `-Werror=author` below 4.4, never a committed preset that sets `dev` or `deprecated` warnings to `false`, and never a schema-12 presets file that still spells `dev`. | CMK-CORE-01, CMK-CORE-02 |
| 2 | A version range has exactly three dots (`VERSION 3.25...4.4`). A "Policy CMPxxxx is not set" error is cleared by adopting NEW, never by an unguarded `cmake_policy(SET … OLD)`. | CMK-VER-01, CMK-VER-07 |
| 3 | Before a CMake bump or a dependency add or re-pin, scan the fetched and vendored trees for an effective policy version below 3.10. Clear one on 4.x with `CMAKE_POLICY_VERSION_MINIMUM` set and restored around the one call that loads it, and on 3.x by a re-pin or a one-line patch. Never a preset, a CI variable, a project-wide `set()` or a warning switch. | CMK-VER-05, CMK-DEP-15, CMK-DEP-30 |
| 4 | Check every command, keyword, variable and preset field against the floor on the pinned binary, and guard anything newer with `if(CMAKE_VERSION VERSION_GREATER_EQUAL X.Y)`. Copy an experimental UUID only from the pinned binary's tag. | CMK-VER-04, CMK-VER-09 |
| 5 | Quote every `${…}` operand of an `if()` comparison, iterate with `foreach(… IN LISTS …)` on lines written or touched, parse a new public command with `PARSE_ARGV`, never `PARSE_ARGN` below a 4.4 floor, and never invent an option or variable named `CMAKE_…`. | CMK-LANG-01, CMK-LANG-02, CMK-LANG-04, CMK-LANG-05, CMK-LANG-11 |
| 6 | Every `target_link_libraries` of a library names `PUBLIC`, `PRIVATE` or `INTERFACE`, defaulting to `PRIVATE`. A definition an installed header reads is `PUBLIC`, and no usage requirement is built on `CMAKE_SOURCE_DIR`. Never overwrite `CMAKE_<LANG>_FLAGS`, `_FLAGS_<CONFIG>` or a linker-flags variable, and never put a literal `-Werror` or `/WX` in an installable library. | CMK-TGT-01, CMK-TGT-03, CMK-TGT-04, CMK-TGT-09, CMK-TGT-21 |
| 7 | `CMAKE_CXX_STANDARD` and `_REQUIRED` are set only inside `if(NOT DEFINED CMAKE_CXX_STANDARD)`, the MSVC runtime only through `CMAKE_MSVC_RUNTIME_LIBRARY` or its property, never a `/MD` or `/MT` flag, and never by a `set()` that runs by default after `project()` outside `if(NOT DEFINED CMAKE_MSVC_RUNTIME_LIBRARY)`, and `CMAKE_BUILD_TYPE` only by the top level on a single-config generator, never by a library. | CMK-TGT-05, CMK-TGT-06, CMK-TGT-16, CMK-TGT-17 |
| 8 | A dependency's library type is chosen by a cache entry or scoped to its one add, never by `BUILD_SHARED_LIBS` with an unguarded `FORCE`. A library that is not top level never lets `option(BUILD_SHARED_LIBS … ON)` create the parent's cache entry. Every static library linked into a shared object is PIC. Raising the standard to C++20 without module sources sets `CMAKE_CXX_SCAN_FOR_MODULES OFF`. | CMK-TGT-10, CMK-TGT-11, CMK-TGT-12, CMK-TGT-18 |
| 9 | Prove every install, export or Config-template change with the round trip, never with a green install. The template redeclares each PUBLIC or INTERFACE dependency with `find_dependency()`, and every destination comes from `GNUInstallDirs`, relative, never a `lib` literal. | CMK-INST-01, CMK-INST-03, CMK-INST-09, CMK-INST-10 |
| 10 | Never pin a fetched git dependency to a branch or `HEAD`, never fetch a URL without `URL_HASH`, and an installable library never forces FetchContent or CPM outside a top-level guard, a `FIND_PACKAGE_ARGS` declare or a try-find fallback. | CMK-DEP-01, CMK-DEP-03, CMK-DEP-07 |
| 11 | Every configure-time network touch is satisfiable offline, proven by a configure with the network removed and `-DCMAKE_POLICY_DEFAULT_CMP0170=NEW`. A wrappable library proves it with the wrap simulation, never with `FETCHCONTENT_FULLY_DISCONNECTED` alone. | CMK-DEP-16, CMK-BZL-01 |
| 12 | `<Pkg>_DIR` in `CMakeCache.txt` is the sticky record of which copy won. Switch copies with `--fresh`, and a module that re-points `<Pkg>_ROOT` unsets `<Pkg>_DIR` when the value changes. | CMK-DEP-13 |
| 13 | One `CMAKE_TOOLCHAIN_FILE` per configure leg from one source of record. It, `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` and every `VCPKG_*` input are set before the first `project()`, preferably in the preset, and project code never sets or appends the top-level includes, because the provider belongs to the user. | CMK-TC-01, CMK-TC-03, CMK-TC-04 |
| 14 | A module's `file(DOWNLOAD)` checks `STATUS`, carries `EXPECTED_HASH` and a `TIMEOUT` or `INACTIVITY_TIMEOUT`, and every `execute_process` tests its result or passes `COMMAND_ERROR_IS_FATAL ANY`. | CMK-MOD-01, CMK-MOD-02, CMK-MOD-04, CMK-MOD-17 |
| 15 | A negative test asserts the exit status and the diagnostic together, never `WILL_FAIL` and never a message-only regex. CI runs ctest with `--output-on-failure --no-tests=error`, a matching `-C` and a `--timeout`, and a consumed library gates its tests on a project-prefixed option, never on `BUILD_TESTING` alone. | CMK-TEST-03, CMK-TEST-06, CMK-TEST-07, CMK-TEST-09 |
| 16 | Every committed presets file, includes too, declares a `"version"` the oldest CI CMake parses, and `CMakeUserPresets.json` is never committed. | CMK-CI-01, CMK-CI-02 |
| 17 | A generated or regenerated `CMakeLists.txt` or `BUILD.bazel` is derived: name its generator before editing it or claiming drift, and never hand-edit it. A pair whose CMake side carries no version is "not knowable statically", never "no drift". | CMK-BZL-11, CMK-BZL-12 |
| 18 | No verification script pipes a match stream into an early-exiting reader under `pipefail`, and each scopes its tree on purpose: own-code checks exclude `_deps` and build trees, the dependency-floor scan includes them. | CMK-CORE-05 |

## Rules This File Owns

The gate and the checks around it, which belong to no single depth file. Run
each command from the repository root, once per directory of CI definitions.

```sh
CI_DIR=.github
# (a) CMK-CORE-01: a committed preset that switches the gate's warnings off
grep -rn --include='CMakePresets.json' --include='CMakeUserPresets.json' -e '"dev"[[:space:]]*:[[:space:]]*false' -e '"deprecated"[[:space:]]*:[[:space:]]*false' .
# (b) CMK-CORE-01: the gate spellings CI passes
grep -rn -e 'Werror=author' -e 'Werror=dev' "$CI_DIR"
# (c) CMK-CORE-02: a schema-12 presets file still spelling dev
find . -name CMakePresets.json -not -path '*/_deps/*' -print0 | xargs -0 -r -n1 jq -e '.version >= 12 and ([.configurePresets[]? | (.warnings // {}), (.errors // {}) | has("dev")] | any)'
# (d) CMK-CORE-03: uninitialized-variable checking, if adopted
grep -rn -e 'Werror=uninitialized' -e 'warn-uninitialized' "$CI_DIR"
# (e) CMK-CORE-04: the dead formatter in configuration or CI
grep -rn --include='*.yml' --include='*.yaml' --include='*.txt' --include='*.toml' -e 'cmake-format' -e 'cmake_format' -e 'cmake-lint' -e 'cmakelang' .
find . -name '.cmake-format*' -not -path './.git/*'
# (f) CMK-CORE-05: early-exit readers in files that set pipefail
grep -rl --include='*.sh' --include='*.bash' --include='*.yml' --include='*.yaml' --exclude-dir='_deps' --exclude-dir='build*' --exclude-dir='.git' -e 'pipefail' -e 'shell: bash' . | xargs -r grep -HnE -e '[|] *grep( +-[a-zA-Z]+)* +-[a-zA-Z]*[qm]' -e '[|] *rg( +-[a-zA-Z]+)* +-[a-zA-Z]*[qm]' -e '[|] *head' -e '[|] *grep( +-[-a-zA-Z=0-9]+)* +--quiet' -e '[|] *grep( +-[-a-zA-Z=0-9]+)* +--silent' -e '[|] *grep( +-[-a-zA-Z=0-9]+)* +--max-count'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CORE-01 | Run every CI configure leg under the gate spelled for the binary it runs: `-Werror=author` on CMake ≥ 4.4, `-Werror=dev` on ≤ 4.3, and `-Werror=dev` when one command line serves both sides. Never pass `-Werror=author` below 4.4. Run the canary through the leg's own `--preset`, and never commit a preset whose `warnings` or `errors` set `dev` or `deprecated` to `false`. A harness's inner configures are `CMK-TEST-02` in `testing.md`. **pinned** spelling. | `-Werror=author` is silently ignored on every binary from 3.31.12 to 4.3.4, 4.0.7, 4.1.6 and 4.2.7 included. `-Werror=dev` fails on all six, and on 4.4.2 maps onto `author`, whose children `deprecated`, `experimental`, `policy` and `install-absolute-destination` it also fails. On 3.31.12 a preset's `"warnings": {"deprecated": false}` let a deprecation through `-Werror=dev` with exit 0 (measured 2026-09-26). The gate fails every `message(AUTHOR_WARNING)`, an informational one too: cpp-best-practices/cmake_template's "Building Tests" note stops its configure, and the same note exits 1 under `-Werror=dev` on 3.31.12, 4.3.4 and 4.4.2 and under `-Werror=author` on 4.4.2, while `message(STATUS)` exits 0 on all three (measured 2026-09-26). Downgrade such a note to `STATUS`, never relax the gate for it. | The Gate's two canaries on each leg's binary and preset: exit 0 from either is the finding. Only the deprecation canary goes red on a preset that sets `deprecated` to `false` (measured 2026-09-26 on 3.31.12 and 4.3.4). (a): empty output passes, any line is the finding. (b) lists the gate lines. Empty output is the finding unless the preset's `errors` carries the gate and the canary exits 1. A `Werror=author` hit on a leg that can resolve CMake below 4.4, such as a runner default of 3.31.6, is the finding. | MUST. Floor: any CMake, the spelling splits at 4.4 |
| CMK-CORE-02 | When a presets file raises `"version"` to 12, rename `warnings.dev` and `errors.dev` to `author` in the same edit. For one presets file that must gate 3.31 through 4.4, stay at schema 10 or lower with `"errors": {"dev": true}`. The ceiling for the oldest CI CMake is `CMK-CI-01` in `presets-and-ci.md`. | 4.4.2 rejects `dev` under schema 12 ("File version must be 11 or lower for warnings.dev support"). 3.31.12 accepts schema 10 at most and 4.3.4 schema 11. Schema 10 with `errors.dev` gates all three binaries with no deprecation notice (measured 2026-09-26). | (c): a printed `true` is the finding. `false` or no output passes. | MUST. Floor: schema 12 is CMake 4.4 |
| CMK-CORE-03 | If the project wants uninitialized-variable checking, spell it per binary: `-Werror=uninitialized` on ≥ 4.4, and `--warn-uninitialized` plus `-Werror=dev` on ≤ 4.3. No single spelling covers both sides. | Neither gate spelling reaches the `uninitialized` or `unused-cli` category on 4.4.2, where both default to ignore. `-Werror=uninitialized` exits 0 silently on 3.31.12 and 4.3.4, and `--warn-uninitialized` only warns on 4.4.2. 0 of 46 exemplar projects run it, and it also fires inside fetched subprojects. | (d): empty output means not adopted, which is no finding at this tier. A `Werror=uninitialized` hit on a leg below 4.4, or a `warn-uninitialized` hit on a 4.4 leg, is inert (finding). | CONSIDER. Floor: the spelling splits at 4.4 |
| CMK-CORE-04 | Gate formatting with `gersemi --check` over tracked listfiles, never `--diff`. Never add cmake-format or cmake-lint, and migrate an existing `.cmake-format*` file or `cmake-format` job, never extend it. No rule demands a `.gersemirc`, except in a module project that runs gersemi (`CMK-MOD-15`). Never write "the linter catches this": name the gate category or the grep. | cmake-format and cmake-lint last released 0.6.13 on 2020-08-19, and no maintained semantic linter exists (`marzer/check-cmake` last pushed 2025-08-07). `--diff` exits 0 when it would reformat, and `gersemi --check .` descends into any build tree that `.gitignore` does not exclude and fails on its generated files (gersemi 0.29.1, measured 2026-09-26). Adoption is 0 of 46, hence SHOULD. | The Gate's gersemi line: exit 0 passes. (e): empty output from both commands passes, and any hit means migrate. | SHOULD. Floor: gersemi 0.29.1 (2026-09-14) |
| CMK-CORE-05 | In any verification script over a CMake tree, never pipe a match stream into an early-exiting reader (`grep -q`, `grep -m1`, ripgrep's `-q`, `head`) under `set -o pipefail`. Use one `grep -rq` with a directory operand and no pipe. Own-code checks exclude build trees and `_deps`, and the dependency-floor scan (`CMK-VER-05`) includes them. | The reader exits at the first match, the writer dies of SIGPIPE, and `pipefail` turns that into "not found" with rc 141 on a tree full of matches. It cost a first exemplar table five cells and a whole repository row. | (f): empty output passes. Each printed line is the finding unless its producer writes one line, such as a hash, `file` output or a scalar: the reader takes that whole line before it exits. `echo` of a variable that holds a file or a command's full output is a stream and stays a finding (measured 2026-09-26, bash 5.3.0 under `pipefail`: a 64 KiB multi-line value into `grep -qF` was nonzero in 199 of 200 runs, 16 KiB and a 1 MiB single line in 0 of 200). It reads every shell script and workflow in the tree, because a fixed directory operand that does not exist scans nothing and prints nothing, and it counts a workflow's `shell: bash`, which GitHub Actions runs as `bash --noprofile --norc -eo pipefail {0}` (workflow-syntax docs, read 2026-09-26). It catches separated flags (`grep -E -q`), ripgrep's `-q`, `grep -m1`, and `--quiet`, `--silent` and `--max-count`. | MUST. Floor: shell-level, any CMake |

## Where the Depth Is

| Doing… | Read |
|---|---|
| Choosing or raising `cmake_minimum_required`, setting or silencing a policy, touching a `CMAKE_EXPERIMENTAL_*` variable, using a feature newer than the floor, or getting an old dependency to configure on CMake 4 | [cmake-build/versions-and-policies.md](cmake-build/versions-and-policies.md) |
| Writing any function, macro, `if()`, loop, cache variable or `option()`, returning a value from a function, or chasing "my `-D` did not take" | [cmake-build/language.md](cmake-build/language.md) |
| Writing a `.cmake` file other projects include (a Find module, a helper or copy-and-own module, a provider file), or anything that downloads or runs a process at configure time | [cmake-build/module-authoring.md](cmake-build/module-authoring.md) |
| Adding or changing a library or executable, linking anything, setting a flag, a language standard, the MSVC runtime or the build type, visibility, PIC, shared or static, or raising the standard to C++20 | [cmake-build/targets.md](cmake-build/targets.md) |
| Making a library installable or consumable: `install()` rules, the Config template and its version file, relocation, RPATH, a `.pc.in`, a multi-config install or a CPS export. A Config template with an unusual suffix loads no rule by glob, so reach it from the `CMakeLists.txt` that wires it | [cmake-build/install-and-export.md](cmake-build/install-and-export.md) |
| Adding, pinning or replacing a dependency (`find_package`, FetchContent, CPM, Hunter, vendoring, CPS import), injecting policy into one, making the configure work offline, or finding out which copy a configure used | [cmake-build/dependencies.md](cmake-build/dependencies.md) |
| Wiring a toolchain file, a package manager's toolchain, `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` or a dependency provider, or cross-compiling (sysroot, find-root modes, host tools, emulator) | [cmake-build/toolchains-and-providers.md](cmake-build/toolchains-and-providers.md) |
| Adding tests, gating the test tree, running CTest in CI, or testing a CMake module itself | [cmake-build/testing.md](cmake-build/testing.md) |
| Editing a presets file, including a file another presets file `include`s or one passed by `cmake --presets-file` (CMake ≥ 4.4), neither of which loads a rule by glob, standing up or changing a pipeline that runs CMake, setting a compiler launcher, or pinning the CMake a pipeline uses | [cmake-build/presets-and-ci.md](cmake-build/presets-and-ci.md), read from here, because no glob in this rule reaches `.github/workflows/`, so `CMK-CI` loads only through this line |
| Making the project wrappable by `rules_foreign_cc`, or keeping a CMake build and a Bazel build of the same code in step | [cmake-build/bazel-seam.md](cmake-build/bazel-seam.md) |
| Editing a vcpkg triplet, which is a `.cmake` file that loads only this rule, or a `portfile.cmake`, `vcpkg.json`, a `conanfile` or a Conan profile | `cpp-packaging/vcpkg.md` or `cpp-packaging/conan.md` (sibling set, see below) |
| Asking which copy, version or mechanism resolved a dependency, and why not the expected one | the `cmake-dependency-triage` skill |
| Moving a legacy tree to targets and a consumable package | the `cmake-modernize` skill |

## Severity

MUST = Block: fix before it lands. SHOULD = Warn: fix, or state why not in the
commit body. CONSIDER = Suggest: never blocks, never re-raised after a decline.

Rules marked **pinned** here or in a depth file encode an agreed decision
rather than a derivable fact: the 3.25 floor written `3.25...4.4`, the gate
spelling per binary, gersemi as SHOULD, the `CMAKE_POLICY_VERSION_MINIMUM`
value 3.10 (3.5 only inside a vcpkg port build), CPS shipped beside the Config
package and never instead of it, the explicit Conan flow over the cmake-conan
provider, `CMK-TGT-16` kept MUST without a Windows measurement, the
`CMK-LANG-04` migration clause, and `CMK-INST-18` and `CMK-BZL-09` held at
SHOULD. They are defaults an adopter overrides once, repository-wide, never per
leg. Overriding one is a decision. Ignoring one is a violation.

## Siblings

- **`cpp-packaging`**, Conan 2 and vcpkg: the manager and lock of record,
  recipes, manifests, ports and profiles. Loads on `conanfile.*`,
  `conandata.yml`, `conan.lock`, the vcpkg manifests and `portfile.cmake`. A
  `portfile.cmake` loads both rules on purpose, and the one-manager ban it
  relies on is `CMK-TC-02` here.
- **`bazel-quality`**, for a repository that also builds with Bazel. It owns
  every Bazel-side fact (`BZL-CC-22`, `-23`, `-24`, `-28`), and `bazel-seam.md`
  cites them by ID and never restates them.
