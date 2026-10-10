# Plan: find_ocx → ocx 0.6.5, family-homogeneous API, CMake-rules compliance, use-case docs revamp with casts

## Context

- `find_ocx` pins ocx **0.3.11**; upstream is **0.6.5** (no unreleased changes). origin/main
  ([#4](https://github.com/ocx-sh/find_ocx/pull/4) site port, [#2](https://github.com/ocx-sh/find_ocx/pull/2)
  preference list) already uses namespaced `ocx.sh/<owner>/<name>` refs but never bumped the pin, env handling,
  exit hints, or CLI verbs. Local `main` is stale; primary checkout holds another session's uncommitted WIP.
- [#2](https://github.com/ocx-sh/find_ocx/pull/2) is **broken on ocx ≥0.5**: `-p` is single-valued (comma = `+feature`
  list only). rules_ocx dropped the list too.
- `rules_ocx` (v0.5.0, ocx 0.6.2) and `www-setup` carry the reference patterns: 4-class env table, exit-hint table
  64–87 with retry on 69/74/75, `inspect --closure` bin validation, config/patch-snapshot attrs, `ocx.policy`,
  lockstep `bump_ocx.py`, Starlight site on `ocx.sh/integrations/<x>/`.
- New repo rules (`cmake-build`, `code-docs`, `docs-quality`; grim bundles `cmake-essentials`,
  `code-docs-essentials`) are untracked in the primary checkout and violated in many places (floor 3.19 untested,
  `${ARGN}` parses, `file(DOWNLOAD)` without TLS/timeout, no `ENCODING`, `_ROOT` without `_DIR` unset, …).
- Docs: Starlight `site/` exists (ported from Sphinx by `site/scripts/port-docs.mjs`) but is a port, not a
  use-case rewrite; no casts; no `doc_type`/`doc_tier` on Sphinx sources.

**Decisions (owner, 2026-10-10):** single `PLATFORM` + keep per-platform `PINS` (rules_ocx parity, `@sha256:` in
`PACKAGE` also accepted); docs SoT = Markdown in `site/pages` + reference generated from in-source `#[=[.rst:` blocks,
Sphinx retired; casts regenerated at site build (gitignored, ocx exemplar). Breaking changes allowed → **v0.4.0**.

## Execution model

Ultracode Workflow, fully autonomous, orchestrator = main loop. All work in a **sibling worktree**
`/home/mherwig/dev/find_ocx-ocx06` (`.agents/worktrees/` is not gitignored; primary checkout untouched), branch
`feat/ocx-0.6-family` off `origin/main`. Parallel implementation pipelines each get their own worktree
(`isolation: worktree`) and merge serially onto the feature branch. Models: `sonnet` default, `haiku` for
mechanical renames/regeneration, `opus` only after a sonnet retry fails (counter rule). ~22 agents total (above
the 10-agent guideline because the ask is max parallelism). Every spawn carries `Model rationale:`.

First commit on the branch: this plan → `.agents/plans/plan_ocx-0.6-family.md`; `.gitignore` gains
`.agents/worktrees/`; `grimoire.toml` merged (clients `claude`,`codex`; bundles docs/cmake/code-docs essentials),
`grim install`, lock + installed copies committed.

## Target public API (the contract every pipeline codes against)

| Concept | rules_ocx | find_ocx after |
|---|---|---|
| CLI download | `ocx.download(version, triple, dist_manifest)` | `ocx_bootstrap(VERSION TRIPLE DIST_MANIFEST)` + knobs `OCX_INSTALL_VERSION/_DIST_URL/_MIRROR_URL` (unchanged, www-setup parity); `OCX_BOOTSTRAP` ON/OFF/ALWAYS, `OCX_EXECUTABLE` kept |
| Project tier | `ocx.project(name, ocx_toml, ocx_lock, groups, bins, platform, config, no_config, patch_snapshot)` | `ocx_project(NAME TOML LOCK GROUPS BINS PLATFORM CONFIG NO_CONFIG PATCH_SNAPSHOT PULL)` |
| Package tier | `ocx.package(name, package, pins, index, bins, …)` | `ocx_package(NAME PACKAGE PINS INDEX\|NO_INDEX BINS PLATFORM CONFIG NO_CONFIG PATCH_SNAPSHOT PULL NO_ROOT)` — single `PLATFORM`, `;`-list = FATAL (revert #2) |
| Policy | `ocx.policy(allow_unverified, allow_yanked, sigstore_trusted_root)` | `ocx_policy(ALLOW_UNVERIFIED ALLOW_YANKED SIGSTORE_TRUSTED_ROOT)`; explicit only, never read from env; second differing call = FATAL |
| Index | `index` attr | `ocx_index(FIND\|UPDATE_COMMAND …)` public façade kept (owner convention), each verb a private function with its own top-level `PARSE_ARGV` (satisfies CMK-MOD-16) |
| Self-update | — | public `ocx_self_update` under `CMAKE_SCRIPT_MODE_FILE` guard, inside policy PUSH/POP (CMK-MOD-14/05) |
| Env classes | `OCX_ENV_CLASSES` (`ocx/private/repo_utils.bzl:45-99`) | same 4 classes: **site** (snapshotted+forwarded: `OCX_MIRRORS OCX_INSECURE_REGISTRIES OCX_OFFLINE OCX_FROZEN OCX_REMOTE OCX_JOBS OCX_INDEX OCX_DEFAULT_REGISTRY OCX_MANAGED_CONFIG OCX_PATCHES OCX_EXTRA_CA_CERTS OCX_HOME`), **translucent** (keyword overrides env: `OCX_CONFIG OCX_PATCH_SNAPSHOT OCX_SIGSTORE_TRUSTED_ROOT OCX_NO_CONFIG`), **explicit** (`ocx_policy` only: `OCX_NO_VERIFY OCX_ALLOW_YANKED`), **pinned** on every call (`OCX_PROJECT= OCX_GLOBAL=0 OCX_QUIET=0 OCX_NO_PROJECT=1 OCX_NO_CONFIG_REFRESH=1 OCX_NO_CONSENT=1 OCX_TOOLCHAIN_DIR= OCX_SELF_UPDATE=` off). `OCX_AUTH_*` never cached. |
| Exit hints | `SYSEXIT_HINTS` 64–85 | same table extended to 86/87; retry ×2 on 69/74/75 for every network call; message taken from the `--format json` error envelope when present |
| BINS | discovered via `inspect --closure` | user `BINS` validated against `closure.surface.interface` (binaries ∪ entrypoints); FATAL naming the typo + declared names; skipped when `binaries_complete=false` |
| CLI verbs | `ocx exec` | `ocx exec` / `ocx package exec` everywhere (zero `ocx run`, `package describe/info`) |

Result vars unchanged (`OCX_<NAME>_RUN[_<BIN>]`, `_PATHS`, `_ENV_<KEY>`); `_ENV_KEYS`, `_CONTENT` get documented.
`<name>_ROOT` change also `unset(<name>_DIR CACHE)`. Second copy of `ocx.cmake` at a different version = FATAL
(GLOBAL property, CMK-MOD-07).

## Phases

### P1 — Contract spikes (parallel, 3 × sonnet, read-only on the repo)
- **S1 ocx 0.6.5 CLI contract**: probe live, verbatim output into `.agents/research/ocx-0.6-contract.md`:
  JSON of `package install|which|env`, `inspect --closure` (project + package), error envelope, exit codes
  (75/78/79/81 paths), `OCX_QUIET`/`OCX_GLOBAL` ambient effect, lock v3 regen, **does an index digest pin all
  platforms?** (decides doc advice only; PINS stay regardless), index snapshot layout (`c/` not committed).
- **S2 cast pipeline**: `ocx exec -- asciinema rec --headless` (asciinema 3.2.1 on ocx.sh) recording a real
  `cmake -S -B` in a temp project; sanitizer (home/tmp paths, digests, timings); verify `<Terminal>` in
  `@ocx-sh/theme` 0.1.1 resolves under base `/integrations/cmake/`. Prototype script + findings note.
- **S3 `/docs-plan` discovery**: follow `.claude/skills/docs-plan/SKILL.md` end to end, product shape `library`.
  Friction logs delegated to a no-repo-context subagent (persona: CMake author who needs `jq`/`ninja` in a build;
  platform engineer behind a mirror), run against the published v0.3.0 module with verbatim output. Outputs:
  `docs/discovery/use-cases.yaml`, `docs/discovery/friction-logs/*.md`, IA plan, delete list. Seed from
  `.agents/research/docs-use-cases.md` only as evidence pointers.

Gate: orchestrator reads S1 and amends the API table if a probe contradicts it (one line in the plan file).

### P2 — Implementation (4 parallel pipelines, each: implement → own tests → sonnet review → fix once)
Region ownership in `ocx.cmake` avoids merge conflicts; shared helper signatures are frozen by this plan.

- **I1 bootstrap & dist** (lines ~167-351, 670-795, 1385-end; `scripts/`, `update-dist.yml`, `renovate.json`):
  port `rules_ocx/scripts/bump_ocx.py` into `scripts/update_dist.py` (lockstep snapshot + `__OCX_PIN_VERSION` +
  every `setup-ocx` `version:` pin; forward-only, stable-only, URL fullmatch guards; unit test); bump to 0.6.5;
  `file(DOWNLOAD)` with `TLS_VERIFY ON`, `TIMEOUT`/`INACTIVITY_TIMEOUT`, `EXPECTED_HASH`; `<sha256>.json` manifest
  self-verify; `DIST_MANIFEST`; public `ocx_self_update`; workflow `update-dist.yml` runs the lockstep bump.
- **I2 runtime core** (lines ~353-668): env-class table + `__ocx_env_prefix` pinned set; passthrough/snapshot of
  site+translucent vars; `CMAKE_CONFIGURE_DEPENDS` for config paths that exist (system/user/`$OCX_HOME`/managed);
  exit-hint table + retry 69/74/75; error-envelope parse; `ENCODING UTF-8` on every `execute_process`;
  `__ocx_require_cli` macro → function; `ocx_policy`.
- **I3 commands** (lines ~797-1381): `ocx_project`/`ocx_package`/`ocx_index` per API table — `PARSE_ARGV` +
  `UNPARSED_ARGUMENTS` FATAL everywhere, single `PLATFORM`, PINS kept, `CONFIG`/`NO_CONFIG`/`PATCH_SNAPSHOT`,
  BINS closure validation, `_DIR` unset, 0.6 JSON shapes from S1, MOD-07 version guard.
- **I4 harness & CI** (`CMakeLists.txt`, `tests/**`, `examples/**`, `taskfile.yml`, `ci.yml`): floor
  `cmake_minimum_required(VERSION 3.25...4.4)` everywhere; legs 3.25 (`ocx exec -- uvx --from cmake==3.25.*`,
  uv from ocx), 3.31, 4.4 via `ocx.sh/kitware/cmake`; gate spelling per CMK-CORE-01; ctest
  `--no-tests=error --timeout` + per-test `TIMEOUT`; negative tests assert exit status (CMK-TEST-03); memoize test
  adds an invalidation step; gersemi `--check` (`.gersemirc`, via uvx) in `task lint`; `ocx run` → `ocx exec`
  (haiku); regenerate locks/index snapshots with 0.6.5 (haiku). New tests: ambient `OCX_QUIET=1 OCX_GLOBAL=1`,
  `OCX_NO_CONFIG=1`, managed-config-unsynced → 78 hint, BINS typo FATAL, PINS per platform, `;`-PLATFORM FATAL,
  exit-75 retry (fake-ocx shim), second-copy version FATAL, fresh pin download reports 0.6.5.

Merge I1→I2→I3→I4 onto the feature branch; integration gate = `task verify` + local Windows run
(`/mnt/c/Users/ecom/find_ocx-wintest/`, xwin not needed — stage tree on `C:`, run ctest via `cmd.exe /c`).
Red → owning pipeline fixes (sonnet retry, then opus).

### P3 — Docs revamp (starts after S3; prose in parallel with P2, casts + reference after P2 merge)
- **D1 site plumbing** (sonnet): `port-docs.mjs` → reference-only generator from in-source blocks
  (`commands.md`, `variables.md`, `findocx.md`); snippet include markers so every CMake fence in a page is
  pulled from a tested `examples/`/`tests/` file (DOC-EX-01/02); retire Sphinx (`docs/*.rst`, `conf.py`,
  `pyproject.toml`, `uv.lock`, `task docs`); `pages.yml`: if `curl -sI https://ocx.sh/integrations/cmake/` is a
  200 from the new zone → stub-only build via `site/scripts/stubs.mjs`, else drop its push trigger (Pages keeps
  the last deploy; stub build stays for website F-fin).
- **D2 casts** (sonnet, from S2): `site/casts/<page>__<name>.sh` scripts with ocx-style headers
  (`# cast: true`, `# doc:`, `# title:`, `# region cast`); each also a ctest (example harness); recorder task
  `site:casts` (ocx-provisioned asciinema, sanitized) runs inside `site:build`/`deploy.yml`; output
  `site/public/casts/` gitignored; `<Terminal src=… />` embeds, no autoplay. Casts: first configure with
  bootstrap, reproducible-first FATAL + fix, `find_package(ocx)`, frozen offline configure, mirror bootstrap,
  BINS typo error.
- **D3 pages** (4 × sonnet, IA from S3): landing + tutorial (first steps, ends in observed `jq` output);
  how-tos per use case (tools in the build without host install; pin & freeze for reproducible CI; feed
  `find_package`; cross-build foreign platform; corporate mirror / air-gapped / CA bundle / managed config;
  superbuilds & nested `OCX_*` env; vendored module update); concepts (how it works, reproducible-first, lazy vs
  eager, `include(ocx)` vs `find_package(ocx)`, env classes & config tiers); troubleshooting (exit code → cause
  → fix, checked against the hint table by a test). README rewritten as `readme` landing → site.
  Every page: `doc_type`/`doc_tier` comments after frontmatter, explicit anchors, voice matched to ocx.sh.
- **D4 in-source reference** (1 × sonnet, after I3 merge): rewrite `#[=[.rst:` blocks per CMake `file.rst`
  style (signature directive, synopsis parsed-literal); rendered interface text, so docs-quality applies there
  and code-docs caps apply to plain `#` comments (`code-docs-cleanup` pass).
- **D5 gate** (sonnet, `docs-instrument`): `doc_declaration.py`, `prose.py`, `page_type.py`, `doc_examples.py`,
  links, anchors, `ocx-site check`, Lighthouse 100×4 wired into `task site:check` / `verify`; then `docs-review`
  per page (parallel sonnet), one fix round.

### P4 — Review, land-ready
- `hex-review` (medium tier, codex adversarial) over the branch; fix loop ≤2 rounds.
- `CHANGELOG.md` unreleased section via git-cliff; migration notes (breaking: floor 3.25, PLATFORM list gone,
  `ocx exec`, new keywords) in the changelog + a how-to.
- Push branch, open PR, watch CI (3 OS × 3 CMake), rerun infra flakes once, fix real reds.
- Remove pipeline worktrees as each merges; the sibling worktree stays until the PR merges.

## Critical files
`ocx.cmake`, `Findocx.cmake`, `CMakeLists.txt`, `tests/**`, `examples/**`, `scripts/update_dist.py`,
`taskfile.yml`, `.github/workflows/{ci,update-dist,pages,deploy,site}.yml`, `renovate.json`, `site/scripts/*.mjs`,
`site/pages/**`, `site/casts/**`, `README.md`, `CHANGELOG.md`, `grimoire.toml`.
Reuse: `rules_ocx/scripts/bump_ocx.py`, `rules_ocx/ocx/private/repo_utils.bzl` (env classes, `SYSEXIT_HINTS`,
`declared_bins`), ocx `test/recordings/cast_recorder.py` (sanitizer ideas), `site/scripts/stubs.mjs`,
`tests/helpers.cmake`.

## Verification
- `task verify` green (lint incl. gersemi/actionlint/hawkeye/lychee; ctest on 3.25/3.31/4.4; examples; site:check).
- `OCX_QUIET=1 OCX_GLOBAL=1 cmake -S examples/project -B build/q` and `OCX_NO_CONFIG=1 …` configure clean.
- Clear `OCX_BOOTSTRAP_CACHE`, `-DOCX_BOOTSTRAP=ALWAYS`: bootstrapped `ocx version` = 0.6.5.
- `grep -rn -e 'ocx run' -e 'package describe' -e 'package info' -e 'ocx.sh/[a-z-]*[:"]' .` → no hits outside changelog.
- Windows local ctest green; macOS via CI.
- `task site:build` produces casts from real runs; `task site:lighthouse` 100×4; docs-plan check greps clean;
  `docs-review` no MUST findings.
- PR CI green on all legs.

## Owner actions after the run
- Merge the PR; cut v0.4.0 (`task release:prepare`, tag, push).
- Close superseded [#3](https://github.com/ocx-sh/find_ocx/pull/3) (dist refresh).
- Discard the primary checkout's WIP + `OCX-*-HANDOVER.md` (superseded).
- Website F-fin: edge flip + Pages stub build, then delete `pages.yml`.

## P1 amendments (2026-10-10, from `.agents/research/ocx-0.6-contract.md` §A/§B, friction logs)
- Retry on **75 only** (69 non-retryable per ocx docs, 74 local I/O). Cross-repo note: rules_ocx retries 69/74/75.
- Error text from **stderr** (`error:` lines, dedupe chain segments); envelope only for `error.kind`.
- Pinned env: drop `OCX_TOOLCHAIN_DIR=`, `OCX_SELF_UPDATE=manual` not empty; `--lazy-mode never` + `--pinned` per call on `env`/`pull`/`exec` instead of pinning `OCX_LAZY_MODE`/`OCX_TOOLCHAIN_PINNED`.
- Foreign `PLATFORM`: `env --pinned` (link paths flip to host otherwise, A5).
- Index discovery: `.ocx/` counts only with `config.json` or `<registry>/p/` (collides with `.ocx/toolchain`, A4).
- `ocx_index(UPDATE_COMMAND)`: unset `OCX_FROZEN` in the refresh command; record only used tags (A9).
- BINS validation: forward `-g <groups>`; run after `pull`; tolerate 79 under `--offline`.
- Policy at project tier only via `OCX_NO_VERIFY`/`OCX_ALLOW_YANKED` env on the call.
- 78 hints: "regenerate with `ocx lock`" (v2), `ocx config update` (managed), bad TOML.
- Index digest pins all platforms → docs recommend `PACKAGE …@<index digest>`; `PINS` stay.
- Friction: `jq_ROOT` became a multi-line JSON blob when the 0.6.5 CLI runs (fix parse); `ocx_package` in a toolchain file fails "duplicate NAME" on CMake's double include (make re-entry with identical args idempotent); `BINS` from a non-default group silently needs `GROUPS` (validate); `find_program` ignores `<name>_ROOT` (docs: `HINTS`); v0.3.0 bootstrap 0.3.11 rejects v3 locks (fixed by the bump).
- Casts: `<Terminal>` needs `.mdx`; port-docs emits `.mdx` for pages with a `<!-- cast: key -->` directive; asciinema has no Windows build → cast ctests `if(NOT WIN32)`.
