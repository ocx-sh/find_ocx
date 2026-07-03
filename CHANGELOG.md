# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-07-03

### Added

- Reproducible-first index snapshots and PATH-first CLI resolution **BREAKING**

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
[0.3.0]: https://github.com/ocx-sh/find_ocx/compare/v0.2.0..v0.3.0
[0.2.0]: https://github.com/ocx-sh/find_ocx/compare/v0.1.0..v0.2.0
[0.1.0]: https://github.com/ocx-sh/find_ocx/tree/v0.1.0

