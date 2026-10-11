# Friction log: fix the floating-tag error

## Setup

- Persona: Marcus, a maintainer who copied one line, `ocx_package(PACKAGE ocx.sh/jqlang/jq:latest)`, from a blog post. First contact with find_ocx and OCX. Has not seen the find_ocx source; uses only the public README, the v0.3.0 release assets and the docs at https://ocx.sh/integrations/cmake/.
- Starting state: an empty CMake project, `ocx` 0.6.5 and `ocx.sh/kitware/cmake:4` available through `ocx`, `ocx.cmake` and `Findocx.cmake` vendored from release v0.3.0 into `cmake/`, isolated `OCX_HOME`.
- Goal: understand why configure refuses a `:latest` tag and make it reproducible. Success: the configure passes, the resolved jq digest or a committed `.ocx/` snapshot is visible in the tree, and a second configure with `OCX_FROZEN` set (offline) still passes.
- Date: 2026-10-10.

## Attempt

$ gh api repos/ocx-sh/find_ocx/readme --jq .content | base64 -d | head -150
```
<!-- doc_type: readme -->

# find_ocx

CMake support for [OCX](https://ocx.sh) — the OCI-backed package manager.
[... 14 lines elided]
# Ad-hoc: a single package. PULL exports jq_ROOT (CMP0074) so a following
# find_package/find_library searches the OCX-provisioned content.
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest PULL)
```

No ocx installation required: the pinned CLI is bootstrapped at first
configure (per-machine cache, manifest sha256 enforced). The classic find
[... 36 lines elided]
```

$ gh release view v0.3.0 -R ocx-sh/find_ocx | head -40
```
title:	v0.3.0
tag:	v0.3.0
[... 5 lines elided]
asset:	Findocx.cmake
asset:	ocx.cmake
asset:	SHA256SUMS
[... 5 lines elided]
- Reproducible-first index snapshots and PATH-first CLI resolution **BREAKING**
[0.3.0]: https://github.com/ocx-sh/find_ocx/compare/v0.2.0..v0.3.0
```

$ gh release download v0.3.0 -R ocx-sh/find_ocx
```
Findocx.cmake  2.8K
ocx.cmake  88.7K
SHA256SUMS  156B
```

$ ocx --version
```
error: unexpected argument '--version' found

Usage: ocx [OPTIONS] [COMMAND]

For more information, try '--help'.
```

$ ocx exec -- cmake --version
```
error: no ocx.toml found in /tmp/.../friction-fix-floating-tag-error/proj or any parent; run `ocx init` to create one
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake --version
```
Package 'ocx.sh/kitware/cmake:4' not found locally, pulling.
Downloading layer sha256:61c5ceac1af3 to /tmp/.../friction-fix-floating-tag-error/ocxhome/temp/5d1c38a94867e65acad24f47e861cc47
cmake version 4.4.4

CMake suite maintained and supported by Kitware (kitware.com/cmake).
```

I wrote a four-line `CMakeLists.txt` around the blog line (verbatim from the post, no `NAME`).

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build
```
CMake Error at cmake/ocx.cmake:1036 (message):
  find_ocx: ocx_package: NAME and PACKAGE are required
Call Stack (most recent call first):
  CMakeLists.txt:5 (ocx_package)


-- Configuring incomplete, errors occurred!
[exit 1]
```

The README example has `NAME jq`; the blog line did not. I added `NAME jq`.

$ cat CMakeLists.txt
```
cmake_minimum_required(VERSION 3.19)
project(demo NONE)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)
ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest)
[exit 0]
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build
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
[exit 1]
```

The error names three fixes. I went to the docs. The sidebar on https://ocx.sh/integrations/cmake/ lists a page "Fix a failing configure"; the guessed URL 404s, the real slug is `nested-builds`.

$ curl -sL -o /dev/null -w '%{http_code}\n' https://ocx.sh/integrations/cmake/guides/fix-a-failing-configure/
```
404
```

$ curl -sL https://ocx.sh/integrations/cmake/guides/nested-builds/   # html to text
```
Fix a failing configure
Error: a nested configure fails with the exit-81 refresh hint
[... 8 lines elided]
Error: a floating tag stops the configure
Section titled “Error: a floating tag stops the configure”
This issue occurs when a package uses a floating tag such as :latest.
No index snapshot is in effect, and no digest is pinned.
find_ocx is reproducible first, so it refuses to resolve the tag live.
Commit an index snapshot or add PINS: see Pin and freeze tag resolution.
To print the digests once, set OCX_ALLOW_FLOATING for a single run.
[... 7 lines elided]
```

$ curl -sL https://ocx.sh/integrations/cmake/guides/pin-and-freeze/   # html to text
```
Pin and freeze tag resolution
Use a committed .ocx/ index snapshot or per-platform digests so a floating tag such as :latest resolves the same way on every machine.
Without one of them, a floating tag is a hard configure error.
Commit an index snapshot
Section titled “Commit an index snapshot”
Create the snapshot for the packages you use and commit it like a lock file.
Terminal window
ocx --index .ocx index update ocx.sh/jqlang/jq ocx.sh/kitware/cmake
git add .ocx
Then fail fast in CMakeLists.txt when the snapshot is missing.
[... 15 lines elided]
Pin per-platform digests instead
[... 11 lines elided]
Get the digests from ocx package install -p <platform> or from the ocx.lock of a project.
You can also print them once with a floating pull, which needs the explicit escape hatch.
[... 6 lines elided]
For why a floating tag is an error, see Reproducible first.
Needs addressed: problem 3 of the use-case research.
Previous
Next
```

The error text and the guide differ: the error gives `index update ocx.sh/jqlang/jq:latest`, the guide gives `ocx.sh/jqlang/jq` without a tag. I used the error text.

$ ocx --index .ocx index update ocx.sh/jqlang/jq:latest
```
Refreshing tags for identifier 'ocx.sh/jqlang/jq:latest'.
[exit 0]
```

$ ls -R .ocx | head -30
```
.ocx:
ocx.sh

.ocx/ocx.sh:
c
config.json
p

.ocx/ocx.sh/c:
index.json

.ocx/ocx.sh/p:
jqlang

.ocx/ocx.sh/p/jqlang:
jq
jq.json

.ocx/ocx.sh/p/jqlang/jq:
o

.ocx/ocx.sh/p/jqlang/jq/o:
sha256

.ocx/ocx.sh/p/jqlang/jq/o/sha256:
c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6.json
[exit 0]
```

$ rm -rf build; ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build
```
-- find_ocx: using ocx from PATH (/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead
-- Configuring done (0.0s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-fix-floating-tag-error/proj/build
[exit 0]
```

$ cat .ocx/ocx.sh/p/jqlang/jq.json | head -c 800; ls build; grep -i jq build/CMakeCache.txt
```
{
  "name": "ocx.sh/jqlang/jq",
  "repository": "oci://ghcr.io/ocx-contrib/jqlang/jq",
  "owners": [
    {
      "login": "ocx-bot",
      "id": 309019509
    }
  ],
  "status": "active",
  "deprecated_message": null,
  "created": "2026-08-02",
  "desc": {
    "digest": "sha256:6e33358a0bf7bfbae68eee78c5fea7692ce95a6ac651c98e10b852a611875e88",
    "title": "jq",
    "description": "Command-line JSON processor \u2014 slice, filter, map and transform structured data",
    "keywords": [
      "jq",
      "json",
      "cli",
      "query",
      "filter",
      "jqlang",
      "data"
    ],
    "readme": "sha256:01ae2f0382124b554357d1432142898ffe7dde53365007ebcc08e3d680cef647",
    "logo": "sha256:aadba923ee9354cacbfb8a0d65cb56f65d01d39b74501e83ad2da49a378d2ca9"
  },
  "upstream": {
    "org"CMakeCache.txt
CMakeFiles
cmake_install.cmake
Makefile
OCX_JQ_RUN:INTERNAL=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-fix-floating-tag-error/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin/cmake;-E;env;OCX_PROJECT=;OCX_HOME=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-fix-floating-tag-error/ocxhome;/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx;--index;/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-fix-floating-tag-error/proj/.ocx;--frozen;package;exec;ocx.sh/jqlang/jq:latest;--
__OCX_R_JQ_FP:INTERNAL=c48687240f0647da0110a4899337bb5d7f55d2f4578290b58ba0849db3a579f9
__OCX_R_JQ_GUARD:INTERNAL=
[exit 0]
```

The configure passes and `.ocx/ocx.sh/p/jqlang/jq/o/sha256/c295...json` is in the tree. Next, the second configure with `OCX_FROZEN` set and offline. `ocx.sh/integrations/cmake/guides/mirror/` and the variables reference say `OCX_OFFLINE` and `OCX_FROZEN` are passthrough variables snapshotted from the environment at first configure, but give no value to set.

$ curl -sL https://ocx.sh/integrations/cmake/guides/mirror/   # html to text
```
[... 20 lines elided]
Set OCX_OFFLINE to run without network access once the local store holds the content.
Clear a knob
Section titled “Clear a knob”
Pass -DVAR= to remove a value from the environment of every ocx call.
The passthrough variables are OCX_HOME, OCX_MIRRORS, OCX_INSECURE_REGISTRIES, OCX_OFFLINE, OCX_FROZEN, OCX_REMOTE, OCX_JOBS, OCX_INDEX and OCX_DEFAULT_REGISTRY.
[... 5 lines elided]
```

I guessed `1` as the value (fresh build dir, because the knobs are sticky per build directory).

$ rm -rf build2; OCX_FROZEN=1 OCX_OFFLINE=1 ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build2
```
-- find_ocx: using ocx from PATH (/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead
-- Configuring done (0.0s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-fix-floating-tag-error/proj/build2
[exit 0]
```

$ grep -E "OCX_(FROZEN|OFFLINE|INDEX)" build2/CMakeCache.txt; echo; grep -c . build2/CMakeCache.txt; grep -o "ocx.sh/jqlang/jq[^;]*" build2/CMakeCache.txt | head -3
```
OCX_FROZEN:STRING=1
OCX_OFFLINE:STRING=1
OCX_JQ_RUN:INTERNAL=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-fix-floating-tag-error/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin/cmake;-E;env;OCX_PROJECT=;OCX_HOME=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-fix-floating-tag-error/ocxhome;OCX_OFFLINE=1;OCX_FROZEN=1;/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx;--index;/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-fix-floating-tag-error/proj/.ocx;--frozen;package;exec;ocx.sh/jqlang/jq:latest;--

127
ocx.sh/jqlang/jq:latest
[exit 0]
```

$ ls ocxhome/packages/ocx.sh/ 2>&1; ls ocxhome
```
ls: cannot access 'ocxhome/packages/ocx.sh/': No such file or directory
ls: cannot access 'ocxhome': No such file or directory
[exit 2]
```

(That `ls` ran from the wrong directory; `ocxhome` is one level up.)

$ ocx --offline --index .ocx package exec ocx.sh/jqlang/jq:latest -- jq --version
```
error: failed to find package: ocx.sh/jqlang/jq:latest — manifest sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae is not in the local cache; run `ocx install ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae` online to populate it
[exit 81]
```

I wanted to see whether the offline configure proves anything. jq was never pulled (lazy), so an offline `package exec` fails by design. The digest `913ff41f...` in the message is the linux/amd64 manifest digest from the snapshot.

$ ls ../ocxhome ../ocxhome/packages/ocx.sh/sha256/*/ 2>&1 | head -20; grep -rl 913ff41f5e .ocx; git -C . status 2>&1 | head -3
```
../ocxhome:
blobs
index
layers
locks
packages
state
temp

../ocxhome/packages/ocx.sh/sha256/03/:
ea6ed6709a4e7a2331fc356f6baee9
.ocx/ocx.sh/p/jqlang/jq/o/sha256/c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6.json
fatal: not a git repository (or any parent up to mount point /)
Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).
[exit 0]
```

$ ocx --index .ocx --frozen package exec ocx.sh/jqlang/jq:latest -- jq --version
```
Package 'ocx.sh/jqlang/jq:latest' not found locally, pulling.
Downloading layer sha256:88ad916b0507 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-fix-floating-tag-error/ocxhome/temp/9c13e7a59201751a36e83176bff4a013
jq-1.8.2
[exit 0]
```

$ ocx --index .ocx index list ocx.sh/jqlang/jq 2>&1 | head
```
Package           Tag   
ocx.sh/jqlang/jq  latest
[exit 0]
```

The pin-and-freeze guide says `OCX_ALLOW_FLOATING` prints the digests once. I tried it in a copy of the project without `PULL`.

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -DOCX_ALLOW_FLOATING=ON -S . -B build
```
-- find_ocx: using ocx from PATH (/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead
CMake Warning at cmake/ocx.cmake:1186 (message):
  find_ocx: ocx_package jq: 'ocx.sh/jqlang/jq:latest' is lazy AND floating -
  the tag resolves on first execution and can drift; add PINS, an index
  snapshot, or an @sha256: digest (or PULL to resolve now)
Call Stack (most recent call first):
  CMakeLists.txt:5 (ocx_package)


-- Configuring done (0.0s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-fix-floating-tag-error/proj2/build
[exit 0]
```

Outcome: first configure passes after `ocx --index .ocx index update ocx.sh/jqlang/jq:latest`; the `.ocx/` snapshot (including manifest digest `sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae` for linux/amd64) is in the tree; the second configure with `OCX_FROZEN=1 OCX_OFFLINE=1` in a fresh build directory passes and both values land in `CMakeCache.txt`.

## Friction

1. Minor. The copied blog line (`ocx_package(PACKAGE ...)`) fails first with "NAME and PACKAGE are required", before the floating-tag error I was told to expect. The README quick start shows `NAME`; the blog line did not. Looked at: README, configure output.
2. Minor. The sidebar entry "Fix a failing configure" lives at `/guides/nested-builds/`; the title and URL slug disagree, so a guessed URL 404s. The floating-tag section is the second of three on that page, below an unrelated exit-81 nested-build error that comes first. Looked at: docs sidebar, `nested-builds` page.
3. Minor. The error message gives `index update ocx.sh/jqlang/jq:latest`; the Pin and freeze guide gives `index update ocx.sh/jqlang/jq ocx.sh/kitware/cmake`. I could not tell whether the tag matters. Both end in the same state for me, but I did not verify that. Looked at: configure error, `pin-and-freeze`.
4. Minor. The error says "next to your CMakeLists"; the guide shows no directory. It worked from the directory holding `CMakeLists.txt`. Separately, `ocx --version` is rejected, so I could not quickly confirm which `ocx` was on PATH. Looked at: error text, `pin-and-freeze`.
5. Major. The goal "second configure with `OCX_FROZEN` set" has no documented value. The mirror guide and variables reference only list `OCX_FROZEN` and `OCX_OFFLINE` as passthrough variables snapshotted from the environment; I guessed `1`. The "Reproducible first" page says "the freshness gate is the frozen configure itself" but no page says how to run one. The generated `OCX_JQ_RUN` already contained `--frozen` before I set anything, so I could not tell what `OCX_FROZEN` changed. Looked at: `mirror`, `reference/variables`, `concepts/reproducible-first`.
6. Minor. The passing offline configure proves little: `ocx_package` is lazy, so nothing is pulled at configure and jq was absent from the store. A later offline `package exec` for jq fails with exit 81 and "run `ocx install ...` online to populate it". The lazy-versus-eager page mentions `PULL` / `-DOCX_PULL=ON` but not as the way to prepare an offline build. Looked at: `mirror`, `concepts/lazy-vs-eager`.
7. Minor. The guide and the "Reproducible first" page say `OCX_ALLOW_FLOATING` can print the digests once ("the eager install prints the digests"). Without `PULL` it only warns "lazy AND floating" and prints no digest. The snapshot under `.ocx/` was the only place I found the digest, via grep. Looked at: `pin-and-freeze`, `concepts/reproducible-first`, configure output.
8. Minor. Internal text leaks into published pages: "Needs addressed: problem 3 of the use-case research." (pin-and-freeze) and "problem 7 ..." (mirror). Looked at: those pages.
9. Minor. Because the knobs are sticky per build directory, the offline configure only passed in a fresh build dir; the docs mention stickiness in the mirror guide but not as a trap for "run configure again with X set". Looked at: `mirror`.
