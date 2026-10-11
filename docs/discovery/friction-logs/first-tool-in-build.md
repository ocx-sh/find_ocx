# Friction log: first jq in a CMake build

## Setup

- Persona: Priya, C++ build engineer, years of CMake, never heard of OCX. Has not seen the find_ocx source; used only the GitHub README, the v0.3.0 release assets and https://ocx.sh/integrations/cmake/.
- Date: 2026-10-10.
- Starting state: empty CMake project (`project(demo LANGUAGES NONE)`), a `data.json`, a README saying "Install jq first". Goal: `cmake --build` prints the jq-pretty-printed JSON on a machine with no jq on PATH and no ocx installed.
- Machine: ocx 0.6.5 on PATH (used once, for `ocx lock`, as the tutorial instructs). `OCX_HOME` isolated to the work dir for that step. This sandbox has jq in `/usr/bin`, so the CMake steps run through a wrapper `./clean` = `env -i HOME=/tmp/priya-home PATH=<copy of /usr/bin without jq and ocx>`; `cmake` below is the kitware/cmake:4 package binary (4.4.4) obtained with `ocx package exec`. `fetch-docs` is a small script that fetches a docs URL and strips HTML to text.

## Attempt

$ which jq cmake ocx; ocx --version; pwd; echo $OCX_HOME
```
/usr/sbin/jq
/home/mherwig/dev/find_ocx/.ocx/toolchain/links/default/cmake/content/bin/cmake
/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx
error: unexpected argument '--version' found

Usage: ocx [OPTIONS] [COMMAND]

For more information, try '--help'.
/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build
/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/ocxhome
```

$ gh api repos/ocx-sh/find_ocx/readme -H "Accept: application/vnd.github.raw"
````
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

[... 1 lines elided]

Vendor `Findocx.cmake` + `ocx.cmake` from the
[release assets](https://github.com/ocx-sh/find_ocx/releases) into your
repository (e.g. `cmake/`):

```cmake
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)

# Flagship: the workspace toolchain from ./ocx.toml + ./ocx.lock (lazy).
ocx_project(BINS jq)
add_custom_command(
  OUTPUT pretty.json
  COMMAND ${OCX_PROJECT_RUN_JQ} . ${CMAKE_SOURCE_DIR}/data.json > pretty.json
)

# Ad-hoc: a single package. PULL exports jq_ROOT (CMP0074) so a following
# find_package/find_library searches the OCX-provisioned content.
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest PULL)
```

No ocx installation required: the pinned CLI is bootstrapped at first
configure (per-machine cache, manifest sha256 enforced). The classic find
module works too — `find_package(ocx REQUIRED)`, with `-DOCX_BOOTSTRAP=ON`
for the same zero-setup behavior.

Requires CMake **3.19** (`Findocx.cmake` alone works on 3.15). Script mode
(`cmake -P`) is fully supported.

[... 1 lines elided]

Guides, concepts and the command and variable reference are at
<https://ocx.sh/integrations/cmake/>.

[... 1 lines elided]

- [`examples/project`](examples/project) — workspace toolchain: zero-arg
  `ocx_project()`, group launchers, genexes in commands, ctest usage
- [`examples/package`](examples/package) — ad-hoc jq: floating + eager,
  digest-pinned + lazy, `<name>_ROOT`
- [`examples/frozen_index`](examples/frozen_index) — a committed `.ocx/`
  snapshot and a deliberate refresh target
- [`examples/find_package`](examples/find_package) — classic
  `find_package(ocx)` discovery

[... 1 lines elided]

The harness dogfoods find_ocx.
The CMake versions under test are provisioned as OCX packages
(`ocx.sh/kitware/cmake:<tag>`) through `ocx_package()` itself, and each fixture runs on every version via
`ctest --build-and-test` — on Linux, macOS, and Windows.

```sh
ocx run -- task verify
```

[... 1 lines elided]

Apache-2.0. See [LICENSE](LICENSE).
````

$ gh release view v0.3.0 -R ocx-sh/find_ocx
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

[... 1 lines elided]

### Added

- Reproducible-first index snapshots and PATH-first CLI resolution **BREAKING**
[0.3.0]: https://github.com/ocx-sh/find_ocx/compare/v0.2.0..v0.3.0
```

$ curl -sSL -o /dev/null -w "%{http_code} %{url_effective}\n" https://ocx.sh/integrations/cmake/; curl -sSL -o /dev/null -w "%{http_code} %{url_effective}\n" https://ocx-sh.github.io/find_ocx/
```
200 https://ocx.sh/integrations/cmake/
200 https://ocx-sh.github.io/find_ocx/
```

$ fetch-docs https://ocx.sh/integrations/cmake/tutorial/
```
integrations
CMake
Run jq in a CMake build without installing it
Run jq in a CMake build without installing it
In this tutorial you add find_ocx to a CMake project and run jq from a build target.
You never install jq on your machine.
You need CMake 3.19 or later.
You also need the ocx CLI once, to write the lock file (install it).
find_ocx downloads its own pinned ocx for the build.
Vendor the two files
Section titled “Vendor the two files”
Download Findocx.cmake and ocx.cmake from the release assets.
Put both in a cmake/ directory of an empty project.
Check that cmake/ocx.cmake and cmake/Findocx.cmake exist next to where your CMakeLists.txt will be.
Pin the tool
[... 64 lines elided]
```

$ ls -la; cat data.json CMakeLists.txt README.md; env | grep -i ocx; gh release download v0.3.0 -R ocx-sh/find_ocx --dir cmake; ls cmake; (cd cmake && sha256sum -c SHA256SUMS)
```
total 12
drwxr-xr-x  3 mherwig mherwig 120 Oct 10 18:44 .
drwx------ 11 mherwig mherwig 240 Oct 10 18:44 ..
-rw-r--r--  1 mherwig mherwig  66 Oct 10 18:44 CMakeLists.txt
-rw-r--r--  1 mherwig mherwig  53 Oct 10 18:44 data.json
drwxr-xr-x  2 mherwig mherwig  40 Oct 10 18:44 ocxhome
-rw-r--r--  1 mherwig mherwig  49 Oct 10 18:44 README.md
{"name":"demo","items":[1,2,3],"nested":{"ok":true}}
cmake_minimum_required(VERSION 3.19)
project(demo LANGUAGES NONE)
# demo
Install jq first, then run cmake --build.
OCX_NO_UPDATE_CHECK=true
WSL_DISTRO_NAME=ocx.sh
[... 1 lines elided]
PWD=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build
OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.ocx.sh:443
GRAFANA_URL=https://grafana.ocx.sh
OCX_HOME=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/ocxhome
[... 1 lines elided]
OLDPWD=/home/mherwig/dev/find_ocx-ocx06
Findocx.cmake
ocx.cmake
SHA256SUMS
Findocx.cmake: OK
ocx.cmake: OK
```

$ cat ocx.toml; ocx lock; echo; ls; cat ocx.lock
```
[tools]
jq = "ocx.sh/jqlang/jq:latest"
pulling count=1
Downloading layer sha256:88ad916b0507 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/ocxhome/temp/9c13e7a59201751a36e83176bff4a013
warning: add `ocx.lock merge=union` to .gitattributes to avoid merge conflicts
Binding  Group    Digest                                                                 
jq       default  sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae

cmake
CMakeLists.txt
data.json
ocxhome
ocx.lock
ocx.toml
README.md
[metadata]
lock_version = 3
declaration_hash_version = 1
declaration_hash = "sha256:e0361206f7a2ebde72dda210f86a838bcd00335fffb2cb77c55bd940b673c4a6"
generated_by = "ocx 0.6.5"
generated_at = "2026-10-10T16:44:48Z"

[[tool]]
name = "jq"
group = "default"
repository = "ocx.sh/jqlang/jq"

[tool.platforms]
"darwin/amd64" = "sha256:f750c91d28769d12298ba9a4c10340152fcbdd48c48102bf275c21d736cc72a2"
"darwin/arm64" = "sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1"
"linux/amd64" = "sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
"linux/arm64" = "sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
"windows/amd64" = "sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989"
```

$ cat CMakeLists.txt
```
cmake_minimum_required(VERSION 3.19)
project(demo LANGUAGES NONE)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)
ocx_project(NAME TOOLS BINS jq)
add_custom_target(pretty ALL
  COMMAND ${OCX_TOOLS_RUN} jq . ${CMAKE_SOURCE_DIR}/data.json
  VERBATIM
)
```

$ ls /usr/bin/jq /usr/bin/make /usr/bin/cmake /usr/bin/ocx 2>&1; ocx package exec ocx.sh/kitware/cmake:4 -- cmake --version
```
ls: cannot access '/usr/bin/cmake': No such file or directory
ls: cannot access '/usr/bin/ocx': No such file or directory
/usr/bin/jq
/usr/bin/make
Package 'ocx.sh/kitware/cmake:4' not found locally, pulling.
Downloading layer sha256:61c5ceac1af3 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/ocxhome/temp/5d1c38a94867e65acad24f47e861cc47
cmake version 4.4.4

CMake suite maintained and supported by Kitware (kitware.com/cmake).
```

$ PATH=<cleanbin>; command -v jq ocx cmake; echo rc=$?
```
rc=1
```

$ ./clean cmake -S . -B build
```
-- find_ocx: downloading ocx 0.3.11 (x86_64-unknown-linux-musl) from https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-x86_64-unknown-linux-musl.tar.xz
-- find_ocx:   version knob: OCX_INSTALL_VERSION (pin: 0.3.11); cache: /tmp/priya-home/.cache/find_ocx; opt out: OCX_BOOTSTRAP=OFF + OCX_EXECUTABLE
-- find_ocx: using bootstrapped ocx 0.3.11 (/tmp/priya-home/.cache/find_ocx/0.3.11/x86_64-unknown-linux-musl/ocx)
CMake Error at cmake/ocx.cmake:443 (message):
  find_ocx: checking
  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/ocx.toml
  against its lockfile failed (exit 78): ocx --project
  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/ocx.toml
  lock --check

  2026-10-10T16:45:14.679842Z ERROR
  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/ocx.lock:
  invalid TOML:
  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/ocx.lock:
  invalid TOML:
  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/ocx.lock:
  invalid TOML: invalid TOML: TOML parse error at line 2, column 16

    |

  2 | lock_version = 3

    |                ^

  invalid value: 3, expected 1 or 2





  hint: no ocx.lock next to
  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/ocx.toml
  - run 'ocx lock' and commit it
Call Stack (most recent call first):
  cmake/ocx.cmake:919 (__ocx_run)
  CMakeLists.txt:5 (ocx_project)


-- Configuring incomplete, errors occurred!
[exit 1]
```

$ fetch-docs https://ocx.sh/integrations/cmake/guides/nested-builds/
```
integrations
CMake
CMake
Guides
Fix a failing configure
Fix a failing configure
Error: a nested configure fails with the exit-81 refresh hint
Section titled “Error: a nested configure fails with the exit-81 refresh hint”
This issue occurs when a find_ocx configure runs inside an ocx launcher, such as an ExternalProject, ctest --build-and-test or a superbuild.
Launchers like ocx run and the OCX_<NAME>_RUN command lists export OCX_FROZEN and OCX_INDEX into child processes.
The inner configure stores those values as if you had set them.
The outer index does not contain the inner packages.
Pass both variables empty to the nested configure:
Terminal window
cmake -DOCX_FROZEN= -DOCX_INDEX= ...
Error: a floating tag stops the configure
Section titled “Error: a floating tag stops the configure”
This issue occurs when a package uses a floating tag such as :latest.
No index snapshot is in effect, and no digest is pinned.
find_ocx is reproducible first, so it refuses to resolve the tag live.
Commit an index snapshot or add PINS: see Pin and freeze tag resolution.
To print the digests once, set OCX_ALLOW_FLOATING for a single run.
Error: the lock check fails
Section titled “Error: the lock check fails”
This issue occurs when ocx.lock no longer matches ocx.toml.
ocx_project always runs ocx lock --check, which is an offline staleness gate.
Run ocx lock, review the diff and commit it.
Previous
Cross-build with foreign contentNext
How find_ocx works
discord·roadmap·securityApache-2.0 · © 2026 The OCX Authors
```

$ gh release list -R ocx-sh/find_ocx
```
v0.3.0	Latest	v0.3.0	2026-07-03T10:25:25Z
v0.2.0		v0.2.0	2026-07-03T06:04:56Z
v0.1.0		v0.1.0	2026-07-02T22:32:24Z
```

$ fetch-docs https://ocx.sh/integrations/cmake/reference/variables/ | grep -n -i -B2 -A6 -E 'INSTALL_VERSION|PIN_VERSION|lock_version|compatib'
```
26-Section titled “OCX_INSTALL_MIRROR_URL”
27-Rewrite the ocx binary download to <mirror>/<tag>/<filename>. The manifest sha256 is still enforced — a mirror can move bytes, not change them.
28:OCX_INSTALL_VERSION
29:Section titled “OCX_INSTALL_VERSION”
30-ocx CLI version to bootstrap (default: the version pinned with this find_ocx release). Same knob as the setup.ocx.sh installer.
31-OCX_BOOTSTRAP
32-Section titled “OCX_BOOTSTRAP”
33:Implicit-bootstrap policy for the first provisioning call when OCX_EXECUTABLE is not set. Unset or ON (default): use an ocx found on PATH, bootstrap the pinned CLI when there is none. ALWAYS: skip the PATH search — every machine runs the identical pinned binary (hermetic mode; pair with OCX_INSTALL_VERSION). OFF: never download — OCX_EXECUTABLE or a PATH ocx is required, anything else is a hard configure error (for environments that forbid configure-time downloads). Inside Findocx.cmake the same variable is the opt-in for the bootstrap fallback (find modules discover by default).
34-OCX_DEFAULT_PLATFORM
35-Section titled “OCX_DEFAULT_PLATFORM”
36-Default PLATFORM for ocx_project / ocx_package (empty = host). For ocx_package this is an ordered platform preference list (first match wins) and may be a CMake ;-list; at the ocx_project tier only the first/single entry is meaningful.
37-OCX_INDEX
38-Section titled “OCX_INDEX”
39-Committed index snapshot directory freezing tag resolution for every ocx_package without an explicit INDEX. When unset, each call discovers the nearest .ocx/ directory between its calling directory and the last project() source dir instead (ocx_index FIND runs that discovery once and locks the result into this variable). Clearing with -DOCX_INDEX= neutralizes a value inherited from an outer ocx launcher without vetoing the project’s own committed snapshot.
```

$ rm -rf build; ./clean cmake -S . -B build -DOCX_INSTALL_VERSION=0.6.5
```
CMake Error at cmake/ocx.cmake:508 (message):
  find_ocx: ocx 0.6.5 for x86_64-unknown-linux-musl not found in the dist
  manifest - refresh the vendored snapshot (task dist:update) or point
  OCX_INSTALL_DIST_URL at a manifest that contains it
Call Stack (most recent call first):
  cmake/ocx.cmake:718 (__ocx_select_release)
  cmake/ocx.cmake:561 (ocx_bootstrap)
  cmake/ocx.cmake:883 (__ocx_require_cli)
  CMakeLists.txt:5 (ocx_project)


-- Configuring incomplete, errors occurred!
[exit 1]
```

$ grep -o '"version": *"[^"]*"' cmake/ocx.cmake | sort | uniq -c; curl -sS https://setup.ocx.sh/dist.json | grep -o '"version": *"[^"]*"' | sort | uniq -c | tail -8
```
      8 "version":"0.1.0"
      8 "version":"0.2.0"
      8 "version":"0.2.1"
      8 "version":"0.3.0"
      8 "version":"0.3.1"
      8 "version":"0.3.10"
      9 "version":"0.3.11"
      8 "version":"0.3.2"
      8 "version":"0.3.3"
      8 "version":"0.3.4"
      8 "version":"0.3.5"
      8 "version":"0.3.6"
      8 "version":"0.3.7"
      8 "version":"0.3.8"
      8 "version":"0.3.9"
      8 "version":"0.5.7"
      8 "version":"0.5.8"
      8 "version":"0.6.0"
      8 "version":"0.6.1"
      8 "version":"0.6.2"
[... 3 lines elided]
```

$ rm -rf build; ./clean cmake -S . -B build -DOCX_INSTALL_VERSION=0.6.5 -DOCX_INSTALL_DIST_URL=https://setup.ocx.sh/dist.json
```
-- find_ocx: downloading ocx 0.6.5 (x86_64-unknown-linux-musl) from https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz
-- find_ocx:   version knob: OCX_INSTALL_VERSION (pin: 0.3.11); cache: /tmp/priya-home/.cache/find_ocx; opt out: OCX_BOOTSTRAP=OFF + OCX_EXECUTABLE
-- find_ocx: using bootstrapped ocx 0.6.5 (/tmp/priya-home/.cache/find_ocx/0.6.5/x86_64-unknown-linux-musl/ocx)
-- Configuring done (0.9s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/build
```

$ ./clean cmake --build build
```
warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7
Package 'ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae' not found locally, pulling.
Downloading layer sha256:88ad916b0507 to /tmp/priya-home/.ocx/temp/9c13e7a59201751a36e83176bff4a013
{
  "name": "demo",
  "items": [
    1,
    2,
    3
  ],
  "nested": {
    "ok": true
  }
}
Built target pretty
```

$ cd readme-try && cat CMakeLists.txt && ./clean cmake -S . -B build -DOCX_INSTALL_VERSION=0.6.5 -DOCX_INSTALL_DIST_URL=https://setup.ocx.sh/dist.json
```
cmake_minimum_required(VERSION 3.19)
project(demo LANGUAGES NONE)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)

ocx_project(BINS jq)
add_custom_command(
  OUTPUT pretty.json
  COMMAND ${OCX_PROJECT_RUN_JQ} . ${CMAKE_SOURCE_DIR}/data.json > pretty.json
)

ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest PULL)
CMake Error at cmake/ocx.cmake:798 (message):
  find_ocx: no ocx.toml found searching upward from
  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/readme-try
  - pass TOML <path>, set OCX_PROJECT_FILE, or create an ocx.toml
Call Stack (most recent call first):
  cmake/ocx.cmake:854 (__ocx_default_toml)
  CMakeLists.txt:6 (ocx_project)


-- Configuring incomplete, errors occurred!
[exit 1]
```

$ cd readme-try && ./clean cmake -S . -B build -DOCX_INSTALL_VERSION=0.6.5 -DOCX_INSTALL_DIST_URL=https://setup.ocx.sh/dist.json
```
-- find_ocx: using bootstrapped ocx 0.6.5 (/tmp/priya-home/.cache/find_ocx/0.6.5/x86_64-unknown-linux-musl/ocx)
CMake Error at cmake/ocx.cmake:1095 (message):
  find_ocx: ocx_package jq: 'ocx.sh/jqlang/jq:latest' is floating and no
  index snapshot is in effect - resolution is not reproducible

  fix (pick one): commit a snapshot ('ocx --index .ocx index update
  ocx.sh/jqlang/jq:latest' next to your CMakeLists, or set OCX_INDEX); pin
  digests with PINS or @sha256:; or accept drift explicitly with
  -DOCX_ALLOW_FLOATING=ON
Call Stack (most recent call first):
  CMakeLists.txt:12 (ocx_package)


-- Configuring incomplete, errors occurred!
[exit 1]
```

$ cd readme-try && ./clean cmake -S . -B build -DOCX_INSTALL_VERSION=0.6.5 -DOCX_INSTALL_DIST_URL=https://setup.ocx.sh/dist.json && ./clean cmake --build build; ls
```
-- find_ocx: PROJECT up to date (memoized)
-- Configuring done (0.0s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-first-tool-in-build/readme-try/build
build
cmake
CMakeLists.txt
data.json
ocx.lock
ocx.toml
```

## Friction

1. **blocker** - Following the tutorial verbatim fails at configure. The tutorial has you run `ocx lock` with whatever ocx you installed (0.6.5 here, `lock_version = 3`), but v0.3.0 bootstraps its own pinned ocx 0.3.11, which rejects that lock file (`invalid value: 3, expected 1 or 2`). The error ends in "no ocx.lock next to ... run 'ocx lock' and commit it", which is wrong (the file exists and re-running `ocx lock` reproduces it). Looked in: configure error text, "Fix a failing configure" (its "the lock check fails" entry says run `ocx lock`, which does not help here), tutorial, README.
2. **major** - Getting past it needed two undocumented-together knobs found by guessing: `-DOCX_INSTALL_VERSION=0.6.5` (from the Variables reference) failed with "ocx 0.6.5 ... not found in the dist manifest - refresh the vendored snapshot (task dist:update) or point OCX_INSTALL_DIST_URL ...". `task dist:update` is a maintainer command that does not exist for a consumer; I had to find the live manifest URL (`https://setup.ocx.sh/dist.json`) myself and pass it as `-DOCX_INSTALL_DIST_URL`. Nothing in the tutorial or the failing-configure guide mentions version skew between the ocx used for `ocx lock` and the pinned bootstrap ocx. Looked in: Variables reference, configure error text.
3. **major** - The README quick start does not produce output. `add_custom_command(OUTPUT pretty.json ...)` is not attached to any target, so `cmake --build` builds nothing and prints nothing (empty output, `pretty.json` never created). The README snippet also never mentions that `ocx.toml` and `ocx.lock` must exist first (configure error: "no ocx.toml found searching upward"), and it pairs `ocx_project` with an `ocx_package(... jq:latest PULL)` line that stops configure ("is floating and no index snapshot is in effect"). Looked in: README quick start.
4. **minor** - The tutorial's `validate` target runs jq silently (`-n -e` check, "The build ends without an error"), so it never shows jq output; the goal here (print pretty JSON from `data.json`) is not covered by any page I read and I composed the target myself from the tutorial snippet. Looked in: tutorial.
5. **minor** - Tutorial says "You also need the ocx CLI once, to write the lock file", while the overview and README say "No ocx installation required" and the README header promises zero-setup. The first claim contradicts the second for any project starting from scratch. Looked in: overview, README, tutorial.
6. **minor** - Successful build prints "warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7", emitted by the launcher find_ocx generates; nothing I wrote uses `ocx run`. Also `ocx lock` warns "add `ocx.lock merge=union` to .gitattributes", which no find_ocx page mentions. Looked in: build output, tutorial.
7. **minor** - `ocx.toml` placed in a parent directory of the CMake project is not found ("no ocx.toml found searching upward"), contrary to the "upward search" wording in the tutorial comment; the search apparently stops at the project source dir. Looked in: configure error text, tutorial code comment.
8. **minor** - `ocx --version` is rejected (`unexpected argument '--version'`), so I could not check which ocx version I had before the skew in item 1. Looked in: CLI help.
