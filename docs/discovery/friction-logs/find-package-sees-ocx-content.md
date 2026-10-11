## Setup

- Persona: Tomas, library maintainer. His C++ library's build needs `jq`, which is not installed on the CI runners. First time using OCX or find_ocx; has not seen the find_ocx source.
- Starting state: empty directory, isolated `OCX_HOME` in the work directory, `ocx` 0.6.5 on PATH, CMake 4.4.4 via `ocx package exec ocx.sh/kitware/cmake:4 -- cmake`. The host has a system `jq` at `/usr/sbin/jq`.
- Material used: the find_ocx GitHub README, release v0.3.0 assets (`ocx.cmake`, `Findocx.cmake`), and the docs at https://ocx.sh/integrations/cmake/ (fetched with curl, HTML stripped to text by a small local helper, `txt.sh`).
- Date: 2026-10-10.
- Goal: starting from `ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:1.8.2 PINS ... PULL)` followed by `find_program(JQ_EXE jq)`, see `jq_ROOT` printed under the OCX content store and `find_program` resolve the binary inside it, not the system copy.
- Notes on the record: the very first `ocx --version` (error: unexpected argument) and the first README fetch were run before the logging wrapper existed and are not reproduced below; `ocx version` and the README are. Each command ran from the work directory (or `proj/`) with `OCX_HOME` exported.

## Attempt

$ ocx --help
````
A simple package manager for pre-built binaries.

Usage: ocx [OPTIONS] [COMMAND]

Commands:
  env      Compose and print the toolchain environment
  add      Add one or more package bindings to ocx.toml
  clean    Remove unreferenced objects from the local object store
  config   Manage the corporate managed-configuration tier
  direnv   direnv integration (init writes .envrc; export emits the env block)
  index    Inspect the package index and refresh the local copy
  about    Print ocx version, registry, platform, shell, and home directory
  init     Create a minimal ocx.toml in the current directory
  lock     Resolve package tags to digests and write ocx.lock
  login    Authenticate to a registry and persist credentials
  logout   Remove credentials for a registry
  update   Re-resolve declared tags against the registry; whole file or a subset
  upgrade  Move declared tags in ocx.toml to the newest published release
  package  Operations related to packages (e.g. bundling or deploying)
  patch    Manage patch overlays for a project
  pull     Pre-warm the object store, then render the project toolchain
  remove   Remove one or more package bindings from ocx.toml [alias: rm]
  exec     Run a command with the composed environment from the project toolchain [alias: x]
  shell    Shell-integration commands
  self     Manage the OCX installation itself (PATH activation, completions, self-update)
  status   Show what ocx.toml and ocx.lock declare, without resolving anything
  inspect  Inspect what the project toolchain resolves to, without installing
  version  Print the version of ocx

Options:
  -c, --config <FILE>
          Path to the ocx configuration file.
          
          Can also be set via the `OCX_CONFIG` environment variable. To disable config discovery entirely, set `OCX_NO_CONFIG=1`.

      --project <PATH>
          Project directory, or the project file itself (project-tier toolchain config).
          
          A directory resolves to the `ocx.toml` inside it, so `--project .` and `--project /path/to/repo` both work; a file may have any name (like Cargo `--manifest-path`). Equivalent env var: `OCX_PROJECT`; `OCX_NO_PROJECT=1` disables project discovery. Paths given here or via `OCX_PROJECT` are trusted and followed through symlinks. The CWD walk looks for the literal name `ocx.toml`, rejects symlinks and continues upward, so a writer with control over an intermediate directory cannot redirect discovery.

[... 57 lines elided]
          [default: auto]
          [possible values: auto, always, never]

  -h, --help
          Print help (see a summary with '-h')
````

$ ocx version
````
0.6.5
````

$ gh release view v0.3.0 -R ocx-sh/find_ocx
````
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
````

$ gh api repos/ocx-sh/find_ocx/readme --jq .content | base64 -d
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

## Quick start

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
[... 29 lines elided]
```

## License

Apache-2.0. See [LICENSE](LICENSE).
````

$ curl -sSL -o /dev/null -w "%{http_code} %{url_effective}\n" https://ocx.sh/integrations/cmake/
````
200 https://ocx.sh/integrations/cmake/
````

$ curl -sSL -o /dev/null -w "%{http_code} %{url_effective}\n" https://ocx-sh.github.io/find_ocx/
````
200 https://ocx-sh.github.io/find_ocx/
````

$ curl -sSL https://ocx.sh/integrations/cmake/ | sed -e "s/<script[^>]*>.*<\/script>//g" | sed -e "s/<[^>]*>/ /g" | grep -v "^\s*$" | head -150
````
      edit this page ↗    report an issue ↗               integrations    find_ocx     find_ocx        
 find_ocx runs pinned, sha256-verified tools such as  jq  or  shellcheck  from your CMake build, using the  OCX  package manager. 
    examples/project/CMakeLists.txt       # The ocx.toml next to this file is found by the upward search; the lock      # is verified; nothing is pulled yet (lazy). NAME picks the prefix of the      # result variables: NAME TOOLS -&gt; OCX_TOOLS_RUN, OCX_TOOLS_RUN_JQ      # (defaults to PROJECT -&gt; OCX_PROJECT_RUN).      ocx_project(  NAME   TOOLS BINS jq)     
     # Build-time tool use, lazily materialized on first execution. Generator      # expressions compose naturally - the command is a plain CMake list.      add_custom_target  (validate ALL          COMMAND     ${OCX_TOOLS_RUN}   jq -n -e --arg config   "$&lt;CONFIG&gt;"                    [[$config | length &gt;= 0]]            VERBATIM      )          OCX_TOOLS_RUN, OCX_TOOLS_RUN_JQ# (defaults to PROJECT -> OCX_PROJECT_RUN).ocx_project(NAME TOOLS BINS jq)# Build-time tool use, lazily materialized on first execution. Generator# expressions compose naturally - the command is a plain CMake list.add_custom_target(validate ALL  COMMAND ${OCX_TOOLS_RUN} jq -n -e --arg config &quot;$ &quot;          [[$config | length >= 0]]  VERBATIM)">      
      Terminal window       cmake -S . -B build &amp;&amp; cmake --build build               
  Run jq in a CMake build  walks through this example step by step. 
 You need CMake 3.19 and network access or a mirror.
You do not need to install  ocx .
An  ocx  on  PATH  is used when present, otherwise the pinned CLI is bootstrapped on first configure into a per-machine cache.
 Findocx.cmake  alone works on CMake 3.15. 
  Pick a goal         Section titled “Pick a goal”   
  Run workspace tools from ocx.toml : launchers, groups and generator expressions 
  Pin and freeze tag resolution : an index snapshot or per-platform digests 
  Use find_package with find_ocx : find the CLI, or search a pulled package 
  Reproduce the build in CI : Linux, macOS and Windows with one configuration 
  Build behind a mirror or offline : mirrors, credentials and no downloads 
  Cross-build with foreign-platform content : content for a platform other than the host 
  Update the vendored files : refresh  ocx.cmake  and  Findocx.cmake  
  Fix a failing configure : nested builds, floating tags and stale locks 
  Understand it         Section titled “Understand it”   
  How find_ocx works  
  Two entry points  
  Reproducible first  
  Lazy versus eager  
  Look it up         Section titled “Look it up”   
  Commands ,  variables  and  Findocx.cmake  
  Examples : the four tested projects in  examples/  
       Next  Tutorial       discord · roadmap · security   Apache-2.0 · © 2026 The OCX Authors             
````

$ curl -sSL https://ocx.sh/integrations/cmake/ | grep -o "href=\"[^\"]*cmake[^\"]*\"" | sort -u
````
href="https://ocx.sh/integrations/cmake/"
href="/integrations/cmake/"
href="/integrations/cmake/_astro/common.D5bcivre.css"
href="/integrations/cmake/_astro/ec.9greh.css"
href="/integrations/cmake/_astro/fonts/0afc56df7fe9322d.woff2"
href="/integrations/cmake/_astro/fonts/9be50d119b1fd79e.woff2"
href="/integrations/cmake/_astro/fonts/a2a359f1fdc16ef0.woff2"
href="/integrations/cmake/_astro/fonts/a3a0a8110b9e369d.woff2"
href="/integrations/cmake/_astro/print.ehPL0gv-.css"
href="/integrations/cmake/concepts/entry-points/"
href="/integrations/cmake/concepts/how-it-works/"
href="/integrations/cmake/concepts/lazy-vs-eager/"
href="/integrations/cmake/concepts/reproducible-first/"
href="/integrations/cmake/favicon.svg"
href="/integrations/cmake/guides/ci/"
href="/integrations/cmake/guides/cross-build/"
href="/integrations/cmake/guides/find-package/"
href="/integrations/cmake/guides/mirror/"
href="/integrations/cmake/guides/nested-builds/"
href="/integrations/cmake/guides/pin-and-freeze/"
href="/integrations/cmake/guides/update-vendored/"
href="/integrations/cmake/guides/workspace-tools/"
href="/integrations/cmake/reference/commands/"
href="/integrations/cmake/reference/examples/"
href="/integrations/cmake/reference/examples-discovery/"
href="/integrations/cmake/reference/examples-packages/"
href="/integrations/cmake/reference/findocx/"
href="/integrations/cmake/reference/variables/"
href="/integrations/cmake/sitemap-index.xml"
href="/integrations/cmake/tutorial/"
````

$ curl -sSL https://ocx-sh.github.io/find_ocx/ | grep -o "href=\"[^\"]*\"" | sort -u | head -40
````
href="#"
href="#corporate-mirrors"
href="examples.html"
href="examples.html#ad-hoc-packages-ocx-package"
href="examples.html#classic-discovery-find-package"
href="examples.html#project-shipped-index-snapshot-ocx"
href="examples.html#running-them"
href="examples.html#workspace-toolchain-ocx-project"
href="#find-ocx"
href="#furo-main-content"
href="genindex.html"
href="https://github.com/ocx-sh/find_ocx/blob/main/docs/index.rst?plain=true"
href="https://github.com/ocx-sh/find_ocx/edit/main/docs/index.rst"
href="https://github.com/ocx-sh/find_ocx/releases"
href="https://github.com/ocx-sh/rules_ocx"
href="https://github.com/ocx-sh/setup.ocx.sh"
href="https://github.com/pradyunsg/furo"
href="https://ocx.sh"
href="https://pradyunsg.me"
href="https://www.sphinx-doc.org/"
href="#index-snapshots-reproducible-first"
href="#lazy-vs-eager"
href="#quick-start"
href="reference.html"
href="reference.html#command:ocx_package"
href="reference.html#command:ocx_project"
href="reference.html#findocx"
href="reference.html#ocx"
href="search.html"
href="_static/pygments.css?v=d111a655"
href="_static/styles/furo.css?v=7bdb33bb"
href="_static/styles/furo-extensions.css?v=8dab3a3b"
href="#svg-arrow-right"
href="#svg-eye"
href="#svg-menu"
href="#svg-moon"
href="#svg-moon-with-sun"
href="#svg-pencil"
href="#svg-sun"
href="#svg-sun-with-moon"
````

$ txt.sh https://ocx.sh/integrations/cmake/guides/find-package/
````
Use find_package with find_ocx | find_ocxSkip to contentGitHub
edit this page ↗
report an issue ↗
Use find_package with find_ocx
Use this page to find the ocx
 CLI the classic way with find_package(ocx)
, and to let a later find_package(<name>)
 search content that find_ocx provisioned.
Find the ocx CLI
Section titled “Find the ocx CLI”
Use find_package(ocx)
 when a system ocx
 should win over the pinned bootstrap.
The module honors -DOCX_EXECUTABLE
, searches PATH
, and defines the ocx::ocx
 imported target.
examples/find_package/CMakeLists.txtcmake_minimum_required(VERSION 3.15)
project(ocx_example_find_package LANGUAGES NONE)
enable_testing()
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../..")
find_package(ocx REQUIRED)
message(STATUS "example: ocx ${OCX_VERSION_STRING} at ${OCX_EXECUTABLE}")
add_test(NAME ocx_version COMMAND ocx::ocx version)
Configure and test it. -DOCX_BOOTSTRAP=ON
 falls back to the pinned CLI when none is found.
Terminal windowcmake -S . -B build -DOCX_BOOTSTRAP=ON && ctest --test-dir build
The module needs CMake 3.15, or 3.19 with ocx.cmake
 next to Findocx.cmake
 when you use the bootstrap.
To choose between this and include(ocx)
, see Two entry points.
Make find_package search a pulled package
Section titled “Make find_package search a pulled package”
Pull a package at configure time with PULL
.
find_ocx then sets <name>_ROOT
 to the package content root, following policy CMP0074.
A later find_package(<name>)
 or find_library
 call searches that content.
examples/package/CMakeLists.txtset(OCX_ALLOW_FLOATING ON)
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest PULL)
unset(OCX_ALLOW_FLOATING)
message(STATUS "example: jq content at ${jq_ROOT}")
Add NO_ROOT
 to suppress the export.
To pull every package at configure time, for example in CI, configure with -DOCX_PULL=ON
.
The example opts out of the floating-tag check on purpose.
In your project, freeze the tag first: see Pin and freeze tag resolution.
Needs addressed: problems 4 and 7 of the use-case research.
PreviousPin and freeze tag resolutionNextUpdate the vendored files
````

$ txt.sh https://ocx.sh/integrations/cmake/reference/commands/
````
Commands | find_ocxSkip to contentGitHub
edit this page ↗
report an issue ↗
Commands
Reference for the four commands that ocx.cmake
 defines.
This page is generated from the .. command::
 blocks in the module source.
ocx_bootstrap
Section titled “ocx_bootstrap”
Downloads a pinned ocx CLI release for the host and sets OCX_EXECUTABLE
:
ocx_bootstrap([VERSION <version>] [TRIPLE <target-triple>])
] [TRIPLE ])">
No-op when OCX_EXECUTABLE
 already points at a binary of the requested version. The release row (URL + sha256) comes from the dist.json snapshot embedded in this file; OCX_INSTALL_DIST_URL
 fetches a mirrored manifest instead, OCX_INSTALL_MIRROR_URL
 rewrites the artifact download to <mirror>/<tag>/<filename>
. The manifest sha256 is enforced either way. Binaries land in the per-machine OCX_BOOTSTRAP_CACHE
 (downloaded once per machine, shared by all build trees).
ocx_project
Section titled “ocx_project”
Provisions the toolchain of a workspace ocx.toml
 + ocx.lock
:
ocx_project([NAME <name>] [TOML <ocx.toml>] [LOCK <ocx.lock>]
            [GROUPS <group>...] [BINS <tool>...]
            [PLATFORM <ocx-platform>] [PULL])
] [TOML ] [LOCK ]            [GROUPS ...] [BINS ...]            [PLATFORM ] [PULL])">
NAME
 (default PROJECT
) prefixes the exported result variables, which are global cache-internal values usable from any directory:
OCX_<NAME>_RUN
Command-list prefix that composes the project environment and runs any tool on it (lazy: content materializes on first execution):
add_custom_command(... COMMAND ${OCX_PROJECT_RUN} jq . in > out)
 out)">
OCX_<NAME>_RUN_<BIN>
Per-tool convenience command for every name in BINS
. Entries are executable names on the composed environment (a package may ship several tools), not package references.
TOML
[... 100 lines elided]
add_custom_target(index-update COMMAND ${refresh} VERBATIM)
# or, in script mode:
execute_process(COMMAND ${refresh} COMMAND_ERROR_IS_FATAL ANY)
Deliberately no built-in target or ctest wiring: a “test” that rewrites a committed file would let CI paper over drift instead of failing. The freshness gate is the frozen configure itself — a tag missing from the snapshot fails with the exit-81 refresh hint. Run the command, review the diff, commit.
PreviousLazy versus eagerNextVariables
````

$ txt.sh https://ocx.sh/integrations/cmake/guides/pin-and-freeze/
````
Pin and freeze tag resolution | find_ocxSkip to contentGitHub
edit this page ↗
report an issue ↗
Pin and freeze tag resolution
Use a committed .ocx/
 index snapshot or per-platform digests so a floating tag such as :latest
 resolves the same way on every machine.
Without one of them, a floating tag is a hard configure error.
Commit an index snapshot
Section titled “Commit an index snapshot”
Create the snapshot for the packages you use and commit it like a lock file.
Terminal windowocx --index .ocx index update ocx.sh/jqlang/jq ocx.sh/kitware/cmake
git add .ocx
Then fail fast in CMakeLists.txt
 when the snapshot is missing.
examples/frozen_index/CMakeLists.txt# Fail-fast when the snapshot is missing, and lock the discovered .ocx/
# into OCX_INDEX for this directory and below. (Each ocx_package would
# also discover it on its own - FIND REQUIRED makes the intent explicit.)
ocx_index(FIND REQUIRED)
# Floating tag, no INDEX argument, no digests: resolves frozen from the
# committed snapshot (.ocx/ocx.sh/p/jqlang/jq.json).
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest BINS jq NO_ROOT)
Each ocx_package
 call discovers the nearest .ocx/
 directory by itself.
The ocx_index(FIND REQUIRED)
 call only makes the intent explicit.
Refresh the snapshot on purpose
Section titled “Refresh the snapshot on purpose”
Snapshots are never updated automatically.
Compose the refresh command and decide how it runs. Here it is a build target.
examples/frozen_index/CMakeLists.txtocx_index(UPDATE_COMMAND refresh)
add_custom_target(index-update
  COMMAND ${refresh}
  COMMAND ${CMAKE_COMMAND} -E echo
    "index snapshot refreshed - review the diff and commit the result"
  VERBATIM)
Run cmake --build build --target index-update
.
Review the diff of .ocx/
[... 26 lines elided]
examples/package/CMakeLists.txtocx_package(NAME jq_frozen PACKAGE ocx.sh/jqlang/jq:latest BINS jq NO_ROOT
  INDEX "${CMAKE_CURRENT_SOURCE_DIR}/index")
For why a floating tag is an error, see Reproducible first.
Needs addressed: problem 3 of the use-case research.
PreviousRun workspace tools from ocx.tomlNextUse find_package with find_ocx
````

$ mkdir -p proj/cmake dl && cd dl && gh release download v0.3.0 -R ocx-sh/find_ocx && ls -la && sha256sum -c SHA256SUMS && cp ocx.cmake Findocx.cmake ../proj/cmake/
````
total 100
drwxr-xr-x 2 mherwig mherwig   100 Oct 10 18:44 .
drwxr-xr-x 5 mherwig mherwig   160 Oct 10 18:44 ..
-rw-r--r-- 1 mherwig mherwig  2891 Oct 10 18:44 Findocx.cmake
-rw-r--r-- 1 mherwig mherwig 90806 Oct 10 18:44 ocx.cmake
-rw-r--r-- 1 mherwig mherwig   156 Oct 10 18:44 SHA256SUMS
Findocx.cmake: OK
ocx.cmake: OK
````

$ ocx package install --help
````
Install packages from a local or remote index (no `ocx.toml` touched)

Usage: ocx package install [OPTIONS] <PACKAGES>...

Arguments:
  <PACKAGES>...
          Package identifiers to install

Options:
  -s, --select
          Also set the installed version as current (creates the current symlink)

      --link <PATH>
          Also link the installed package at PATH, which keeps it from `ocx clean` while the link exists.
          
          Takes exactly one package. PATH must be absent or a link an earlier `--link` wrote; anything else is refused (exit 65). Delete the link to release the package. Read it back with `--link` on `package which`, `package env` or `package exec`.

  -p, --platform <PLATFORM>
          Target platform to resolve packages against.
          
          The value is `os/arch[/variant][+feature[,feature...]]`, for example `linux/amd64`, `linux/arm64`, or `linux/amd64+libc.glibc`. The optional `+feature` suffix filters by `os.features`: OCX selects the manifest whose features are a subset of the value you pass, so `+libc.glibc` or `+libc.musl` forces a specific libc variant. WebAssembly targets (`wasip1/wasm`, `wasip2/wasm`) are reachable only by naming them here. Defaults to the host platform. <https://ocx.sh/docs/authoring/multi-platform>

      --verify
          Verify the package's Sigstore signature before installing (default).
          
          When a `[[trust.policy]]` covers the package, its keyless Sigstore signature is verified before the package is installed; a failure aborts the install fail-closed. Overrides an `OCX_NO_VERIFY` opt-out for this invocation.

      --no-verify
          Skip Sigstore signature verification. Equivalent env var: `OCX_NO_VERIFY`

  -h, --help
          Print help (see a summary with '-h')
````

$ which cmake ninja jq; cmake --version | head -1
````
/home/mherwig/dev/find_ocx/.ocx/toolchain/links/default/cmake/content/bin/cmake
/home/mherwig/dev/find_ocx/.ocx/toolchain/links/default/ninja/content/ninja
/usr/sbin/jq
cmake version 3.31.12
````

$ ocx package install -p linux/amd64 ocx.sh/jqlang/jq:1.8.2
````
Installing packages: ocx.sh/jqlang/jq:1.8.2
pulling count=1
Downloading layer sha256:88ad916b0507 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/ocxhome/temp/9c13e7a59201751a36e83176bff4a013
Package                 Version                 Path                                                                                                                                                                                 
ocx.sh/jqlang/jq:1.8.2  ocx.sh/jqlang/jq:1.8.2  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/ocxhome/symlinks/ocx.sh/jqlang/jq/candidates/1.8.2
````

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake --version
````
Package 'ocx.sh/kitware/cmake:4' not found locally, pulling.
Downloading layer sha256:61c5ceac1af3 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/ocxhome/temp/5d1c38a94867e65acad24f47e861cc47
cmake version 4.4.4

CMake suite maintained and supported by Kitware (kitware.com/cmake).
````

$ ocx --json package install -p linux/amd64 ocx.sh/jqlang/jq:1.8.2
````
Installing packages: ocx.sh/jqlang/jq:1.8.2
pulling count=1
{
  "ocx.sh/jqlang/jq:1.8.2": {
    "identifier": "ocx.sh/jqlang/jq:1.8.2@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": {
      "type": "bundle",
      "version": 1,
      "env": [
        {
          "key": "PATH",
          "type": "path",
          "required": true,
          "value": "${installPath}",
          "visibility": "public"
        }
      ],
      "binaries": [
        "jq"
      ]
    },
    "path": "/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/ocxhome/symlinks/ocx.sh/jqlang/jq/candidates/1.8.2"
  }
}
````

$ ocx package --help
````
Operations related to packages (e.g. bundling or deploying)

Usage: ocx package <COMMAND>

Commands:
  announce     Observe an owner-curated set of registry tags and publish the rebuilt entry into the index
  attest       Attach an in-toto attestation to a published package manifest
  cascade      Audit and repair the rolling tags a published package cascades into
  claim        Claim a package in the index so its tags can be announced
  copy         Promote an already-published package to another registry or repository
  create       Creates an archive from a local package directory
  description  Publish or fetch a package repository's catalog description
  deps         Show the dependency tree for one or more installed packages
  env          Print the resolved environment variables for one or more installed packages
  inspect      Inspect one or more package references (candidates, metadata, or resolution chain)
  install      Install packages from a local or remote index (no `ocx.toml` touched)
  prune        Delete tags from a package's registry repository, guarded by the index
  pull         Downloads packages into the local object store without creating install symlinks
  push         Publish a package's layers and metadata to a registry
  receipt      Print the build receipt `ocx package create` wrote beside a bundle
  sbom         List or extract the SBOM attestations a published package carries
  select       Set the current version of one or more packages
  deselect     Remove the current-version symlink for one or more packages
  sign         Sign a published package's manifest (keyless Sigstore, via OCI Referrers)
  test         Materialize a package locally (no registry round-trip) and run a command in its env
  verify       Verify a published package's Sigstore signature (keyless, via OCI Referrers)
  exec         Runs installed packages [alias: x]
  uninstall    Remove an installed candidate for one or more packages
  which        Resolve installed packages and print their package-root (or, with `--candidate`/`--current`, install-symlink) paths

Options:
  -h, --help  Print help
````

$ cat proj/CMakeLists.txt
````
cmake_minimum_required(VERSION 3.19)
project(tomas_jq LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)

ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:1.8.2 PULL
  PINS
    "linux/amd64=sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    "linux/arm64=sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
    "darwin/amd64=sha256:f750c91d28769d12298ba9a4c10340152fcbdd48c48102bf275c21d736cc72a2"
    "darwin/arm64=sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1"
    "windows/amd64=sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989"
)
message(STATUS "jq_ROOT=${jq_ROOT}")
find_program(JQ_EXE jq)
message(STATUS "JQ_EXE=${JQ_EXE}")
````

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build
````
-- find_ocx: using ocx from PATH (/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead
-- jq_ROOT={
  "kind" : "package",
  "path" : "/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/ocxhome/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e"
}/content
-- JQ_EXE=/usr/sbin/jq
-- Configuring done (0.0s)
CMake Warning:
  Value of jq_ROOT contained a newline; truncating


CMake Warning:
  Value of OCX_JQ_CONTENT contained a newline; truncating


CMake Warning:
  Value of __OCX_R_JQ_GUARD contained a newline; truncating


-- Generating done (0.0s)
CMake Warning:
  Value of jq_ROOT contained a newline; truncating


CMake Warning:
  Value of OCX_JQ_CONTENT contained a newline; truncating


CMake Warning:
  Value of __OCX_R_JQ_GUARD contained a newline; truncating


-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/proj/build
````

$ env | grep -i ocx | sed "s/=.*//"; which ocx; ocx version
````
OCX_NO_UPDATE_CHECK
WSL_DISTRO_NAME
__OCX_ENV_STATE
PWD
OTEL_EXPORTER_OTLP_ENDPOINT
GRAFANA_URL
OCX_HOME
PATH
OLDPWD
/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx
0.6.5
````

$ ocx package which ocx.sh/jqlang/jq:1.8.2
````
Package                 Kind     Path                                                                                                                                                                                               
ocx.sh/jqlang/jq:1.8.2  package  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/ocxhome/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e
````

$ ocx package which --help
````
Resolve installed packages and print their package-root (or, with `--candidate`/`--current`, install-symlink) paths

Usage: ocx package which [OPTIONS] <PACKAGE>...

Arguments:
  <PACKAGE>...
          Package identifiers to resolve

Options:
  -p, --platform <PLATFORM>
          Target platform to resolve packages against.
          
          The value is `os/arch[/variant][+feature[,feature...]]`, for example `linux/amd64`, `linux/arm64`, or `linux/amd64+libc.glibc`. The optional `+feature` suffix filters by `os.features`: OCX selects the manifest whose features are a subset of the value you pass, so `+libc.glibc` or `+libc.musl` forces a specific libc variant. WebAssembly targets (`wasip1/wasm`, `wasip2/wasm`) are reachable only by naming them here. Defaults to the host platform. <https://ocx.sh/docs/authoring/multi-platform>

      --candidate
          Resolve the content path via the installed candidate symlink (`~/.ocx/symlinks/<registry>/<repo>/candidates/<tag>`).
          
          The package must be installed before this flag can be used. Digest identifiers are rejected - use a tag-only identifier instead. No auto-install is performed.

      --current
          Resolve the content path via the current-selected symlink (`~/.ocx/symlinks/<registry>/<repo>/current`).
          
          A version of the package must be selected before this flag can be used. Digest identifiers are rejected. The tag portion of the identifier is not validated against the selected version - only the registry and repository are used to locate the symlink. No auto-install is performed.

      --link <PATH>
          Resolve the content path via a link written by `ocx package install --link <PATH>`.
          
          Takes exactly one package, whose identifier names it in the output. Digest identifiers are rejected. No auto-install is performed.

      --lazy-mode <MODE>
          Control when a package's content downloads: now, or on first use.
          
          `never` composes eagerly: a package's content is materialized before its binaries reach `PATH`. `always` composes a shim: the declared names are on `PATH` immediately and the content downloads when one of them first runs.
          
          When omitted, read from `ocx.toml` (the package entry, then the group, then the top-level `lazy-mode` key), then `OCX_LAZY_MODE`, else `never`; the flag overrides all of them. Resolution order in full: https://ocx.sh/docs/reference/command-line#arg-lazy-mode
          
          [possible values: never, always]

  -h, --help
          Print help (see a summary with '-h')
````

$ ocx --json package which ocx.sh/jqlang/jq:1.8.2
````
{
  "ocx.sh/jqlang/jq:1.8.2": {
    "path": "/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/ocxhome/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e",
    "kind": "package"
  }
}
````

$ txt.sh https://ocx.sh/integrations/cmake/reference/variables/
````
Variables | find_ocxSkip to contentGitHub
edit this page ↗
report an issue ↗
Variables
Reference for the OCX_*
 variables of ocx.cmake
.
This page is generated from the .. variable::
 blocks in the module source.
CMake support for OCX — the OCI-backed package manager. Bootstraps the pinned ocx
 CLI (sha256-enforced, corporate-mirror aware) and provisions tools through it. find_ocx deliberately never re-implements OCX internals in CMake: all resolution goes through the ocx
 binary; the durable contracts are ocx.lock
 digests and the OCI manifests.
Vendor this file together with Findocx.cmake
 into your project (e.g. cmake/
), then:
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)
ocx_project()                    # toolchain from ./ocx.toml + ./ocx.lock
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest)   # frozen via ./.ocx snapshot
Requires CMake 3.19 (string(JSON)
, file(ARCHIVE_EXTRACT)
). Include after project()
.
Resolution is reproducible-first: a floating tag resolves through a committed index snapshot (the nearest .ocx/
 directory, discovered like ocx.toml
; create it with ocx --index .ocx index update <package>
) or through digest pins — with neither, the configure fails (OCX_ALLOW_FLOATING
 is the explicit escape hatch).
include(ocx)
 itself is passive — it only defines commands and snapshots the OCX_*
 knobs. The first provisioning call (ocx_project
, ocx_package
, or an explicit ocx_bootstrap
) resolves the CLI: OCX_EXECUTABLE
 when set, else an ocx
 on PATH
, else it downloads the pinned, sha256-verified CLI into the per-machine cache. OCX_BOOTSTRAP=ALWAYS
 skips the PATH
 search (hermeticity: every machine runs the identical pinned binary); OCX_BOOTSTRAP=OFF
[... 114 lines elided]
 -DOCX_INDEX=
.
OCX_AUTH_<REGISTRY>_{TYPE,USER,TOKEN}
 credentials are deliberately never snapshotted into the cache — export them in the environment and reconfigure after changing them.
PreviousCommandsNextFindocx.cmake
````

$ rm -rf build && ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build -DOCX_BOOTSTRAP=ALWAYS
````
-- find_ocx: using bootstrapped ocx 0.3.11 (/home/mherwig/.cache/find_ocx/0.3.11/x86_64-unknown-linux-musl/ocx)
-- jq_ROOT=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/ocxhome/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content
-- JQ_EXE=/usr/sbin/jq
-- Configuring done (0.2s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/proj/build
````

$ ls -la ocxhome/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content
````
total 2216
drwxr-xr-x 2 mherwig mherwig      60 Oct 10 18:44 .
drwxr-xr-x 4 mherwig mherwig     180 Oct 10 18:44 ..
-rwxr-xr-x 2 mherwig mherwig 2267912 Jul 24  2006 jq
````

$ txt.sh https://ocx.sh/integrations/cmake/concepts/how-it-works/
````
How find_ocx works | find_ocxSkip to contentGitHub
edit this page ↗
report an issue ↗
How find_ocx works
This page explains what find_ocx does at configure and build time, and why it keeps all resolution inside the ocx
 binary.
Why it never re-implements ocx
Section titled “Why it never re-implements ocx”
find_ocx deliberately never re-implements OCX internals in CMake.
All resolution goes through the ocx
 binary.
The durable contracts are the ocx.lock
 digests and the OCI manifests, so CMake code never has to track how ocx resolves a tag.
What happens, in order
Section titled “What happens, in order”
ocx_bootstrap()
 runs implicitly on first use.
It downloads the pinned ocx release listed in the dist.json snapshot embedded in ocx.cmake
, checks its sha256, and stores it in ~/.cache/find_ocx
.
All build trees on the machine share that cache.
ocx_project()
 and ocx_package()
 shell out to that binary.
They run ocx lock --check
 as a staleness gate every time.
Eager mode adds ocx pull
 or ocx package install
, and foreign platforms use ocx --format json env
.
The exported OCX_<NAME>_RUN
 variables are plain CMake command lists.
They re-enter ocx run
 or ocx package exec
, so no wrapper scripts are needed and generator expressions compose.
Content materializes lazily on first execution into the shared, content-addressed OCX_HOME
 store.
Reconfigures are memoized by input fingerprints.
With unchanged inputs no ocx
 process starts, and -DOCX_REFRESH=ON
 bypasses the memo once.
Where to go next
Section titled “Where to go next”
Two entry points explains which binary runs.
Lazy versus eager explains when the network is touched.
Reproducible first explains why a floating tag is an error.
PreviousFix a failing configureNextTwo entry points
````

$ txt.sh https://ocx.sh/integrations/cmake/tutorial/ | head -120
````
Run jq in a CMake build without installing it | find_ocxSkip to contentGitHub
edit this page ↗
report an issue ↗
Run jq in a CMake build without installing it
In this tutorial you add find_ocx to a CMake project and run jq
 from a build target.
You never install jq
 on your machine.
You need CMake 3.19 or later.
You also need the ocx
 CLI once, to write the lock file (install it).
find_ocx downloads its own pinned ocx
 for the build.
Vendor the two files
Section titled “Vendor the two files”
Download Findocx.cmake
 and ocx.cmake
 from the release assets.
Put both in a cmake/
 directory of an empty project.
Check that cmake/ocx.cmake
 and cmake/Findocx.cmake
 exist next to where your CMakeLists.txt
 will be.
Pin the tool
Section titled “Pin the tool”
Create ocx.toml
 next to the cmake/
 directory.
ocx.toml[tools]
jq = "ocx.sh/jqlang/jq:latest"
Write the lock file and keep both files in version control.
Terminal windowocx lock
Check that ocx.lock
 exists. It holds the exact digest of jq
.
Declare the project
Section titled “Declare the project”
Create CMakeLists.txt
 with the project header.
[... 52 lines elided]
Run workspace tools from ocx.toml to add more tools and groups.
Pin and freeze tag resolution to use ocx_package
 without a project file.
How find_ocx works for what ran under the hood.
PreviousOverviewNextRun workspace tools from ocx.toml
````

$ for p in guides/workspace-tools guides/ci guides/cross-build guides/mirror guides/nested-builds concepts/entry-points concepts/lazy-vs-eager concepts/reproducible-first reference/examples reference/examples-packages reference/examples-discovery reference/findocx; do echo "== $p"; txt.sh https://ocx.sh/integrations/cmake/$p/ | grep -n -i -E "find_program|find_package|_ROOT|CMP0074|PREFIX_PATH"; done
````
== guides/workspace-tools
== guides/ci
37:    # the bootstrap fallback for the find_package one.
46:, which only matters for the find_package
== guides/cross-build
19:ocx_package(NAME JQ_ARM PACKAGE ocx.sh/jqlang/jq:latest PLATFORM linux/arm64 NO_ROOT)
== guides/mirror
== guides/nested-builds
== concepts/entry-points
6: and find_package(ocx)
12:find_package(ocx REQUIRED)
15:, checks the version via find_package_handle_standard_args
21: cache variable — set by you, by a previous find_package(ocx)
29: opt-in under find_package(ocx)
39: is the optional classic front door for projects that want find_package
41:To use the find module, see Use find_package with find_ocx.
== concepts/lazy-vs-eager
10: (global, recommended for CI) materializes at configure time and enables the <name>_ROOT
== concepts/reproducible-first
== reference/examples
61:, the project-shipped index snapshot and classic find_package
== reference/examples-packages
9:No project file at all — pull straight from the registry, floating or digest-pinned per platform, with an optional <name>_ROOT
10: export that makes a later find_package()
12: search the OCX-provisioned content (CMP0074).
22:# digests below were generated in the first place. Exports jq_ROOT
23:# (CMP0074) - a subsequent find_package(jq)/find_program would search the
28:message(STATUS "example: jq content at ${jq_ROOT}")
32:ocx_package(NAME jq_pinned PACKAGE ocx.sh/jqlang/jq:1.8.2 BINS jq NO_ROOT
53:ocx_package(NAME jq_frozen PACKAGE ocx.sh/jqlang/jq:latest BINS jq NO_ROOT
58:` or the ocx.lock of a project);# nothing is fetched until the first execution.ocx_package(NAME jq_pinned PACKAGE ocx.sh/jqlang/jq:1.8.2 BINS jq NO_ROOT  PINS    "linux/amd64=sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"    "linux/arm64=sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"    "darwin/amd64=sha256:f750c91d28769d12298ba9a4c10340152fcbdd48c48102bf275c21d736cc72a2"    "darwin/arm64=sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1"    "windows/amd64=sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989")add_custom_target(pretty ALL  COMMAND ${OCX_JQ_PINNED_RUN_JQ} . "${CMAKE_CURRENT_SOURCE_DIR}/data.json"  VERBATIM)add_test(NAME jq_pinned_filter  COMMAND ${OCX_JQ_PINNED_RUN_JQ} -e ".target == \"cmake\""          "${CMAKE_CURRENT_SOURCE_DIR}/data.json")# Frozen-index + lazy with an explicit INDEX override: the tag resolves# from the committed snapshot (index/ocx.sh/p/jqlang/jq.json) - reproducible# without digests in this file. Prefer a project-shipped .ocx/ directory# (auto-discovered; see the frozen_index example); an explicit INDEX# points anywhere. Refresh deliberately (compose the command with# ocx_index(UPDATE_COMMAND ...)), review the diff, commit.ocx_package(NAME jq_frozen PACKAGE ocx.sh/jqlang/jq:latest BINS jq NO_ROOT  INDEX "${CMAKE_CURRENT_SOURCE_DIR}/index")add_test(NAME jq_frozen_filter  COMMAND ${OCX_JQ_FROZEN_RUN_JQ} -e ".target == \"cmake\""          "${CMAKE_CURRENT_SOURCE_DIR}/data.json")">
== reference/examples-discovery
22:ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest BINS jq NO_ROOT)
43:Classic discovery (find_package)
44:Section titled “Classic discovery (find_package)”
49:examples/find_package/CMakeLists.txtcmake_minimum_required(VERSION 3.15)
50:project(ocx_example_find_package LANGUAGES NONE)
53:find_package(ocx REQUIRED)
== reference/findocx
11:find_package(ocx [<version>] [REQUIRED])
32:find_package(ocx REQUIRED)   # -DOCX_BOOTSTRAP=ON => zero-setup corporate UX
````

$ cat >> proj/CMakeLists.txt   # appended lines
````
find_program(JQ_HINT jq HINTS ${jq_ROOT})
message(STATUS "JQ_HINT=${JQ_HINT}")
find_package(jq QUIET)
message(STATUS "jq_FOUND=${jq_FOUND}")
````

$ rm -rf build && ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build -DOCX_BOOTSTRAP=ALWAYS --log-level=VERBOSE 2>&1 | grep -v "^-- Looking\|^-- Check" | head -60
````
-- find_ocx: using bootstrapped ocx 0.3.11 (/home/mherwig/.cache/find_ocx/0.3.11/x86_64-unknown-linux-musl/ocx)
-- jq_ROOT=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/ocxhome/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content
-- JQ_EXE=/usr/sbin/jq
-- JQ_HINT=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/ocxhome/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content/jq
-- jq_FOUND=0
-- Configuring done (0.1s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-find-package-sees-ocx-content/proj/build
````

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake --help-policy CMP0074 | head -20
````
CMP0074
-------

.. versionadded:: 3.12

``find_package()`` uses ``<PackageName>_ROOT`` variables.

In CMake 3.12 and above the ``find_package(<PackageName>)`` command now
searches prefixes specified by the ``<PackageName>_ROOT`` CMake
variable and the ``<PackageName>_ROOT`` environment variable.
Package roots are maintained as a stack so nested calls to all ``find_*``
commands inside find modules and config packages also search the roots as
prefixes.  This policy provides compatibility with projects that have not been
updated to avoid using ``<PackageName>_ROOT`` variables for other purposes.

The ``OLD`` behavior for this policy is to ignore ``<PackageName>_ROOT``
variables.  The ``NEW`` behavior for this policy is to use
``<PackageName>_ROOT`` variables.

This policy was introduced in CMake version 3.12.
````

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake --help-command find_program | grep -n -i -B2 -A6 "_ROOT" | head -40
````
20-           [REQUIRED|OPTIONAL]
21-           [NO_DEFAULT_PATH]
22:           [NO_PACKAGE_ROOT_PATH]
23-           [NO_CMAKE_PATH]
24-           [NO_CMAKE_ENVIRONMENT_PATH]
25-           [NO_SYSTEM_ENVIRONMENT_PATH]
26-           [NO_CMAKE_SYSTEM_PATH]
27-           [NO_CMAKE_INSTALL_PREFIX]
28:           [CMAKE_FIND_ROOT_PATH_BOTH |
29:            ONLY_CMAKE_FIND_ROOT_PATH |
30:            NO_CMAKE_FIND_ROOT_PATH]
31-          )
32-
33-This command is used to find a program.
34-
35-Prior to searching, find_program checks if variable ``<VAR>`` is defined. If
36-the variable is not defined, the search will be performed. If the variable is
--
159-   Specifically, search paths specified by the following variables, in order:
160-
161:   a. ``<PackageName>_ROOT`` CMake variable,
162-      where ``<PackageName>`` is the case-preserved package name.
163-
164:   b. ``<PACKAGENAME>_ROOT`` CMake variable,
165-      where ``<PACKAGENAME>`` is the upper-cased package name.
166-      See policy ``CMP0144``.
167-
168-      .. versionadded:: 3.27
169-
170:   c. ``<PackageName>_ROOT`` environment variable,
171-      where ``<PackageName>`` is the case-preserved package name.
172-
173:   d. ``<PACKAGENAME>_ROOT`` environment variable,
174-      where ``<PACKAGENAME>`` is the upper-cased package name.
175-      See policy ``CMP0144``.
176-
177-      .. versionadded:: 3.27
178-
179-   The package root variables are maintained as a stack, so if called from
--
````

## Friction

1. **Pass 1 configure with the documented default (ocx from PATH) yields a broken `jq_ROOT`.** With `ocx` 0.6.5 on PATH, `jq_ROOT` was set to a multi-line JSON object (`{ "kind" : "package", "path" : ... }/content`), CMake warned "Value of jq_ROOT contained a newline; truncating" (also for `OCX_JQ_CONTENT` and `__OCX_R_JQ_GUARD`), and configure still exited 0. The success criterion could not be met by following the Quick start. The docs describe PATH ocx as the default ("An ocx on PATH is used when present") and give no supported-ocx-version range for find_ocx v0.3.0; the README and the tutorial say nothing about CLI version compatibility. Severity: blocker. Looked in: README Quick start, guides/find-package, reference/variables (`OCX_BOOTSTRAP`).
2. **The only way out was a guess.** Nothing in the warning or in the docs connects the symptom to the PATH ocx version. I found `-DOCX_BOOTSTRAP=ALWAYS` only by reading the variables reference for anything about which binary runs; it worked (bootstrapped ocx 0.3.11, `jq_ROOT` correct). Severity: major. Looked in: reference/variables, concepts/entry-points, guides/nested-builds.
3. **`find_program(JQ_EXE jq)` does not search `jq_ROOT`; it returned `/usr/sbin/jq`.** The README and the find-package guide promise "a following find_package/find_library searches the OCX-provisioned content" (so find_program is not promised there), but the examples-packages page comment says "a subsequent find_package(jq)/find_program would search the" content (my scenario also assumed find_program). The CMake docs show `<PackageName>_ROOT` applies to `find_package()` and to `find_*` calls made inside find modules, not to a plain top-level `find_program`. The result is a silent fall back to the system tool, which is the opposite of the goal and looks like success in the log. Severity: blocker for the stated scenario (find_program), major in general. Looked in: guides/find-package, reference/commands (`ocx_package`), reference/examples-packages.
4. **No documented way to find a program in the pulled package.** Making `find_program` work needed my own `HINTS ${jq_ROOT}`; I also had to discover that the binary sits directly in `content/` (`content/jq`), not `content/bin/`. `find_package(jq)` reported `jq_FOUND=0` (no Find/Config module for jq), and the docs do not say what a "find_package(<name>)" is expected to find for a tool-only package. Severity: major. Looked in: guides/find-package, reference/examples-packages, reference/commands.
5. **`PINS` digests: the docs point at a command that does not show them.** "Get the digests from `ocx package install -p <platform>`" - in ocx 0.6.5 the plain table omits the digest; I only got it with the global `--json` flag. The docs' 5-platform example happened to contain the digest I needed, so I copied it. Severity: minor. Looked in: guides/pin-and-freeze, reference/commands.
6. **Docs and README reference commands that do not exist in the ocx I have.** README Testing section says `ocx run -- task verify`; how-it-works says launchers "re-enter `ocx run`"; `ocx --help` in 0.6.5 lists `exec`, no `run`. Same confusion with the `--version` flag (`ocx version` is the command). Severity: minor. Looked in: README, concepts/how-it-works, reference/variables.
7. **Two doc sites with different contents.** https://ocx-sh.github.io/find_ocx/ (Sphinx) and https://ocx.sh/integrations/cmake/ both exist; the README only names the latter. I did not know which is authoritative for v0.3.0. Severity: minor. Looked in: README Documentation section, both sites.
8. **A stale value could persist.** Pass 1 left a bad `jq_ROOT` in the CMake cache of `build/`; I removed the build directory before retrying, so I did not learn whether a reconfigure with `OCX_BOOTSTRAP=ALWAYS` alone would have recovered. Severity: minor. Looked in: reference/variables (`OCX_REFRESH`, snapshot pattern).

Outcome summary: partial. `jq_ROOT` printed the OCX content store path (with the bootstrapped CLI); plain `find_program(JQ_EXE jq)` resolved `/usr/sbin/jq`; only an explicit `HINTS ${jq_ROOT}` resolved the binary inside the store.
