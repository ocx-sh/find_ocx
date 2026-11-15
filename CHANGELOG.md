# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-11-15

### Added

- Accept a platform preference list in ocx_package (#2)
- Adopt ocx 0.6.5, align the API with rules_ocx, rewrite the docs (#5) **BREAKING**: CMake 3.25 is the minimum for ocx.cmake. PLATFORM takes

### Documentation

- Landing, tutorial, guides, concepts and reference pages for the ocx.sh site *(site)*

### Fixed

- Use package names ocx 0.6 can lock, follow the 0.6 index and CLI output
- No font swap on page load; theme pinned for sized terminals (#6) *(site)*
- The Lighthouse audit skips the noindex frag/ fragments *(site)*
- Windows resolves the gnullvm archive and falls back to msvc

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
[0.4.0]: https://github.com/ocx-sh/find_ocx/compare/v0.3.0..v0.4.0
[0.3.0]: https://github.com/ocx-sh/find_ocx/compare/v0.2.0..v0.3.0
[0.2.0]: https://github.com/ocx-sh/find_ocx/compare/v0.1.0..v0.2.0
[0.1.0]: https://github.com/ocx-sh/find_ocx/tree/v0.1.0

