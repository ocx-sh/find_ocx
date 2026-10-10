# Friction log: add a tool and fix the stale lock

## Setup

- Persona: Dana, a developer on a team that already uses `ocx_project` with a committed `ocx.toml` and `ocx.lock`. First time touching find_ocx; has not seen its source. Used only the public README, the v0.3.0 release assets, https://ocx.sh/integrations/cmake/ and `--help` of the installed `ocx 0.6.5`.
- Date: 2026-10-10.
- Starting state (built in the first commands of the Attempt): a project vendoring `cmake/ocx.cmake` + `cmake/Findocx.cmake` from release v0.3.0 (sha256 verified), `ocx.toml` with only `jq` in `[tools]`, a matching committed `ocx.lock`, `CMakeLists.txt` calling `ocx_project(BINS jq)` with one ctest (`data_valid`) that runs jq. The baseline configure and ctest were green.
- Goal: add shellcheck to a `lint` group in `ocx.toml`, get configure green again after the stale-lock failure, and finish with `OCX_PROJECT_RUN_SHELLCHECK` exported and a ctest running shellcheck on a script passing.
- Environment: WSL2, isolated `OCX_HOME`, cmake 4 via `ocx package exec ocx.sh/kitware/cmake:4 -- cmake`. The host has a system shellcheck at `/usr/bin/shellcheck` and `/usr/sbin/shellcheck`. To simulate a teammate's/CI machine without one, `../nohost.sh` (my wrapper, a minimal PATH with no shellcheck) is used in the later commands.

## Attempt

$ gh api repos/ocx-sh/find_ocx/readme --jq .content | base64 -d

```
[... 74 lines elided]
```

README quick start: `ocx_project(BINS jq)`, "Guides ... are at https://ocx.sh/integrations/cmake/". Nothing about changing the toolchain after the first commit.

$ gh release view v0.3.0 -R ocx-sh/find_ocx | head -40

```
title:	v0.3.0
tag:	v0.3.0
[... 3 lines elided]
asset:	Findocx.cmake
asset:	ocx.cmake
asset:	SHA256SUMS
--
[... 7 lines elided]
```

$ curl -sL https://ocx.sh/integrations/cmake/guides/workspace-tools/   # page text, HTML stripped

```
[... 38 lines elided]
ocx.toml[tools]
jq = "ocx.sh/jqlang/jq:latest"
[group.lint.tools]
shellcheck = "ocx.sh/shellcheck/shellcheck:latest"
[... 8 lines elided]
ocx_project(NAME TOOLS BINS jq)
NAME TOOLS gives OCX_TOOLS_RUN and OCX_TOOLS_RUN_JQ.
[... 20 lines elided]
ocx_project(NAME LINT GROUPS lint)
add_custom_target(lint
  COMMAND ${OCX_LINT_RUN} shellcheck "${CMAKE_CURRENT_SOURCE_DIR}/hello.sh"
  VERBATIM
)
[... 20 lines elided]
Needs addressed: problems 1 and 2 of the use-case research.
```

$ curl -sL https://ocx.sh/integrations/cmake/reference/commands/   # page text, HTML stripped; ocx_project section

```
[... 20 lines elided]
ocx_project([NAME <name>] [TOML <ocx.toml>] [LOCK <ocx.lock>]
            [GROUPS <group>...] [BINS <tool>...]
            [PLATFORM <ocx-platform>] [PULL])
[... 6 lines elided]
OCX_<NAME>_RUN_<BIN>
Per-tool convenience command for every name in BINS. Entries are executable names on the composed environment (a package may ship several tools), not package references.

TOML defaults to OCX_PROJECT_FILE or the nearest ocx.toml between the calling directory and the last project() source dir; LOCK defaults to the sibling ocx.lock. ocx lock --check always runs (offline staleness gate); PULL (or the global OCX_PULL) materializes eagerly at configure time.
[... 80 lines elided]
```

The ocx_project section never describes GROUPS (BINS and NAME are described, GROUPS is only in the signature).

$ mkdir -p proj/cmake && cd proj   # all commands below run from proj/ with OCX_HOME=<scratch>/ocxhome (each prefixed with a "$ " line; a trailing "[exit N]" line is added by my logging wrapper)

$ gh release download v0.3.0 -R ocx-sh/find_ocx -D cmake && ls cmake && cd cmake && sha256sum -c SHA256SUMS

```
Findocx.cmake
ocx.cmake
SHA256SUMS
Findocx.cmake: OK
ocx.cmake: OK
[exit 0]
```

$ ocx lock 2>&1 | tail -20; cat ocx.lock

```
pulling count=1
Downloading layer sha256:88ad916b0507 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome/temp/9c13e7a59201751a36e83176bff4a013
warning: add `ocx.lock merge=union` to .gitattributes to avoid merge conflicts
Binding  Group    Digest                                                                 
jq       default  sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
[metadata]
lock_version = 3
declaration_hash_version = 1
declaration_hash = "sha256:e0361206f7a2ebde72dda210f86a838bcd00335fffb2cb77c55bd940b673c4a6"
generated_by = "ocx 0.6.5"
generated_at = "2026-10-10T16:44:45Z"

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

$ git init -q -b main . && git add -A && git -c user.name=Dana -c user.email=dana@example.com commit -qm "jq toolchain" && git log --oneline

```
6c98274 jq toolchain
[exit 0]
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build 2>&1 | tail -25

```
Package 'ocx.sh/kitware/cmake:4' not found locally, pulling.
Downloading layer sha256:61c5ceac1af3 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome/temp/5d1c38a94867e65acad24f47e861cc47
-- find_ocx: using ocx from PATH (/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx) - OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead
-- Configuring done (0.0s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
[exit 0]
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- ctest --test-dir build --output-on-failure 2>&1 | tail -15

```
Test project /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
    Start 1: data_valid
1/1 Test #1: data_valid .......................   Passed    0.02 sec

100% tests passed out of 1

Total Test time (real) =   0.02 sec
[exit 0]
```

$ cat >> ocx.toml <<EOF

```

[group.lint.tools]
shellcheck = "ocx.sh/shellcheck/shellcheck:latest"
EOF
cat ocx.toml
[tools]
jq = "ocx.sh/jqlang/jq:latest"

[group.lint.tools]
shellcheck = "ocx.sh/shellcheck/shellcheck:latest"
[exit 0]
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build 2>&1 | tail -25

```
CMake Error at cmake/ocx.cmake:443 (message):
  find_ocx: checking
  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/ocx.toml
  against its lockfile failed (exit 65): ocx --project
  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/ocx.toml
  lock --check

  ocx.lock does not match ocx.toml; run `ocx lock` to update it



  hint: run 'ocx lock' next to
  /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/ocx.toml
  and commit the updated ocx.lock
Call Stack (most recent call first):
  cmake/ocx.cmake:919 (__ocx_run)
  CMakeLists.txt:5 (ocx_project)


-- Configuring incomplete, errors occurred!
[exit 0]
```

$ ocx lock

```
pulling count=2
Downloading layer sha256:794849587f27 to /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome/temp/e65c6e61c6a61998d63a31ef4f597d59
warning: add `ocx.lock merge=union` to .gitattributes to avoid merge conflicts
Binding     Group    Digest                                                                 
jq          default  sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
shellcheck  lint     sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379
[exit 0]
```

$ git status --short; git diff --stat

```
 M ocx.lock
 M ocx.toml
?? build/
 ocx.lock | 16 ++++++++++++++--
 ocx.toml |  3 +++
 2 files changed, 17 insertions(+), 2 deletions(-)
[exit 0]
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build

```
-- Configuring done (0.0s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
[exit 0]
```

$ git add -A && git -c user.name=Dana -c user.email=dana@example.com commit -qm "add shellcheck to lint group" && git log --oneline

```
14f3da4 add shellcheck to lint group
6c98274 jq toolchain
[exit 0]
```

$ sed -i "s/^ocx_project(BINS jq)/ocx_project(BINS jq shellcheck)/" CMakeLists.txt && cat >> CMakeLists.txt <<EOF

```
add_test(NAME shellcheck_hello COMMAND \${OCX_PROJECT_RUN_SHELLCHECK} \${CMAKE_SOURCE_DIR}/hello.sh)
EOF
cat CMakeLists.txt
cmake_minimum_required(VERSION 3.19)
project(demo NONE)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
include(ocx)
ocx_project(BINS jq shellcheck)
enable_testing()
add_test(NAME data_valid COMMAND ${OCX_PROJECT_RUN_JQ} -e ".greeting == \"hello\"" ${CMAKE_SOURCE_DIR}/data.json)
add_test(NAME shellcheck_hello COMMAND ${OCX_PROJECT_RUN_SHELLCHECK} ${CMAKE_SOURCE_DIR}/hello.sh)
[exit 0]
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build

```
-- Configuring done (0.0s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
[exit 0]
```

$ ocx package exec ocx.sh/kitware/cmake:4 -- ctest --test-dir build --output-on-failure

```
Test project /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
    Start 1: data_valid
1/2 Test #1: data_valid .......................   Passed    0.01 sec
    Start 2: shellcheck_hello
2/2 Test #2: shellcheck_hello .................   Passed    0.03 sec

100% tests passed out of 2

Total Test time (real) =   0.05 sec
[exit 0]
```

$ printf "#!/bin/sh\necho \$x \$(ls)\nrm -rf \$d/\n" > bad.sh; ocx package exec ocx.sh/kitware/cmake:4 -- cmake -E echo; ocx exec -- true 2>&1 | head -3; ocx --project ocx.toml exec -- shellcheck bad.sh 2>&1 | head -20

```


In bad.sh line 2:
echo $x $(ls)
     ^-- SC2154 (warning): x is referenced but not assigned.
     ^-- SC2086 (info): Double quote to prevent globbing and word splitting.
        ^---^ SC2046 (warning): Quote this to prevent word splitting.

Did you mean:
echo "$x" $(ls)


In bad.sh line 3:
rm -rf $d/
       ^-^ SC2115 (warning): Use "${var:?}" to ensure this never expands to / .
       ^-- SC2154 (warning): d is referenced but not assigned.
       ^-- SC2086 (info): Double quote to prevent globbing and word splitting.

Did you mean:
rm -rf "$d"/

[exit 0]
```

$ grep -E "OCX_PROJECT_RUN" build/CMakeCache.txt

```
OCX_PROJECT_RUN:INTERNAL=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin/cmake;-E;env;OCX_PROJECT=;OCX_HOME=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome;/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx;--project;/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/ocx.toml;run;--
OCX_PROJECT_RUN_JQ:INTERNAL=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin/cmake;-E;env;OCX_PROJECT=;OCX_HOME=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome;/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx;--project;/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/ocx.toml;run;--;jq
OCX_PROJECT_RUN_SHELLCHECK:INTERNAL=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin/cmake;-E;env;OCX_PROJECT=;OCX_HOME=/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome;/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx;--project;/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/ocx.toml;run;--;shellcheck
[exit 0]
```

$ echo "add_test(NAME shellcheck_bad COMMAND \${OCX_PROJECT_RUN_SHELLCHECK} \${CMAKE_SOURCE_DIR}/bad.sh)" >> CMakeLists.txt; ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build >/dev/null && ocx package exec ocx.sh/kitware/cmake:4 -- ctest --test-dir build 2>&1 | tail -12

```
    Start 3: shellcheck_bad
3/3 Test #3: shellcheck_bad ...................***Failed    0.03 sec

67% tests passed, 1 tests failed out of 3

Total Test time (real) =   0.07 sec

The following tests FAILED:
	  3 - shellcheck_bad (Failed)
Errors while running CTest
Output from these tests are in: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build/Testing/Temporary/LastTest.log
Use "--rerun-failed --output-on-failure" to re-run the failed cases verbosely.
[exit 0]
```

$ ocx run --help 2>&1 | head -30

```
Deprecated spelling of `ocx exec`; removed in 0.7

Usage: ocx run [OPTIONS] [NAMES]... -- <ARGV>...

Arguments:
  [NAMES]...
          Binding names to compose into the child env. Each name must resolve unambiguously inside the selected scope. Only the named tools are resolved to a host leaf, so an unrelated tool in scope that ships no leaf for this host does not block the run. An empty list means "every binding in scope"; then every tool must resolve

  <ARGV>...
          Command to execute, with arguments. The command runs with the composed package env. `--` is mandatory and at least one argv token is required

Options:
  -g, --group <GROUPS>
          Restrict the composition to the named group(s).
          
          Repeatable and comma-separated: `-g ci,lint -g release`. The reserved name `default` selects the top-level `[tools]` table. The reserved name `all` expands to `default` plus every declared `[group.*]`. When omitted, scope is exactly `[tools]` - an omitted `-g` does not mean "everything", it means "the default group".
          
          A group's own `[env]` composes after the project's, in the order the groups are given, so a later `-g` wins.

      --clean
          Start with a clean environment containing only the package variables, instead of inheriting the current shell environment

      --env <NAME|KEY[:TYPE[:SEP]]=VALUE>
          Set an environment variable for this invocation, or pass one by name.
          
          Repeatable; a later `--env` for the same key wins. Applied last, so it overrides package variables and, for the project toolchain, the project and group `[env]` tables. Splits on the FIRST `=` (`--env FOO=a=b` sets `FOO` to `a=b`); values are literal. A bare `--env NAME` copies this process's own `NAME` into the child (skipped if unset) -- the way an allowlist survives `--clean`. `TYPE` is `constant` (replace, default), `path` (prepend, resolved against the current directory) or `list` (append, joined by `SEP`); `PATH` without `:path` replaces the composed `PATH`, dropping every package directory. `OCX_*`/`__OCX_*` keys and a qualified key with no value are rejected; every failure exits 64. Full grammar, including the `SEP` default: <https://ocx.sh/docs/reference/command-line#exec>

      --lazy-mode <MODE>
          Control when a package's content downloads: now, or on first use.
          
[exit 0]
```

$ which shellcheck; ocx --project ocx.toml run -- sh -c "command -v shellcheck"; ocx --project ocx.toml run -g lint -- sh -c "command -v shellcheck"; ocx --project ocx.toml run --clean -- sh -c "command -v shellcheck"

```
/usr/sbin/shellcheck
warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7
/usr/sbin/shellcheck
warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7
/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/.ocx/toolchain/links/lint/shellcheck/content/shellcheck
warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7
error: "sh" does not resolve in the composed environment; searched: ["/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/.ocx/toolchain/links/default/jq/content"]
[exit 65]
```

$ git status --short; PATH=$(echo $PATH | tr : '\n' | grep -v -x /usr/sbin | paste -sd:) bash -c 'command -v shellcheck || echo "no host shellcheck"; ocx package exec ocx.sh/kitware/cmake:4 -- ctest --test-dir build --output-on-failure -R shellcheck_hello 2>&1 | tail -25'

```
 M CMakeLists.txt
?? bad.sh
/usr/bin/shellcheck
Test project /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
    Start 2: shellcheck_hello
1/1 Test #2: shellcheck_hello .................   Passed    0.02 sec

100% tests passed out of 1

Total Test time (real) =   0.02 sec
[exit 0]
```

$ ../nohost.sh bash -c 'command -v shellcheck || echo "no host shellcheck"; ocx package exec ocx.sh/kitware/cmake:4 -- ctest --test-dir build --output-on-failure -R shellcheck_hello 2>&1 | tail -25'

```
no host shellcheck
bash: line 1: tail: command not found
[exit 127]
```

$ ../nohost.sh bash -c 'command -v shellcheck || echo "no host shellcheck"; ocx package exec ocx.sh/kitware/cmake:4 -- ctest --test-dir build --output-on-failure -R shellcheck_hello 2>&1 | tail -25'

```
no host shellcheck
Test project /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
    Start 2: shellcheck_hello
1/1 Test #2: shellcheck_hello .................***Failed    0.01 sec
warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7
error: "shellcheck" does not resolve in the composed environment; searched: ["/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/.ocx/toolchain/links/default/jq/content", "/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin", "/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/nohost-bin", "/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin"]


0% tests passed, 1 tests failed out of 1

Total Test time (real) =   0.02 sec

The following tests FAILED:
	  2 - shellcheck_hello (Failed)
Errors while running CTest
[exit 0]
```

$ sed -i "s/^ocx_project(BINS jq shellcheck)/ocx_project(GROUPS lint BINS jq shellcheck)/" CMakeLists.txt; grep -n ocx_project CMakeLists.txt

```
5:ocx_project(GROUPS lint BINS jq shellcheck)
[exit 0]
```

$ ../nohost.sh bash -c 'ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build; ocx package exec ocx.sh/kitware/cmake:4 -- ctest --test-dir build --output-on-failure 2>&1 | tail -30'

```
-- Configuring done (0.0s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
     ^-- SC2086 (info): Double quote to prevent globbing and word splitting.
        ^---^ SC2046 (warning): Quote this to prevent word splitting.

Did you mean:
echo "$x" $(ls)


In /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/bad.sh line 3:
rm -rf $d/
       ^-^ SC2115 (warning): Use "${var:?}" to ensure this never expands to / .
       ^-- SC2154 (warning): d is referenced but not assigned.
       ^-- SC2086 (info): Double quote to prevent globbing and word splitting.

Did you mean:
rm -rf "$d"/

For more information:
  https://www.shellcheck.net/wiki/SC2046 -- Quote this to prevent word splitt...
  https://www.shellcheck.net/wiki/SC2115 -- Use "${var:?}" to ensure this nev...
  https://www.shellcheck.net/wiki/SC2154 -- d is referenced but not assigned.


33% tests passed, 2 tests failed out of 3

Total Test time (real) =   0.05 sec

The following tests FAILED:
	  1 - data_valid (Failed)
	  3 - shellcheck_bad (Failed)
Errors while running CTest
[exit 0]
```

$ ../nohost.sh bash -c 'ocx package exec ocx.sh/kitware/cmake:4 -- ctest --test-dir build --output-on-failure -R data_valid 2>&1 | tail -30'

```
Test project /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
    Start 1: data_valid
1/1 Test #1: data_valid .......................***Failed    0.01 sec
warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7
error: "jq" does not resolve in the composed environment; searched: ["/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/.ocx/toolchain/links/lint/shellcheck/content", "/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin", "/tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/nohost-bin", "/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin"]


0% tests passed, 1 tests failed out of 1

Total Test time (real) =   0.01 sec

The following tests FAILED:
	  1 - data_valid (Failed)
Errors while running CTest
[exit 0]
```

$ grep OCX_PROJECT_RUN_JQ build/CMakeCache.txt | sed "s#/tmp/claude[^;]*/scratchpad/[^/]*/##g"

```
OCX_PROJECT_RUN_JQ:INTERNAL=ocxhome/packages/ocx.sh/sha256/03/ea6ed6709a4e7a2331fc356f6baee9/content/bin/cmake;-E;env;OCX_PROJECT=;OCX_HOME=ocxhome;/home/mherwig/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx;--project;proj/ocx.toml;run;-g;lint;--;jq
[exit 0]
```

$ sed -i "s/^ocx_project(GROUPS lint BINS/ocx_project(GROUPS default lint BINS/" CMakeLists.txt; grep -n ocx_project CMakeLists.txt

```
5:ocx_project(GROUPS default lint BINS jq shellcheck)
[exit 0]
```

$ ../nohost.sh bash -c 'ocx package exec ocx.sh/kitware/cmake:4 -- cmake -S . -B build; ocx package exec ocx.sh/kitware/cmake:4 -- ctest --test-dir build --output-on-failure -E shellcheck_bad 2>&1 | tail -30'

```
-- Configuring done (0.0s)
-- Generating done (0.0s)
-- Build files have been written to: /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
Test project /tmp/claude-1000/-home-mherwig-dev-find-ocx/d69e2447-3248-4443-aa8b-a84060647905/scratchpad/friction-add-tool-and-fix-stale-lock/proj/build
    Start 1: data_valid
1/2 Test #1: data_valid .......................   Passed    0.01 sec
    Start 2: shellcheck_hello
2/2 Test #2: shellcheck_hello .................   Passed    0.02 sec

100% tests passed out of 2

Total Test time (real) =   0.03 sec
[exit 0]
```

$ sed -i "/shellcheck_bad/d" CMakeLists.txt; rm bad.sh; git status --short; ls -a; ls .ocx 2>&1

```
 M CMakeLists.txt
.
..
build
cmake
CMakeLists.txt
data.json
.git
.gitignore
hello.sh
.ocx
ocx.lock
ocx.toml
toolchain
[exit 0]
```

$ git add -A && git -c user.name=Dana -c user.email=dana@example.com commit -qm "run shellcheck from the lint group in ctest" && git log --oneline && git status --short

```
f7e5924 run shellcheck from the lint group in ctest
14f3da4 add shellcheck to lint group
6c98274 jq toolchain
[exit 0]
```

$ git ls-files; ls -a .ocx; cat .ocx/.gitignore 2>&1

```
.gitignore
CMakeLists.txt
cmake/Findocx.cmake
cmake/SHA256SUMS
cmake/ocx.cmake
data.json
hello.sh
ocx.lock
ocx.toml
.
..
toolchain
cat: .ocx/.gitignore: No such file or directory
[exit 1]
```

$ git check-ignore -v .ocx/toolchain; git status --short --ignored

```
!! .ocx/
!! build/
[exit 0]
```

## Friction

1. **Silent false green: `OCX_PROJECT_RUN_SHELLCHECK` exists and the test passes, but it ran the host shellcheck, not the OCX one** (major). After relocking I added `shellcheck` to `BINS` only. Configure and ctest were green. Only by checking `command -v shellcheck` inside `ocx run` did I see that `/usr/sbin/shellcheck` from my machine was used; with the host PATH stripped the same test fails with `"shellcheck" does not resolve in the composed environment`. A teammate or CI runner without shellcheck would fail while I see green. Looked in: guides/workspace-tools, reference/commands (`ocx_project`). Neither says that `BINS` entries from a non-default group are resolved only if that group is listed in `GROUPS`.
2. **`GROUPS lint` drops the top-level tools** (major). Adding `GROUPS lint` made shellcheck work but broke the previously passing jq test (`"jq" does not resolve in the composed environment`). The working form was `GROUPS default lint`. The token `default` appears only in `ocx run --help` (the `-g` option), not in the find_ocx docs; the `ocx_project` reference describes `NAME`, `BINS`, `PLATFORM` but gives no description of `GROUPS`. Looked in: reference/commands, guides/workspace-tools (its group example uses a separate `ocx_project(NAME LINT GROUPS lint)` call, which hides this).
3. **No guidance for the "I edited ocx.toml" case** (minor). The stale-lock error itself was good (names exit 65, says run `ocx lock`, says commit the lock). But none of the guide, README or commands page covers the add-a-tool loop (edit toml, `ocx lock`, commit, reconfigure); the reference only says `ocx lock --check always runs`. `ocx lock` also printed `warning: add `ocx.lock merge=union` to .gitattributes to avoid merge conflicts`, which the find_ocx docs do not mention. Looked in: guides/workspace-tools, concepts/how-it-works, reference/commands.
4. **Deprecation warning on every launcher run** (minor). The launchers use `ocx ... run --`; with ocx 0.6.5 each invocation prints `warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7`. It is invisible while tests pass (ctest hides output) and only surfaces in failures. As a user I cannot tell whether the vendored v0.3.0 module keeps working on ocx 0.7. Looked in: no find_ocx doc mentions the ocx version range.
5. **Error text is very long** (minor). The configure error for the stale lock repeats the absolute `ocx.toml` path three times with blank lines in between; the actual instruction is at the bottom. The "searched:" list in the launcher failures lists package directories but never names the group set in effect, so it was not obvious from the error that the group was the cause (see 1 and 2). Looked in: the error output.
6. **Leaked internal text in the guide** (minor). The workspace-tools page ends with "Needs addressed: problems 1 and 2 of the use-case research." which means nothing to a reader.
7. **Unclear whether `.ocx/` in the project root should be committed** (minor). After running launchers a `.ocx/toolchain/` directory exists in the project root; git reported it ignored (I did not add an ignore rule and did not find out why). The docs use `.ocx/` as the name of a committed index snapshot ("commit it next to your CMakeLists.txt as `.ocx/`"), so the same name for a local, uncommitted directory is confusing. Looked in: reference/commands (`ocx_index`), README (`examples/frozen_index`).

Outcome: succeeded. Final state committed (`f7e5924`): `ocx.lock` relocked with shellcheck in group `lint`, `ocx_project(GROUPS default lint BINS jq shellcheck)`, `OCX_PROJECT_RUN_SHELLCHECK` exported, and ctest `data_valid` + `shellcheck_hello` passing with no host shellcheck on PATH.
