---
title: Conan 2 at the CMake Seam
summary: The CMK-CONAN family. Conan 2 recipes and consumer conanfiles, profiles, conan.lock, how Conan enters a CMake configure, and publishing a recipe
---

# Conan 2 at the CMake Seam

Owns `CMK-CONAN`: what a `conanfile.py` or `conanfile.txt` may say, which
generator feeds CMake, how Conan enters the configure, what `conan.lock` must
do in CI, which settings the profile owns once `conan_toolchain.cmake` is
loaded, and the shape of a recipe you publish. A Conan profile has no fixed
file name, so no glob loads this file for it: the index routes profile edits
here. Choosing a manager of record and the per-mechanism lock table are
`CMK-PKG` in the `cpp-packaging` index. The ban on vcpkg's and Conan's
toolchains in one configure is `CMK-TC-02`, and provider injection and its
limits are `CMK-TC-04` and `CMK-TC-05`, all in
`cmake-build/toolchains-and-providers.md`. The language-standard and MSVC
runtime guards are `CMK-TGT-05` and `CMK-TGT-16` in `cmake-build/targets.md`.
Never committing `CMakeUserPresets.json` is `CMK-CI-02` in
`cmake-build/presets-and-ci.md`. URL hashes for CMake fetches are `CMK-DEP-03`
in `cmake-build/dependencies.md`. CPS import and export are `CMK-DEP` and
`CMK-INST`. vcpkg is `CMK-VCPKG`. A `conanfile.py`
also loads the Python quality rule, which owns its style.

Written against Conan 2.32.0 (released 2026-08-31) and cmake-conan `develop2`
as of 2026-06-05, verified 2026-09-26. CMake behaviour was measured on
3.31.12, 4.3.4 and 4.4.2. Every rule assumes the CMake floor 3.25.

Contents: [Greps Over the Conanfile](#greps-over-the-conanfile) ·
[Generator Choice Against find_package](#generator-choice-against-find_package) ·
[How Conan Enters the Configure](#how-conan-enters-the-configure) ·
[The conan install Line in CI](#the-conan-install-line-in-ci) ·
[Profile Against Project](#profile-against-project) ·
[Publishing a Recipe](#publishing-a-recipe) ·
[Before You Describe a Conan Feature](#before-you-describe-a-conan-feature) ·
[What Agents Get Wrong Here](#what-agents-get-wrong-here)

## Greps Over the Conanfile

Static greps from the repository root. Empty output is the pass unless the
row says otherwise. `CMK-CONAN-02` pipes one list into a second grep:

```sh
# CMK-CONAN-02: every listed file sets names but no set_property. Non-empty output is the finding.
grep -rl --include='conanfile.py' -e 'cpp_info.names' -e 'cpp_info.filenames' . | xargs -r grep -L -e cmake_target_name -e cmake_file_name
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CONAN-01 | Write Conan 2 imports only: `from conan import ConanFile` and `conan.tools.*`. Never write `from conans import`, `generators = "cmake"`, `conan_basic_setup()` or `include(conanbuildinfo.cmake)`, in a recipe or its `test_package`. | At Conan 2.32.0 `conans/__init__.py` is empty, so a Conan-1 recipe dies at import under every Conan 2 client. Conan Center still carries 40 such recipe folders (counted 2026-09-26), so copying one is easy. A `>=1.5x` floor on a `from conan import` recipe is not residue: Conan 1.50 and later ship a forward shim. Floor: Conan 2.0. | `grep -rn --include='conanfile.py' --include='CMakeLists.txt' -e 'from conans' -e conan_basic_setup -e conanbuildinfo -e 'generators = "cmake"' .` Empty output is the pass. | MUST |
| CMK-CONAN-02 | Name exported CMake files and targets with `self.cpp_info.set_property("cmake_file_name", ...)` and `("cmake_target_name", ...)`, plus `cmake_module_file_name` and `cmake_module_target_name` when `cmake_find_mode` is `module` or `both`, and `pkg_config_name` for pkg-config. Never add `cpp_info.names` or `cpp_info.filenames` to a recipe, and delete them on any edit where `set_property` already exists. | Conan 2 keeps `names` as a mock that discards the value and only warns, so a names-only recipe silently hands consumers Conan's default target names. Deleting the dead copy breaks no one: Conan Center's Conan-1 remote froze on 2024-11-04. Floor: Conan 2.0. | The block above. Non-empty output is the finding. A file in the first list but not the second is dead code, deleted on the next edit. | MUST |
| CMK-CONAN-03 | Declare build tools as `tool_requires`, either the attribute or `self.tool_requires()` inside `build_requirements()`. Never write `build_requires`. | Deprecated in Conan 2.28.0, and `[build_requires]` in a `conanfile.txt` is already a parse error at 2.32.0. `tool_requires` exists since 2.0, so the replacement always works. Floor: Conan 2.0. | `grep -rn --include='conanfile.py' --include='conanfile.txt' -e build_requires .` Empty output is the pass (`def build_requirements` does not match). | MUST (new or edited recipes) |

```python
# wrong: Conan 1 import and generator, the recipe dies at import under Conan 2
from conans import ConanFile


class AppConan(ConanFile):
    generators = "cmake"
```

```python
# right: Conan 2 imports and the two CMake generators
from conan import ConanFile
from conan.tools.cmake import cmake_layout


class AppConan(ConanFile):
    settings = "os", "arch", "compiler", "build_type"
    generators = "CMakeToolchain", "CMakeDeps"

    def layout(self):
        cmake_layout(self)
```

## Generator Choice Against find_package

Grep the conanfiles for the generator, then read the `find_package` calls it
must serve. `CMK-CONAN-04` is **pinned**: `CMakeDeps` stays the default until a
Conan changelog line calls `CMakeConfigDeps` stable, and then the default flips
as a dated edit. An adopter overrides it once, repository-wide.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CONAN-04 | **Pinned.** In the explicit flow generate with `CMakeToolchain` plus `CMakeDeps`. Use `CMakeConfigDeps` only with the cmake-conan provider, or with a comment naming it experimental at Conan 2.32.0. A recipe's own `generate()` and its `test_package/conanfile.py` always use `CMakeDeps`. | `CMakeConfigDeps` moved from incubating to experimental in 2.25.0 and its reference page still carries the experimental banner at 2.32.0. The CCI template and every non-provider consumer checked use `CMakeDeps`. A recipe's `generate()` runs in `conan create`, never inside a provider's configure. Floor: Conan 2.25.0 for `CMakeConfigDeps`. | `grep -rn --include='conanfile.py' --include='conanfile.txt' -e CMakeConfigDeps .` Empty output is the pass. Read each hit: the finding is a hit with neither the provider (`grep -rn -e conan_provider.cmake .`) nor an "experimental" comment, and any hit in a published recipe or its `test_package`. | SHOULD |
| CMK-CONAN-05 | Never pair `CMakeConfigDeps` with `find_package(<Pkg> MODULE)` for a Conan-provided package, or with code that expects a Conan-generated `Find<Pkg>.cmake`. | `CMakeConfigDeps` writes no Find modules, and Conan's docs say support is not planned. Measured on Conan 2.32.0 with `cmake_find_mode` `both`: `CMakeDeps` writes `FindGamma.cmake`, `CMakeConfigDeps` only `GammaConfig*.cmake`. Floor: Conan 2.25.0. | Runs only when the `CMK-CONAN-04` grep hits. `grep -rn --include='CMakeLists.txt' --include='*.cmake' -e 'find_package(.* MODULE' .` Empty output is the pass. A hit naming a Conan-provided package is the finding. It sees single-line calls only, so read multi-line `find_package(` calls by hand. | MUST |
| CMK-CONAN-06 | Under `CMakeDeps`, when CMake must `find_package` a `tool_requires` dependency (a code generator's targets, say), list it in `build_context_activated`. Add `build_context_suffix` when the same package is also a host `requires`. | By default `CMakeDeps` writes no config files for a build-context requirement, so the `find_package` fails or finds a host copy. Measured on Conan 2.32.0: 0 tool files by default, 5 when activated. `CMakeConfigDeps` does not need it. Floor: Conan 2.0. | Reading heuristic. `grep -rn --include='conanfile.py' -e tool_requires -e build_context_activated .` lists both sides. A `tool_requires` name that also appears in a `find_package(` call but not in `build_context_activated` is the finding. Empty output means not applicable. | MUST |

## How Conan Enters the Configure

Read the presets, the CI configure lines and every `CMakeLists.txt` for the
provider. `CMK-CONAN-07` is **pinned**: the explicit flow is the default an
adopter may override once, and the provider is legal only inside the
measured limits of `CMK-TC-05`.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CONAN-07 | **Pinned.** Run `conan install` first, then `cmake --preset conan-release` (single-config) or `conan-default` (multi-config). Adopt the cmake-conan provider only for IDE or one-command use, and then inject it from a preset or the command line through `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` (`CMK-TC-04`), generate `CMakeConfigDeps`, set `CMAKE_BUILD_TYPE` for single-config generators, supply profiles for anything but Windows+MSVC, Linux+gcc and Apple+clang, and put the first `find_package` of a Conan package in the top-level `CMakeLists.txt` before any `add_subdirectory` (`CMK-TC-05`). Never offer `cmake_language(DEFER)` as the ordering fix. Never run `conan install` through `execute_process()` in project code and then `include()` the generated `conan_toolchain.cmake`: that loads the toolchain after `project()`, which `CMK-TC-03` forbids. | Conan calls the explicit flow "the recommended flow for most cases". The provider needs CMake 3.24, only warns when the generator is missing, and exposes Conan paths to `find_program` and `find_library` only under `CMakeConfigDeps`, only after the first intercepted `find_package`, and only in that directory scope. `DEFER` runs at the end of the directory, too late. An `include()` after `project()` leaves the detected compiler's identity in place while the toolchain's compiler path takes over: measured 2026-09-26 on Conan 2.32.0 with CMake 3.31.12 and 4.4.2, a profile naming a clang wrapper compiled with it while `CMAKE_C_COMPILER_ID` stayed `GNU`, configure exit 0 under the gate, and loading the same file with `--toolchain` reported `Clang`. jasp-stats/jasp-desktop at `ac15123` does this in `Tools/CMake/Conan.cmake`. Floor: CMake 3.24 for the provider, which checks for Conan 2.0.5. | `grep -rn -e conan_provider.cmake .` Then `grep -rni --include='CMakeLists.txt' --include='*.cmake' --exclude='conan_provider.cmake' -e 'include(.*conan_toolchain' .` Empty output from both means the explicit flow, a pass. A hit from the first triggers the reading of the five limits above, and a hit inside a `CMakeLists.txt` is a `CMK-TC-04` finding. A hit from the second is the `CMK-TC-03` finding. | SHOULD (the `include()` clause is MUST, owned by `CMK-TC-03`) |
| CMK-CONAN-08 | Cites `CMK-CI-02` (never commit `CMakeUserPresets.json`, list it in `.gitignore`). The Conan consequence: `CMakeToolchain` rewrites only a user-presets file whose `vendor` carries `conan`, so a hand-written one makes Conan skip silently and the `conan-*` presets never appear. | Conan 2.32.0's presets writer returns early when `"conan"` is missing from the file's `vendor` object. Floor: CMake 3.23 for the schema-4 user presets Conan writes. | `git ls-files -- '*CMakeUserPresets.json'` Empty output is the pass (`CMK-CI-02`'s command). | MUST, owned by `CMK-CI-02` |

## The conan install Line in CI

Two conanfile greps decide whether the lock applies, then the pipeline's
`conan install` lines are read against it. The commands assume the pipeline
lives in `.github`. Point them at your CI directory otherwise.

```sh
# CMK-CONAN-09, step 1: any output means ranges are in use and the lock is owed.
grep -rn --include='conanfile.py' --include='conanfile.txt' -e '/\[' .
# Step 2: when step 1 printed anything, empty output here is the finding.
git ls-files conan.lock
# Step 3: every install line (first command) must also appear in the lock-passing list (second).
grep -rn -e 'conan install' .github
grep -rn -e '--lockfile[= ]' -e ' -l ' .github
# Step 4: empty output is the pass. An empty --lockfile= switches the lock off.
grep -rn -e '--lockfile=""' -e "--lockfile=''" -e '--lockfile= ' -e '--lockfile=$' -e '--lockfile-partial' .github
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CONAN-09 | An application whose `requires` or `tool_requires` use a version range commits `conan.lock`. CI passes `--lockfile=conan.lock` explicitly and never `--lockfile-partial`. Regenerate the lock with `--lockfile-out` (plus `--lockfile-clean`), never by hand. A published recipe is exempt because it floats by design (on Conan Center, only within `CMK-CONAN-20`). This is Conan's entry in `CMK-PKG`'s per-mechanism lock of record. | Without a lock a range resolves to whatever is newest today. Measured on Conan 2.32.0: a `conan.lock` beside the conanfile is picked up implicitly, also when `conan install` runs from another directory with the conanfile's path (`Using lockfile:`, 2026-09-26), `--lockfile=` (empty) disables it and resolved the newer version, a requirement missing from the lock fails with `not in lockfile`, and `--lockfile-partial` lets that install exit 0. Floor: Conan 2.0. | The block above, steps 1 to 4. An install line missing from step 3's second list is the finding, and so is any output from step 4. Read multi-line install commands by hand. A committed lock that no script names is still live, because every install of the conanfile beside it reads it. | MUST |
| CMK-CONAN-12 | For a cross build pass both profiles explicitly (`-pr:h` and `-pr:b`), and put code generators in the build context (`tool_requires`), never in a host `requires`. | A `tool_requires` is built for the build machine, a `requires` for the host, so a generator in `requires` is built for a target that cannot run it. Conan 2.27.0 added negated-OR patterns in a profile's `[tool_requires]` section for build-context cycles. Floor: Conan 2.0. | Reading heuristic. `grep -rn -e 'conan install' .github` lists the install lines, and each leg whose host profile names another arch or OS must show `-pr:b`. Empty output means no install line, not applicable. | SHOULD |

```sh
# wrong: the lock is switched off, then drift is accepted
conan install . --build=missing --lockfile=
conan install . --build=missing --lockfile-partial
# right: explicit and strict, so a requirement missing from the lock fails the job
conan install . --build=missing --lockfile=conan.lock
```

## Profile Against Project

The configure gate does not catch this. The watch line Conan prints is a
`STATUS` message, and the configure exits 0 under `-Werror=dev` (CMake ≤ 4.3)
and `-Werror=author` (CMake ≥ 4.4), measured on 3.31.12, 4.3.4 and 4.4.2. So
the check greps configure output, on legs that load `conan_toolchain.cmake`
only (a vcpkg leg's runtime `set()` is `CMK-VCPKG-06`'s business). Spell the
gate for the binary the leg runs.

```sh
# CMK-CONAN-10: pass = the configure exits 0 and this prints nothing. Shown for CMake <= 4.3; use -Werror=author on CMake >= 4.4.
cmake --preset conan-release --fresh -Werror=dev 2>&1 | grep -e 'has been modified to'
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CONAN-10 | When a build loads `conan_toolchain.cmake`, the profile owns `CMAKE_CXX_STANDARD`, `CMAKE_CXX_EXTENSIONS` and `CMAKE_MSVC_RUNTIME_LIBRARY`. Never write an unguarded `set()` of them after `project()`, and never pass `-DCMAKE_CXX_STANDARD` beside the Conan toolchain. State a library's minimum as `target_compile_features(<t> PUBLIC cxx_std_NN)`. A project default goes inside `if(NOT DEFINED <var>)`, the guard `CMK-TGT-05` (standard) and `CMK-TGT-16` (runtime) own. | Measured with the toolchain Conan 2.32.0 generated (cppstd 17): a later `set(CMAKE_CXX_STANDARD 20)` wins with one `STATUS` line and exit 0, `-DCMAKE_CXX_STANDARD=20` silently loses, and the guarded default keeps 17 with no line. The runtime block is a plain `set()` with no watch, so a runtime override is fully silent. On a real tree, 2026-09-26: BehaviorTree/BehaviorTree.CPP at `ca4edbf` sets `CMAKE_CXX_STANDARD 17` right after `project()`, and under a `compiler.cppstd=20` profile it compiled with `-std=c++17`, configure exit 0 under `-Werror=author` on 4.4.2. Floor: Conan 2.7.0 for the watch line. The precedence holds on every CMake tested. | The block above: empty output is the pass only when the configure itself succeeded. When grep prints nothing, rerun the configure without the pipe and require exit 0, because a missing `conan-release` preset also prints nothing. Static, on Conan legs only: `grep -rnE --include='CMakeLists.txt' --include='*.cmake' -e 'set[[:space:]]*\(CMAKE_CXX_STANDARD' -e 'set[[:space:]]*\(CMAKE_CXX_EXTENSIONS' -e 'set[[:space:]]*\(CMAKE_MSVC_RUNTIME_LIBRARY' .` Read each hit: one after the first `project()` and outside `if(NOT DEFINED ...)` is the finding. | MUST |
| CMK-CONAN-11 | A recipe whose library needs C++NN calls `check_min_cppstd(self, NN)` in `validate()`. | Without it a profile below NN still builds, because `target_compile_features` silently raises the standard, and the binary ships under a package id that claims the lower one. Catch2 and 31 of 40 sampled Conan Center recipes do this (as of 2026-09-26). Floor: Conan 2.0. | `grep -rn --include='CMakeLists.txt' -e cxx_std_ .` lists the raises. For a recipe whose CMake raises above the profile default, `grep -rn --include='conanfile.py' -e check_min_cppstd .` printing nothing for it is the finding. | SHOULD |

```cmake
# wrong: silently overrides the profile's cppstd for everything below
project(app CXX)
set(CMAKE_CXX_STANDARD 20)

# right: the profile wins when present, the default applies otherwise
project(app CXX)
if(NOT DEFINED CMAKE_CXX_STANDARD)
    set(CMAKE_CXX_STANDARD 20)
endif()
```

## Publishing a Recipe

Recipe-author rows. No maintained linter replaces the archived `conan-io/hooks`
(archived 2026-03-24), so every check is a grep followed by a read. The piped
checks:

```sh
# CMK-CONAN-13: listed files build with CMake but call no cmake_layout. A header-only one calling basic_layout is cleared.
grep -rl --include='conanfile.py' -e 'CMake(self)' -e CMakeToolchain . | xargs -r grep -L -e cmake_layout
# CMK-CONAN-14: listed files use the mixin and also define a method it yields to. Read each.
grep -rl --include='conanfile.py' -e auto_shared_fpic . | xargs -r grep -l -e 'def config_options' -e 'def configure'
# CMK-CONAN-15: non-empty output is the finding (mixin disabled by an own package_id).
grep -rl --include='conanfile.py' -e auto_header_only . | xargs -r grep -l -e 'def package_id'
# CMK-CONAN-15: a listed file with a settings attribute is the finding.
grep -rl --include='conanfile.py' --exclude-dir=test_package -e '"header-library"' . | xargs -r grep -L -e auto_header_only -e 'info.clear()'
# CMK-CONAN-18: listed files install upstream CMake and remove nothing. Read the package folder.
grep -rl --include='conanfile.py' -e 'cmake.install()' . | xargs -r grep -L -e rmdir
# CMK-CONAN-21: listed files use a mixin under a floor below 2.0.9.
grep -rl --include='conanfile.py' -e implements . | xargs -r grep -l -e 'required_conan_version = ">=1'
# CMK-CONAN-22: both commands, empty output is the pass.
find . -path '*/test_package/CMakeLists.txt' -print0 | xargs -0 -r grep -L -e CONFIG -e MODULE
find . -path '*/test_package/conanfile.py' -print0 | xargs -0 -r grep -L -e can_run
# CMK-CONAN-23, hand-written half: lists literal-URL downloads. A hit without sha256= is the finding.
grep -rn --include='conanfile.py' -e 'download(self, *"' -e "download(self, *'" -e 'download(self, *f"' -e 'get(self, *"' -e "get(self, *'" -e 'get(self, *f"' .
```

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CONAN-16 | Never call `self.info.header_only()`. Clear the package id with `self.info.clear()` (`CMK-CONAN-15`). | It does not exist in Conan 2. Measured on 2.32.0: `conan graph info` fails with `AttributeError: 'ConanInfo' object has no attribute 'header_only'`, exit 1. Floor: Conan 2.0. | `grep -rn --include='conanfile.py' -e '^[^#]*info\.header_only()' .` Empty output is the pass (commented-out calls are skipped). | MUST |
| CMK-CONAN-23 | Every `conandata.yml` source entry carries a `sha256`, and `source()` fetches through `get(self, **self.conan_data["sources"][self.version], ...)`, never a hand-written unchecked download. Two exceptions: a host serving non-byte-stable archives (googlesource `+archive`), whose entry names a commit in its URL and says why in a comment, and a git source with a full `commit` hash fetched by `Git(self).fetch_commit(...)`. | `get()` and `download()` check a hash only when one is passed (`sha256=None` by default at 2.32.0), so a hashless entry accepts whatever the server returns. The recipe-side twin of `CMK-DEP-03`. Floor: Conan 2.0. | `grep -rL --include='conandata.yml' -e sha256 .` Empty output is the pass, and each listed file is cleared only by an exception. Then the literal-URL grep in the block above, read for `sha256=`. A file with one hash can still miss an entry, so read each `sources:` block you edit. | MUST |
| CMK-CONAN-13 | A recipe that runs a CMake build calls `cmake_layout(self, src_folder="src")` in `layout()`. A recipe that never builds calls `basic_layout(self, src_folder="src")`. | The CCI template and 21 of 22 sampled CMake-building recipes do. A recipe without a layout still builds, which is why this is not a MUST. Floor: Conan 2.0. | The block above. Non-empty output lists findings. | SHOULD |
| CMK-CONAN-14 | A new or heavily edited recipe declares `implements = ["auto_shared_fpic"]` instead of hand-written `shared`/`fPIC` logic, and then defines neither `config_options()` nor `configure()` unless that method repeats the `fPIC` removal. An existing hand-rolled removal need not migrate. | In Conan 2.32.0 the mixin runs only when the recipe lacks the matching method, so defining either one silently disables that half. Floor: Conan 2.0.9. | The block above. Read each listed file: a defined method that does not remove `fPIC` (on Windows, or when `shared`) is the finding. | SHOULD |
| CMK-CONAN-15 | A header-only recipe clears its package id: `implements = ["auto_header_only"]` with no `package_id()` method, or a `package_id()` calling `self.info.clear()`, plus `no_copy_source = True`. `package_type = "header-library"` alone does not clear it. | Measured on Conan 2.32.0: `package_type` alone keeps os, arch, compiler and build_type, so consumers hit one missing binary per configuration. An own `package_id()` silently disables the mixin. The mixin also covers an option `header_only=True`. Floor: Conan 2.0.9. | The two `CMK-CONAN-15` commands in the block above. Non-empty output from the first is the finding. From the second, a listed file with a `settings` attribute is the finding. | SHOULD |
| CMK-CONAN-17 | A tool recipe (`package_type = "application"`, consumed through `tool_requires`) removes `compiler` in `package_id()` with `del self.info.settings.compiler`, and keeps `build_type`. | Conan Center advises dropping the compiler and advises against dropping `build_type`, so consumers can still run debug executables. Floor: Conan 2.0. | Reading heuristic. `grep -rn --include='conanfile.py' -e 'del self.info.settings.build_type' .` hitting an application recipe is the finding. Empty output is the pass. | SHOULD |
| CMK-CONAN-18 | When `package()` calls `cmake.install()` and upstream installs a Config package or a `.pc` file, remove them (`rmdir` of `lib/cmake`, `lib/pkgconfig`, and any package-specific copy such as `lib/spdlog/cmake`), so the generator's files are the only package description consumers see. | Two package descriptions for one package let `find_package` pick upstream's config, which knows nothing of Conan's paths. The CCI template removes both. Floor: Conan 2.0. | The block above lists candidates, and empty output is the pass. One is a finding only if the package folder after `conan create` holds `lib/cmake` or `lib/pkgconfig`. | SHOULD |
| CMK-CONAN-20 | A recipe for Conan Center uses a version range only for a dependency on CCI's allow-list, at the listed range: OpenSSL, CMake, doxygen, libcurl, zlib, libpng, expat, libxml2, libuv, qt5, qt6, c-ares, zstd, ninja, meson, pkgconf and xz_utils. Internal remotes set their own policy. | Conan Center policy as of 2026-09-26: outside the listed cases ranges are not allowed. Independent of `CMK-CONAN-09`, which exempts published recipes from the lock. Floor: CCI policy as of 2026-09-26. | `grep -rn --include='conanfile.py' -e 'requires(.*\[' .` Empty output is the pass. A hit whose dependency is off the list is the finding. | SHOULD |
| CMK-CONAN-21 | Every recipe, a consumer's unpublished `conanfile.py` included, declares `required_conan_version`, at a floor that covers every feature it uses (`implements` needs `>=2.0.9`). A new recipe declares `>=2.0` or higher. Never raise an existing `>=1.5x` floor on a `from conan import` recipe only because it is below 2.0. | All six CCI templates declare one. A missing floor makes an old client fail with a confusing error rather than a clear one, and a consumer conanfile meets old clients first. Measured 2026-09-26: Conan 1.66.0 loaded BehaviorTree.CPP's (`ca4edbf`) floorless Conan-2 consumer file and failed later with `Unable to find 'flatbuffers/24.12.23' in remotes`, while the same file with `>=2.0` stopped at load with `does not satisfy the defined one (>=2.0)`. Conan 1.50 and later honour `from conan import`, so the low floor is correct. Floor: Conan 2.0. | `grep -rL --include='conanfile.py' --exclude-dir=test_package -e required_conan_version .` Empty output is the pass. The `CMK-CONAN-21` command in the block above lists floors below the mixin's, each a finding. | SHOULD |
| CMK-CONAN-22 | `test_package/CMakeLists.txt` consumes the package as a user would: `find_package(<Pkg> REQUIRED CONFIG)` (`MODULE` only when the package ships a Find module), one `add_executable`, one `target_link_libraries(... PRIVATE <Pkg>::<target>)`. `test_package/conanfile.py` generates `CMakeDeps` and `CMakeToolchain` (plus `VirtualRunEnv` when the binary needs a runtime path) and runs the binary only under `can_run(self)`. The floor line follows the CCI template (`3.15`) in a CCI submission and `CMK-VER-02` everywhere else. | The template shape, matched by 37 of 38 sampled test packages. `can_run()` is what lets a cross build package without executing a foreign binary. Floor: Conan 2.0. | The two `CMK-CONAN-22` commands in the block above. Empty output is the pass for both. | SHOULD |

```python
# wrong: declaring the mixin and a package_id() silently disables the mixin
class HeaderOnlyConan(ConanFile):
    package_type = "header-library"
    implements = ["auto_header_only"]

    def package_id(self):
        del self.info.settings.build_type
```

```python
# right: the mixin alone, no package_id() method
class HeaderOnlyConan(ConanFile):
    package_type = "header-library"
    implements = ["auto_header_only"]
    no_copy_source = True
```

## Before You Describe a Conan Feature

This row governs generated prose and profiles. Only a read catches it.

| ID | Rule | Rationale | Verification | Severity |
|---|---|---|---|---|
| CMK-CONAN-24 | Never describe `CPSDeps`, `conan.cps`, `[replace_requires]` or `[platform_requires]` as stable, GA or documented. Consume a system copy through a wrapper recipe plus `[replace_requires]`, not a bare `[platform_requires]`. | At Conan 2.32.0 `CPSDeps` exists in source only, with no docs page and no adopters sampled, and both profile sections carry the experimental banner. The CMake-side CPS rows are `CMK-DEP` (import) and `CMK-INST` (export). Floor: Conan 2.32.0. | `grep -rn --include='*.md' -i -e CPSDeps -e platform_requires -e replace_requires .` lists passages. Empty output means nothing to read. A passage calling one stable or GA is the finding. | SHOULD |

## What Agents Get Wrong Here

1. **Writing a Conan-1 recipe.** `from conans import`, `generators = "cmake"`,
   `self.copy`, `cpp_info.names`. Training text is full of them and Conan
   Center still carries dozens, so the shape looks current. `CMK-CONAN-01` and
   `CMK-CONAN-02`.
2. **Writing `build_requires` for a tool.** The older and more frequent term.
   `CMK-CONAN-03`.
3. **Setting `CMAKE_CXX_STANDARD` or `CMAKE_MSVC_RUNTIME_LIBRARY` after
   `project()` in a Conan build**, or passing `-DCMAKE_CXX_STANDARD` and
   expecting it to win. The configure exits 0 either way. `CMK-CONAN-10`.
4. **Reaching for `CMakeConfigDeps` as "the newer one"**, then writing
   `find_package(X MODULE)` or putting it in a recipe's `generate()`.
   `CMK-CONAN-04` and `CMK-CONAN-05`.
5. **Making the cmake-conan provider the default**, registering it from a
   `CMakeLists.txt`, or "fixing" an early `find_program` with
   `cmake_language(DEFER)`. `CMK-CONAN-07`.
6. **Adding `conan.lock` without `--lockfile=conan.lock` in CI**, or missing
   that a `conan.lock` beside the conanfile silently constrains every
   `conan install` of it. `CMK-CONAN-09`.
7. **Writing `self.info.header_only()`**, or trusting `package_type =
   "header-library"` to clear the package id. `CMK-CONAN-16` and
   `CMK-CONAN-15`.
8. **Adding `implements = [...]` and then also a `package_id()` or
   `configure()`**, which disables the mixin without a word. `CMK-CONAN-14`
   and `CMK-CONAN-15`.
9. **Bumping a working `>=1.53` `required_conan_version` to `>=2.0` as a
   fix**, or adding `cpp_info.names` "for Conan 1 compatibility".
   `CMK-CONAN-21` and `CMK-CONAN-02`.
10. **Running `conan install` from `execute_process()` during the configure**,
    the Conan 1 `conan_cmake_run` shape, then `include()`ing
    `conan_toolchain.cmake` after `project()`. The compiler identity stays
    the detected one and the configure exits 0. `CMK-CONAN-07`, `CMK-TC-03`.

Re-check:

- D2: `CMK-CONAN-04` flips its default to `CMakeConfigDeps` on the first Conan
  changelog line that calls it stable, as a dated edit (verified experimental
  at Conan 2.32.0, 2026-09-26).
- D4: the Conan release tag. Re-run the version floors and the `CMK-CONAN-24`
  status on each Conan minor after 2.32.0.
