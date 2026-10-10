# find_ocx discovery notes (docs-plan steps 1-3 and 7)

Scope: steps 1, 2, 3 and 7 of `.claude/skills/docs-plan`. Steps 4-6 and 8-13 (friction logs, ranking,
needs, coverage, tiers, delete list, IA, declarations, `use-cases.yaml`) are not done here.

Evidence rule: every candidate cites repo source (`ocx.cmake`, `Findocx.cmake`, `examples/`, `tests/`,
`.github/workflows/ci.yml`, README headings, `CHANGELOG.md`, git log, `gh pr list`), the plan, or an
alternative-contrast pointer. No candidate is sourced from a docs page title. `gh issue list` for
`ocx-sh/find_ocx` returns no issues; PR titles are #1 and #3 (dist refresh), #2 (platform preference list),
#4 (site port). The sibling research note `.agents/research/docs-use-cases.md` is used only as a pointer to
the alternatives' documented behavior.

## 1. Product shape

`library`, sub-shape **wrapper over a CLI**. find_ocx is a CMake module pair that drives the `ocx` binary
and never re-implements it (README intro, `ocx.cmake` header block).

- Precondition sentence is required above the first fence: CMake and network access (or a mirror). No
  `ocx` install is needed because the module bootstraps a pinned, sha256-verified CLI at first configure.
  The version floor is 3.19 today and 3.25 after the plan.
- Exit condition for first steps: one observed value, the `jq` output printed during a build. Budget:
  at most 4 fenced blocks from the heading that introduces the runnable snippet to the first block
  showing output. Count fences, not list items.
- Not declared in a docs config today. Write `product_shape = "library"` into the site config in the
  artifact step (docs-plan step 1 says to record it).

## 2. Pain points find_ocx solves against CMake-world alternatives

Repo evidence is the left column. The alternative column is contrast from the alternatives' documented
behavior (pointers in `.agents/research/docs-use-cases.md` section 1) and must be re-verified in the
friction logs before any page states it.

| Pain | find_ocx answer (repo evidence) | Alternative and its gap (contrast only) |
|---|---|---|
| Build needs a tool (`jq`, `ninja`, `shellcheck`, a specific `cmake`) and the README says "install X first" per OS | `ocx_project(BINS jq)` exports `OCX_PROJECT_RUN_JQ`, a command list for `add_custom_command` (`examples/project`, `ocx_project` block) | `find_program` + README prerequisite: fails late with "not found", per-OS install steps |
| Tools, not source libraries | `ocx_package` / `ocx_project` provision pre-built binaries | FetchContent / CPM / ExternalProject build dependency source; a tool means building the tool |
| Package manager needs its own bootstrap before CMake starts | `include(ocx)` downloads the pinned CLI into a per-machine cache (`ocx_bootstrap`, `OCX_BOOTSTRAP*`) | vcpkg and Conan need a clone or a Python client plus toolchain/profile setup before `cmake -S -B` |
| Same tool version on laptop and CI | `ocx.lock` digests, `OCX_BOOTSTRAP=ALWAYS`, tests matrix on three OS (`ci.yml`) | `find_program` takes whatever the runner has; floating FetchContent tags drift |
| Silent drift of floating tags | floating tag with no snapshot or pin is `FATAL_ERROR` (`ocx_package` error text; `tests/fixtures/floating_fatal.cmake`); `OCX_ALLOW_FLOATING` is the explicit escape | CPM/FetchContent branch names resolve live; pinning is advice, not enforcement |
| Supply-chain trust of the downloaded tool | manifest sha256 enforced even through `OCX_INSTALL_MIRROR_URL` (`ocx.cmake` variable blocks) | FetchContent without `URL_HASH` trusts the mirror |
| Feeding `find_package` / `find_library` from a provisioned package | `ocx_package(... PULL)` sets `<name>_ROOT` under CMP0074 (`examples/package`) | vcpkg needs a toolchain file, Conan a generator, both before configure |
| Cross build needs the other platform's content from the same pins | `PLATFORM` exports `OCX_<NAME>_PATHS` / `_ENV_<KEY>` (`tests/fixtures/foreign_platform`) | per-platform download URLs hand-maintained in CMake |
| Corporate mirror, offline, credentials out of the cache | `OCX_INSTALL_DIST_URL`, `OCX_INSTALL_MIRROR_URL`, `OCX_MIRRORS`, `OCX_AUTH_*` never snapshotted (`ocx.cmake` header block) | `file(DOWNLOAD)` to a locked mirror fails like a network error |
| Stale lock after editing `ocx.toml` | `ocx lock --check` runs on every configure, exit 65 hint (`tests/fixtures/stale_lock`, `__ocx_default_hint`) | none: the lock-gate is a find_ocx/ocx trait |
| A configure nested in another launcher fails | `OCX_FROZEN`/`OCX_INDEX` inheritance and the `-DOCX_FROZEN= -DOCX_INDEX=` opt-out (`ocx.cmake` header block, `tests/fixtures/package/subproject`) | ExternalProject superbuilds have the analogous variable-leak class |
| Update a vendored module safely | `cmake -P ocx.cmake` self-update verified against `SHA256SUMS` (`tests/self_update_check.cmake`) | copy-paste of CPM.cmake or a Find module |

## 3. Candidate longlist

Source codes: `ocx.cmake` (public command or `.. variable::` block), `find` (`Findocx.cmake`), `ex`
(`examples/<dir>`), `test` (`tests/` or `ci.yml`), `readme` (README heading), `changelog`, `git`/`pr`
(commit or PR title), `alt` (alternative-contrast), `plan` (the plan's Target public API table).

| Id | Candidate (reader task) | Source |
|---|---|---|
| C01 | Get a pinned tool into a custom command or test without installing it on the host | `ocx.cmake` ocx_project; `ex` project; `readme` Quick start; `alt` find_program |
| C02 | Run the tools of a workspace `ocx.toml` in groups, lazily, from genexes and ctest | `ocx.cmake` ocx_project (GROUPS, BINS); `ex` project |
| C03 | Provision one ad-hoc package without an `ocx.toml` | `ocx.cmake` ocx_package; `ex` package |
| C04 | Make a floating tag reproducible: understand the FATAL and pick snapshot, `PINS` or digest | `ocx.cmake` ocx_package, OCX_ALLOW_FLOATING; `test` floating_fatal; `changelog` 0.3.0 |
| C05 | Create, commit and deliberately refresh a `.ocx/` index snapshot | `ocx.cmake` ocx_index FIND/UPDATE_COMMAND; `ex` frozen_index; `changelog` 0.2.0 |
| C06 | Generate the `PINS` digests for a package once | `ocx.cmake` OCX_ALLOW_FLOATING, PINS; `ex` package |
| C07 | Make `find_package`/`find_library` see provisioned content (`PULL`, `<name>_ROOT`) | `ocx.cmake` ocx_package; `ex` package |
| C08 | Use a system `ocx` through `find_package(ocx)` and the `ocx::ocx` target | `find` result vars; `ex` find_package; `changelog` 0.2.0 |
| C09 | Choose `include(ocx)` versus `find_package(ocx)` and know which binary runs | `ocx.cmake` header block; `find` Hints; `changelog` 0.3.0 PATH-first |
| C10 | Make every machine run the identical pinned `ocx` (`OCX_BOOTSTRAP=ALWAYS`, `OCX_INSTALL_VERSION`) | `ocx.cmake` OCX_BOOTSTRAP, OCX_INSTALL_VERSION |
| C11 | Forbid configure-time downloads (`OCX_BOOTSTRAP=OFF`) | `ocx.cmake` OCX_BOOTSTRAP; `test` bootstrap_off |
| C12 | Run the same pinned tools on Linux, macOS and Windows CI, eager pull to fail fast | `ocx.cmake` OCX_PULL, OCX_BOOTSTRAP_CACHE; `test` ci.yml matrix |
| C13 | Place the bootstrap cache where CI can restore it | `ocx.cmake` OCX_BOOTSTRAP_CACHE; `changelog` 0.2.0 (cache hardening) |
| C14 | Configure behind a corporate mirror (dist manifest, binary, registry mirrors) | `ocx.cmake` OCX_INSTALL_DIST_URL/MIRROR_URL, OCX_MIRRORS |
| C15 | Pass registry credentials without leaking them into `CMakeCache.txt` | `ocx.cmake` header block (OCX_AUTH_*) |
| C16 | Configure offline or air-gapped | `ocx.cmake` OCX_BOOTSTRAP=OFF, OCX_OFFLINE passthrough, OCX_FROZEN |
| C17 | Cross-build with another platform's content from the same lock | `ocx.cmake` ocx_project/ocx_package PLATFORM; `test` foreign_platform |
| C18 | Accept a fallback platform (arm64 else amd64 under emulation) | `pr` #2; `ocx.cmake` OCX_DEFAULT_PLATFORM; plan reverts the list to single `PLATFORM` |
| C19 | Fix "stale lock" (exit 65) after editing `ocx.toml` | `ocx.cmake` `__ocx_default_hint`; `test` stale_lock |
| C20 | Fix a nested configure (ExternalProject, superbuild, `ctest --build-and-test`) | `ocx.cmake` header block; `test` package/subproject |
| C21 | Update the vendored `ocx.cmake` / `Findocx.cmake` | `ocx.cmake` OCX_SELF_UPDATE_VERSION/URL; `test` self_update_check; `changelog` 0.2.0 |
| C22 | Use find_ocx in script mode (`cmake -P`) | `readme` Quick start (script mode sentence); `test` script_mode |
| C23 | Understand when a configure hits the network and what a reconfigure costs (memoization, `OCX_REFRESH`) | `ocx.cmake` OCX_REFRESH, memo helpers; `test` reconfigure_check |
| C24 | Force a refresh of memoized ocx results | `ocx.cmake` OCX_REFRESH |
| C25 | Look up one command signature or variable | `ocx.cmake` command and variable blocks; `find` |
| C26 | Understand why find_ocx never re-implements ocx (trust and lock contracts) | `readme` intro; `ocx.cmake` header block |
| C27 | Run the repo's own test matrix across CMake versions (dogfooding) | `readme` Testing; `test` helpers.cmake |
| C28 | Refresh the embedded dist snapshot and bump the pin | `pr` #1, #3; `.claude/rules/dist-snapshot.md` (maintainer) |
| C29 | Run `ocx_bootstrap` explicitly (VERSION, TRIPLE) | `ocx.cmake` ocx_bootstrap |
| C30 | Declare site policy: allow unverified or yanked, custom Sigstore root | `plan` ocx_policy |
| C31 | Point at an ocx config file or disable config discovery (CONFIG, NO_CONFIG, managed config) | `plan` CONFIG/NO_CONFIG |
| C32 | Use a patch snapshot in a build (PATCH_SNAPSHOT) | `plan` PATCH_SNAPSHOT |
| C33 | Catch a typo in `BINS` at configure time, with the declared names listed | `plan` BINS validation |
| C34 | Know which `OCX_*` env vars are forwarded, translucent, explicit-only or pinned | `plan` env classes |
| C35 | Decode an ocx exit code to a cause and a fix (hints 64-87, retry on 69/74/75) | `plan` exit hints; `ocx.cmake` `__ocx_default_hint` |
| C36 | Fix a second `ocx.cmake` copy at another version in one build | `plan` MOD-07 version guard |
| C37 | Bootstrap from a mirror with `DIST_MANIFEST` self-verify | `plan` ocx_bootstrap DIST_MANIFEST |
| C38 | Migrate from 0.3 to 0.4 (floor, PLATFORM list gone, `ocx exec`, new keywords) | `plan` breaking changes; `changelog` |

## 4. Shortlist

Merged duplicates: C06 into C04, C24 into C23, C13 into C12, C26 into C09, C18 into C17, C29 into C10.

| Rank seed | Task | Merged ids | Notes |
|---|---|---|---|
| S1 | A tool in the build, no host install | C01, C02 | entry task; precondition sentence needed |
| S2 | Fix and prevent the floating-tag FATAL | C04, C05, C06 | `ocx.cmake` error text names three fixes |
| S3 | Add or change a tool in `ocx.toml` and fix the stale lock | C19 | everyday loop, exit 65 |
| S4 | Make `find_package` see provisioned content | C07, C03 | |
| S5 | Configure behind a mirror, keep credentials out of the cache | C14, C15, C16, C11, C37 | integration |
| S6 | Cross-build with foreign platform content | C17, C18 | integration |
| S7 | Reproducible CI on three OS | C12, C10, C13 | integration |
| S8 | Fix a nested configure | C20 | troubleshooting |
| S9 | Choose and understand the two entry points | C08, C09 | explanation |
| S10 | Update the vendored files | C21 | |
| S11 | Understand reconfigure cost and refresh | C23 | explanation |
| S12 | Catch BINS typos, decode exit hints, policy and config (new 0.4 surface) | C30-C36 | cannot be friction-logged against v0.3.0; log after P2 merges |
| S13 | Migrate 0.3 to 0.4 | C38 | after P2 |
| S14 | Look up a signature or variable | C25 | reference, generated |

## 5. Out-of-scope list

Named so the longlist stays auditable. Each is a maintainer task or an internal.

- C27 repo test matrix across CMake versions: maintainer/contributor material, covered by the repo's
  CONTRIBUTING-style notes, not a reader task of the module.
- C28 embedded dist snapshot refresh and pin bump: maintainer task (`.claude/rules/dist-snapshot.md`).
- C22 script mode as its own page: one sentence in the entry-points explanation and the self-update
  how-to (S10); no separate page.
- C24 `OCX_REFRESH`: one entry in the generated variable reference plus a sentence in S11.
- Memoization fingerprint internals, `__ocx_*` private helpers, `taskfile.yml` tasks, `renovate.json`:
  internals, not exported entry points.
- Writing an ocx package or publishing to a registry: owned by the `ocx` docs, not find_ocx.

Every exported entry point appears in a shortlist row or here: `ocx_bootstrap` (S9/C10, S5),
`ocx_project` (S1, S3, S6), `ocx_package` (S2, S4, S6), `ocx_index` (S2), `ocx_self_update` (S10),
`include(ocx)` / `find_package(ocx)` (S9), `ocx::ocx` (S9), the `OCX_*` variables (S5, S7, S14),
`ocx_policy` (S12).

## 6. Existing page inventory

Published tree: `site/pages/**` (Starlight sources; the reference pages are generated at build from
`#[=[.rst:` blocks) and `docs/*.rst` (Sphinx source, retired by the plan). Prose words exclude fenced
code, HTML comments and directive bodies. Type source `declared` means a `<!-- doc_type: -->` comment is
already on the page; `nav` means seeded from the `astro.config.mjs` sidebar group; `content` means a
content read. Sidebar groups seed as follows: Overview `landing`, Guides `how-to`, Concepts `explanation`,
Reference `reference`; Tutorial is a single link and needs a content read.

| Path | Prose words | Proposed doc_type | Type source | Note |
|---|---|---|---|---|
| `site/pages/index.md` | 223 | landing | declared, matches nav Overview | |
| `site/pages/tutorial.md` | 365 | tutorial | declared | Tutorial is justified only if the reader assembles two or more interacting concepts (vendor, `ocx.toml`, `ocx_project`, custom command); else retype as a quickstart `how-to` in the IA step |
| `site/pages/guides/workspace-tools.md` | 195 | how-to | declared, matches nav | |
| `site/pages/guides/pin-and-freeze.md` | 270 | how-to | declared, matches nav | |
| `site/pages/guides/find-package.md` | 199 | how-to | declared, matches nav | |
| `site/pages/guides/update-vendored.md` | 36 | how-to | declared, matches nav | very short; 36 words, check for a stub in step 8 |
| `site/pages/guides/ci.md` | 237 | how-to | declared, matches nav | |
| `site/pages/guides/mirror.md` | 262 | how-to | declared, matches nav | |
| `site/pages/guides/cross-build.md` | 153 | how-to | declared, matches nav | |
| `site/pages/guides/nested-builds.md` | 186 | troubleshooting | declared, nav says how-to ("Fix a failing configure") | content wins: symptom-keyed catalogue of three errors |
| `site/pages/concepts/how-it-works.md` | 244 | explanation | declared, matches nav | |
| `site/pages/concepts/entry-points.md` | 36 | explanation | declared, matches nav | 36 words; stub candidate |
| `site/pages/concepts/reproducible-first.md` | 37 | explanation | declared, matches nav | 37 words; stub candidate |
| `site/pages/concepts/lazy-vs-eager.md` | 32 | explanation | declared, matches nav | 32 words; stub candidate |
| `site/pages/reference/commands.md` | 23 | reference | declared, matches nav | generated directive page, exempt from stub test |
| `site/pages/reference/variables.md` | 22 | reference | declared, matches nav | generated directive page, exempt |
| `site/pages/reference/findocx.md` | 18 | reference | declared, matches nav | generated directive page, exempt |
| `site/pages/reference/examples.md` | 50 | reference | declared, matches nav | verbatim includes of `examples/` |
| `site/pages/reference/examples-packages.md` | 24 | reference | declared | verbatim include, candidate to merge into `examples.md` |
| `site/pages/reference/examples-discovery.md` | 28 | reference | declared | verbatim include, candidate to merge into `examples.md` |
| `docs/index.rst` | 846 | explanation | content (mixed: landing, quick start, how-to, explanation in one page) | Sphinx source, retired by the plan; content already ported to the pages above |
| `docs/examples.rst` | 393 | reference | content | Sphinx source, retired |
| `docs/reference.rst` | 29 | reference | content | autodoc-style directive page, exempt from stub test; retired |
| `README.md` | 229 (headings: Quick start, Documentation, Examples, Testing, License) | readme | declared (`<!-- doc_type: readme -->`) | counted in the README step, not in the published tree |
| `CHANGELOG.md` | n/a | changelog | content | generated by git-cliff |

Declaration findings for step 12 (proposals only, nothing edited here):

- Every `site/pages` page carries a `doc_type` comment already. `doc_tier` is declared on every page, but
  the skill requires it only on `tutorial`, `how-to` and `landing`. Explanation, reference and
  troubleshooting pages therefore should drop `doc_tier`, or the gate must tolerate it. Decide in step 12.
- The three reference example pages and the three short concept pages are the main merge/expand
  candidates for step 8.
- No page lives outside the declared tiers per nav; tier was assigned by the earlier port, not derived
  from the sidebar, which is the right direction.

## 7. Friction-log targets (top 6 for the no-repo-context subagent)

Run against the published v0.3.0 module. Ids and one-line goals are returned in the structured result.
S7 (CI), S8 (nested), S9, S10 are shortlisted but ranked below the six.
