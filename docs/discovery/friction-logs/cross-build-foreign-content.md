## Setup

- Persona: Aiko, embedded developer, builds on linux/amd64 for linux/arm64 targets. First-time user of find_ocx and of OCX; has never seen the find_ocx source.
- Date: 2026-10-10.
- Goal: get the content of another platform (arm64) from the same lock for a cross build, e.g. sysroot-style content for a toolchain file.
- Starting state: empty scratch directory, isolated `OCX_HOME`, `ocx` 0.6.5 on PATH, CMake 4.4.4 provisioned through `ocx package exec ocx.sh/kitware/cmake:4`. find_ocx v0.3.0 vendored from the GitHub release assets. Only public material consulted: GitHub README and release, https://ocx.sh/integrations/cmake/ pages.
- Scenario: starts from an `ocx_package` / `ocx_project` call, first tries `BINS` together with `PLATFORM`. Success = configure shows `OCX_<NAME>_PATHS` pointing at existing arm64 content directories and no `RUN` command variable exists.
- Note on transcript: commands were run with `OCX_HOME` set to an isolated directory and a recording wrapper (not shown); file edits done with heredocs/sed are shown as `$` lines with the resulting file content.

## Attempt

$ gh api repos/ocx-sh/find_ocx/readme --jq .content | base64 -d | head -150
```
<!-- doc_type: readme -->

# find_ocx

CMake support for [OCX](https://ocx.sh) — the OCI-backed package manager.
Two copy-and-own files bootstrap a pinned, sha256-verified `ocx` CLI and
provision development tools through it.
Tools arrive as command-list launchers, as content roots for `find_package`,
or as foreign-platform content.

find_ocx deliberately **never re-implements OCX internals in CMake**. All
resolution goes through the `ocx` binary; the durable contracts are
`ocx.lock` digests and the OCI manifests.

[... 60 lines elided]
```

$ gh release view v0.3.0 -R ocx-sh/find_ocx 2>&1 | head -40
```
title:	v0.3.0
tag:	v0.3.0
draft:	false
prerelease:	false
immutable:	false
author:	github-actions[bot]
created:	2026-07-03T10:25:12Z
published:	2026-07-03T10:25:25Z
url:	https://github.com/ocx-sh/find_ocx/releases/tag/v0.3.0
asset:	Findocx.cmake
asset:	ocx.cmake
asset:	SHA256SUMS
--

## [0.3.0] - 2026-07-03

### Added

- Reproducible-first index snapshots and PATH-first CLI resolution **BREAKING**
[0.3.0]: https://github.com/ocx-sh/find_ocx/compare/v0.2.0..v0.3.0
```

$ python3 -I pg.py https://ocx.sh/integrations/cmake/
```
integrations
find_ocx
find_ocx
find_ocx runs pinned, sha256-verified tools such as jq or shellcheck from your CMake build, using the OCX package manager.
examples/project/CMakeLists.txt# The ocx.toml next to this file is found by the upward search; the lock
# is verified; nothing is pulled yet (lazy). NAME picks the prefix of the
# result variables: NAME TOOLS -> OCX_TOOLS_RUN, OCX_TOOLS_RUN_JQ
# (defaults to PROJECT -> OCX_PROJECT_RUN).
ocx_project(NAME TOOLS BINS jq)
# Build-time tool use, lazily materialized on first execution. Generator
# expressions compose naturally - the command is a plain CMake list.
add_custom_target(validate ALL
  COMMAND ${OCX_TOOLS_RUN} jq -n -e --arg config "$<CONFIG>"
          [[$config | length >= 0]]
  VERBATIM
)
 OCX_TOOLS_RUN, OCX_TOOLS_RUN_JQ# (defaults to PROJECT -> OCX_PROJECT_RUN).ocx_project(NAME TOOLS BINS jq)# Build-time tool use, lazily materialized on first execution. Generator# expressions compose naturally - the command is a plain CMake list.add_custom_target(validate ALL  COMMAND ${OCX_TOOLS_RUN} jq -n -e --arg config "$"          [[$config | length >= 0]]  VERBATIM)">
Terminal windowcmake -S . -B build && cmake --build build
Run jq in a CMake build walks through this example step by step.
You need CMake 3.19 and network access or a mirror.
You do not need to install ocx.
An ocx on PATH is used when present, otherwise the pinned CLI is bootstrapped on first configure into a per-machine cache.
[... 23 lines elided]
```

$ python3 -I pg.py https://ocx.sh/integrations/cmake/reference/commands/ | grep -n -i platform
```
20:            [PLATFORM <ocx-platform>] [PULL])
21:] [TOML ] [LOCK ]            [GROUPS ...] [BINS ...]            [PLATFORM ] [PULL])">
30:A foreign PLATFORM (default OCX_DEFAULT_PLATFORM) pulls that platform’s content from the same ocx.lock and exports OCX_<NAME>_PATHS / OCX_<NAME>_ENV_<KEY> instead of RUN commands (foreign binaries cannot execute; BINS is an error).
35:            [PINS <platform>=sha256:<digest> ...]
37:            [PLATFORM <ocx-platform>...] [PULL] [NO_ROOT])
38: PACKAGE             [PINS =sha256: ...]            [INDEX  | NO_INDEX] [BINS ...]            [PLATFORM ...] [PULL] [NO_ROOT])">
39:Exports the same OCX_<NAME>_RUN / OCX_<NAME>_RUN_<BIN> command lists as ocx_project (re-entering ocx package exec, lazy by default). PINS maps ocx platform keys to per-platform manifest digests (as reported by ocx package install -p <platform>); the matching platform installs registry/repo@<digest>. BINS entries are executable names on the composed environment (a package may ship several tools), not package references.
42:With PULL (or the global OCX_PULL) the package is installed at configure time and <name>_ROOT (original case, CMP0074) is set to the package content root so a following find_package(<name>) / find_library searches the OCX-provisioned content — suppress with NO_ROOT. A foreign PLATFORM exports OCX_<NAME>_PATHS / OCX_<NAME>_ENV_<KEY> instead of RUN commands.
43:PLATFORM is an ordered preference list — multiple values (or a CMake ;-list) are forwarded to a single ocx ... -p a,b,c resolution and the first tier with a match wins (concrete cross-arch/variant fallback, e.g. PLATFORM linux/arm64 linux/amd64 to accept amd64 under qemu/rosetta). PINS keys off the primary (first) entry.
```

(Read the ocx_project / ocx_package sections of the Commands page. Decided to try BINS + PLATFORM first because I want the arm64 binary and a runner command.)

$ mkdir -p dl && cd dl && gh release download v0.3.0 -R ocx-sh/find_ocx && ls -la && sha256sum -c SHA256SUMS; cp Findocx.cmake ocx.cmake ../proj/cmake/
```
total 100
drwxr-xr-x 2 mherwig mherwig   100 Oct 10 18:44 .
drwxr-xr-x 5 mherwig mherwig   140 Oct 10 18:44 ..
-rw-r--r-- 1 mherwig mherwig  2891 Oct 10 18:44 Findocx.cmake
-rw-r--r-- 1 mherwig mherwig 90806 Oct 10 18:44 ocx.cmake
-rw-r--r-- 1 mherwig mherwig   156 Oct 10 18:44 SHA256SUMS
Findocx.cmake: OK
ocx.cmake: OK
```

(Downloaded the v0.3.0 vendored files; `ocx --version` is rejected, `ocx exec` needs an ocx.toml. Switched to `ocx version` and `ocx package exec`.)

$ which ocx; ocx --version; ocx exec -- cmake --version 2>&1 | head -3
```
/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx
error: unexpected argument '--version' found

Usage: ocx [OPTIONS] [COMMAND]

For more information, try '--help'.
error: no ocx.toml found in /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content or any parent; run `ocx init` to create one
```

$ ocx version; ocx package exec ocx.sh/kitware/cmake:4 -- cmake --version 2>&1 | head -3
```
0.6.5
Package 'ocx.sh/kitware/cmake:4' not found locally, pulling.
Downloading layer sha256:61c5ceac1af3 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/temp/5d1c38a94867e65acad24f47e861cc47
cmake version 4.4.4
```

$ mkdir -p proj/cmake && cp dl/Findocx.cmake dl/ocx.cmake proj/cmake/ && cat > proj/CMakeLists.txt   # (heredoc)
```
cmake_minimum_required(VERSION 3.19)
project(cross NONE)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest BINS jq PLATFORM linux/arm64 PULL)
```

$ cat proj/CMakeLists.txt; ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S proj -B proj/build
```
cmake_minimum_required(VERSION 3.19)
project(cross NONE)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest BINS jq PLATFORM linux/arm64 PULL)
CMake Error at cmake/ocx.cmake:1047 (message):
  find_ocx: ocx_package: PLATFORM is incompatible with BINS - foreign
  binaries cannot execute on this host
Call Stack (most recent call first):
  CMakeLists.txt:5 (ocx_package)


-- Configuring incomplete, errors occurred!
```

(Error says BINS is the problem but not what to use instead. Removed BINS.)

$ sed -i 's/ BINS jq//' proj/CMakeLists.txt
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S proj -B proj/build
```
-- find_ocx: using ocx from PATH (/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead
CMake Error at cmake/ocx.cmake:1095 (message):
  find_ocx: ocx_package jq: 'ocx.sh/jqlang/jq:latest' is floating and no
  index snapshot is in effect - resolution is not reproducible

  fix (pick one): commit a snapshot ('ocx --index .ocx index update
  ocx.sh/jqlang/jq:latest' next to your CMakeLists, or set OCX_INDEX); pin
  digests with PINS or @sha256:; or accept drift explicitly with
  -DOCX_ALLOW_FLOATING=ON
Call Stack (most recent call first):
  CMakeLists.txt:5 (ocx_package)


-- Configuring incomplete, errors occurred!
```

(Floating tag is a hard error. The 'fix' text offered three options; I took -DOCX_ALLOW_FLOATING=ON as `set(OCX_ALLOW_FLOATING ON)`. Then went to the guide linked from the docs front page: https://ocx.sh/integrations/cmake/guides/cross-build/ ; it recommends `ocx_package(NAME JQ_ARM PACKAGE ocx.sh/jqlang/jq:latest PLATFORM linux/arm64 NO_ROOT)` and says to read OCX_<NAME>_PATHS. Rewrote CMakeLists to print the variables.)

$ python3 -I pg.py https://ocx.sh/integrations/cmake/guides/cross-build/
```
integrations
CMake
CMake
Guides
Cross-build with foreign-platform content
Cross-build with foreign-platform content
Use PLATFORM to provision a package or a project toolchain for a platform other than the host, for example to bundle linux/arm64 content.
Request a foreign platform
Section titled “Request a foreign platform”
Pass PLATFORM to ocx_package or ocx_project.
The default comes from OCX_DEFAULT_PLATFORM, and empty means the host.
The commands below come from the foreign_platform test fixture, which runs in find_ocx’s own test suite.
tests/fixtures/foreign_platform/CMakeLists.txtset(OCX_ALLOW_FLOATING ON)
ocx_package(NAME JQ_ARM PACKAGE ocx.sh/jqlang/jq:latest PLATFORM linux/arm64 NO_ROOT)
Read the exported content
Section titled “Read the exported content”
A foreign platform exports content, not commands.
Foreign binaries cannot execute, so OCX_<NAME>_RUN is not defined and passing BINS is an error.
Use these variables instead:
OCX_<NAME>_PATHS lists the content paths.
OCX_<NAME>_ENV_<KEY> holds each environment value the package sets.
The fixture checks that the paths exist.
tests/fixtures/foreign_platform/CMakeLists.txtforeach(case JQ_ARM JQ_PREF)
  if(DEFINED CACHE{OCX_${case}_RUN})
[... 5 lines elided]
  foreach(dir IN LISTS OCX_${case}_PATHS)
    if(NOT EXISTS "${dir}")
      message(FATAL_ERROR "foreign_platform fixture: env path '${dir}' does not exist (${case})")
    endif()
  endforeach()
  message(STATUS "foreign_platform fixture: ok ${case} ($CACHE{OCX_${case}_PATHS})")
endforeach()
The harness runs this fixture on Linux hosts only.
For the signatures, see ocx_project and ocx_package.
Needs addressed: problem 6 of the use-case research.
PreviousBuild behind a mirror or offlineNextFix a failing configure
discord·roadmap·securityApache-2.0 · © 2026 The OCX Authors
```

$ cat > proj/CMakeLists.txt <<'EOF' ... EOF; rm -rf proj/build
```
cmake_minimum_required(VERSION 3.19)
project(cross NONE)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)
set(OCX_ALLOW_FLOATING ON)
ocx_package(NAME JQ_ARM PACKAGE ocx.sh/jqlang/jq:latest PLATFORM linux/arm64 NO_ROOT)
message(STATUS "paths: ${OCX_JQ_ARM_PATHS}")
if(DEFINED CACHE{OCX_JQ_ARM_RUN})
  message(STATUS "RUN var exists: ${OCX_JQ_ARM_RUN}")
else()
  message(STATUS "no RUN var")
endif()
foreach(d IN LISTS OCX_JQ_ARM_PATHS)
  message(STATUS "exists(${d}) = ")
  if(EXISTS "${d}")
    message(STATUS "  yes")
  else()
    message(STATUS "  NO")
  endif()
endforeach()
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S proj -B proj/build
```
-- find_ocx: using ocx from PATH (/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead
-- paths: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content
-- no RUN var
-- exists(/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content) = 
--   yes
-- Configuring done (1.8s)
CMake Warning:
  Value of OCX_JQ_ARM_CONTENT contained a newline; truncating


CMake Warning:
  Value of __OCX_R_JQ_ARM_GUARD contained a newline; truncating


-- Generating done (0.0s)
CMake Warning:
  Value of OCX_JQ_ARM_CONTENT contained a newline; truncating


CMake Warning:
  Value of __OCX_R_JQ_ARM_GUARD contained a newline; truncating


-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/proj/build
```

(Success criterion met for ocx_package: PATHS printed, exists, no RUN var. The two newline warnings are unexplained. Inspecting the cache and the content.)

$ grep -i "OCX_JQ_ARM" proj/build/CMakeCache.txt; P=$(grep "^OCX_JQ_ARM_PATHS" proj/build/CMakeCache.txt | cut -d= -f2); find $P | head; file $P/bin/jq
```
OCX_JQ_ARM_CONTENT:INTERNAL={
# WARNING: Value of OCX_JQ_ARM_CONTENT contained a newline and
OCX_JQ_ARM_ENV_KEYS:INTERNAL=
OCX_JQ_ARM_PATHS:INTERNAL=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content
/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content
/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content/jq
/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content/bin/jq: cannot open `/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content/bin/jq' (No such file or directory)
```

$ file ocxhome/packages/ocx.sh/sha256/81/*/content/jq; sed -n "/OCX_JQ_ARM_CONTENT/,+4p" proj/build/CMakeCache.txt; OCX_HOME=$PWD/ocxhome ocx package info ocx.sh/jqlang/jq:latest -p linux/arm64 2>&1 | head -20
```
ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content/jq: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, BuildID[sha1]=5a9325bec5b88594a0097a4d660419459067357e, for GNU/Linux 3.7.0, stripped
OCX_JQ_ARM_CONTENT:INTERNAL={
# WARNING: Value of OCX_JQ_ARM_CONTENT contained a newline and
#  was truncated. Original value:
# {
# \n  "kind" : "package",
error: unexpected argument '-p' found

  tip: to pass '-p' as a value, use '-- -p'

Usage: ocx package info [OPTIONS] <PACKAGE>...

For more information, try '--help'.
```

(Now the real goal: use it from a toolchain file. jq stands in for a sysroot package; I could not find a sysroot-style package in the docs.)

$ mkdir -p proj2/cmake && cp dl/*.cmake proj2/cmake/ && cat > proj2/toolchain.cmake   # (heredoc), plus a 3-line proj2/CMakeLists.txt with project(cross2 NONE) and message(STATUS "root path: ${CMAKE_FIND_ROOT_PATH}")
```
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR}/cmake)
include(ocx)
set(OCX_ALLOW_FLOATING ON)
ocx_package(NAME SYSROOT PACKAGE ocx.sh/jqlang/jq:latest PLATFORM linux/arm64 NO_ROOT)
set(CMAKE_FIND_ROOT_PATH ${OCX_SYSROOT_PATHS})
message(STATUS "toolchain: CMAKE_FIND_ROOT_PATH=${CMAKE_FIND_ROOT_PATH}")
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S proj2 -B proj2/build -DCMAKE_TOOLCHAIN_FILE=$PWD/proj2/toolchain.cmake 2>&1 | cut -c1-250
```
-- find_ocx: using ocx from PATH (/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead
-- toolchain: CMAKE_FIND_ROOT_PATH=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content
CMake Error at cmake/ocx.cmake:571 (message):
  find_ocx: duplicate ocx_package NAME 'SYSROOT'
Call Stack (most recent call first):
  cmake/ocx.cmake:1040 (__ocx_register_name)
  toolchain.cmake:6 (ocx_package)
  build/CMakeFiles/4.4.4/CMakeSystem.cmake:6 (include)
  CMakeLists.txt:2 (project)


CMake Error: CMake was unable to find a build program corresponding to "Unix Makefiles".  CMAKE_MAKE_PROGRAM is not set.  You probably need to select a different build tool.
-- Configuring incomplete, errors occurred!
CMake Warning:
  Value of OCX_SYSROOT_CONTENT contained a newline; truncating


CMake Warning:
  Value of __OCX_R_SYSROOT_GUARD contained a newline; truncating
```

(Toolchain file is included a second time by CMake itself; ocx_package refuses a duplicate NAME. Also no make on this box. Wrapped the call in a guard and switched to Ninja.)

$ sed -i  (wrap the ocx_package line in if(NOT DEFINED OCX_SYSROOT_PATHS) ... endif()); rm -rf proj2/build
```
if(NOT DEFINED OCX_SYSROOT_PATHS)
ocx_package(NAME SYSROOT PACKAGE ocx.sh/jqlang/jq:latest PLATFORM linux/arm64 NO_ROOT)
endif()
```

$ ocx package exec ocx.sh/kitware/cmake:4 ocx.sh/ninja-build/ninja -- cmake -G Ninja -S proj2 -B proj2/build -DCMAKE_TOOLCHAIN_FILE=$PWD/proj2/toolchain.cmake 2>&1 | cut -c1-250
```
Package 'ocx.sh/ninja-build/ninja' not found locally, pulling.
Downloading layer sha256:a6a29ca649b7 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/temp/da01f22ae7d8a48c31525f16bdf9810a
-- find_ocx: using ocx from PATH (/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead
-- toolchain: CMAKE_FIND_ROOT_PATH=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content
-- toolchain: CMAKE_FIND_ROOT_PATH=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content
-- root path: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content
-- Configuring done (0.1s)
CMake Warning:
  Value of OCX_SYSROOT_CONTENT contained a newline; truncating


CMake Warning:
  Value of __OCX_R_SYSROOT_GUARD contained a newline; truncating


-- Generating done (0.0s)
CMake Warning:
  Value of OCX_SYSROOT_CONTENT contained a newline; truncating


CMake Warning:
  Value of __OCX_R_SYSROOT_GUARD contained a newline; truncating


-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/proj2/build
```

(Works with the guard; toolchain message printed twice.) Now the ocx_project variant.

$ cd proj3 && ocx init 2>&1 | tail -3; cat ocx.toml; ocx add ocx.sh/jqlang/jq:latest 2>&1 | tail -3; ocx lock 2>&1 | tail -3; ls
```
created /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/proj3/ocx.toml
#:schema https://ocx.sh/schemas/project/v1.json
# OCX project toolchain — managed by `ocx add` / `ocx remove`

[tools]
Downloading layer sha256:88ad916b0507 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/ocxhome/temp/9c13e7a59201751a36e83176bff4a013
Binding  Group    Digest                                                                 
jq       default  sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
warning: add `ocx.lock merge=union` to .gitattributes to avoid merge conflicts
Binding  Group    Digest                                                                 
jq       default  sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
cmake
CMakeLists.txt
ocx.lock
ocx.toml
```

$ cat > proj3/CMakeLists.txt   # (heredoc); mkdir -p proj3/cmake && cp dl/*.cmake proj3/cmake/
```
cmake_minimum_required(VERSION 3.19)
project(cross3 NONE)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)
ocx_project(NAME ARM BINS jq PLATFORM linux/arm64)
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S proj3 -B proj3/build 2>&1 | cut -c1-250
```
CMake Error at cmake/ocx.cmake:873 (message):
  find_ocx: ocx_project: PLATFORM is incompatible with BINS - foreign
  binaries cannot execute on this host
Call Stack (most recent call first):
  CMakeLists.txt:5 (ocx_project)


-- Configuring incomplete, errors occurred!
```

$ sed -i 's/ BINS jq//' proj3/CMakeLists.txt && echo 'message(STATUS "ARM paths: ${OCX_ARM_PATHS}")' >> proj3/CMakeLists.txt && rm -rf proj3/build
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S proj3 -B proj3/build 2>&1 | cut -c1-250; ls proj3/build | head
```
-- find_ocx: using ocx from PATH (/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead
-- ARM paths: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/proj3/.ocx/toolchain/links/default/jq/content
-- Configuring done (0.1s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/proj3/build
CMakeCache.txt
CMakeFiles
cmake_install.cmake
Makefile
```

$ ls -la proj3/.ocx proj3/.ocx/toolchain/links/default/jq/; file -L proj3/.ocx/toolchain/links/default/jq/content/*; grep -E "OCX_ARM" proj3/build/CMakeCache.txt | cut -c1-200
```
proj3/.ocx:
total 0
drwx------ 3 mherwig mherwig  60 Oct 10 18:45 .
drwxr-xr-x 5 mherwig mherwig 160 Oct 10 18:45 ..
drwx------ 4 mherwig mherwig 120 Oct 10 18:45 toolchain

proj3/.ocx/toolchain/links/default/jq/:
total 20
drwxr-xr-x 4 mherwig mherwig 180 Oct 10 18:45 .
drwxr-xr-x 3 mherwig mherwig  60 Oct 10 18:45 ..
drwxr-xr-x 2 mherwig mherwig  60 Oct 10 18:45 content
-rw-r--r-- 1 mherwig mherwig  71 Oct 10 18:45 digest
-rw-r--r-- 1 mherwig mherwig  65 Oct 10 18:45 install.json
-rw-r--r-- 1 mherwig mherwig 530 Oct 10 18:45 manifest.json
-rw-r--r-- 1 mherwig mherwig 225 Oct 10 18:45 metadata.json
drwxr-xr-x 5 mherwig mherwig 100 Oct 10 18:45 refs
-rw-r--r-- 1 mherwig mherwig  24 Oct 10 18:45 resolve.json
proj3/.ocx/toolchain/links/default/jq/content/jq: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, BuildID[sha1]=5a9325bec5b88594a0097a4d660419459067357e, for GNU/Linux 3.7.0, stripped
OCX_ARM_ENV_KEYS:INTERNAL=
OCX_ARM_PATHS:INTERNAL=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-cross-build-foreign-content/proj3/.ocx/toolchain/links/default/jq/content
```

## Friction

1. **minor** - `BINS` + `PLATFORM` error names the conflict but gives no way forward: "PLATFORM is incompatible with BINS - foreign binaries cannot execute on this host". Nothing says which variables to read instead (`OCX_<NAME>_PATHS`) or where the guide is. Looked in: configure output, Commands page (the `ocx_project` entry says "BINS is an error" in a parenthetical; the `ocx_package` entry only says "instead of RUN commands" and never states the BINS error).
2. **major** - Using `ocx_package` inside a toolchain file fails: `find_ocx: duplicate ocx_package NAME 'SYSROOT'`. CMake includes the toolchain file a second time (stack shows `CMakeSystem.cmake:6 (include)`), and the module rejects the repeated NAME. Neither the guide nor the Commands page mentions toolchain files or this. I found a guard (`if(NOT DEFINED OCX_SYSROOT_PATHS)`) only by guessing. Looked in: Cross-build guide, Commands page.
3. **major** - The Cross-build guide is an excerpt of an internal test fixture, not a how-to for my goal. It shows `ocx_package` with `set(OCX_ALLOW_FLOATING ON)` and `NO_ROOT` (neither explained), a fixture assertion loop, and the lines "The harness runs this fixture on Linux hosts only." and "Needs addressed: problem 6 of the use-case research." (internal wording). No example of consuming the paths from a toolchain file (`CMAKE_FIND_ROOT_PATH`, `CMAKE_SYSROOT`), no example with `ocx_project` and a lock, which is the "same lock" half of my goal. Looked in: Cross-build guide.
4. **major** - Every configure that uses a foreign `ocx_package` prints `CMake Warning: Value of OCX_JQ_ARM_CONTENT contained a newline; truncating` and the same for `__OCX_R_JQ_ARM_GUARD`, twice per run (configure and generate). `CMakeCache.txt` then holds a garbled `OCX_JQ_ARM_CONTENT:INTERNAL={ # WARNING: ... Original value: # { ...` entry containing the raw package JSON. Docs say nothing; I cannot tell whether the result is trustworthy. Did not occur with `ocx_project PLATFORM`. Looked in: configure output, CMakeCache.txt, docs (nothing found).
5. **minor** - Success is invisible: configure prints nothing about the foreign content by default. I had to write my own `message()` and `EXISTS` checks to see `OCX_<NAME>_PATHS`; the variables are `INTERNAL` cache entries, so `cmake -L` / cmake-gui do not show them. Guide gives a fixture assertion but no "what you should see" output. Looked in: Cross-build guide, Variables page not opened (Commands page lists the names only).
6. **minor** - What "content paths" means is unclear for a sysroot-style use: with jq I got one path, the package `content` root, with the binary at `content/jq` (no `bin/`), and `OCX_<NAME>_ENV_KEYS` empty. The docs do not say whether PATHS is the content root, the package's declared PATH entries, or something else, nor what `ENV_<KEY>` looks like in practice. No sysroot-style package is named anywhere; I used jq as a stand-in. Looked in: Commands page, Cross-build guide.
7. **minor** - Eager vs lazy is implicit: no `PULL` given in the second run, yet the arm64 package was downloaded at configure time (needed network). The Commands page says launchers are lazy by default and does not say foreign content is always eager. Looked in: Commands page, front page.
8. **minor** - Floating tag hard error (`OCX_ALLOW_FLOATING`) hits a first cross-build immediately; the guide's snippet silently sets the override. The error text itself is clear, but how a foreign platform is pinned reproducibly (PINS keyed to primary platform, or the lock for `ocx_project`) is only in the Commands page, not connected to the cross-build story. Looked in: configure output, Commands page.
9. **minor** - `ocx_project PLATFORM linux/arm64` writes into the source tree: `proj3/.ocx/toolchain/links/default/jq/...` (the per-project links). `.ocx/` is also the name of the committed index snapshot directory the docs tell me to commit, so I could not tell if this directory should be committed or ignored. Looked in: Commands page, front page (nothing).
10. **minor** - Discovery: README and front-page example never mention `PLATFORM`; the cross-build guide is the fifth of eight "Pick a goal" links. Valid `<ocx-platform>` strings are not listed; I guessed `linux/arm64` from the guide. Looked in: README, front page, Commands page.
11. **minor** (outside find_ocx) - `ocx --version` is rejected and `ocx exec` needs an `ocx.toml`; I had to find `ocx version` and `ocx package exec` to run cmake. The find_ocx docs do not show how to run the vendored files with a tool-managed CMake. Looked in: `ocx --help` output, docs front page.
