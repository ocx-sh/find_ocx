# Failure classes, instance by instance

Read this when a class check in `SKILL.md` fails, or a symptom looks like a
case below. Each class is one mechanism, and the list under it holds its
instances: FM1 to FM19 and the steps that misled, stalled or went wrong on real
and held-out trees. The fix is always the rule the instance cites, and this
file states no standard. Measured 2026-09-26 on CMake 3.31.12, 4.3.4 and 4.4.2,
with the tool versions `SKILL.md` and [reading-the-answers.md](reading-the-answers.md) name.

Contents: [C1 Proxy record](#c1-a-proxy-record-read-as-the-record) · [C2 Sticky state](#c2-sticky-state-outlives-its-input) ·
[C3 Substitution after resolution](#c3-substitution-after-resolution) ·
[C4 Absent or rejected candidate](#c4-an-absent-or-rejected-candidate-read-as-precedence) · [C5 Record shape](#c5-a-read-calibrated-on-one-mechanism) ·
[C6 Gate stop in third-party code](#c6-a-gate-stop-in-third-party-code-cleared-at-the-wrong-knob) ·
[C7 Narrow proof](#c7-a-proof-that-exercises-one-consumer-kind) · [C8 Several lookups](#c8-one-dependency-several-lookups) ·
[Re-check](#re-check-on-each-tool-bump)

## C1 A proxy record read as the record

A declaration, a version request, a manager's current resolution or a success
message is read as the record of what this tree consumed. Each proxy is true
about something else. The record of consumption is written by the configure
or the install that this tree actually ran.

| Proxy | What it describes | The record of consumption |
|---|---|---|
| `conan graph info` | What the conanfile resolves to now | The generators folder's version file and `_PACKAGE_FOLDER_` line (T8) |
| vcpkg `version>=` | A floor, one constraint among the baseline and every other floor | `vcpkg_installed/vcpkg/status` `Version:` of an `install ok installed` entry (T9) |
| The `CPMAddPackage` call, or the declare grep's hit | The call that may have lost to an earlier declaration | `CPM_PACKAGE_<name>_VERSION` and `_SOURCE_DIR` cache lines (T15) |
| `CMAKE_TOOLCHAIN_FILE` in the cache | The toolchain the cache was last given | The `include(` line of `CMakeSystem.cmake` |
| `Package was found by the dependency provider` | That the provider's macro returned | The `The file was found at` path above it (T13) |
| A passing CMK-VCPKG-01 check | That a baseline exists | The installed version, then the baseline's entry for the port |

- **FM12. Reading vcpkg's `version>=` as the version installed** (T9,
  measured in [vcpkg](reading-the-answers.md#vcpkg)). Wave 5 A1-f misled:
  CMK-VCPKG-01's grep passed (exit 1, empty) and named no cause.
- **FM14. Taking `conan graph info` as the build tree's record** (T8, measured
  in [the Conan graph](reading-the-answers.md#the-conan-graph)). Wave 5 B1-b
  and B1-c misled: a `cJSON_DIR` under `generators` read as "the right copy"
  whatever version the folder held.
- **FM15. Trusting `Package was found by the dependency provider`.**
  cmake-conan prints it after its fallback search found a copy outside Conan
  (T13). Wave 5 B2-d misled: the line followed
  `considered but not accepted: .../generators/cJSONConfig.cmake, version: 1.7.19`
  and the host `The file was found at` path, on 3.31.12 and 4.4.2.
- **FM17. Reading a CPM project's copy from its `CPMAddPackage` call.** A
  lock, a cached `CPM_USE_LOCAL_PACKAGES` or a shared source cache decides
  (T15). Wave 6 B1-f wrong: the declare grep of that time named
  `CPMAddPackage("gh:fmtlib/fmt#12.1.0")`, the call that lost, and missed the
  lock's `CPMDeclarePackage`. CPM built 12.0.0 with exit 0 on 3.31.12, 4.3.4
  and 4.4.2.
- **Wave 5 A2-d wrong.** The references once said the cache's
  `CMAKE_TOOLCHAIN_FILE` named the loaded toolchain. The `CMakeSystem.cmake`
  grep printed nothing (exit 1) on the day-2 tree, 3.31.12 and 4.4.2.
- **Wave 5 A1-e and B1-e stalled.** Step 3's patterns dropped the event's
  `version:` lines, which held the consumed version (`"1.7.19"` in A1,
  `"1.7.17"` in B1, 4.4.2), and 3.x had no version read.

## C2 Sticky state outlives its input

A configure-time decision is cached, or written once, and survives the change
that should have replaced it. A remedy that clears one entry finds the old copy
again, because another sticky input still points at it. A remedy that clears
everything removes the symptom without naming which input was sticky.

| Sticky input | Written | Cleared by |
|---|---|---|
| `<Pkg>_DIR` | The first configure that resolves the call | `-U <Pkg>_DIR`, `--fresh`, a new tree |
| The toolchain | `CMakeSystem.cmake`, first configure only | `--fresh` or a new tree, never `-U` |
| `CPM_USE_LOCAL_PACKAGES` | `option()` seeded from the environment, then cached | `-DCPM_USE_LOCAL_PACKAGES=OFF`, or `--fresh` with the variable unset |
| A vendored module's `<name>_ROOT` `CACHE PATH ... FORCE` | Every configure | CMK-DEP-13's guarded `unset(<Pkg>_DIR CACHE)` |
| A `CPM_SOURCE_CACHE` checkout | The first project to fetch the pin | Nothing in the build tree. Restore the checkout (C3) |
| A manager root outside the tree (`HUNTER_ROOT`) | The first configure on the machine | Nothing in the build tree. Reproduce CI on a new, empty root |
| A nested configure's cache (ExternalProject `<name>-prefix/src/<name>-build`) | Its configure step, which keeps a cached `_DIR` when the forwarded arguments change | That tree's own `--fresh`, with `-C <name>-prefix/tmp/<name>-cache-.cmake` when the project uses `CMAKE_CACHE_ARGS`. Never the outer `--fresh` (C8) |

A vendored bootstrap module that writes `<name>_ROOT` as `CACHE PATH ... FORCE`
keeps the old copy for as long as it exists on disk. List modules with that
shape:

```sh
grep -rlzE --include='*.cmake' -e '_ROOT[^)]*CACHE' . | xargs -r grep -L -e '_DIR CACHE'
```

Empty output passes. A listed file writes a `_ROOT` cache entry and never
unsets a `_DIR` one. A `FORCE` in that call is the finding (CMK-DEP-13).

- **FM5. Wiping the build tree first.** The stale `_DIR` was the evidence.
- **FM13. Giving an existing build tree a toolchain, then clearing `_DIR`
  with `-U`.** The toolchain is never loaded, so `-U` finds the old copy (T1,
  measured in [toolchain-injected paths](reading-the-answers.md#toolchain-injected-paths)).
  Wave 5 A2-c misled (no step 1 row read a missing `VCPKG_INSTALLED_DIR`), A2-f
  misled (`-U cJSON_DIR` exit 0, still `pfx/cjson-1.7.15`).
- **Wave 4 scenario 3, T3-a stalled.** A re-pointed `CMAKE_PREFIX_PATH` kept
  `cJSON_DIR` on 1.7.15, and the step 1 grep had no `^CMAKE_PREFIX_PATH`
  pattern to compare it with. `--fresh` moved it (both lines).
- **Wave 6 B2.** `CPM_USE_LOCAL_PACKAGES:BOOL=ON` stayed cached after `unset`
  (4.4.2). B2-c misled (not in the grep), B2-d wrong (`-U fmt_DIR` kept
  fmt@12.1.0), B2-e misled (`--fresh` fixed it, credited to a stale `_DIR`).
- **Wave 8 B-j stalled.** HunterGate's bootstrap configure runs only while
  `HUNTER_ROOT` lacks the release: an empty root exited 1 on 4.3.4 and 4.4.2,
  a populated one 0. Only the developer tree cached `HUNTER_CACHED_ROOT`.

## C3 Substitution after resolution

Every configure record names the intended copy, and the artifact still carries
another. The substitution happens after `find_package`: at load time, at
generate time, inside another package's headers and library, or in the source
a pinned fetch compiled. Only a read of the artifact or its source finds it.

| Where the other copy enters | The read |
|---|---|
| The loader, a same-SONAME copy on its path | `ldd` and `readelf -d` (T11) |
| A copy bundled in another package | The version macro over each prefix (T14) |
| A source override that skips the declare's `PATCH_COMMAND` | The patch and override greps (T7) |
| A shared source checkout someone edited | `git status --porcelain` on `_SOURCE_DIR` (T15) |
| The generator, taking an installed configuration for the leg's | `IMPORTED_CONFIGURATIONS` beside the build type and map lines |

- **FM6. Passing `FETCHCONTENT_SOURCE_DIR_<X>` for a patched dependency**,
  then debugging the dependency. The override skips `PATCH_COMMAND`, so
  pristine source fails the gate or builds differently (3.31.12, 4.3.4 and
  4.4.2).
- **FM8. Stopping at "the configured copy is right"** when the binary reports
  another version (T11). Wave 4 scenario 2: cJSON 1.7.15 configured, and the
  installed binary printed `library 1.7.18` from `/lib64/libcjson.so.1`
  because install stripped the RUNPATH (3.31.12 and 4.4.2, exit 0). T2-a
  stalled (no row), T2-b misled (step 1's last row routed to a manager).
  `INSTALL_RPATH_USE_LINK_PATH ON` printed 1.7.15.
- **FM16. Stopping at a right `<dep>_DIR` when another package bundles the
  dependency.** The bundled copy never passes through `find_package` (T14).
  Wave 6 A, spdlog 1.17.0 beside fmt 11.1.4 (measured in
  [bundled copies](reading-the-answers.md#bundled-copies)): A-b misled (only
  T11 named another copy), A-f stalled (`ldd` listed no fmt), A-g stalled (no
  rule).
- **Wave 6 B3 stalled (B3-c, B3-d, B3-e).** An edit in the shared
  `CPM_SOURCE_CACHE` checkout was built by a brand-new tree, with one ungated
  `Cache for fmt (...) is dirty` warning, exit 0 on 3.31.12 and 4.4.2. The
  step 1 grep was empty, steps 2 and 3 had no event, and the declare grep
  showed the same pin CI used.
- **Wave 8 A, lz4 1.10.0 (`ebb370ca`), Debug (postfix `d`) and Release in one
  prefix.** RelWithDebInfo and MinSizeRel loaded `liblz4d.so.1`, exit 0, no
  warning, either install order (3.31.12, 4.3.4, 4.4.2): an unmapped
  configuration takes the first listed, `DEBUG` by file name. A-h misled (`ldd`
  printed the `d` file, read by directory), A-j stalled (a false stop). The
  map to `RelWithDebInfo;Release` loaded `liblz4.so.1` on all three.

## C4 An absent or rejected candidate read as precedence

The winning copy won because the expected one was never a candidate, or was a
candidate the request rejected, not because it ranked lower. The precedence
readings (stale cache, a rooted copy wins) then prescribe a `_DIR` pin that
fixes one package and hardens the cause.

| The expected copy in step 2's output | Cause | Fix at |
|---|---|---|
| Never listed | The search space: find-root modes, an empty `CMAKE_LIBRARY_ARCHITECTURE`, a provider's directory scope, or the arguments a nested configure received | The toolchain (CMK-TC-08, CMK-TC-11), the first `find_package`'s placement (CMK-TC-05), or the forwarding line (C8) |
| `considered but not accepted` | The request rejects it, and a wider search ran | The request or the conanfile (T13) |
| Listed and beaten | Precedence: a stale `_DIR` or a rooted copy | T1, CMK-DEP-13, CMK-DEP-21 |

- **FM3. Assuming a provider widens search paths like a toolchain file**, or
  that `DEFER` runs a call earlier. `find_program` sees Conan content only
  under `CMakeConfigDeps`, after the first intercepted `find_package`, in that
  directory scope (4.4.2).
- **FM18. Reading a `_DIR` outside every root as "a rooted copy won"**
  because `CMAKE_SYSROOT` is set. The sysroot's copy was never searched, often
  because `CMAKE_LIBRARY_ARCHITECTURE` is empty (T1, measured in
  [toolchain-injected paths](reading-the-answers.md#toolchain-injected-paths)).
  Wave 6 C: 0 candidates under `sysroot/usr/lib/aarch64-linux-gnu`, and the
  build failed with `is incompatible with aarch64linux`. C-d wrong (T1's rooted
  reading inverted), C-e misled (a `-Dexpat_DIR` pin linked one Config package,
  left `BOTH`, and did nothing for FindEXPAT).
- **Wave 5 B2.** cmake-conan's fallback found the host copy after the
  generators copy failed `EXACT 1.7.15` or was absent (3.31.12 and 4.4.2).
  B2-b stalled (no row), B2-c misled (no row for a provider's `_DIR` line),
  B2-f wrong: T1's rooted branch, with both roots empty, pinned the host copy.

## C5 A read calibrated on one mechanism

Config-mode `find_package` writes `<Pkg>_DIR`, prints `The file was found at`
the package file and logs one event. A redirect, a provider, a Find module and
CPM each write something else, or file it under another name. A read tuned to
the Config shape reports their difference as absence, or as a CMK-DEP-17
finding.

| Mechanism | Its record |
|---|---|
| FetchContent or CPM redirect | `_DIR` under `pkgRedirects`, no `The file was found at`, one event only under `--debug-find-pkg`, blank found version. CPM writes it for every fetched package with no `OVERRIDE_FIND_PACKAGE` in the tree |
| A `FIND_PACKAGE_ARGS` try-find | `<declared>_DIR:INTERNAL=` under the declare's spelling, not the call's |
| cmake-conan with `CMakeConfigDeps` | No `_DIR` cache line. Events only under `--debug-find-pkg`, a `config` one then a `provider` one |
| A Find module | `<NAME>_LIBRARY*` and `<NAME>_INCLUDE_DIR`, printed as `The item was found at`. Its version is the one it parsed |
| CPM's local search | `CMake Debug Log at cmake/CPM.cmake` above the debug block |
| pkg-config (`pkg_check_modules`, `pkg_search_module`) | `pkgcfg_lib_<PREFIX>_<lib>:FILEPATH=`, and `<PREFIX>_VERSION` and `<PREFIX>_LIBDIR` `INTERNAL` lines, never `<Pkg>_DIR`. A `find-v1` event (not `find_package-v1`) with `variable: "pkgcfg_lib_<PREFIX>_<lib>"`, and the console line `Found <module>, version` |

- **FM4. Reading an empty `_DIR` grep as "never looked up"** when a Find
  module or a `CMakeConfigDeps` provider answered.
- **FM9. Spelling a `FIND_PACKAGE_ARGS` declare's name differently from the
  package's Config file**, case included. Wave 4 T1-h misled: `cjson` missed
  `cJSONConfig.cmake` and fetched ([FetchContent redirects](reading-the-answers.md#fetchcontent-redirects)).
- **FM10. Reporting a CMK-DEP-17 finding for a zero event count** when a
  redirect answered. Wave 4 T1-f wrong: 0 `find_package-v1` events beside 17
  `find-v1` on 4.3.4 and 4.4.2. Wave 6 B1-h wrong: the step 3 text said "no
  event", while after step 2's flag the redirect logged 1 with `version: ""`
  (CPM lock and a plain `OVERRIDE_FIND_PACKAGE` control, 4.3.4 and 4.4.2).
- **Wave 6 C-g and C-h.** In FM19's tree (now C8) the module's cache lines
  were unread (C-g stalled), and `The file was found at` named
  `FindEXPAT.cmake` (C-h misled).
- **Wave 5 B2-e wrong.** The provider exception said "no event", while step
  2's flag made the provider log 3 events (failing) and 2 (control), with the
  last one's path `dependency_provider::conan_provide_dependency`.
- **Wave 6 B1-d, B1-g, B2-f.** B1-d misled: the `OVERRIDE_FIND_PACKAGE` grep
  hit a comment in `CPM.cmake:334`. B1-g stalled: a redirect prints no
  `The file was found at` line. B2-f stalled: the tell was the debug header
  `CMake Debug Log at cmake/CPM.cmake:309 (find_package)`.

## C6 A gate stop in third-party code cleared at the wrong knob

The gate promotes a diagnostic inside code the project does not own: a floor
below 3.10, or an absolute install destination on 4.4. Lowering its severity
or scope fails, is forbidden, or is a silent no-op on 3.x. Only a change to the
dependency's input clears it: a scoped floor value, a re-pin, or a patch. A
child configure never sees a scoped value or a `-D`, so there only the last two.

- **FM1. "Fixing" a floor error with a global switch** (a warning switch, or
  a preset or CI `CMAKE_POLICY_VERSION_MINIMUM`), or with the value 3.5.
- **FM2. `CMAKE_POLICY_VERSION_MINIMUM` for a 3.x build.** 3.31.12 ignores it, exit 0.
- **FM11. Clearing 4.4's `install-absolute-destination` stop in a dependency
  with a scoped `cmake_diagnostic` or `CMAKE_SKIP_INSTALL_RULES`.** Only a
  patch does (T12). Wave 4 T1-e stalled: cJSON 1.7.15, 1.7.18 and master
  `6d9f2443ab` all install to `CMAKE_INSTALL_FULL_*`. A scoped
  `cmake_diagnostic(SET CMD_INSTALL_ABSOLUTE_DESTINATION WARN)`, a scoped
  `CMAKE_SKIP_INSTALL_RULES ON` and `-Werror=dev` all exited 1 on 4.4.2, and
  4.3.4 exited 0. `PATCH_COMMAND sed -i "s/CMAKE_INSTALL_FULL_/CMAKE_INSTALL_/g" CMakeLists.txt`
  exited 0, and patching only the export line moved the error to line 149.
- **Wave 8 B-h wrong.** cpp-pm/gate v0.9.2 (`958e65c6`) writes
  `cmake_minimum_required(VERSION 3.2)` into HunterGate's bootstrap project.
  CMK-DEP-15's set/unset around `HunterGate(` and a `-D` exited 1 on 4.4.2,
  3.31.12 printed the child's deprecation ungated, and gate `92050736` (3.10)
  exited 0 on all three.

## C7 A proof that exercises one consumer kind

A proof passes with a consumer that cannot fail: a `LANGUAGES NONE` consumer
never compiles, an empty `main` never pulls a static archive member, and a
`CONFIG` consumer never meets the Find module a plain `find_package` loads.

- **FM7. Proving a missing `find_dependency` fixed with a `LANGUAGES NONE`
  consumer.** It stays green either way. The proof is the CMK-INST-01 round
  trip with a compiled consumer (T4).
- **The same class in the cmake-modernize runs.** On slembcke/Chipmunk2D the
  round trip's empty `main` exited 0 for `chipmunk::chipmunk_static`, and a
  consumer calling `cpBodySetAngle` failed with ``undefined reference to `sincos'``
  (3.31.12 and 4.4.2). On madler/zlib v1.3.1 the `CONFIG` round trip passed,
  a plain `find_package(ZLIB)` was answered by FindZLIB and never read the
  Config, and a `CMAKE_FIND_PACKAGE_PREFER_CONFIG` consumer of `ZLIB::ZLIB`
  exited 1 at configure (both lines).

## C8 One dependency, several lookups

One dependency reaches the build through more than one lookup or configure, each with its
own inputs, search order and record, so each can land on another copy with
exit 0. A triage that reads one lookup's record credits it for the whole
artifact. Only a read from the artifact's side (step 4's C8 reads) sees all.

| Second lookup | Its record | Why it lands elsewhere |
|---|---|---|
| `pkg_check_modules` beside `find_package` | The pkg-config row of C5 | `FindPkgConfig.cmake` searches `$ENV{PKG_CONFIG_PATH}` before the `CMAKE_PREFIX_PATH` directories (4.4.2) |
| A Find module's `find_path` beside its `find_library` | `<NAME>_INCLUDE_DIR` and `<NAME>_LIBRARY*` | Each call searches on its own, and the module reports the header's version |
| An ExternalProject configure beside the outer one | The inner tree's `CMakeCache.txt` | Its forwarded arguments. `CMAKE_ARGS` splits a list at `;`, so `-DCMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH}` passes the first entry only |
| A manager's bootstrap configure (HunterGate) | Its `CMakeCache.txt` under the manager's root | Only its own command line and environment reach it |

- **FM19. Taking a Find module's reported version as the linked copy's.**
  Wave 6 C-i wrong: FindEXPAT printed `found suitable version "2.8.5"` (the
  sysroot header) beside the host `libexpat.so` 2.7.3, and 4.4.2's
  `found.version` said 2.8.5.
- **Held-out A, pkg-config beside a Config package.** facebook/zstd v1.5.6
  (`794ea1b0`) and v1.5.7 (`f8745da6`). `zstd_DIR` named 1.5.7, a
  subdirectory's `pkg_check_modules` took 1.5.6 from the shell's
  `PKG_CONFIG_PATH`, and the app printed `zstd runtime 1.5.6` (exit 0 on
  3.31.12, 4.3.4 and 4.4.2). The link line held both directories beside one
  ungated runtime-path `cycle` warning. Step 1's last row, step 2 and C3's T11
  route each assumed one lookup. One `find_package` for both linked 1.5.7.
- **Held-out B, an ExternalProject superbuild.** json-c 0.17 (`b4c371fa`) and
  0.18 (`41a55cfc`). The outer `json-c_DIR` named 0.18, the inner configure got
  the split list (`Ignoring extra path from command line`, printed only when
  that step ran) and took 0.17 from the environment (exit 0 on 3.31.12, 4.3.4
  and 4.4.2). `CMAKE_CACHE_ARGS "-DCMAKE_PREFIX_PATH:STRING=${CMAKE_PREFIX_PATH}"`
  built 0.18 on new trees, and on a used tree only the inner `--fresh` moved
  `json-c_DIR`. CMK-DEP-34 owns the forwarding line.
- **Wave 8 B-b and B-g misled.** `CMake Error at CMakeLists.txt:1` was the
  bootstrap project's line (`3.2`), not the project's (`3.25...4.4`). The
  console's `To reproduce` line named its `-H` and `-B`, and the cache count
  over `build` printed one file (4.4.2).

## Re-check on each tool bump

The cmake-conan provider's `CMakeConfigDeps` behaviour and fallback search
(`b1593849`), whether `CMakeConfigDeps` leaves experimental status (Conan
2.32.0, 2026-09-26), the `find_package-v1` event layout (4.4.2), vcpkg's
no-lockfile, no-provider stance and version selection (vcpkg-tool 2026-09-26
and 2026-07-27), CPM's redirect stub, cached options and lock precedence
(CPM.cmake 0.43.2), whether zig cc still reports no implicit link directories
(0.16.0-dev), and FindPkgConfig's `PKG_CONFIG_PATH`-first order (4.4.2).
