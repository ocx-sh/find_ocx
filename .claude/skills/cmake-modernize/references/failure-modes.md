# Failure modes by class

Read this when a class in SKILL.md "Failure classes" fires, or when a step's
rule needs the measured case behind it. Each class states the mechanism, the
check that catches it, and every measured instance. `FM1` to `FM26` are the
failure-mode numbers the skill listed before the classes. "Both lines" means
CMake 3.31.12 under `-Werror=dev` and 4.4.2 under `-Werror=author`, with gcc
15.2.1 for C and clang 21.1.0 for C++ (2026-09-26). The trees are
slembcke/Chipmunk2D at `f2f3d662`, open-source-parsers/jsoncpp at `3347a4b8`,
c42f/tinyformat at `aef402d8`, uclouvain/openjpeg at `8314119b` and
madler/zlib at `v1.3.1`, then held out: commonmark/cmark at `0.30.3` and
libssh2/libssh2 at `libssh2-1.11.1`. The held-out pair added instances, no class.

Contents: [C1 Consumer](#c1-the-proofs-consumer-is-weaker-than-a-real-one) ·
[C2 Outer layer](#c2-a-default-crosses-the-boundary-with-an-outer-layer) ·
[C3 Output drift](#c3-an-edit-changes-the-output-while-presence-checks-pass) ·
[C4 Policy version](#c4-the-policy-version-cmake-applies-is-not-the-one-written) ·
[C5 Visibility](#c5-visibility-comes-from-a-default-instead-of-the-readers) ·
[C6 Caller contract](#c6-a-name-default-or-knob-a-caller-uses-today-breaks) ·
[C7 Memory](#c7-a-cmake-name-or-citation-written-from-memory) ·
[C8 Silent check](#c8-a-check-that-could-not-fire-reads-clean) ·
[C9 Unowned finding](#c9-a-finding-no-step-owns-stalls-the-run-or-rides-along)

## C1 The proof's consumer is weaker than a real one

A check that builds only the tree, links no consumer, calls no symbol, or reads
one interface (the build tree, or `INSTALL_INTERFACE`) passes a package that a
compiled consumer on another channel rejects. Check: the round trip, once per
target, and the smoke's third pass link a consumer that calls an exported
function, through the moved install and through `add_subdirectory`.

- **FM1. Calling a green build and install "consumable".** Only the round trip
  with a compiled consumer shows a missing `find_dependency`, which stays green
  for a `LANGUAGES NONE` consumer.
- **FM11. Writing a raw `${PROJECT_SOURCE_DIR}/include` into a `PUBLIC` include
  directory in step 2.** Steps 2 to 5 pass, then step 6's generate fails with
  `INTERFACE_INCLUDE_DIRECTORIES property contains path` (Chipmunk2D, both
  lines).
- **FM12. Trusting an empty `main` to catch a static library's missing link
  dependency.** It pulls no archive member. Chipmunk2D's static target never
  linked `m` and failed ``undefined reference to `sincos'`` once `main` called
  `cpBodyNew`, and openjpeg's `openjp2_static` failed
  `undefined reference to lrintf` under `SYM_CALL` (both lines).
- **FM18. Keeping a tree's `${CMAKE_SOURCE_DIR}` in a usage requirement.** It
  is the parent's source root under `add_subdirectory`. The round trip reads
  only `INSTALL_INTERFACE` and the smoke's first two passes compile nothing, so
  they pass, and the third pass fails with `'tinyformat.h' file not found`
  (tinyformat, both lines). Write `CMAKE_CURRENT_SOURCE_DIR` or
  `PROJECT_SOURCE_DIR`, and the same for `CMAKE_BINARY_DIR` in generated files.
- **One round trip over a shared and a static target.** cmark's consumer
  resolved `cmark_version` from `libcmark.so`, and `libcmark.a` on the same link
  line supplied nothing. Per target, the static consumer defines 106 `cmark_`
  symbols (both lines).

## C2 A default crosses the boundary with an outer layer

The tree shares one cache and one set of top-level variables with its outer
layers: a parent under `add_subdirectory`, a toolchain, a manager profile, the
user's `-D`. A write that creates or overrides their entry, or an unprefixed
read of a name they also set, changes their build while every top-level check
passes. Check: guards, prefixes, the smoke under an adversarial parent, its
state diff of the parent's cache and build root, and the round trip's
`CMAKE_MODULE_PATH` guard. The last two need no name in advance.

- **FM5. Guarding `CMAKE_CXX_STANDARD` with `PROJECT_IS_TOP_LEVEL` alone.** The
  top level is exactly where it overrides a Conan profile. C is the same:
  cmark's bare `set(CMAKE_C_STANDARD 99)` kept `-std=c99` under
  `-DCMAKE_C_STANDARD=11`, exit 0, and `I11` listed only C++ setters.
- **FM8. Running the as-subproject check from a parent without
  `include(CTest)`.** `BUILD_TESTING` then stays off and a leaked test tree
  reads clean.
- **FM13. Gating demos on an unprefixed
  `option(BUILD_DEMOS ... ${PROJECT_IS_TOP_LEVEL})`.** A parent owning
  `BUILD_DEMOS=ON` switches the demos on, and fails `Could NOT find OpenGL`
  (Chipmunk2D, both lines), while the plain smoke passes. A `CACHE BOOL` toggle
  is an option too: a parent owning openjpeg's `WITH_ASTYLE=ON` failed
  `No CMAKE_CXX_COMPILER could be found`. tinyformat's `COMPILE_SPEED_TEST`
  leaked the same way, and openjpeg's options declared after the
  `add_subdirectory(src/lib)` that reads them leaked two targets.
  A cache `STRING` is one too: libssh2's `set(CRYPTO_BACKEND "" CACHE` split
  across lines, and a parent owning `mbedTLS` failed `Could NOT find MbedTLS`.
- **FM16. Keeping a library's `option(BUILD_SHARED_LIBS ... ON)` as found.**
  It creates the parent's cache entry, and the parent's later libraries build
  `SHARED_LIBRARY` with every smoke target grep empty (jsoncpp, both lines).
  `asub_bsl` shows it. A cached `EXECUTABLE_OUTPUT_PATH` moves the parent's
  later executables into `lib-build/bin/` the same way (openjpeg).
  tinyformat's unguarded `file(WRITE ${CMAKE_BINARY_DIR}/_empty.cpp)` writes
  into the parent's build root, which failed nothing.
- **A write through another channel.** libssh2's `include(CPack)` rewrote a
  parent's `CPackConfig.cmake` version `9.9.9` to `1.11.1_DEV` with every smoke
  grep clean, and its installed Config left its own directory on the consumer's
  `CMAKE_MODULE_PATH`, shadowing the consumer's `FindWolfSSL.cmake` (both
  lines). Per-name lists missed both, and the state diff and guard show them.

## C3 An edit changes the output while presence checks pass

An inventory grep proves the old command is gone, and a green build proves the
tree compiles. Neither sees a lost flag, a compile feature below the compiler's
default, a build-type swap, or a policy that rewrites a configured file. Check:
the per-target flag-set diff and the configured-file diff against the step-1
commit.

- **The bare negative control.** Deleting Chipmunk2D's `include_directories`
  passes `I2` and the gated configure, and the build fails (4.4.2).
- **FM6. Copying the build-type idiom without `FORCE` after `project()`.** A
  plain `CACHE` set there does nothing. Copying its `RelWithDebInfo` over a
  tree that defaulted to `Release` silently swaps `-O3` for `-O2 -g` (jsoncpp,
  the flag-set check, 4.4.2).
- **FM10. Replacing `-std=gnu99` with
  `target_compile_features(<t> PUBLIC c_std_99)` alone.** The feature is a
  floor. gcc 15.2.1 defaults to C 23, so CMake adds no `-std` and Chipmunk2D
  compiled as gnu23 with every other step 4 check green (both lines). The
  flag-set diff shows the lost `-std=gnu99`, and `cxx_std_NN` is the same.
- **FM20. Trusting step 1's checks after raising `<max>`.** On 4.4.2, CMP0219
  stopped re-escaping `macro()` arguments and openjpeg's `.pc` macro wrote
  `libdir=\/lib64`, while the canary, the gated configure and the policy probe
  passed. The configured-file check shows it. cmark's CMP0148 dropped
  `FindPythonInterp` and 9 tests became 2 with ctest's `100% tests passed`
  (`CMK-DEP-19`, both lines). The test-name diff and `I13` show it.
- **FM21. Reading the flag-set union of two targets that compile one source.**
  `openjp2_static` lost `-DMUTEX_pthread` and the union diff exited 0 (both
  lines). Filter each run on `TGT`.
- **One configuration, compile flags only.** A dropped Debug-only
  `-DCMARK_DEBUG_NODES` passed the Release diff (4.4.2). A dropped Asan
  `target_link_options` passed the Asan flag-set diff, and the link failed with
  ``undefined reference to `__asan_option_detect_stack_use_after_return'``.
- **The false loss.** Two `-I` spellings of one directory print as a `<` and a
  `>` line (jsoncpp: `-I.../include` against
  `-I.../src/lib_json/../../include`, both lines). Compare them with
  `realpath` before calling either a loss.

## C4 The policy version CMake applies is not the one written

A range the checks read as done leaves newer policies unset: two dots, a floor
through a variable, a later own-code `cmake_policy(VERSION)`, or a three-dot
range whose max is older than the CI line. Check: `F1b` lists every such line,
and the policy probe reads `NEW`.

- **FM2. Writing `3.15..4.3`.** Two dots are one literal and collapse to
  `VERSION 3.15` with no diagnostic, even under the gate.
- **FM14. Adding `...<max>` to a floor spelled through a variable, then
  stopping.** `F1` never lists `cmake_minimum_required(VERSION ${VAR})`, and a
  later own-code `cmake_policy(VERSION 3.13.2)` resets what the range set. On
  jsoncpp every step 1 check passed while CMP0083 to CMP0177 stayed unset
  (3.31.12 and 4.4.2). Run `F1b` and the policy probe.
- **FM19. Reading an empty `F1` as done when the floor is a range with an old
  max.** openjpeg's `3.10...3.31.5` and zlib's `2.4.4...3.15.0` print nothing,
  and every later policy stays unset (openjpeg's 4.4.2 gate failed on
  `Policy CMP0219 is not set`). `F1b` lists every range.
- **Also measured.** tinyformat's floor below `project()` fails the gated
  configure (`should be called prior to this top-level project()`). Moved above
  it, `2.8...4.4` exits 0 on 3.31.12, 4.0.7 and 4.4.2.

## C5 Visibility comes from a default instead of the readers

A keyword decided by the `PRIVATE` default, or by a reader grep over a
directory that also holds sources, is wrong, and the plan options never build
the reader it breaks. Check: `I2b`, the reader grep over installed headers
only, and a build per option that adds a definition or in-tree dependent.

- **FM15. Moving a definition that an installed header reads onto the target
  as `PRIVATE`.** Every step 2 check passes under the plan options, and the
  option that sets it breaks the link: jsoncpp failed
  `undefined symbol: Json::Value::operator[]` under
  `-DJSONCPP_USE_SECURE_MEMORY=ON` (both lines), and `PUBLIC` built. Upstream's
  directory-scoped define failed its install consumer the same way, so the round
  trip also runs with that option in `CFG_ARGS`.
- **FM22. Grepping a header directory that also holds sources, or making a
  consumer opt-in macro `PUBLIC`.** openjpeg installs `openjpeg.h` from
  `src/lib/openjp2`, which also holds every source, so a grep of that directory
  read all three of its private definitions as `PUBLIC`. zlib's `zlib.h` reads
  `_LARGEFILE64_SOURCE` only to ask whether the consumer wants the 64-bit API,
  and `PUBLIC` put `-D_LARGEFILE64_SOURCE=1` on every installed consumer (both
  lines).
- **FM23. Closing step 3 on `I1` alone.** The `PRIVATE` default took `m` from
  openjpeg's in-tree `compare_images`, which failed with
  `DSO missing from command line` under `-DBUILD_TESTING=ON` (4.4.2).
- **A definition set as a property.** cmark's `COMPILE_FLAGS -DCMARK_STATIC_DEFINE`
  escaped every inventory command. The Linux round trip passed, and a
  Windows-target consumer failed `__declspec(dllimport) cmark_version` until it
  became `PUBLIC` (zig cross toolchain, linked, not run). `I2b` lists it.

## C6 A name, default or knob a caller uses today breaks

A caller outside the tree uses option spellings and defaults, install knobs,
exported target names, a Find module's names, `.pc` files and public commands.
Changing one passes every check written for the new spelling. Check: the
caller contract in the plan file, and the old spelling run once at the step
that changes it.

- **FM7. Swapping `${ARGN}` for `PARSE_ARGV` mechanically**, which silently
  changes every caller that passes a quoted list. The flatten line keeps them.
- **FM17. Adding `NAMESPACE` to an existing export and trusting the round trip
  on the new name.** On jsoncpp it passed for `jsoncpp::jsoncpp_static`, failed
  `JsonCpp::JsonCpp` at generate, and turned a bare `jsoncpp_static` into a `-l`
  flag, while the tree's own CI links `JsonCpp::JsonCpp` (both lines). With the
  old names shipped, all five spellings exit 0. An old-name `ALIAS` without its
  `NOT TARGET` guard fails a second `find_package` with
  `add_library cannot create ALIAS target` (openjpeg, both lines).
- **FM24. Renaming or re-defaulting an option without its legacy behaviour.** A
  plain rename dropped `-DBUILD_TESTING=ON` with exit 0 and 0 tests, which
  openjpeg's CI seeds. A test gate that defaulted `OFF` came on at top level and
  failed without libtiff (openjpeg, both lines). zlib's documented
  `-DINSTALL_LIB_DIR` was ignored after step 6. openjpeg's vendored
  `thirdparty/CMakeLists.txt` reads the renamed `BUILD_THIRDPARTY` and
  `WITH_ASTYLE`, and gets them back as directory-scoped variables. libssh2's
  shim took `-DENABLE_WERROR=ON` only on a fresh configure: on the step-4 tree
  it left 105 `-Werror` at 0 with exit 0 until the `UNINITIALIZED` block.
- **FM25. Shipping a Config package under a Find-module name with only new
  targets.** On zlib the round trip passed without them, plain
  `find_package(ZLIB)` never read the Config, and a `CMAKE_FIND_PACKAGE_PREFER_CONFIG`
  consumer (`-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON`) lost `ZLIB::ZLIB` at
  configure and FindZLIB's variables at compile (both lines).
- **FM26. Leaving a hand-written `.pc` template on the variables step 6
  replaced.** zlib's `zlib.pc.cmakein` reads `@INSTALL_LIB_DIR@`, so after the
  switch to `CMAKE_INSTALL_*` the `.pc` shipped empty `libdir` and
  `includedir`, and pkg-config printed `-I -L -lz` with exit 0 while the round
  trip passed (both lines).

## C7 A CMake name or citation written from memory

A name or a page an agent recalls, rather than reads from the pinned binary or
tag, passes review and does nothing. Check: the variable-existence check
against the pinned binary (`CMK-LANG-11`), and each cited page fetched at the
pinned tag.

- **FM4. Inventing `CMAKE_CXX_STANDARD_EXTENSIONS`** or
  `CMAKE_DEBUG_PREFIX_MAP`. Run the placeholder-expanded variable check. A raw
  match against `cmake --help-variable-list` also reports the real
  `CMAKE_CXX_FLAGS` as invented, because the list prints `CMAKE_<LANG>_FLAGS`.
- **FM9. Citing the CMake Tutorial by its old step titles.** At v4.4.2 it is
  organised as topic pages. Fetch the page at the pinned tag first.

## C8 A check that could not fire reads clean

Empty output is a pass only from a check that could have printed. An ignored
gate spelling, a failed configure, a missing grep operand, a pattern that
misses a spelling, or a proof that resolved another copy all read clean. Check:
the exit code first, the canary per leg, each pass grep's list command, and the
round trip's anchored `_DIR` line.

- **FM3. Passing `-Werror=author` to a 3.31 leg** and reading the green run as
  a live gate. Run the canary on that leg. A leg on the runner image's CMake has
  no binary to run it through, so its gate is spelled `-Werror=dev` (jsoncpp).
- **A failed configure.** After smoke pass 1 failed, `ctest -N` still printed
  `Total Tests: 0` and every target grep was empty (tinyformat, both lines).
- **A missing operand.** `I9` over absent `build/_deps` and `third_party`, and
  the CI greps over an absent `.github/workflows`, exit 2 (Chipmunk2D,
  tinyformat). The `CMK-CORE-05` grep over an absent `scripts` exits 2 while
  `-s` hides the message and the hits in `.github` still print (jsoncpp, zlib).
- **A pattern that misses a spelling.** `I2` once missed jsoncpp's three live
  `add_compile_definitions` calls and printed only their dead `add_definitions`
  twins. The `CMK-CORE-01` grep over `.github/workflows` reads "no gate" for
  openjpeg, whose workflows configure through
  `ctest -S tools/ctest_scripts/travis-ci.cmake`, until `CI_SCRIPTS` names it.
  The configured-file list missed cmark's `CONFIGURE_FILE(` until `-i`, and the
  `CMK-INST-18` greps missed libssh2's `make ... install` in `tests/cmake/test.sh`.
- **A proof that resolved another copy.** libssh2's own `export(PACKAGE)` at the
  entry check wrote a registry entry. With no version file installed, the round
  trip exited 0 through that build tree, and with the registry switch and the
  anchored `_DIR` grep it exits 1, `version: unknown` (both lines).

## C9 A finding no step owns stalls the run or rides along

A finding whose step, status or reviewable unit the procedure does not name
stops a literal agent, or lands in a diff no plan row covers. Check: a plan row
with step and status for every hit and touched file, the floor's second diff,
the per-category demotion, and `git status --short` after each configure.

- **The entry check.** Chipmunk2D and cmark need a C++ compiler for an
  implicit or declared CXX, and Chipmunk2D's demos OpenGL: a plan option, the
  owner's. tinyformat's floor of 2.8 configures on 3.31.12 and fails on 4.0.7
  and 4.4.2: step 1's to fix, not a stop.
- **A configure that edits the source tree.** zlib renames its `zconf.h` on
  every out-of-source configure (` D zconf.h`), a deletion no plan row names.
- **A gate error a later step owns.** zlib's absolute install destinations stop
  every gated 4.4.2 configure of steps 1 to 5 (`install-absolute-destination`).
  Demoted, the configure exits 0 with six warnings, and the canary exits 1.
- **No CI, or CI on an unpinned runner image.** `<max>` and the CI lines were
  undefined until the pinned defaults named 4.4 and the lines 3.31 and 4.4.
- **A structure no step created.** tinyformat's missing header-only target is
  now step 3's. Chipmunk2D's step-6 fix of a raw include path is step 6's one
  named `CMK-TGT` exception.
- **A version.** `write_basic_package_version_file` without one stops with
  `No VERSION specified` (tinyformat, 3.31.12 and 4.4.2). zlib states
  `set(VERSION "1.3.1")`, which is passed as `VERSION ${VERSION}`.
- **A repair with no step.** openjpeg's CMP0219 `.pc` repair (a `macro()`
  turned `function()`) is the floor diff's second diff, and so is libssh2's
  CMP0175 error (`add_custom_command(TARGET): DEPENDS`, gated exit 1 on both
  lines), migrated to `NEW` under `CMK-VER-07`. openjpeg's three
  unconditional `-Werror=<category>` flags under GCC are `flagged-not-converted`
  with a `CMK-TGT-09` note. Its `BUILD_JPIP`, `BUILD_JAVA` and `BUILD_VIEWER`
  components, which the host cannot configure, are `flagged-not-converted` with
  the missing prerequisite named.
- **Vendored files in a whole-tree step.** The `gersemi` gate line listed 39 of
  openjpeg's files, 8 of them vendored, so the line takes one `':!:thirdparty/**'`
  pathspec per vendored directory, and the first reformat ships as its own diff.
