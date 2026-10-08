---
doc_type: reference
doc_tier: integration
---

# find_ocx docs: use cases, survey and page inventory

Research note for the move of the find_ocx docs onto the shared ocx.sh Starlight
site (`/integrations/cmake/`). Product shape: `library` (CMake module pair, a
wrapper over the `ocx` CLI, so the quickstart needs a precondition sentence:
CMake 3.19 and network or a mirror; no ocx install). Evidence is the repo
(`README.md`, `docs/*.rst`, `ocx.cmake` `.. command::` blocks, `examples/`,
`taskfile.yml`, `.github/workflows/ci.yml`); survey pages fetched 2026-10-07.

## 1. Comparable sites

| Site | What it does well | Gap find_ocx can fill |
|---|---|---|
| [CMake FetchContent](https://cmake.org/cmake/help/latest/module/FetchContent.html) | Overview, command signatures, six graded examples, "first declaration wins" explained | Dense, one reference page; no troubleshooting; dependencies are source, never tools |
| [CPM.cmake](https://github.com/cpm-cmake/CPM.cmake) | One-line tagline, 3-line quickstart, setup-free (one vendored file), supply-chain advice (pin commit hashes), offline via `CPM_SOURCE_CACHE`, honest Limitations | Source libraries only; no pre-built binaries, no toolchain |
| [vcpkg: install and use packages with CMake](https://learn.microsoft.com/en-us/vcpkg/get_started/get-started) | A single tutorial that ends in a printed "Hello World!"; per-shell tabs; manifest + baseline = version consistency | Needs a clone + bootstrap + `VCPKG_ROOT` + toolchain preset before step one; per-OS branching |
| [Conan 2 tutorial](https://docs.conan.io/2/tutorial.html) | Sections by user job (consume, create, repositories, develop, versioning); lockfiles and CI get their own guides | Heavy: profiles, a Python-side client; little troubleshooting |
| [mise getting started](https://mise.jdx.dev/getting-started.html) | Linear path: install, ad-hoc run, commit `mise.toml`, tasks; lockfiles named for deterministic CI | Floating series like `"24"` are not exact pins; no CMake integration |
| [Nix first steps](https://nix.dev/tutorials/first-steps/) | Reproducibility taught from lesson one: ad-hoc shell, script, declarative shell, pinning | High concept cost; nothing for "I only need `jq` in my build" |
| [asdf getting started](https://asdf-vm.com/guide/getting-started.html) | `.tool-versions` per project, plain mental model | Shell-activation setup varies per OS; execution fails until versions are set; no hash verification |

Patterns to copy: CPM's three-line proof on the landing page; vcpkg's single
tutorial ending in an observed result; Conan's navigation by job, not by
command; Nix's reproducibility-first framing; mise's "commit the file" step.
Pattern to avoid: FetchContent's one dense page where task and reference mix.

## 2. Problems find_ocx solves

Each is traced to the repo, not to an existing page title.

1. **Tools in the build without a host install.** A build step needs `jq`,
   `shellcheck`, a specific `cmake`, `ninja`. Today that is a README line
   ("install X first") per OS. `ocx_project(BINS jq)` exports
   `OCX_PROJECT_RUN_JQ`, a plain command list for `add_custom_command`.
   Source: `ocx.cmake` `ocx_project`; `examples/project`.
2. **A pinned, verified bootstrap of the package manager itself.** `include(ocx)`
   downloads a sha256-checked `ocx` into a per-machine cache when none is on
   `PATH`; `-DOCX_BOOTSTRAP=ALWAYS` makes every developer and CI runner run the
   identical binary. Source: `docs/index.rst` "Two entry points".
3. **Reproducible by default.** A floating tag with no snapshot and no digest is
   a hard configure error; fixes are `ocx.lock`, a committed `.ocx/` index
   snapshot, or per-platform `PINS`. Source: `docs/index.rst` "Index snapshots",
   `examples/frozen_index`, `examples/package`.
4. **Feeding `find_package`.** `ocx_package(... PULL)` exports `<name>_ROOT`
   (CMP0074), so a later `find_package`/`find_library` searches provisioned
   content. Source: `examples/package`.
5. **Cross-platform CI with one config.** Command lists re-enter `ocx run`, so
   no wrapper scripts; CI runs Linux, macOS, Windows (`ci.yml` matrix);
   `-DOCX_PULL=ON` materializes at configure time. Source: `docs/examples.rst`.
6. **Foreign-platform content.** `ocx_project(PLATFORM ...)` exports
   `OCX_<NAME>_PATHS` / `OCX_<NAME>_ENV_<KEY>` for cross builds from the same
   lock. Source: `ocx.cmake` `ocx_project`.
7. **Corporate and air-gapped environments.** `OCX_INSTALL_MIRROR_URL`,
   `OCX_MIRRORS`, `OCX_AUTH_*` (env only), `OCX_BOOTSTRAP=OFF`. Source:
   README/`docs/index.rst` "Corporate mirrors".
8. **Pitfall: nested builds** inherit `OCX_FROZEN`/`OCX_INDEX` (warning in
   `docs/index.rst`), a friction point worth a troubleshooting section.

Out of scope for the docs (internals, not reader tasks): `ocx_bootstrap`
internals, memoization fingerprints (one explanation sentence only), the
dist.json snapshot embed, `taskfile.yml` maintainer tasks, `renovate.json`.

## 3. User needs

| Id | Reader | Need |
|---|---|---|
| N1 | CMake author | "Tell me in 5 minutes whether I can use `jq`/`cmake` in my build without asking users to install it" |
| N2 | CMake author | "Show me the pinned toolchain from `ocx.toml` in `add_custom_command`" |
| N3 | Maintainer | "Make my CI and my laptop run byte-identical tool versions" |
| N4 | Maintainer | "Understand when a configure hits the network, and make it stop" |
| N5 | Platform engineer | "Run behind a mirror, offline, with credentials that never reach `CMakeCache.txt`" |
| N6 | Any | "Look up one variable or command signature fast" |
| N7 | Packager | "Choose `include(ocx)` versus `find_package(ocx)` and know which binary wins" |

## 4. Page inventory (docs-plan, product shape `library`)

Site base `/integrations/cmake/`. Reference pages are kept from the Sphinx
source; everything else is added around them (D10: refactor, not rewrite).
Reference is outside the tier progression; it still declares `doc_tier` for the
gate, set to the tier of its closest reader.

| Page | doc_type | doc_tier | Maps from | Serves |
|---|---|---|---|---|
| Landing (`index`) | explanation | first-steps | README intro + `index.rst` lead | N1 |
| Tutorial: first tool in a build (vendor, `ocx_project(BINS jq)`, see `jq` output on build) | tutorial | first-steps | `index.rst` Quick start, `examples/project` | N1, N2 |
| How-to: run workspace tools from `ocx.toml` (groups, genexes, lazy lint group) | how-to | everyday | `examples.rst` "Workspace toolchain" | N2 |
| How-to: pin and freeze (lock, `.ocx/` snapshot, `PINS`, refresh deliberately) | how-to | everyday | `index.rst` "Index snapshots", `examples/frozen_index`, `examples/package` | N3 |
| How-to: make `find_package` see an ocx package (`PULL`, `<name>_ROOT`) | how-to | everyday | `examples.rst` "Ad-hoc packages" | N2 |
| How-to: reproducible CI on Linux, macOS, Windows (`OCX_PULL`, `BOOTSTRAP=ALWAYS`, GitHub Actions snippet) | how-to | integration | `ci.yml`, `examples.rst` "Running them" | N3, N4 |
| How-to: use behind a mirror or offline (`OCX_MIRRORS`, `OCX_AUTH_*`, `BOOTSTRAP=OFF`) | how-to | integration | README/`index.rst` "Corporate mirrors" | N5 |
| How-to: cross-build with foreign-platform content (`PLATFORM`) | how-to | integration | `ocx_project` block | N3 |
| How-to: update the vendored files (`cmake -P ocx.cmake`, mirror URL) | how-to | everyday | `index.rst` "Updating the vendored files" | N3 |
| Explanation: two entry points and which binary runs | explanation | everyday | `index.rst` "Two entry points", `Findocx.cmake` | N7 |
| Explanation: lazy versus eager, and what a reconfigure costs | explanation | everyday | `index.rst` "Lazy vs eager" | N4 |
| Explanation: why reproducible-first (floating tag is an error) and why no re-implementation of ocx in CMake | explanation | everyday | README intro, `index.rst` | N3 |
| Troubleshooting: nested builds, exit 81 refresh hint, `-DOCX_FROZEN= -DOCX_INDEX=` | how-to | integration | `index.rst` warning | N4 |
| Reference: commands (`ocx_bootstrap`, `ocx_project`, `ocx_package`, `ocx_index`) | reference | everyday | `.. command::` blocks in `ocx.cmake` | N6 |
| Reference: variables (`OCX_*`, 14 `.. variable::` blocks, mirror table) | reference | everyday | `.. variable::` blocks, mirrors table | N6 |
| Reference: `Findocx.cmake` (`ocx::ocx`, `OCX_BOOTSTRAP`) | reference | everyday | `Findocx.cmake` rst block | N7 |
| Examples index (links to the four `examples/` projects, run commands) | reference | first-steps | `examples.rst`, README Examples | N1 |

Seventeen pages; five tutorial/how-to for first-steps and everyday jobs plus
four integration how-tos satisfy C-004 (3 or more use-case pages citing this
note). Each use-case page cites section 2 by number.

Mapping rules for the port (C-007): every `.. command::` / `.. variable::`
block in `ocx.cmake` and `Findocx.cmake` becomes an anchored reference entry;
Sphinx roles `:command:` and `:variable:` map to links to those anchors;
`literalinclude` of `examples/**` maps to a code import of the real file (so
the page cannot drift); an unknown directive fails the port loudly.

## 5. Delete list

Nothing is deleted from content; the delete signals (no unique reader task, no
inbound link) fail for every current page. Superseded presentation only:

- `docs/conf.py`, `docs/pyproject.toml`, `docs/uv.lock`, `docs/_build`: Sphinx
  toolchain, removed with `pages.yml` at the flip (D6), not before.
- `docs/index.rst`, `docs/examples.rst`, `docs/reference.rst`: replaced by the
  generated pages once the port script covers them (script reads, never edits
  them until then).
- README "How it works", "Corporate mirrors", "Lazy vs eager" duplicate the
  landing and how-tos: cut to a short pitch plus a link to
  `https://ocx.sh/integrations/cmake/` in the README step.
- Duplicate quick-start text between README and `index.rst` collapses into the
  tutorial page.

## 6. Open points

- README says "Findocx.cmake alone works on 3.15"; confirm before the landing
  states a version floor.
- `index.rst` Quick start uses `ocx --index .ocx index update`; README does
  not. The tutorial should use the shorter ocx_project path (no snapshot) and
  leave snapshots to the pin-and-freeze how-to.
- Quality gate: `task site:lighthouse` audits every built page (mobile, 100 in
  performance, accessibility, best practices and SEO, plus JS, weight, DOM and
  HTML-size budgets from `site/lighthouse.budgets.mjs`). It has not run yet:
  the first full run may force page trims.
