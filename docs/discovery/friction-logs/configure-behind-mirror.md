## Setup

- Persona: Henrik, platform engineer. Network blocks github.com but allows an internal artifact host. First time with find_ocx; has never seen its source. Only public material was used: the GitHub README and release assets, ocx.sh/integrations/cmake/ and ocx.sh docs.
- Goal: configure a CMake project through an internal mirror (`OCX_INSTALL_DIST_URL`, `OCX_INSTALL_MIRROR_URL`) with the registry credential exported only in the environment and absent from `CMakeCache.txt`.
- Starting state: clean machine. No `ocx` on the PATH of the configure (cmake 4.4.4 and ninja provisioned separately; `PATH` reduced to cmake, ninja, /usr/bin, /bin). Empty bootstrap cache (`XDG_CACHE_HOME` isolated). Isolated `OCX_HOME`. A local `python3 -m http.server` on 127.0.0.1:8099 stands in for the mirror and serves a copy of `dist.json` plus ocx archives.
- Tooling versions: find_ocx v0.3.0 (latest release), ocx 0.6.5 on the author machine for `ocx lock`.
- Date: 2026-10-10

## Attempt

Paths below are shortened: `$W` is the scratch directory for this run (`.../friction-configure-behind-mirror`). Commands run through a transcript wrapper are shown exactly; the few early reconnaissance commands are reproduced from my terminal with long output elided.

$ gh api repos/ocx-sh/find_ocx/readme -q .content | base64 -d | head -200
```
<!-- doc_type: readme -->

# find_ocx

CMake support for [OCX](https://ocx.sh) — the OCI-backed package manager.
Two copy-and-own files bootstrap a pinned, sha256-verified `ocx` CLI and
provision development tools through it.
[... 40 lines elided]
No ocx installation required: the pinned CLI is bootstrapped at first
configure (per-machine cache, manifest sha256 enforced). The classic find
module works too — `find_package(ocx REQUIRED)`, with `-DOCX_BOOTSTRAP=ON`
for the same zero-setup behavior.

Requires CMake **3.19** (`Findocx.cmake` alone works on 3.15). Script mode
(`cmake -P`) is fully supported.

[... 30 lines elided]
Guides, concepts and the command and variable reference are at
<https://ocx.sh/integrations/cmake/>.
[... 28 lines elided]
```

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
[... 2 lines elided]
- Reproducible-first index snapshots and PATH-first CLI resolution **BREAKING**
[0.3.0]: https://github.com/ocx-sh/find_ocx/compare/v0.2.0..v0.3.0
```

$ curl -sSL https://ocx.sh/integrations/cmake/ -o overview.html -w 'HTTP %{http_code}\n'   # then read it as text
```
HTTP 200
[... 62 lines elided]
```

$ curl -sSL https://ocx.sh/integrations/cmake/guides/mirror/ | (render as text)
```
Build behind a mirror or offline
Use these variables to run a configure in a corporate or air-gapped environment.
They are the same knobs as the setup.ocx.sh installer and rules_ocx.
Every variable follows the snapshot pattern.
A CMake cache variable wins, otherwise the environment value at the first configure is stored in the cache and stays for that build directory.
Mirror the ocx download
Set OCX_INSTALL_DIST_URL to fetch the release manifest from your mirror instead of the embedded snapshot.
Set OCX_INSTALL_MIRROR_URL to rewrite the binary download to <mirror>/<tag>/<filename>.
The manifest sha256 is still enforced, so a mirror can move bytes but not change them.
Mirror the packages
Set OCX_MIRRORS to a JSON map such as {"ocx.sh": "https://mirror.corp/ocx"}.
Package pulls go to the mirror, and lock digests stay keyed to the upstream host.
Set OCX_INSECURE_REGISTRIES to a comma list when a mirror speaks plain HTTP.
Pass credentials
Export OCX_AUTH_<REGISTRY>_TYPE, OCX_AUTH_<REGISTRY>_USER and OCX_AUTH_<REGISTRY>_TOKEN in the environment.
These are never stored in CMakeCache.txt, so reconfigure after you change them.
[... 14 lines elided]
```

$ curl -sSL https://ocx.sh/integrations/cmake/reference/variables/ | (render as text)  # and tutorial/
```
[... 95 lines elided]
OCX_INSTALL_DIST_URL
Fetch the ocx release manifest (dist.json) from a mirror instead of the snapshot embedded in this file.
OCX_INSTALL_MIRROR_URL
Rewrite the ocx binary download to <mirror>/<tag>/<filename>. The manifest sha256 is still enforced — a mirror can move bytes, not change them.
OCX_INSTALL_VERSION
ocx CLI version to bootstrap (default: the version pinned with this find_ocx release). Same knob as the setup.ocx.sh installer.
[... 40 lines elided]
```

$ export W=<scratch dir>; mkdir -p $W/proj/cmake $W/dl && cd $W/dl && gh release download v0.3.0 -R ocx-sh/find_ocx -D .
```
Findocx.cmake  2.8K
ocx.cmake  88.7K
SHA256SUMS  156B
```

$ sha256sum -c SHA256SUMS; cp Findocx.cmake ocx.cmake ../proj/cmake/
```
Findocx.cmake: OK
ocx.cmake: OK
```

$ export OCX_HOME=$W/ocxhome; ocx package exec ocx.sh/kitware/cmake:4 -- sh -c 'command -v cmake; cmake --version | head -1'
```
Package 'ocx.sh/kitware/cmake:4' not found locally, pulling.
Downloading layer sha256:61c5ceac1af3 to $W/ocxhome/temp/5d1c38a94867e65acad24f47e861cc47
$W/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin/cmake
cmake version 4.4.4
```

$ mkdir -p $W/mirror && cd $W/mirror && curl -sS -o dist.json -w '%{http_code}\n' https://setup.ocx.sh/dist.json
```
200
```

$ grep -n -i 'OCX_PIN_VERSION' $W/dl/ocx.cmake | head -5
```
186:set(__OCX_PIN_VERSION "0.3.11")
393:    set(hint "the pinned ocx and find_ocx disagree on the CLI surface - check OCX_INSTALL_VERSION against the find_ocx pin (${__OCX_PIN_VERSION})")
661:  set(version "${__OCX_PIN_VERSION}")
730:      "${__OCX_PIN_VERSION}); cache: ${cache_root}; opt out: "
```

$ mkdir -p v0.3.11 && curl -sSL -o v0.3.11/ocx-x86_64-unknown-linux-gnu.tar.xz https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-x86_64-unknown-linux-gnu.tar.xz; sha256sum v0.3.11/*
```
44fc65490cf3a9dbdb9a364b4f67e30c6d31363a5927de351a465856b6ebd0b7  v0.3.11/ocx-x86_64-unknown-linux-gnu.tar.xz
```

$ python3 -I -m http.server 8099 --bind 127.0.0.1 --directory $W/mirror &   # the stand-in mirror, access log kept
```
[... 0 lines elided]
```

$ curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8099/dist.json
```
200
```

Fixture note: I created ocx.toml (`jq = "ocx.sh/jqlang/jq:latest"`), CMakeLists.txt and cmake/ exactly as the tutorial shows (`ocx_project(NAME TOOLS BINS jq)` plus the `validate` target), then locked with the ocx on my machine because the tutorial says the CLI is needed once.

$ export OCX_HOME=$W/ocxhome; ocx lock && ls && cat ocx.lock
```
pulling count=1
Downloading layer sha256:88ad916b0507 to $W/ocxhome/temp/9c13e7a59201751a36e83176bff4a013
warning: add `ocx.lock merge=union` to .gitattributes to avoid merge conflicts
Binding  Group    Digest                                                                 
jq       default  sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
cmake
CMakeLists.txt
ocx.lock
ocx.toml
[metadata]
lock_version = 3
declaration_hash_version = 1
declaration_hash = "sha256:e0361206f7a2ebde72dda210f86a838bcd00335fffb2cb77c55bd940b673c4a6"
generated_by = "ocx 0.6.5"
generated_at = "2026-10-10T16:45:24Z"

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
[exit 0]
```

$ . ../log/env.sh; command -v ocx; echo "ocx on PATH? exit=$?"; cmake --version | head -1
```
ocx on PATH? exit=1
cmake version 4.4.4
[exit 0]
```

$ curl -sSL https://ocx.sh/docs/reference/environment/ | (render as text) | grep -n -i -A6 'OCX_AUTH'
```
81:OCX_AUTH_<REGISTRY>_TYPE
82-The authentication type for the registry.
83-Valid values are:
84-basic
85-token (or bearer)
86-anonymous
87:OCX_AUTH_<REGISTRY>_USER
[... 10 lines elided]
```

$ . ../log/env.sh; export OCX_INSTALL_DIST_URL=http://127.0.0.1:8099/dist.json OCX_INSTALL_MIRROR_URL=http://127.0.0.1:8099; export OCX_AUTH_OCX_SH_TYPE=bearer OCX_AUTH_OCX_SH_TOKEN=hunter2-SECRET-TOKEN-4711; cmake -S . -B build -G Ninja
```
-- find_ocx: downloading ocx 0.3.11 (x86_64-unknown-linux-musl) from http://127.0.0.1:8099/v0.3.11/ocx-x86_64-unknown-linux-musl.tar.xz
-- find_ocx:   version knob: OCX_INSTALL_VERSION (pin: 0.3.11); cache: $W/cache/find_ocx; opt out: OCX_BOOTSTRAP=OFF + OCX_EXECUTABLE
CMake Error at cmake/ocx.cmake:732 (file):
  file DOWNLOAD cannot compute hash on failed download

    from url: "http://127.0.0.1:8099/v0.3.11/ocx-x86_64-unknown-linux-musl.tar.xz"
    status: [22;"HTTP response code said error"]
Call Stack (most recent call first):
  cmake/ocx.cmake:561 (ocx_bootstrap)
  cmake/ocx.cmake:883 (__ocx_require_cli)
  CMakeLists.txt:5 (ocx_project)


CMake Error at cmake/ocx.cmake:736 (message):
  find_ocx: download of
  http://127.0.0.1:8099/v0.3.11/ocx-x86_64-unknown-linux-musl.tar.xz failed:
  "HTTP response code said error"

  hint: corporate networks - set OCX_INSTALL_MIRROR_URL (artifacts) and/or
  OCX_INSTALL_DIST_URL (manifest)
Call Stack (most recent call first):
  cmake/ocx.cmake:561 (ocx_bootstrap)
  cmake/ocx.cmake:883 (__ocx_require_cli)
  CMakeLists.txt:5 (ocx_project)


-- Configuring incomplete, errors occurred!
[exit 1]
```

$ tail -3 ../log/mirror-access.log; curl -sSL -o ../mirror/v0.3.11/ocx-x86_64-unknown-linux-musl.tar.xz https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-x86_64-unknown-linux-musl.tar.xz && sha256sum ../mirror/v0.3.11/*; rm -rf build
```
127.0.0.1 - - [10/Oct/2026 18:45:52] "GET /dist.json HTTP/1.1" 200 -
127.0.0.1 - - [10/Oct/2026 18:45:52] code 404, message File not found
127.0.0.1 - - [10/Oct/2026 18:45:52] "GET /v0.3.11/ocx-x86_64-unknown-linux-musl.tar.xz HTTP/1.1" 404 -
44fc65490cf3a9dbdb9a364b4f67e30c6d31363a5927de351a465856b6ebd0b7  ../mirror/v0.3.11/ocx-x86_64-unknown-linux-gnu.tar.xz
29cff0027a070f3bf85ef9e7616ada5e54e9fc3471988513eb9087c80f79d278  ../mirror/v0.3.11/ocx-x86_64-unknown-linux-musl.tar.xz
[exit 0]
```

$ . ../log/env2.sh; cmake -S . -B build -G Ninja
```
-- find_ocx: downloading ocx 0.3.11 (x86_64-unknown-linux-musl) from http://127.0.0.1:8099/v0.3.11/ocx-x86_64-unknown-linux-musl.tar.xz
-- find_ocx:   version knob: OCX_INSTALL_VERSION (pin: 0.3.11); cache: $W/cache/find_ocx; opt out: OCX_BOOTSTRAP=OFF + OCX_EXECUTABLE
-- find_ocx: using bootstrapped ocx 0.3.11 ($W/cache/find_ocx/0.3.11/x86_64-unknown-linux-musl/ocx)
CMake Error at cmake/ocx.cmake:443 (message):
  find_ocx: checking
  $W/proj/ocx.toml
  against its lockfile failed (exit 78): ocx --project
  $W/proj/ocx.toml
  lock --check

  2026-10-10T16:45:59.655500Z ERROR
  $W/proj/ocx.lock:
  invalid TOML:
  $W/proj/ocx.lock:
  invalid TOML:
  $W/proj/ocx.lock:
  invalid TOML: invalid TOML: TOML parse error at line 2, column 16

    |

  2 | lock_version = 3

    |                ^

  invalid value: 3, expected 1 or 2





  hint: no ocx.lock next to
  $W/proj/ocx.toml
  - run 'ocx lock' and commit it
Call Stack (most recent call first):
  cmake/ocx.cmake:919 (__ocx_run)
  CMakeLists.txt:5 (ocx_project)


-- Configuring incomplete, errors occurred!
[exit 1]
```

$ mkdir -p ../mirror/v0.6.5 && curl -sSL -o ../mirror/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.xz https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.xz && sha256sum ../mirror/v0.6.5/*; grep -o "\"version\":\"0.6.5\"[^}]*x86_64-unknown-linux-musl[^}]*" ../mirror/dist.json | grep -o "sha256\":\"[0-9a-f]*"
```
0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5  ../mirror/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.xz
sha256":"bb4d306debca428fdc326ec587047c7efc3f3a2262b06eacfdaca46fa75a4dac
[exit 0]
```

$ . ../log/env2.sh; export OCX_INSTALL_VERSION=0.6.5; rm -rf build; cmake -S . -B build -G Ninja
```
-- find_ocx: downloading ocx 0.6.5 (x86_64-unknown-linux-musl) from http://127.0.0.1:8099/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz
-- find_ocx:   version knob: OCX_INSTALL_VERSION (pin: 0.3.11); cache: $W/cache/find_ocx; opt out: OCX_BOOTSTRAP=OFF + OCX_EXECUTABLE
CMake Error at cmake/ocx.cmake:732 (file):
  file DOWNLOAD cannot compute hash on failed download

    from url: "http://127.0.0.1:8099/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz"
    status: [22;"HTTP response code said error"]
Call Stack (most recent call first):
  cmake/ocx.cmake:561 (ocx_bootstrap)
  cmake/ocx.cmake:883 (__ocx_require_cli)
  CMakeLists.txt:5 (ocx_project)


CMake Error at cmake/ocx.cmake:736 (message):
  find_ocx: download of
  http://127.0.0.1:8099/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz failed:
  "HTTP response code said error"

  hint: corporate networks - set OCX_INSTALL_MIRROR_URL (artifacts) and/or
  OCX_INSTALL_DIST_URL (manifest)
Call Stack (most recent call first):
  cmake/ocx.cmake:561 (ocx_bootstrap)
  cmake/ocx.cmake:883 (__ocx_require_cli)
  CMakeLists.txt:5 (ocx_project)


-- Configuring incomplete, errors occurred!
[exit 1]
```

$ rm ../mirror/v0.6.5/*; u=$(python3 -I -c "
import json;d=json.load(open(\"../mirror/dist.json\"))
print([r[\"url\"] for r in d[\"releases\"] if r[\"version\"]==\"0.6.5\" and r[\"target\"]==\"x86_64-unknown-linux-musl\"][0])"); echo $u; curl -sSL -o ../mirror/v0.6.5/$(basename $u) $u && sha256sum ../mirror/v0.6.5/*; ls ../mirror/v0.6.5
```
https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz
bb4d306debca428fdc326ec587047c7efc3f3a2262b06eacfdaca46fa75a4dac  ../mirror/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz
ocx-x86_64-unknown-linux-musl.tar.gz
[exit 0]
```

$ . ../log/env2.sh; export OCX_INSTALL_VERSION=0.6.5; rm -rf build; cmake -S . -B build -G Ninja
```
-- find_ocx: downloading ocx 0.6.5 (x86_64-unknown-linux-musl) from http://127.0.0.1:8099/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz
-- find_ocx:   version knob: OCX_INSTALL_VERSION (pin: 0.3.11); cache: $W/cache/find_ocx; opt out: OCX_BOOTSTRAP=OFF + OCX_EXECUTABLE
-- find_ocx: using bootstrapped ocx 0.6.5 ($W/cache/find_ocx/0.6.5/x86_64-unknown-linux-musl/ocx)
-- Configuring done (0.2s)
-- Generating done (0.0s)
-- Build files have been written to: $W/proj/build
[exit 0]
```

$ grep -n "hunter2\|OCX_AUTH" build/CMakeCache.txt; echo "grep exit=$?"; grep -n "OCX_" build/CMakeCache.txt; grep -rl hunter2 build | head; echo "grep -r exit=$?"; tail -4 ../log/mirror-access.log
```
grep exit=1
61:OCX_EXECUTABLE:FILEPATH=$W/cache/find_ocx/0.6.5/x86_64-unknown-linux-musl/ocx
64:OCX_HOME:STRING=$W/ocxhome
67:OCX_INSTALL_DIST_URL:STRING=http://127.0.0.1:8099/dist.json
70:OCX_INSTALL_MIRROR_URL:STRING=http://127.0.0.1:8099
73:OCX_INSTALL_VERSION:STRING=0.6.5
150:OCX_TOOLS_RUN:INTERNAL=$W/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin/cmake;-E;env;OCX_PROJECT=;OCX_HOME=$W/ocxhome;$W/cache/find_ocx/0.6.5/x86_64-unknown-linux-musl/ocx;--project;$W/proj/ocx.toml;run;--
152:OCX_TOOLS_RUN_JQ:INTERNAL=$W/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin/cmake;-E;env;OCX_PROJECT=;OCX_HOME=$W/ocxhome;$W/cache/find_ocx/0.6.5/x86_64-unknown-linux-musl/ocx;--project;$W/proj/ocx.toml;run;--;jq
154:__OCX_R_TOOLS_FP:INTERNAL=d80e8fb422abb9174143118e29ce6f37cf75217d0cb93d1215bda3e267581917
156:__OCX_R_TOOLS_GUARD:INTERNAL=
grep -r exit=0
127.0.0.1 - - [10/Oct/2026 18:46:05] code 404, message File not found
127.0.0.1 - - [10/Oct/2026 18:46:05] "GET /v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz HTTP/1.1" 404 -
127.0.0.1 - - [10/Oct/2026 18:46:10] "GET /dist.json HTTP/1.1" 200 -
127.0.0.1 - - [10/Oct/2026 18:46:10] "GET /v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz HTTP/1.1" 200 -
[exit 0]
```

$ . ../log/env2.sh; export OCX_INSTALL_VERSION=0.6.5; env | grep ^OCX_AUTH; cmake --build build 2>&1 | tail -15
```
OCX_AUTH_OCX_SH_TOKEN=hunter2-SECRET-TOKEN-4711
OCX_AUTH_OCX_SH_TYPE=bearer
[1/1] cd $W/proj/build && $W/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin/cmake -E env OCX_PROJECT= OCX_HOME=$W/ocxhome $W/cache/find_ocx/0.6.5/x86_64-unknown-linux-musl/ocx --project $W/proj/ocx.toml run -- jq -n -e --arg config "" "\$config | length >= 0"
warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7
true
[exit 0]
```

$ . ../log/env2.sh; export OCX_INSTALL_VERSION=0.6.5 OCX_HOME=$W/ocxhome2; rm -rf build2; cmake -S . -B build2 -G Ninja 2>&1 | tail -4; cmake --build build2 2>&1 | cut -c1-200 | tail -8; grep -c hunter2 build2/CMakeCache.txt
```
-- find_ocx: using bootstrapped ocx 0.6.5 ($W/cache/find_ocx/0.6.5/x86_64-unknown-linux-musl/ocx)
-- Configuring done (0.0s)
-- Generating done (0.0s)
-- Build files have been written to: $W/proj/build2
warning: failed to retrieve authentication for registry 'ghcr.io', falling back to anonymous: failed to retrieve Docker credentials: Credential helper `pass` not found on PATH
Package 'ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae' not found locally, pulling.
warning: failed to retrieve Docker credentials for registry 'ghcr.io'
warning: failed to retrieve authentication for registry 'ghcr.io', falling back to anonymous: failed to retrieve Docker credentials: Credential helper `pass` not found on PATH
warning: failed to retrieve Docker credentials for registry 'ghcr.io'
warning: failed to retrieve authentication for registry 'ghcr.io', falling back to anonymous: failed to retrieve Docker credentials: Credential helper `pass` not found on PATH
Downloading layer sha256:88ad916b0507 to $W/ocxhome2/temp/9c13e7a59201751a36e8
true
0
[exit 1]
```

$ grep -rn hunter2 build build2 ../cache ocx.lock ocx.toml; echo "grep exit=$?"; grep -n "OCX_INSTALL\|download" ../log/mirror-access.log | tail -3
```
grep exit=1
[exit 0]
```

Result of the run: configure completed with both URLs set, the mirror access log shows `GET /dist.json` and `GET /v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz` answered 200, `OCX_AUTH_OCX_SH_*` were exported only in the environment, and the final `grep -rn hunter2` over both build directories, the bootstrap cache, `ocx.lock` and `ocx.toml` printed nothing.

## Friction

1. **The pinned CLI cannot read a lock file written by the CLI the tutorial tells me to install.** The tutorial says to install ocx once and run `ocx lock`. That wrote `lock_version = 3` (ocx 0.6.5). find_ocx v0.3.0 bootstraps ocx 0.3.11, which fails with `invalid value: 3, expected 1 or 2`. The error then ends with the hint `no ocx.lock next to ... - run 'ocx lock' and commit it`, although the lock exists and is the thing that is invalid. I found `OCX_INSTALL_VERSION` only by reading the variables reference and guessing that setting it to my own ocx version would help. Nothing in the tutorial, the mirror guide or the README names the pinned ocx version or says the lock must be written by a compatible CLI. Severity: major. Looked at: tutorial, "Fix a failing configure" was not consulted because the message pointed elsewhere, variables reference (`OCX_INSTALL_VERSION`), the error text itself.
2. **The mirror guide does not say which files to put on the mirror.** It gives the shape `<mirror>/<tag>/<filename>` and nothing else. I had to find out by trial that the module wants the `x86_64-unknown-linux-musl` target (not gnu), that the extension differs by version (`.tar.xz` for 0.3.11, `.tar.gz` for 0.6.5), and that every extra version I set via `OCX_INSTALL_VERSION` needs its own archive and a `dist.json` that lists it. The URL of `dist.json` itself (`https://setup.ocx.sh/dist.json`) is not given on the guide page, I inferred it from the sentence "same knobs as the setup.ocx.sh installer". Severity: major. Looked at: mirror guide, variables reference, README.
3. **The download failure message hides the cause.** A missing file on the mirror gave `file DOWNLOAD cannot compute hash on failed download` followed by `"HTTP response code said error"`, with no HTTP status and no hint that the file simply was not on the mirror or which target was requested beyond the URL. The hint still suggests setting the two mirror variables, which I had already set. Severity: minor. Looked at: the configure output; the mirror access log told me it was a 404.
4. **The credential variable name is not derivable.** The docs say `OCX_AUTH_<REGISTRY>_TYPE/USER/TOKEN` but never say how `ocx.sh` or `ghcr.io` becomes `<REGISTRY>`. I guessed `OCX_AUTH_OCX_SH_*`. There is no log line that says a credential was found or used, so I could not distinguish "token applied" from "variable name ignored". In the build the pull actually went to `ghcr.io`, a different registry than the one in the lock, so I still cannot tell whether my variable was consulted. Severity: major (the stated goal cannot be confirmed from the output). Looked at: mirror guide ("Pass credentials"), variables reference, ocx.sh environment reference.
5. **Docker credential helper noise on pull.** Every pull printed `failed to retrieve Docker credentials ... Credential helper 'pass' not found on PATH` for `ghcr.io` before falling back to anonymous. On a locked-down machine this reads like a failure and also shows `OCX_AUTH_*` is not the only credential source consulted. Severity: minor. Looked at: build output; ocx.sh environment reference (DOCKER_CONFIG paragraph).
6. **Mirror guide covers the CLI download but I could not tell what else leaves the network.** Package pulls contacted `ghcr.io` directly. `OCX_MIRRORS` is described but I did not exercise it, and the guide does not list which upstream hosts a firewall must allow or which a mirror must replace. Severity: minor (not attempted). Looked at: mirror guide, tutorial ("network access or a mirror").
7. **The tutorial's prerequisite is circular for the persona.** "You also need the ocx CLI once, to write the lock file (install it)" assumes access to the installer, which downloads from github.com. I only got past it because ocx was already available on my machine. Severity: major for a truly blocked network, none for me. Looked at: tutorial.
8. **Version status line is contradictory.** After I set `OCX_INSTALL_VERSION=0.6.5` the log still said `version knob: OCX_INSTALL_VERSION (pin: 0.3.11)` next to `downloading ocx 0.6.5`, which reads like the knob was ignored. Severity: minor. Looked at: configure output.
9. **Deprecation warning from the generated launcher.** With ocx 0.6.5 the build prints `warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7` because `OCX_TOOLS_RUN` uses `ocx run`. Not a blocker today; it means the documented way of combining find_ocx v0.3.0 with a newer ocx has a visible expiry. Severity: minor. Looked at: build output.
