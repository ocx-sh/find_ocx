# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Accept a platform preference list in ocx_package (#2)
- Env classes, ocx_policy and exit-code hints for ocx 0.6
- Single PLATFORM, BINS validation, ocx exec and config keywords *(commands)* **BREAKING**: PLATFORM no longer accepts a list; RUN commands run 'ocx exec'.
- Bump snapshot, pin and setup-ocx pins in lockstep *(dist)*
- Hardened downloads, DIST_MANIFEST, public ocx_self_update *(bootstrap)*
- Find the provisioned program with find_program HINTS *(examples)*
- Snippet and cast directives, heading ids, six-group sidebar *(site)*
- Production cast pipeline and nine cast scripts *(site)*
- Docs-quality gate in site:check, file.rst support in rst.mjs *(site)*

### Changed

- Pass config env via ENV, keep empty ocx_index args *(commands)*

### Documentation

- Landing, tutorial, guides, concepts and reference pages for the ocx.sh site *(site)*
- Ocx 0.6.5 contract probe, docs-plan artifact, friction logs, cast pipeline prototype *(discovery)*
- Correct the trust-root header, cap over-long comment blocks *(dist)*
- Retire Sphinx and the examples reference pages
- Rewrite the landing page and tutorial, add the everyday guides hub *(site)*
- Rewrite the README as a readme that points to the site
- Correct tutorial claims, register the README drift check *(site)*
- Mark snippet regions and test the combined groups and find_program recipes *(examples)*
- Rewrite the everyday how-tos and add the system-ocx and 0.4 migration pages *(site)*
- Correct the mirror trust claim, the 0.3 platform-list claim and three smaller gaps *(site)*
- Add ci, cross_build and policy example projects for the integration guides *(examples)*
- Rewrite the ci, mirror and cross-build guides, add policy-and-config, drop nested-builds *(site)*
- Correct the mirror guide from a live probe, drop body H1s and the toolchain guard *(site)*
- Rewrite the four concept pages against the 0.4 API *(site)*
- Add the env-and-config concept page *(site)*
- Add troubleshooting pages for configure errors and exit codes *(site)*
- Fix exit-code claims and split the configure-errors page *(site)*
- Restyle the in-source reference after CMake's file.rst *(module)*
- Verify page claims against the module and ocx 0.6.5 contract *(site)*
- Fold the credentials heading into environment classes, shorten the bootstrap check text *(module)*
- Split the mirror and pin guides, one page per command *(site)*
- Drop a time-relative word from the package mirror guide *(site)*
- Correct the guides against the module behavior, 3.15 floor wording *(site)*
- Hold the docs-gate prose and page-type caps on the new text *(site)*

### Fixed

- Use package names ocx 0.6 can lock, follow the 0.6 index and CLI output
- Keep ocx version from freezing policy, survive brackets in ocx errors
- Point the examples stub at a built page, flag the cast warning flip *(site)*
- Portable sed, fixture-backed cast projects, short cast comments *(site)*
- Match the 0.6.5 tar.gz archive in the mirror cast check *(site)*
- Cite casts by their doc key, skip the fixtures dir in the uncited-cast scan *(site)*
- Index and dotted page links resolve, port tests follow the six commands *(site)*
- Index leaf path, translucent env tests, CA bundle knob, gersemi *(module)*
- Port test counts the OCX_INSTALL_CA_BUNDLE variable, lower docs baseline *(site)*
- Hold the lighthouse budgets on every page *(site)*
- Keep asciinema out of the default tool group *(ci)*
- Store package content paths as CMake paths *(module)*
- Empty OCX_BOOTSTRAP is unset, validate CA bundle and PINS, sharper hints *(module)*
- Settle review findings in ocx.cmake and Findocx.cmake *(module)* **BREAKING**: an unknown OCX_BOOTSTRAP value and a ';' in OCX_EXECUTABLE or
- Cross toolchain find-root modes, ci example flags and permissions *(examples)*
- Do not persist checkout credentials, read-only dist update token *(ci)*
- Validate the manifest schema before indexing rows *(dist)*

## [0.3.0] - 2026-07-03

### Added

- Reproducible-first index snapshots and PATH-first CLI resolution **BREAKING**: reproducible-first index snapshots and PATH-first CLI resolution

## [0.2.0] - 2026-07-03

### Added

- OCX_BOOTSTRAP policy knob, find_package example, entry-point docs
- Index snapshots, refresh target, self-update

### Changed

- Ocx_index_update() -&gt; ocx_index_update_command()

### Documentation

- Switch to furo theme, add examples page

### Fixed

- Align version knob with setup.ocx.sh, skip manifest when cached
- Harden bootstrap cache resolution for CI environments
- Honor OCX_FROZEN/OCX_INDEX env, make -DVAR= an active unset

## [0.1.0] - 2026-07-02

### Added

- Initial find_ocx — CMake support for OCX
[unreleased]: https://github.com/ocx-sh/find_ocx/compare/v0.3.0..HEAD
[0.3.0]: https://github.com/ocx-sh/find_ocx/compare/v0.2.0..v0.3.0
[0.2.0]: https://github.com/ocx-sh/find_ocx/compare/v0.1.0..v0.2.0
[0.1.0]: https://github.com/ocx-sh/find_ocx/tree/v0.1.0

