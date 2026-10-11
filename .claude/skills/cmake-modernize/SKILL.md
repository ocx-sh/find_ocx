---
name: cmake-modernize
description: Ordered, once-per-repository procedure that takes a legacy directory-scoped CMake tree to target-based, installable and find_package-consumable CMake, with one exit check per step, a gated install-move-consume round trip and an as-subproject smoke as the two end proofs. Use when someone asks to modernize, clean up or migrate an old CMake tree as a whole, meaning replace include_directories, add_definitions or global CMAKE_CXX_FLAGS with target_* commands across the tree, make a legacy library installable, exportable and consumable through a Config package or CPS, or bring a legacy tree under the configure gate. Not for a one-line edit such as a single target_link_libraries keyword or one cmake_parse_arguments call, which the cmake-build rules cover without a procedure. Not for a tree that does not configure or finds the wrong dependency copy, which is cmake-dependency-triage, not for Conan or vcpkg manifests, which is cpp-packaging, and not for the standards themselves, which are the cmake-build rules.
license: Apache-2.0
metadata:
  summary: Takes a legacy CMake tree to target-based and consumable in ten ordered steps, each closed by a command, never in one rewrite
  keywords: cmake,modernize,modern-cmake,legacy,migration,targets,target_link_libraries,include_directories,add_definitions,CMAKE_CXX_FLAGS,cmake_minimum_required,PROJECT_IS_TOP_LEVEL,install,export,find_package,config-package,round-trip,cps,pkg-config,cmake_parse_arguments,PARSE_ARGV,configure-gate,gersemi
---

# cmake-modernize

Take a CMake tree that already builds from directory scope to targets, then make
it consumable by a separate project, in a fixed order that keeps every step
reviewable on its own. The procedure flags a legacy tree and converts it one
target per diff. It never rewrites the tree in one pass, and it never raises the
project's minimum CMake on its own.

This skill assumes the `cmake-build` rule set is installed and cites rules by ID.
Every command here was run against planted violating and compliant projects on
CMake 3.31.12, 4.3.4 and 4.4.2, and the whole procedure end to end on seven real
legacy trees (listed in the failure-modes reference) on 3.31.12 and 4.4.2
(2026-09-26). Their failures group into nine classes, `C1` to `C9`, and the
procedure checks classes, not instances.

Contents: [Stop condition](#stop-condition) · [Before you start](#before-you-start) ·
[The procedure](#the-procedure) · [Reviewable units](#reviewable-units) · [What it refuses](#what-it-refuses) ·
[Pinned defaults](#pinned-defaults) · [Failure classes](#failure-classes) ·
[MUST rows this procedure enforces](#must-rows-this-procedure-enforces) ·
[References](#references)

## Stop condition

Stop when all three hold:

- The gated round trip (`CMK-INST-01`) exits 0 on every CMake line CI runs.
- The as-subproject smoke (step 7) passes.
- Every inventory hit in the plan file is marked `converted`,
  `flagged-not-converted` or `vacuous`, with the step that settled it.

Then stop. Do not start a second modernization pass, do not bump the minimum,
and do not add CPS unless step 9 was asked for. A step with no exit-check output
captured in the plan file is not done, whatever the build says.

## Before you start

**Entry check.** The unmodified tree configures and builds today with the
options its documentation gives for a library-only build (`-DBUILD_DEMOS=OFF`).
Write them into the plan file once, and every later configure, the round trip
(`CFG_ARGS`) and the smoke pass them. Run the entry check ungated on the oldest
CMake line CI runs (3.31 with no CI). A floor below 3.5 stops every 4.x
configure with `Compatibility with CMake < 3.5 has been removed from CMake`,
which is step 1's to fix as long as the oldest line configures. Otherwise stop.
A wrong dependency copy is `cmake-dependency-triage`, and an absent host
dependency or compiler is the owner's to install or switch off.

Run `git status --short` after the entry configure. Empty output = pass. A
tracked file the configure changed is restored before each step's commit, or it
rides along unnamed (`C9`). A 4.4 gate error whose category a later step owns
(`install-absolute-destination`, `CMK-INST-10`, is step 6's) is demoted on the
4.4 line alone until that step, with
`-Werror=author -Wno-error=install-absolute-destination`, as a row of that
step. The canary still exits 1, and step 6's round trip runs without it.

**The gate is on from step 1, not step 8.** Every configure this skill runs
uses the configure gate spelled for its binary (`CMK-CORE-01`):

| Binary line | Gate spelling |
|---|---|
| CMake 4.4 and later | `-Werror=author` |
| CMake 4.3 and older | `-Werror=dev` |
| One command line serving both sides | `-Werror=dev` |

`-Werror=author` on 3.31.12 or 4.3.4 exits 0 and does nothing (re-measured
2026-09-26). The scripts below take the spelling in `GATE`.

**The evidence rule.** "Done" comes from a command's output captured in the
plan file: an exit code, a grep's lines, the round trip's last `_DIR` line.
Never from a green build or install, and never from reading the diff. Read the
exit code first (`C8`). A configure that did not exit 0 voids every grep of its
build tree. A grep that exits 2 on a missing operand is neither a pass nor a
hit. A gate is live on a leg only when the canary exits 1 through that leg's own
binary, preset or script. Where a pass grep cannot see a spelling, read its list
command too (`F1b` beside `F1`, the option lister beside the smoke).

**The plan file.** Write `cmake-modernize-plan.md` at the repository root (the
adopter may name it otherwise, once). One row per inventory hit:

| Column | Holds |
|---|---|
| Hit | `file:line` as the inventory printed it |
| Command | The inventory command ID that printed it (`I1` to `I14`, `I2b`, `F1`, `F1b`) |
| Rule | The rule ID the hit violates |
| Step | The step that will touch it |
| Status | `open`, `converted`, `flagged-not-converted` (vendored, the owner declined, or a component the host cannot configure, with the missing prerequisite named) or `vacuous` |

Every hit, and every file a diff touches, has a row naming the step that
settles it (`C9`). A finding that blocks an earlier step's check is a row of the
step that owns it. One no step can convert is `flagged-not-converted` with its
owner or prerequisite named, never left `open`.

**The caller contract (`C6`).** Step 0 also writes one `contract:` row per name
a caller outside the tree uses today: each option with its default, documented
install knob, exported target name, the Find-module name when CMake ships one,
each installed `.pc`, and each public command. Read them from the option lister
in [references/proofs.md](references/proofs.md#the-as-subproject-smoke), the
`install()` and `export()` calls, the documentation and CI. A diff that changes
one keeps the old spelling working or records a changelog item, and its step's
exit runs the old spelling once.

## The procedure

Ten steps, in this order, each with the command that decides "done" and the
classes its exit check covers. The commands with their readings are in
[references/inventory.md](references/inventory.md) (steps 0 to 4) and
[references/proofs.md](references/proofs.md) (steps 5 to 9).

| Step | Do | Exit check | Cites | Classes |
|---|---|---|---|---|
| 0 Inventory | Run `I1` to `I14`, `I2b`, `F1` and `F1b` read-only. Write every hit into the plan file, and the caller contract | The plan file lists every hit, possibly none. No command in the inventory pipes into an early-exiting reader | `CMK-TGT-01/-03/-04/-17`, `CMK-LANG-04/-11`, `CMK-VER-05`, `CMK-DEP-07/-15`, `CMK-CORE-05` | C6, C8, C9 |
| 1 Floor | Keep the existing minimum. Add `...<max>`, or raise an existing `...<max>` below it, where `<max>` is the newest CMake CI runs. Re-scan fetched and vendored trees | `F1` prints no line outside a vendored directory (a vendored hit is recorded `flagged-not-converted`), every `F1b` line is settled as step 1 below says, `I13` prints nothing, the policy probe reads `NEW`, the canary exits 1, the project's gated configure exits 0 on each CI binary, and the configured-file check prints nothing for files and test names | `CMK-VER-01/-02/-05/-07`, `CMK-DEP-15/-19/-30` | C3, C4, C8, C9 |
| 2 Targets | Move directory scope onto `target_*`, one target at a time, leaves of the in-tree graph first. A `PUBLIC` or `INTERFACE` include directory under the source or build tree is written `$<BUILD_INTERFACE:...>` from the start, because `install(EXPORT)` rejects a raw source path at generate time. A definition that an installed header reads is `PUBLIC`, never `PRIVATE` (see below) | `I2`, scoped to that target's directory, is empty, the gated configure and build exit 0, and the flag-set diff for one source of that target is empty | `CMK-TGT-03` | C1, C3, C5 |
| 3 Keywords | Name `PUBLIC`, `PRIVATE` or `INTERFACE` on that target's links. Default to `PRIVATE` unless the type is in its installed headers. Add the namespaced `ALIAS`. A header-only library with no target gets `add_library(<pkg> INTERFACE)`, its `ALIAS` and a `$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>` include directory here, as a `new:` plan row, so step 6 carries no `CMK-TGT` change | `I1` on that file shows only keyworded calls, and the gated build exits 0 with every option that adds an in-tree dependent of the target switched on, tests included | `CMK-TGT-01/-02` | C5, C9 |
| 4 Flags and standards | Overwrites and appends become `target_compile_options`, a toolchain file or a preset. A `-std=` flag becomes the target property `<LANG>_STANDARD NN` (with `<LANG>_EXTENSIONS ON` for a `gnu` spelling) plus `target_compile_features(<t> PUBLIC <lang>_std_NN)` for consumers. The compile feature alone is a floor: when the compiler's default is newer, CMake adds no flag. Fix the parses `I4` listed | `I3` shows no overwrite, `I11` hits sit in a `NOT DEFINED` guard, every `I12` hit sits in a developer option that defaults `OFF`, every new `CMAKE_*` name passes the variable check, and the flag-set diff for one source per converted target is empty | `CMK-TGT-04..09`, `CMK-LANG-04/-11` | C2, C3, C6, C7 |
| 5 Top-level gating | Gate the test tree on a project-prefixed option that defaults to `PROJECT_IS_TOP_LEVEL`, or `OFF` where the legacy option defaulted `OFF`, with `include(CTest)` inside the gate (`CMK-TEST-09`). Gate examples, demos and developer options on project-prefixed options (`<PROJECT>_BUILD_EXAMPLES`) that default to `PROJECT_IS_TOP_LEVEL`. An unprefixed name such as `BUILD_DEMOS` reads the parent's own entry of that name. Guard the `CMAKE_BUILD_TYPE` default and any non-test fetch on `PROJECT_IS_TOP_LEVEL`. A library whose `option(BUILD_SHARED_LIBS ...)` defaults `ON` first sets it as a normal variable under `if(NOT PROJECT_IS_TOP_LEVEL AND NOT DEFINED BUILD_SHARED_LIBS)`, or the option creates the parent's cache entry and every later `add_library()` of the parent turns `SHARED` | The step 7 smoke, run here too, the top-level gated build with the plan options, the old `-D` spelling of each renamed option on a fresh configure and as a re-configure of the step-4 build tree, the flag-set diff, and the `CMK-DEP-07` probe when `I7` listed a hit | `CMK-DEP-07`, `CMK-TGT-11/-17`, `CMK-TEST-09` | C2, C3, C6 |
| 6 Install and export | `GNUInstallDirs` destinations, `configure_package_config_file`, `find_dependency` per public dependency, `write_basic_package_version_file`, `NAMESPACE`, all in one diff | The gated round trip exits 0 on every CI line, once per exported target, once for the new names and once per `contract:` spelling. A tree that ships a `.pc` also passes the pkg-config check, and `I14` prints nothing | `CMK-INST-01..06/-09/-24` | C1, C2, C6, C8 |
| 7 As-subproject smoke | Configure the tree under a parent that includes `CTest`, then under a parent that also owns each unprefixed option the library declares | Every pass configures with exit 0. The state diff shows no write into the parent's build root. The tests grep prints `Total Tests: 0`, the `asub_bsl=[ON]` grep and the target grep are empty for every developer-only name, the second pass's target grep is empty, and the third pass, a compiled consumer through `add_subdirectory`, builds with exit 0 | `CMK-DEP-07`, `CMK-TGT-11`, `CMK-TEST-09` | C1, C2, C8 |
| 8 CI | Wire the gate per leg, `gersemi --check` (never `--diff`), and the round trip as its own job. In a tree with no CI, report the three items to the owner and stop. Do not create a CI system. A first `gersemi` reformat ships as its own diff, never inside a conversion diff. A leg that takes CMake from the runner image has no binary to run the canary through here: spell its gate `-Werror=dev`, record the unpinned CMake as a `CMK-VER-03` finding and the canary run as the owner's | The canary exits 1 through each leg's own binary and preset. `gersemi --check` exits 0 | `CMK-CORE-01/-02/-04/-05`, `CMK-MOD-15`, `CMK-INST-18` | C8, C9 |
| 9 CPS and pkg-config (optional) | `install(PACKAGE_INFO)` behind `if(CMAKE_VERSION VERSION_GREATER_EQUAL 4.3)`, once the namespace equals the package name, the schema is `simple` and the genexes are configuration-only | The round trip on 4.3 or later ends in `/cps/<pkg>`, on 3.31 in `/cmake/<pkg>`, and both exit 0 | `CMK-INST-12..17` | C1 |

**Output drift (`C3`).** At the step-1 commit, record the
[flag set](references/inventory.md#the-flag-set-check) of one source per target
in each configuration the tree names, its link line where a diff moves a linker
flag, and every [configured file](references/inventory.md#the-configured-file-check)
and test name. Diff them after every diff that can change them: the exit checks
prove an old command is gone, only the diff proves the behaviour stayed.

### Step 1 in detail

The floor diff touches only `cmake_minimum_required` lines, plus any vendored
floor fix the re-scan exposes. It never rides with a content change, because a
gate failure after a combined diff cannot be bisected. Any repair the raised
range needs is the floor's second diff, before step 2, never a lower `<max>`:

- a configured file or a test that changes (the configured-file check),
- a policy-removed Find module the tree calls (`CMK-DEP-19`, `I13`): cmark's
  `find_package(PythonInterp)` becomes `find_package(Python3 COMPONENTS Interpreter)`,
- an error a newly `NEW` policy raises: migrate the code (`CMK-VER-07`), never
  `cmake_policy(SET ... OLD)`. libssh2's `add_custom_command(TARGET ... DEPENDS)`
  failed under CMP0175, and dropped `DEPENDS` and gained `POST_BUILD`.

A `cmake_minimum_required` below the top-level `project()` moves above it in the
same diff: in place, the gated configure fails with
`cmake_minimum_required() should be called prior to this top-level project()`.

`F1` and `F1b` are in
[references/inventory.md](references/inventory.md#floors-and-hand-off-tokens).
An existing range whose max is below the plan's `<max>` gets the plan's
`<max>`, and so does a floor through a variable. An own-code
`cmake_policy(VERSION <v>)` after the floor resets the policy version, so the
floor diff gives it the same `...<max>`, or raises the variable that caps it.

Whatever `F1` and `F1b` print, confirm the policy version CMake applies (`C4`)
with a `-DCMAKE_PROJECT_INCLUDE` probe file holding `cmake_policy(GET CMP0083 _v)`
and `message(STATUS "CMP0083=${_v}")`: `NEW` after the diff, and empty means
an older policy version still wins.

A kept minimum below 3.10 goes into the plan file as a `CMK-VER-05` hazard,
with the question whether to raise it. The added `...<max>` already keeps a
gated consumer green, so it is the owner's compatibility promise, not a gate
failure.

A vendored or fetched floor below 3.10 that `I9` lists is fixed where it is
loaded. On CMake 4.x, set `CMAKE_POLICY_VERSION_MINIMUM` to 3.10 around that one
add and restore it (`CMK-DEP-15`). On 3.x, re-pin a fetched dependency or add a
`PATCH_COMMAND` to its declare (`CMK-DEP-30`). A vendored subtree is never
edited: it is `flagged-not-converted` with the `CMK-DEP-30` remedy named, for
the owner. Never a warning switch or `"warnings": {"deprecated": false}`.

### Steps 2 to 4: one target per diff

Work from the leaves of the in-tree link graph upward: a target nothing else
links converts first, because a parent's keyword depends on whether the child's
types leak into its headers. Mutually independent leaves may share a diff.

`link_directories` becomes `target_link_directories` only for a non-CMake
vendored library. An in-tree CMake target never needs it, because usage
requirements propagate through `target_link_libraries`. Where
`CMAKE_<LANG>_STANDARD` must stay (a top level, a manager profile), the whole
trio sits in one guard (`CMK-TGT-05..07`), the same for C:

```cmake
if(NOT DEFINED CMAKE_CXX_STANDARD)
    set(CMAKE_CXX_STANDARD 20)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    set(CMAKE_CXX_EXTENSIONS OFF)
endif()
```

`PROJECT_IS_TOP_LEVEL` may be added with `AND`, never instead: a top-level
`set()` after `project()` silently beats a Conan toolchain's standard (`C2`). C++20
or later with no module sources also needs `CMAKE_CXX_SCAN_FOR_MODULES OFF`
(CMake ≥ 3.28, `CMK-TGT-18`).

Every keyword comes from who reads the requirement, never from step 3's
`PRIVATE` default alone (`C5`). A compile definition's readers are the
installed headers. List them:

```sh
# NAME = the definition, the operand = the directory the library installs headers from, when it
# holds only installed headers. Otherwise name each installed header file, generated ones from the build tree.
NAME=JSONCPP_USE_SECURE_MEMORY
grep -rn -e "$NAME" include
```

Empty output = `PRIVATE`. Any line = `PUBLIC`, or a configured header that
bakes the value in, except a header that only asks whether the consumer wants
an API: `PUBLIC` there puts the macro on every installed consumer. A link's
readers are the in-tree dependents, which step 3's exit builds. Then configure,
build and test once more with each option that adds such a definition or
dependent: the plan options never set it. A static library beside a shared one
shares its `generate_export_header` header, which reads `<BASE>_STATIC_DEFINE`:
`PUBLIC` on the static target. Only a Windows consumer shows it missing, so a
tree with a Windows CI leg runs the static target's round trip there (cmark:
`undefined symbol: __declspec(dllimport) cmark_version`).

### Step 5: the guard and its shim

```cmake
get_property(_is_multi GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(PROJECT_IS_TOP_LEVEL AND NOT _is_multi AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Build type" FORCE)
endif()
```

`PROJECT_IS_TOP_LEVEL` needs CMake 3.21. Below that, test
`CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR` when it is not defined. A
`FetchContent_MakeAvailable` or `CPMAddPackage` outside test code runs only
under this guard, on a declare with `FIND_PACKAGE_ARGS`, or as the fallback of
a `find_package` that ran first (`CMK-DEP-07`). Each guard is a `new:` row.

Keep the value the legacy tree defaulted to, for the build type and every
option (`C6`). `RelWithDebInfo` is for a tree that had none. The smoke compares
no flags, so re-run the flag-set check after this edit.

The tree shares one cache and one build root with any parent (`C2`). Every
cache entry the library writes for a variable CMake or the parent reads
(`BUILD_SHARED_LIBS`, `EXECUTABLE_OUTPUT_PATH`, `LIBRARY_OUTPUT_PATH`, `CMAKE_<KIND>_OUTPUT_DIRECTORY`)
moves under `PROJECT_IS_TOP_LEVEL` or a `NOT DEFINED` guard, and every toggle or
cache choice carries the project prefix. `include(CPack)`, `feature_summary()`
and any write under `${CMAKE_BINARY_DIR}` run only under `PROJECT_IS_TOP_LEVEL`.

A renamed option takes its old spelling as its default at top level only, and
is declared before the first `add_subdirectory` that reads it:

```cmake
if(PROJECT_IS_TOP_LEVEL AND DEFINED BUILD_TESTING)
    set(_opj_testing_default ${BUILD_TESTING})
else()
    set(_opj_testing_default OFF)
endif()
option(OPENJPEG_BUILD_TESTING "Build the tests" ${_opj_testing_default})
get_property(_old_type CACHE BUILD_TESTING PROPERTY TYPE)
if(PROJECT_IS_TOP_LEVEL AND _old_type STREQUAL "UNINITIALIZED")
    set(OPENJPEG_BUILD_TESTING
        "${BUILD_TESTING}"
        CACHE BOOL
        "Build the tests"
        FORCE
    )
    unset(BUILD_TESTING CACHE)
endif()
```

It reads `OFF` at top level, `ON` with `-DBUILD_TESTING=ON`, and `OFF` under a
parent that includes `CTest` (3.31.12 and 4.4.2). The `UNINITIALIZED` block
lets an old `-D` win on a re-configure too: without it, libssh2's
`-DENABLE_WERROR=ON` on an existing tree left 0 `-Werror` with exit 0. A plain
rename drops the old `-D` with only a "not used" warning. A file that still
reads an old name, vendored glue included, gets it back as a directory-scoped
variable set from the new option before the `add_subdirectory` that reads it.

### Step 6: one coherent diff

The `CMK-INST` MUSTs the round trip depends on (`-02`, `-04`, `-05`, `-06`,
`-03` per public dependency, `-09` for the destinations) land together, with no
`CMK-TGT` change except the `$<BUILD_INTERFACE:>` and `INCLUDES DESTINATION`
form of an include directory the round trip rejects. Each file the step creates
(the Config template) gets a `new:` row first. None alone makes a consumable
package, so the [round trip](references/proofs.md#the-gated-round-trip) runs
once, after all of them: a missing `find_dependency` stays green through
`cmake --install` until a compiled consumer's Generate step (`CMK-INST-01`).

Step 6 changes most of the caller contract (`C6`), so its exit runs the round
trip once per `contract:` spelling as well as the new one:

- **Exported names.** When the tree already exports targets without a
  namespace, adding `NAMESPACE` renames every imported target consumers link
  today. Ship the old names in the Config package as an `ALIAS` of each
  namespaced imported target, each under `if(NOT TARGET <old>)` (a consumer on
  CMake 3.18 or later, the version that allows it). Without the guard, a second
  `find_package` in one directory fails with
  `add_library cannot create ALIAS target`. Keep every name a hand-written
  targets file defined. Dropping an old name instead is the owner's call,
  written into the plan file as a changelog item. An exported executable is no
  `TARGETS` entry: the consumer checks it with `if(NOT TARGET <name>)` and
  `message(FATAL_ERROR)`.
- **Find-module names.** A package CMake ships a Find module for (`ZLIB`,
  `PNG`, `CURL`) is consumed today through its imported target and result
  variables. The Config package defines them too (`ZLIB::ZLIB`,
  `ZLIB_INCLUDE_DIRS`), and the round trip runs once more on that target.
- **`.pc` files.** A hand-written `.pc` template reads the variables step 6
  replaces. Run the pkg-config check in
  [references/proofs.md](references/proofs.md#the-pkg-config-check).
- **Install knobs.** An install knob the tree documents (`-DINSTALL_LIB_DIR`)
  keeps working, or goes into the plan file as a changelog item: after the
  switch it is dropped with only a "not used" warning.
- **The consumer's scope.** A Config that puts its own directory on
  `CMAKE_MODULE_PATH` for `find_dependency` restores the consumer's value
  before it includes the targets file (`C2`, the round trip's guard).

`write_basic_package_version_file` without `VERSION` reads `PROJECT_VERSION`,
and stops with `No VERSION specified` when `project()` has none. A version the
tree states (zlib's `set(VERSION "1.3.1")`) is passed as `VERSION ${VERSION}`.
Only a tree that states none asks the owner, never a version from a git tag.

Step 8's CI items are in [references/proofs.md](references/proofs.md#ci-checks),
and the `I4` parse migration in
[references/inventory.md](references/inventory.md#migrating-a-parse).

## Reviewable units

Each of these ships as its own diff:

- The floor change, alone, then any repair the raised range needs.
- Each target's conversion (steps 2 to 4). Independent leaves may share one.
- The first install and export (step 6), with no `CMK-TGT` change in it.
- CPS or pkg-config, only after the round trip is already green without it.
- The first `gersemi` reformat, alone, with no content change.

A diff that touches a file no plan-file row names is out of scope, so steps 5
and 6 add `new:` rows first. Vendored subtrees are `flagged-not-converted`.

## What it refuses

- Raising an existing `cmake_minimum_required` minimum. It reports and asks.
  The owner raises it in a diff of its own.
- Rewriting a file the inventory did not name, the whole tree in one pass, or
  a vendored subtree.
- Rewriting a public command's parse without the flatten line.
- Adding `install(PACKAGE_INFO)` before the Config round trip is green on 3.31.
- Adding `cmake-format` or `cmake-lint`.
- Editing `conanfile.*` or `vcpkg.json`. A Conan 1 token (`I10`) stops the skill
  and hands off to `cpp-packaging`.

## Pinned defaults

Agreed decisions, not derivations. Each is a default an adopter overrides once.

| Decision | Default (pinned) |
|---|---|
| The minimum | Kept as found. `...<max>` is added. The program floor `3.25...4.4` applies to new code only |
| `<max>` | The newest CMake CI runs, never the newest release. A tree with no CI, or whose CI takes CMake from the runner image without pinning a version (a `CMK-VER-03` finding), takes the program's pinned newest line (4.4) and records it in the plan file |
| CI lines | The CMake lines CI pins. A tree with no CI, or with an unpinned runner-image CMake, takes 3.31 and 4.4 for every "each CI line" check, and step 8 is reported to the owner, not created |
| Gate spelling | `-Werror=author` on 4.4 and later, `-Werror=dev` on 4.3 and older and on a shared line |
| Migrating a parse | `PARSE_ARGV` plus the flatten line for list-valued multi-value keywords |
| Formatting gate | `gersemi --check`, SHOULD, gersemi 0.29.1 |
| Plan file | `cmake-modernize-plan.md` at the repository root |

## Failure classes

Each class is one mechanism that recurs on trees nobody has tried, with its
check. Every measured instance, and the old failure-mode numbers 1 to 26, are
in [references/failure-modes.md](references/failure-modes.md).

1. **C1 The proof's consumer is weaker than a real one.** A check that builds
   only the tree, calls no symbol, or reads one interface passes a package a
   compiled consumer rejects. Check: the round trip, once per target, and the
   smoke's third pass each call an exported function (`SYM_CALL`).
2. **C2 A default crosses the boundary with an outer layer.** The tree shares
   one cache, build root and scope with its parent, toolchain, manager profile,
   consumer and the user's `-D`. A write into theirs, or an unprefixed read of
   their name, changes their build while every top-level check passes. Check:
   `NOT DEFINED` and `PROJECT_IS_TOP_LEVEL` guards, project prefixes, the
   smoke's state diff, and the round trip's `CMAKE_MODULE_PATH` guard.
3. **C3 An edit changes the output while presence checks pass.** An inventory
   grep proves the old command is gone, and a green build proves it compiles.
   Neither sees a lost flag, a compile feature below the compiler default, or a
   policy that rewrites a configured file or drops a test. Check: the output
   drift diffs against the step-1 commit.
4. **C4 The policy version CMake applies is not the one written.** A two-dot
   range, a floor through a variable, a later own-code `cmake_policy(VERSION)`
   or a range with an old max leaves newer policies unset. Check: `F1b` lists
   every such line, and the policy probe reads `NEW`.
5. **C5 Visibility comes from a default instead of the readers.** `PRIVATE` by
   default, or a reader grep over a mixed directory, decides a keyword wrongly,
   and the plan options never build the reader. Check: `I2b`, the reader grep
   over installed headers, and a build per option that adds a reader.
6. **C6 A name, default or knob a caller uses today breaks.** A renamed or
   re-defaulted option, `NAMESPACE`, a replaced Find module or `.pc` variable,
   or a migrated public parse passes every check written for the new spelling.
   Check: the caller contract, and the old spelling run at the step changing it.
7. **C7 A CMake name or citation written from memory.** Check: the
   variable-existence check against the pinned binary (`CMK-LANG-11`), and each
   cited page fetched at the pinned tag.
8. **C8 A check that could not fire reads clean.** An ignored gate spelling, a
   failed configure, a missing grep operand, a pattern that misses a spelling,
   or a proof that resolved another copy (a registry entry, a stale install)
   reads as a pass. Check: the evidence rule, the canary per leg, each pass
   grep's list command, and the round trip's anchored `_DIR` line.
9. **C9 A finding no step owns stalls the run or rides along.** Check: the plan
   file's row, step and status for every hit and every touched file, the floor's
   second diff for any repair the raised range needs, the 4.4 category
   demotion, and `git status --short` after each configure.

## MUST rows this procedure enforces

Duplicated as a hedge against the scoped rule not being loaded. The rule text,
rationale and full verification live in the `cmake-build` rule and its depth
files, and a disputed row is settled there.

| # | Finding | Rule |
|---|---|---|
| 1 | Run every CI configure leg under the configure gate spelled for the binary that leg runs: `-Werror=author` on CMake 4.4 and later, `-Werror=dev` on 4.3 and older, and `-Werror=dev` when one command line serves legs on both sides | CMK-CORE-01 |
| 2 | In any verification script over a CMake tree, never pipe a match stream into an early-exiting reader (`grep -q`, `head`) under `set -o pipefail` | CMK-CORE-05 |
| 3 | An installable library resolves its dependencies with `find_package` and never forces acquisition | CMK-DEP-07 |
| 4 | On CMake 4.x, set a third-party dependency's policy knobs with set and restore around the one `add_subdirectory`, `FetchContent_MakeAvailable` or `find_package` that loads it, with `CMAKE_POLICY_VERSION_MINIMUM` at 3.10 | CMK-DEP-15 |
| 5 | Whenever install, export, Config-template or dependency wiring changes, prove the package can be consumed with the round-trip script, and never treat a green build and install as proof | CMK-INST-01 |
| 6 | In a `function()`, parse with `cmake_parse_arguments(PARSE_ARGV ...)` and never forward an unquoted `${ARGN}` into the parse. Migrating an existing public command needs the flatten line or a changelog entry naming the behaviour change | CMK-LANG-04 |
| 7 | Never declare an option, cache entry or variable of your own whose name begins with `CMAKE_` or `_CMAKE_` (in any case), or with `_` followed by a CMake command name | CMK-LANG-11 |
| 8 | In every `target_link_libraries` call in an installable library's own code, name `PUBLIC`, `PRIVATE` or `INTERFACE` | CMK-TGT-01 |
| 9 | Never overwrite `CMAKE_<LANG>_FLAGS`, `CMAKE_<LANG>_FLAGS_<CONFIG>` or `CMAKE_<KIND>_LINKER_FLAGS` (the MUST half, appending is SHOULD) | CMK-TGT-04 |
| 10 | Only the top-level project defaults `CMAKE_BUILD_TYPE`, and only on a single-config generator. A library never writes it | CMK-TGT-17 |
| 11 | Write a version range with exactly three literal dots | CMK-VER-01 |
| 12 | Before a CMake bump, and whenever a dependency is added or re-pinned, scan the fetched and vendored trees for effective policy versions below 3.10 | CMK-VER-05 |
| 13 | A compile definition that an installed header reads is `PUBLIC` on the library target, or baked into a configured installed header, never `PRIVATE` or directory-scoped (the MUST half) | CMK-TGT-03 |
| 14 | In a library, never write `BUILD_SHARED_LIBS` with a `FORCE` outside `if(NOT DEFINED BUILD_SHARED_LIBS)`, and never let a non-top-level `option(BUILD_SHARED_LIBS … ON)` create the parent's cache entry (the MUST half) | CMK-TGT-11 |
| 15 | A library others consume never builds its usage requirements on `CMAKE_SOURCE_DIR` or `CMAKE_BINARY_DIR` (the MUST half) | CMK-TGT-21 |
| 16 | Give every export a `NAMESPACE`. Adding one to an export that shipped without it keeps every old exported name as an `ALIAS` in the Config package, each under `if(NOT TARGET <old>)`, or ships a changelog entry naming the rename | CMK-INST-06 |
| 17 | Never call a policy-removed Find module (`CUDA`, `PythonInterp`, `PythonLibs`, `GCCXML`, `CABLE`) where its removal policy is `NEW`, read from the `...<max>` end of the range | CMK-DEP-19 |
| 18 | Resolve a "Policy CMPxxxx" gate error by adopting NEW and migrating the code, never with `cmake_policy(SET … OLD)`. A temporary OLD sits behind `if(POLICY)` with its reason and exit | CMK-VER-07 |
| 19 | Never call `export(PACKAGE)`. Another project uses a build tree through `<Pkg>_DIR` pointing at the `export(EXPORT)` file | CMK-INST-24 |

## References

Read one level down, on demand. These files do not link each other.

| File | Read it when |
|---|---|
| [references/inventory.md](references/inventory.md) | Running step 0, or re-running an inventory command as the exit check of steps 1 to 4. Holds `I1` to `I14`, `I2b`, `F1` and `F1b` with the reading of each, the parse migration, the flag-set, configured-file and variable-existence checks |
| [references/proofs.md](references/proofs.md) | Running steps 5 to 9. Holds the gate canary, the gated round trip, the pkg-config check, the as-subproject smoke, the `CMK-DEP-07` offline probe, the CI greps and the CPS checks |
| [references/failure-modes.md](references/failure-modes.md) | A class above fires, or a step's rule needs its measured case. Holds each class with every instance measured on the seven trees and the old failure-mode numbers |

Re-check on each tool bump (as of 2026-09-26): the gate spelling split and
preset `warnings` behaviour and the `/cps/<pkg>` round-trip ending (CMake after
4.4.2), and the `gersemi --diff` exit code (gersemi after 0.29.1).
