---
title: Installing and Exporting a Consumable Package
summary: The CMK-INST family. Install rules, the Config package and its version file, relocation, RPATH, pkg-config, multi-config installs and the CPS export, each proven by consuming the installed package from a separate project
---

# Installing and Exporting a Consumable Package

Owns what a library installs and how a separate project finds and links it: install destinations, the export set, the Config template and its version file, relocation, RPATH, the `.pc` file, multi-config installs and the CPS export. It does not own the usage requirements on the targets being exported (scope keywords, the namespaced `ALIAS`, `target_compile_features`, flags), which are CMK-TGT in `targets.md`. Consuming a package, including which of a `.cps` and a Config file wins and how version ranges resolve, is CMK-DEP in `dependencies.md`. The configure gate is CMK-CORE in the `cmake-build` index. The Bazel wrap's view of install destinations is CMK-BZL in `bazel-seam.md`, and vcpkg's `unofficial-<name>` packages are CMK-VCPKG in `cpp-packaging/vcpkg.md`. CPack and SBOM generation carry no rule: no measured failure depends on them (as of 2026-09-26). Every row assumes `cmake_minimum_required(VERSION 3.25...4.4)` (**pinned**: the floor is a default an adopter overrides once) and was measured 2026-09-26 on CMake 3.31.12, 4.3.4 and 4.4.2 with gcc 15.2.1 on Linux unless it says otherwise. The configure gate is `-Werror=author` on CMake ≥ 4.4, `-Werror=dev` on ≤ 4.3, and `-Werror=dev` when one command line serves both (CMK-CORE-01).

Contents: [The Round Trip](#the-round-trip) · [The Multi-Config Leg](#the-multi-config-leg) · [Greps Over the Install Rules](#greps-over-the-install-rules) · [Installed Binaries and pkg-config Files](#installed-binaries-and-pkg-config-files) · [The CPS Export Guard](#the-cps-export-guard) · [Reading Checks](#reading-checks) · [What Agents Get Wrong Here](#what-agents-get-wrong-here)

## The Round Trip

One script verifies CMK-INST-01 to -06 and, run on a CMake ≥ 4.3 line, CMK-INST-14 to -17. Run it from an empty scratch directory, once per CMake line under test. It stops at the first failure, and any non-zero exit is a finding. `GATE` defaults to `-Werror=dev`, which serves every line. Set `GATE=-Werror=author` on a leg that only runs CMake ≥ 4.4.

```sh
# CMK-INST-01 round trip. Run from an empty scratch directory, once per CMake line under test.
# The caller exports PKG (the find_package name), VER (a version the package satisfies),
# TARGETS (its imported targets), SRC (the absolute source directory), and SYM_DECL and SYM_CALL:
# an include and a call of one exported function per target, e.g.
# SYM_DECL='#include <mylib/mylib.h>' SYM_CALL='mylib_version() != 0'.
# CFG_ARGS (optional): the library's own -D options.
# GATE is the configure gate: -Werror=dev serves every line, -Werror=author only CMake >= 4.4.
set -eu
: "${PKG:?}" "${VER:?}" "${TARGETS:?}" "${SRC:?}" "${SYM_DECL:?}" "${SYM_CALL:?}"
GATE="${GATE:--Werror=dev}"
W="$PWD"
cmake -S "$SRC" -B "$W/build" "$GATE" ${CFG_ARGS:-}
cmake --build "$W/build"
cmake --install "$W/build" --prefix "$W/prefix"
# (a) Text files in the prefix naming the source, build or install tree. Empty = pass.
grep -rIl --exclude='*.pc' -e "$SRC" -e "$W/build" -e "$W/prefix" "$W/prefix" > "$W/leaks.txt" || true
test ! -s "$W/leaks.txt"
# (b) An export file with a baked absolute import prefix. Empty = pass.
grep -rn --include='*.cmake' -e 'set(_IMPORT_PREFIX "/' "$W/prefix" > "$W/abs-import.txt" || true
test ! -s "$W/abs-import.txt"
# (c) An imported target declared without a namespace. Empty = pass.
grep -rhn --include='*.cmake' -e 'add_library(' "$W/prefix" | grep -v -e '::' > "$W/bare.txt" || true
test ! -s "$W/bare.txt"
# (d) Move the prefix, then configure, build and link a separate consumer against it.
mv "$W/prefix" "$W/moved"
mkdir -p "$W/consumer"
printf '%s\n' "$SYM_DECL" "int main(void) { return $SYM_CALL; }" > "$W/consumer/main.c"
printf '%s\n' 'cmake_minimum_required(VERSION 3.25...4.4)' 'project(rt LANGUAGES C)' \
  "find_package($PKG $VER CONFIG REQUIRED)" 'add_executable(rt main.c)' \
  "target_link_libraries(rt PRIVATE $TARGETS)" > "$W/consumer/CMakeLists.txt"
cmake -S "$W/consumer" -B "$W/consumer-build" "$GATE" -DCMAKE_PREFIX_PATH="$W/moved"
cmake --build "$W/consumer-build"
grep -e "^${PKG}_DIR" "$W/consumer-build/CMakeCache.txt"
```

The consumer enables a compiled language on purpose, because a `LANGUAGES NONE` project never searches `lib64`. The last line prints the file the consumer resolved: `…/cmake/<pkg>` for a Config package, `…/cps/<pkg>` on CMake ≥ 4.3 when a valid `.cps` is installed. Step (a) lists a `.cps` file when a dependency was found inside the tree under test, through the absolute `requires.<dep>.hints` entry CMake 4.3.4 and 4.4.2 write. That is a real finding here. Over a shared prefix holding several packages, a hit whose only absolute string sits in `"hints"` is expected.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-INST-01 | Whenever install, export, Config-template or dependency wiring changes, prove the package can be consumed with the round-trip script. Never treat a green build and install as proof. Floor: any. | A missing `find_dependency` fails only in the consumer's Generate step ("the target was not found"). The exporting project's build and install stay green. An empty consumer `main` pulls no member out of a static archive, so the consumer calls one exported function per target: a static target that never linked `m` passed with an empty `main` and failed with ``undefined reference to `sincos'`` once `main` called `cpBodyNew` (slembcke/Chipmunk2D at f2f3d662 with a modernized build, 3.31.12 and 4.4.2, 2026-09-26). | The script exits 0. Any non-zero exit is the finding. A package that also ships a `.pc` compares `pkg-config --cflags --libs` against a `DESTDIR` install of the pre-change commit: an empty `-I` or `-L`, or a path that lost its prefix, is the finding (madler/zlib at `v1.3.1`: `-I -L -lz`, exit 0, while the round trip exited 0, measured 2026-09-26 on 3.31.12 and 4.4.2). | MUST |
| CMK-INST-02 | Give `install(EXPORT … DESTINATION)` a relative path from `GNUInstallDirs`, such as `${CMAKE_INSTALL_LIBDIR}/cmake/<pkg>` (or `${CMAKE_INSTALL_DATADIR}/cmake/<pkg>` for an arch-independent package). Never build it from `${CMAKE_INSTALL_PREFIX}` or another absolute base. Floor: any. | An absolute destination makes CMake write a literal `set(_IMPORT_PREFIX "/…")` instead of the relocation chain, so the package breaks once its prefix moves. A `$<INSTALL_INTERFACE>` include path alone does not make a package relocatable, and `cmake-packages(7)` never says so: rapidjson ships a non-relocatable package for this reason. | Steps (a) and (b) print nothing and step (d) links after the move. An absolute destination also fails the install itself when the configure-time prefix is not writable, and on CMake ≥ 4.4 the gate fails the configure (CMK-INST-10). | MUST |
| CMK-INST-03 | In the Config template, redeclare every imported dependency on an exported target's PUBLIC or INTERFACE link line with `find_dependency()` from `CMakeFindDependencyMacro`, under the same condition the build used to add it. Never use a raw `find_package()` there. Floor: 3.0. | CMake neither generates these calls nor checks for them at export. `find_dependency` forwards the consumer's `QUIET` and `REQUIRED`, while a raw `find_package(Threads REQUIRED)` stays fatal under `find_package(<pkg> QUIET)`. | Step (d) fails on a missing call. For raw calls, `grep -rn --include='*Config.cmake.in' --include='*config.cmake.in' --include='*config.in.cmake' --include='*Config.cmake' --include='*-config.cmake' --exclude='Find*.cmake' -e 'find_package[[:space:]]*(' .` Empty output is the pass. A hit is the finding unless a comment explains it or the file is not installed as a package Config file. | MUST |
| CMK-INST-04 | Install a `<Pkg>ConfigVersion.cmake` beside the Config file, generated by `write_basic_package_version_file()`. Floor: any. | Without it every versioned request fails with "considered but not accepted … version: unknown". A hand-written file passes step (d) and can still ignore a range's upper bound: Tencent/rapidjson's `RapidJSONConfigVersion.cmake.in` at `24b5e7a8`, configured to 1.1.0, accepts `find_package(Foo 1.0...<1.1)`, which a generated `SameMajorVersion` file rejects (measured 2026-09-26 on 3.31.12 and 4.4.2). | Step (d)'s `find_package($PKG $VER …)` fails with "version: unknown". That failure is the finding. Step (d) cannot see a hand-written file, so also run `grep -rl --include='*.in' --include='*ConfigVersion.cmake' --include='*-config-version.cmake' --exclude-dir='build*' --exclude-dir='_deps' -e 'PACKAGE_VERSION_COMPATIBLE' .` Empty output is the pass. A listed file is the finding. | MUST |
| CMK-INST-05 | Process a Config template that contains `@PACKAGE_INIT@` with `configure_package_config_file()`, never with `configure_file()`. A hand-written template does no prefix or path arithmetic of its own. Floor: 2.8.8. | Only `configure_package_config_file()` defines `PACKAGE_INIT`. Through `configure_file(@ONLY)` the token silently becomes an empty line, and the `set_and_check` and `check_required_components` helpers it defines vanish. | Step (d) fails with `Unknown CMake command "check_required_components"` when the template calls a helper. For one that calls none, list the templates with `grep -rln --include='*.cmake.in' --include='*.in.cmake' -e '@PACKAGE_INIT@' .` and the calls with `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'configure_package_config_file(' .` A listed template named in no call is the finding. The second listing also finds a template with an unconventional suffix. | MUST |
| CMK-INST-06 | Give every `install(EXPORT)` and `export(EXPORT)` a `NAMESPACE`, so each imported target is spelled `<Ns>::<name>`. Floor: CMP0028 (3.0). Adding `NAMESPACE` to an export that shipped without one keeps every previously exported name, and every name a hand-written targets file defined, as an `ALIAS` of the namespaced imported target in the Config package, each under `if(NOT TARGET <old>)` (CMake ≥ 3.18), or ships with a changelog entry naming the rename. | Under CMP0028 a name containing `::` must be a target, so a typo or a missing `find_package` fails at configure. A bare name falls back to a `-l<name>` link flag. On open-source-parsers/jsoncpp at `3347a4b8`, the `NAMESPACE` edit alone passed the round trip on the new name, failed `JsonCpp::JsonCpp` at generate and turned `jsoncpp_static` into `-ljsoncpp_static`, which failed the consumer's compile with `'json/json.h' file not found`, and all five spellings exit 0 with the aliases (measured 2026-09-26 on 3.31.12 and 4.4.2). Without the `NOT TARGET` guard, a second `find_package` in one directory fails with `add_library cannot create ALIAS target` (uclouvain/openjpeg at `8314119b`, measured 2026-09-26 on 3.31.12 and 4.4.2). | Step (c). Empty output is the pass. A listed `add_library(` line is the finding. When `NAMESPACE` was added to an existing export, run the round trip once per old spelling, and once with `find_package` called twice in one directory. Exit 0 = pass. | MUST |
| CMK-INST-07 | Make the export namespace equal the package name consumers pass to `find_package`, spelled exactly. Floor: any. | CPS names imported targets `<package>::<component>`, so a mismatch becomes a breakage for every CMake ≥ 4.3 consumer the day CPS ships (CMK-INST-15). | Reading heuristic: compare each `NAMESPACE X::` with the directory name under `lib*/cmake/` or `share/cmake/` in the installed prefix. A difference is the finding. | SHOULD |
| CMK-INST-25 | A Config package whose name CMake ships a Find module for (`ZLIB`, `PNG`, `CURL`) also defines that module's imported targets and result variables. Floor: any. | Plain `find_package(ZLIB)` resolves through FindZLIB and never reads the Config, so the round trip on the new names passes, while a consumer with `CMAKE_FIND_PACKAGE_PREFER_CONFIG` loses `ZLIB::ZLIB` (configure exit 1) and `ZLIB_INCLUDE_DIRS` (build exit 1) (madler/zlib at `v1.3.1` with a modernized build, measured 2026-09-26 on 3.31.12 and 4.4.2). | Run the round trip once more on the module's target name with `-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON` in the consumer configure. Exit 0 = pass. | SHOULD |
| CMK-INST-08 | Match `write_basic_package_version_file`'s `COMPATIBILITY` to the ABI promise: `ExactVersion` for no ABI stability, `SameMajorVersion` for semver. For a header-only package add `ARCH_INDEPENDENT` and install the Config files under `${CMAKE_INSTALL_DATADIR}/cmake/<pkg>`. Floor: `ARCH_INDEPENDENT` 3.14. | A header-only package without `ARCH_INDEPENDENT` rejects consumers whose pointer size differs. `share/` is searched by a project that enables no language, and `lib64` is not. | Reading heuristic: `grep -rn -A4 --include='CMakeLists.txt' --include='*.cmake' -e 'write_basic_package_version_file' .` then read each call against the project's versioning statement. Empty output means the row does not apply. | SHOULD |

```cmake
# wrong: fatal even under find_package(foo QUIET), and unconditional
find_package(Threads REQUIRED)

# right: forwards QUIET and REQUIRED, under the condition the build used
include(CMakeFindDependencyMacro)
if(@FOO_WITH_THREADS@)
    find_dependency(Threads)
endif()
```

## The Multi-Config Leg

Run it after the round trip, in the same directory, with the same exported variables. It needs `Ninja Multi-Config` (or Visual Studio or Xcode), and `NINJA` names a ninja binary when none is on `PATH`. Any non-zero exit is a finding. The round trip alone never passes `--config`, so it cannot see these defects.

```sh
# CMK-INST-22 multi-config leg. Run after the round trip, in the same directory and environment.
set -eu
: "${PKG:?}" "${VER:?}" "${TARGETS:?}" "${SRC:?}"
GATE="${GATE:--Werror=dev}"
W="$PWD"
cmake -S "$SRC" -B "$W/mc-build" -G "Ninja Multi-Config" "$GATE" ${CFG_ARGS:-} ${NINJA:+-DCMAKE_MAKE_PROGRAM="$NINJA"}
for c in Debug Release; do
  cmake --build "$W/mc-build" --config "$c"
  cmake --install "$W/mc-build" --config "$c" --prefix "$W/mc-prefix"
done
# (e) An installed file claimed by two configurations. Empty = pass.
grep -rhoE --include='*-*.cmake' -e 'IMPORTED_LOCATION_[A-Z_]+ "[^"]+"' -e 'IMPORTED_IMPLIB_[A-Z_]+ "[^"]+"' "$W/mc-prefix" \
  | sed -E 's/^[^ ]+ //' | sort | uniq -d > "$W/dup.txt"
test ! -s "$W/dup.txt"
# (f) Move, then consume each configuration with the map pinned to itself.
mv "$W/mc-prefix" "$W/mc-moved"
cmake -S "$W/consumer" -B "$W/mc-consumer-build" -G "Ninja Multi-Config" "$GATE" ${NINJA:+-DCMAKE_MAKE_PROGRAM="$NINJA"} \
  -DCMAKE_PREFIX_PATH="$W/mc-moved" -DCMAKE_MAP_IMPORTED_CONFIG_DEBUG=Debug -DCMAKE_MAP_IMPORTED_CONFIG_RELEASE=Release
for c in Debug Release; do cmake --build "$W/mc-consumer-build" --config "$c"; done
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-INST-21 | When more than one configuration installs into one prefix, give each configuration's binaries a distinct file name: set `CMAKE_DEBUG_POSTFIX` before the first `add_library` (under `if(NOT DEFINED CMAKE_DEBUG_POSTFIX)`), set the `DEBUG_POSTFIX` property, or install each configuration into its own prefix. Floor: any. | With one file name, `cmake --install --config Release` overwrites the Debug file. Both `IMPORTED_LOCATION_DEBUG` and `_RELEASE` then name the Release binary, and a Debug consumer links it with every step exiting 0. The variable only initialises targets created after it, so set after `add_library` it changes nothing. Conan and vcpkg keep configurations apart themselves, so this binds the project's own install. | Step (e). Empty output is the pass. A printed path is the finding. The scan cannot tell whether a distinctly named file holds the right configuration's binary. | MUST |
| CMK-INST-22 | For a library that can be built with a multi-config generator, run the leg beside the round trip, in CI where CMK-INST-18 applies. To prove a configuration is present, pin `CMAKE_MAP_IMPORTED_CONFIG_<CONFIG>` to that same configuration, never to an empty value. A consuming leg whose configuration is not one every imported package installs (RelWithDebInfo, MinSizeRel, a custom one) sets `CMAKE_MAP_IMPORTED_CONFIG_<CONFIG>` to that configuration followed by `Release`, in its preset or toolchain. Floor: any. | With no map, a Release consumer against a Debug-only install configures, builds and runs with no warning, and the `IMPORTED_LOCATION` documentation allows that fallback. An empty map names the configuration-less location, which exports never set, so it rejects installed configurations too. | The leg exits 0. Negative control: install Debug only, and step (f) must then fail at the consumer configure. A green negative control is the finding. Consumer side: `grep -rn --include='CMakeCache.txt' -e '^CMAKE_BUILD_TYPE' -e '^CMAKE_MAP_IMPORTED_CONFIG_' build`. A RelWithDebInfo or MinSizeRel build type with no map line for it = finding, unless the leg's toolchain file sets the map (a plain `set()` there never reaches the cache). Empty = not a configured tree. | SHOULD |

## Greps Over the Install Rules

Run each from the source root. A build tree inside the source tree holds a generated `cmake_install.cmake` full of absolute destinations and resolved RPATHs, so the two commands that would read it exclude it. Every grep is blind to a path built through a variable, and the round trip catches that case.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-INST-09 | Take every install destination from `GNUInstallDirs` variables, and derive RPATH suffixes and `.pc` paths from them. Never hard-code `lib` or `lib64`, and never define or read `LIB_SUFFIX`, `LIB_INSTALL_DIR`, `INCLUDE_INSTALL_DIR`, `SYSCONF_INSTALL_DIR` or `SHARE_INSTALL_PREFIX`. Floor: any. | `CMAKE_INSTALL_LIBDIR` is `lib64` on some hosts and `lib/<multiarch-tuple>` on Debian under `/usr`. Fedora 45's `%cmake` macro stopped injecting the five legacy variables (change page updated 2026-03-10). | `grep -rn --include='CMakeLists.txt' --include='*.cmake' --exclude='cmake_install.cmake' -e 'LIB_SUFFIX' -e 'LIB_INSTALL_DIR' -e 'INCLUDE_INSTALL_DIR' -e 'SYSCONF_INSTALL_DIR' -e 'SHARE_INSTALL_PREFIX' -e 'DESTINATION lib' -e 'DESTINATION "lib' -e 'ORIGIN/../lib' .` Empty output is the pass. A hit is the finding unless it is a documented back-compat shim that only reads `GNUInstallDirs`. `DESTINATION lib` also matches `lib64` and `libexec`, which are hard-coded too. | MUST |
| CMK-INST-10 | Never write an absolute `DESTINATION` in `install()`. Floor: the grep works on any version, the diagnostic needs 4.4. | An absolute destination ignores `CMAKE_INSTALL_PREFIX` and `--prefix`: the install writes the literal path or fails with "Maybe need administrative privileges". Only `DESTDIR` staging still works. CMK-BZL-04 carries the Bazel wrap's reason and cites this row. | On CMake ≥ 4.4 the gate fails the configure, because `-Werror=author` and `-Werror=dev` both promote `install-absolute-destination` (4.4.2). Tencent/rapidjson at `24b5e7a8` exits 1 at the 4.4.2 configure under `-Werror=author` with three `install-absolute-destination` errors, `CMakeLists.txt:200`, `204` and `256` (measured 2026-09-26). On 3.31 and 4.3 every one of those flags is accepted silently and does nothing, so every line also runs `grep -rnE --include='CMakeLists.txt' --include='*.cmake' --exclude='cmake_install.cmake' --exclude-dir='build-wrap' --exclude-dir='wrap-prefix' -e 'DESTINATION[[:space:]]+(\\?")?/' -e 'DESTINATION[[:space:]]+(\\?")?\$\{CMAKE_INSTALL_PREFIX\}' .` Empty output is the pass. The 4.4 diagnostic reads only an `install()` command's own `DESTINATION`, so on every version only the grep sees a `file(INSTALL DESTINATION …)` inside `install(CODE)`. In a quoted `install(CODE "…")` an unescaped `${CMAKE_INSTALL_PREFIX}` expands at configure time and ignores `--prefix`, and the optional `\"` in the pattern catches it. In an `install(CODE [[…]])` bracket argument, or escaped as `\${CMAKE_INSTALL_PREFIX}`, it expands at install time and honours `--prefix`, so a hit inside a bracket argument passes on read (measured 2026-09-26 on 3.31.12 and 4.4.2: configure rc 0 for all three forms). | MUST |
| CMK-INST-24 | Never call `export(PACKAGE)`. To let another project use a build tree without installing, point it at the `export(EXPORT)` file through `<Pkg>_DIR`. Floor: any. CMP0090 since 3.15. | Whether the call writes depends on the project's floor, not the running CMake. Below 3.15 it writes `~/.cmake/packages/<Pkg>/` at configure time, pointing into a build tree that every later `find_package(<Pkg>)` on the machine may pick up. rapidjson's floor of 3.5 makes its call write on 3.31.12 and 4.4.2. A packager building such a project passes `-DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON`. | `grep -rniE --include='CMakeLists.txt' --include='*.cmake' -e 'export[[:space:]]*\([[:space:]]*package[[:space:])]' -e 'export[[:space:]]*\([[:space:]]*package$' .` Empty output is the pass. The pattern stops at the word, so the 4.3 build-tree call `export(PACKAGE_INFO …)` is not a hit. | MUST |

```cmake
# wrong: a hard-coded directory, a legacy suffix and a fixed RPATH depth
install(TARGETS foo LIBRARY DESTINATION lib${LIB_SUFFIX})
set_target_properties(foo PROPERTIES INSTALL_RPATH "$ORIGIN/../lib")

# right: every path from GNUInstallDirs, relative to the prefix
include(GNUInstallDirs)
install(TARGETS foo LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})
set_target_properties(
    foo
    PROPERTIES INSTALL_RPATH "$ORIGIN/../${CMAKE_INSTALL_LIBDIR}"
)
```

## Installed Binaries and pkg-config Files

Both checks run on the moved prefix the round trip leaves in `$W/moved`. `LIBDIR` is the configured `CMAKE_INSTALL_LIBDIR`. Floor: any CMake, pkg-config 2.3.0 measured.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-INST-11 | For an installed executable or shared library that loads another shared library from the same prefix, set `INSTALL_RPATH` to `$ORIGIN/../${CMAKE_INSTALL_LIBDIR}` (`@loader_path/../…` on Apple) and leave `BUILD_WITH_INSTALL_RPATH` off. The exception is a package that only installs into a prefix on the loader's default path. For a dependency installed in another prefix, set `INSTALL_RPATH_USE_LINK_PATH ON` on the executable, or name that prefix's library directory in `INSTALL_RPATH`. Floor: any. | Install strips the build RPATH ("Set non-toolchain portion of runtime path … to """), so the installed binary dies with "cannot open shared object file". With `$ORIGIN` it survives a move (measured on 4.4.2, Linux. The Apple spelling is documented, not measured). Never paper over it with `LD_LIBRARY_PATH`. Without the other-prefix entry a same-SONAME copy on the loader's default path loads instead, with exit 0 everywhere: cJSON 1.7.15 configured, the host 1.7.18 loaded (3.31.12 and 4.4.2, 2026-09-26). | `readelf -d "$W/moved/bin/app"`, then run the binary under `env -i PATH=/usr/bin:/bin`. No RUNPATH entry, or a loader error, is the finding. | SHOULD |
| CMK-INST-12 | When shipping a `.pc` file, generate it with `configure_file(… @ONLY)` from the same target data, install it to `${CMAKE_INSTALL_LIBDIR}/pkgconfig` (`DATADIR` for arch-independent packages), and write `prefix=${pcfiledir}/<rel>`, with `<rel>` computed by `file(RELATIVE_PATH)` as below, never a fixed `../..`. Floor: pkg-config's `pcfiledir`. | A `${pcfiledir}`-relative file resolves after the prefix moves. A fixed `../..` resolves one level short under `lib/x86_64-linux-gnu`. Upstream `.pc.in` files bake an absolute prefix almost everywhere, so an existing one is not a MUST finding. | `PKG_CONFIG_PATH="$W/moved/$LIBDIR/pkgconfig" pkg-config --variable=prefix "$PKG"`, resolved with `realpath` because pkg-config keeps the `..` segments, must print the moved prefix. Repeat with `-DCMAKE_INSTALL_LIBDIR=lib/x86_64-linux-gnu`. For new files, `grep -rnF --include='*.pc.in' -e 'prefix=@CMAKE_INSTALL_PREFIX@' .` Empty output is the pass. | SHOULD |

```cmake
file(
    RELATIVE_PATH
    PC_PREFIX_RELPATH
    "${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/pkgconfig"
    "${CMAKE_INSTALL_PREFIX}"
)
string(REGEX REPLACE "/$" "" PC_PREFIX_RELPATH "${PC_PREFIX_RELPATH}")
# The .pc.in then says: prefix=${pcfiledir}/@PC_PREFIX_RELPATH@
```

## The CPS Export Guard

Every row here needs CMake ≥ 4.3. On 4.3.4 and 4.4.2 `find_package` selects a valid `.cps` over the Config file in the same prefix, with or without `CONFIG`, so the CPS file is what every CMake ≥ 4.3 consumer loads. **Pinned**: CPS ships in addition to the Config package, never instead of it, and adding it is SHOULD. The import side is CMK-DEP-11 and CMK-DEP-12 in `dependencies.md`. The gate is the round trip run on a 3.31 line and on a ≥ 4.3 line, plus this pipeline for CMK-INST-16, whose empty output is the pass:

```sh
grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'VERSION_SCHEMA' . | grep -v -e 'VERSION_SCHEMA simple'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-INST-13 | Never ship `install(PACKAGE_INFO)` without the paired `install(EXPORT)` and Config package, and never enable it through a retired experimental gate. Floor: 4.3. | CPS import is ungated only from 4.3. On 4.0.7 to 4.2.7 a `.cps` loads only behind `CMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES`, and 3.31.12 has no import path, so a CPS-only package is unreadable below 4.3 without an experimental opt-in. `install(PACKAGE_INFO)` is a hard error on 3.31.12 to 4.2.7 unless `CMAKE_EXPERIMENTAL_EXPORT_PACKAGE_INFO` is set (measured 2026-09-26). Both gates were retired at 4.3.0. `CMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO` is for distributors, not projects. | `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'CMAKE_EXPERIMENTAL_EXPORT_PACKAGE_INFO' -e 'CMAKE_EXPERIMENTAL_FIND_CPS_PACKAGES' -e 'CMAKE_INSTALL_EXPORTS_AS_PACKAGE_INFO' .` Empty output is the pass. Then read: every project that `grep -rln -e 'install(PACKAGE_INFO' .` lists must also call `install(EXPORT`. | MUST |
| CMK-INST-14 | Beside an existing Config package, also emit CPS with `install(PACKAGE_INFO <pkg> EXPORT <set> VERSION … COMPAT_VERSION …)`, guarded by `if(CMAKE_VERSION VERSION_GREATER_EQUAL 4.3)`. Add it only after CMK-INST-15 to -17 hold and while every PUBLIC or INTERFACE dependency is itself found through a Config or CPS file. Floor: 4.3. **Pinned**, see above. | A `.cps` `requires` entry is resolved in config mode only: a `Threads::Threads` dependency made every 4.3.4 and 4.4.2 consumer fail with "Could not find a package configuration file provided by "Threads"" while 3.31.12 passed. Without `COMPAT_VERSION`, a request for 1.0 against 1.2.0 rejects the `.cps` and falls through silently to the Config file. | On the ≥ 4.3 run the script's last line ends in `/cps/$PKG`, and on 3.31 in `/cmake/$PKG`. Both runs exit 0. A `/cmake/` path on ≥ 4.3 is the finding. | SHOULD |
| CMK-INST-15 | Before adding CPS, make the export `NAMESPACE` equal the CPS package name (the first argument of `install(PACKAGE_INFO)`), exactly, including case. To publish a target under another name, set its `EXPORT_NAME`, never a different namespace. Floor: 4.3. | CPS never reads `NAMESPACE`. `install(PACKAGE_INFO foo)` over an `acme::` or a `Foo::` export succeeds with no diagnostic, then a consumer of `acme::foo` configures on 3.31.12 and fails at Generate on 4.3.4 and 4.4.2, where the `.cps` defines `foo::foo`. `EXPORT_NAME` is honoured by both generators. | The round trip on ≥ 4.3 with `TARGETS` set to the existing namespaced names. Before that, read `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'install(PACKAGE_INFO' -e 'NAMESPACE' .` A `PACKAGE_INFO` name that differs in any character from the `NAMESPACE` of the export it names is the finding. | MUST |
| CMK-INST-16 | On `install(PACKAGE_INFO)`, omit `VERSION_SCHEMA` or set it to `simple`. Never use `custom`, `rpm`, `dpkg` or `pep440`. Floor: 4.3. | CMake writes any schema without validation, but its own `find_package` orders only `simple`. Under the other four, an exact request (`1.2.0` against `1.2.0`) is accepted and any other versioned request is rejected, then falls through silently to the Config file. | The pipeline above. Empty output is the pass. A hit is the finding, except a `VERSION_SCHEMA` line whose value, on the next line, is `simple`. | MUST |
| CMK-INST-17 | A target exported through CPS carries only configuration-dependent generator expressions in its `INTERFACE_*` properties. Gate on the configure exit code as its own step. Floor: 4.3. | `$<COMPILE_LANGUAGE:C>` on `INTERFACE_COMPILE_DEFINITIONS` is a fatal configure error once `install(PACKAGE_INFO)` is present, yet an ignored configure still lets `--build` and `--install` exit 0 and write a `.cps` with the property dropped. | The script's first `cmake -S` exits 0 on a ≥ 4.3 line. A non-zero exit is the finding. Never grep the log: CMake wraps "contains a" / "generator expression" across two lines. | MUST |

```cmake
# wrong: CPS never reads NAMESPACE, so a 4.3+ consumer of acme::foo fails
install(EXPORT foo NAMESPACE acme:: DESTINATION ${FOO_CMAKEDIR})

# right: the namespace is the CPS name, the call is gated, COMPAT_VERSION is set
install(EXPORT foo NAMESPACE foo:: DESTINATION ${FOO_CMAKEDIR})
if(CMAKE_VERSION VERSION_GREATER_EQUAL 4.3)
    install(PACKAGE_INFO foo EXPORT foo VERSION 1.2.0 COMPAT_VERSION 1.0.0)
endif()
```

## Reading Checks

No command decides these. Each grep lists what to read, and the Verification cell names the finding. CMK-INST-23 rests on `install.rst` at 4.4.2 alone: no Windows host measured it.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-INST-18 | Keep the round trip in CI as its own step, which configures and builds a separate consumer against the just-installed prefix, apart from the library's own tests. Floor: any. **Pinned** at SHOULD, a default an adopter may raise to MUST once. | curl, yaml-cpp and zlib do this. libuv and cmake-init install and never consume the result, so a broken package ships green. | `grep -rn -e 'cmake --install' .github/workflows` lists the install steps, and `grep -rn -e 'CMAKE_PREFIX_PATH' .github/workflows` must show a consumer configure after each. Hits from the first with empty output from the second is the finding. | SHOULD |
| CMK-INST-19 | Generate the package in-tree with `CMakePackageConfigHelpers`. Never do it through a packaging helper that downloads code at configure time. Floor: any. | A fetched helper costs a network fetch on every configure and hands the packaging contract to a third party. CMP0169 does not deprecate the full-details `FetchContent_Populate(… URL …)` form such helpers use. | `grep -rn --include='*.cmake' --exclude='Find*.cmake' -e 'FetchContent_Populate(' -e 'file(DOWNLOAD' .` Empty output is the pass. A hit inside an install or packaging helper is the finding. A hit in a dependency fetcher such as `CPM.cmake` is CMK-DEP territory, not this row. The exclude drops a Find module's own fetch (ccache/ccache at `b471bbde`, `cmake/FindZstd.cmake`) and keeps cpp-best-practices/cmake_template's `PackageProject.cmake` at `b86318a` (measured 2026-09-26). Scoping to files that call `CMakePackageConfigHelpers` would lose that hit, because the helper packages through a fetched module instead. | SHOULD |
| CMK-INST-20 | For a new library whose floor is ≥ 3.23, consider installing public headers with `target_sources(… FILE_SET HEADERS)` and `install(TARGETS … FILE_SET HEADERS)`. Never convert an existing `install(DIRECTORY)` unprompted. Floor: 3.23. | The mechanism is documented but not practice among flagship libraries (as of 2026-09-26), so an unprompted conversion is churn a reviewer must re-verify. | Reading heuristic on the diff: a removed `install(DIRECTORY` with no request for it is the finding. | CONSIDER |
| CMK-INST-23 | For a target that can be built `SHARED`, either give `install(TARGETS)` no `RUNTIME` and no `ARCHIVE` destination, or name `RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}` whenever you name `ARCHIVE`. Never rely on `LIBRARY DESTINATION` to place a Windows DLL. Floor: any. `RUNTIME_DEPENDENCY_SET` since 3.21. | On DLL platforms the DLL is a `RUNTIME` artefact and its import library is `ARCHIVE`. If either destination is given, "the other component is not installed", so a Linux-shaped `LIBRARY` plus `ARCHIVE` call ships no DLL. A `LIBRARY`-only call sends both to their defaults. `$<TARGET_RUNTIME_DLLS>` is a build-tree copy for tests, not an install mechanism. | `grep -rn -A6 --include='CMakeLists.txt' --include='*.cmake' -e 'install(TARGETS' .` then read each hit. Empty output means the row does not apply. A call for a possibly-`SHARED` target that names `ARCHIVE DESTINATION` but no `RUNTIME DESTINATION` is the finding. | SHOULD |

## What Agents Get Wrong Here

1. **Taking a green build and install as proof the package can be consumed.** A missing `find_dependency` and a CPS property dropped by an ignored failed configure both stay green upstream and break downstream. CMK-INST-01, with the configure gated as its own step.
2. **Fixing relocation in the wrong place.** The agent edits `$<INSTALL_INTERFACE:…>` because `cmake-packages(7)` shows it, and leaves an absolute `install(EXPORT … DESTINATION)`. Step (b) and CMK-INST-02.
3. **Writing `LIB_SUFFIX`, a literal `lib`, or `$ORIGIN/../lib`.** The "lib64 fix" of older answers, and exactly what Fedora 45 stopped injecting. CMK-INST-09.
4. **Copying a raw `find_package(X REQUIRED)` into a Config template.** Real projects get this right and wrong in the same file, so copying is a coin flip. CMK-INST-03.
5. **Adding `LD_LIBRARY_PATH` to a run script instead of `INSTALL_RPATH`.** `readelf -d` on the installed binary after the move, per CMK-INST-11.
6. **Getting CPS wrong in either direction.** Ignoring it, or shipping it CPS-only, leaving a retired `CMAKE_EXPERIMENTAL_*` gate, copying `VERSION_SCHEMA rpm` from distro packaging, adding it over a `Vendor::` or case-different namespace, or adding it to a library with a Find-module dependency. When a ≥ 4.3 consumer reports "target was not found", read the `.cps` file's `components` keys. CMK-INST-13 to -16.
7. **Trusting `-Werror=install-absolute-destination` on a 3.x or 4.3 leg, or for an `install(CODE)` body on 4.4.** It is accepted silently and does nothing on 3.x and 4.3, and on 4.4 it never reads the text inside `install(CODE)`. CMK-INST-10's grep runs on every line.
8. **Writing a `LANGUAGES NONE` orchestrator that calls `find_package(CONFIG)` for a package under `lib64`.** It never searches there, even through `<Pkg>_ROOT`. Run `--debug-find-pkg=<name>` and look for a `lib64` candidate, or ship arch-independent packages under `share/` (CMK-INST-08).
9. **Vendoring a "best practices" packaging helper wholesale.** CMK-INST-19.
10. **Converting `install(DIRECTORY)` to `FILE_SET HEADERS` unprompted, or emitting `export(PACKAGE)`.** The registry write is off by default only when the project's floor is 3.15 or later. CMK-INST-20 and CMK-INST-24.
11. **Adding `-G "Ninja Multi-Config"` and declaring victory when `--build --config Release` exits 0.** A shared file name makes the two installs overwrite each other silently, and a `CMAKE_DEBUG_POSTFIX` set after `add_library` does not help. CMK-INST-21, step (e).
12. **Expecting CMake to refuse a configuration missing from the install, or forcing it with an empty `CMAKE_MAP_IMPORTED_CONFIG_<CONFIG>`.** The default borrows another configuration, and the empty map rejects installed ones too. CMK-INST-22, step (f).
13. **Reaching for `-DCMAKE_POLICY_DEFAULT_CMP0090` to stop someone else's registry write.** With a floor of 3.15 or later there is nothing to stop and CMake reports the variable unused. Pass `-DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON`.
14. **Adding `NAMESPACE` to an existing export and proving it on the new name only.** Every name consumers already link breaks (CMK-INST-06).
15. **Keeping or copying a hand-written `ConfigVersion.cmake.in` because the round trip passes.** Most never read `PACKAGE_FIND_VERSION_RANGE` and accept a version a range excludes. CMK-INST-04's listing.

Re-check: (D1) CMake 4.5, whether `-Werror=dev` still maps onto the author gate the scripts default to. (D7) the CPS experimental-gate UUID rotation, should Kitware reopen an export gate. Kitware's silent CPS export gaps (a mismatched namespace accepted, non-`simple` schemas written, absolute `hints`, Find-module `requires`), none reported upstream as of 2026-09-26.
