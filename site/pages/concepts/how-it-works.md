<!-- doc_type: explanation -->
<!-- doc_tier: everyday -->
<!-- description: Why find_ocx shells out to the ocx CLI instead of re-implementing it in CMake, and what runs at configure and build time. -->
# How find_ocx works

This page explains what find_ocx does at configure and build time, and why it keeps all resolution inside the `ocx` binary.

## Why it never re-implements ocx

find_ocx deliberately never re-implements OCX internals in CMake.
All resolution goes through the `ocx` binary.
The durable contracts are the `ocx.lock` digests and the OCI manifests, so CMake code never has to track how ocx resolves a tag.

## What happens, in order

1. `ocx_bootstrap()` runs implicitly on first use.
   It downloads the pinned ocx release listed in the dist.json snapshot embedded in `ocx.cmake`, checks its sha256, and stores it in `~/.cache/find_ocx`.
   All build trees on the machine share that cache.
2. `ocx_project()` and `ocx_package()` shell out to that binary.
   They run `ocx lock --check` as a staleness gate every time.
   Eager mode adds `ocx pull` or `ocx package install`, and foreign platforms use `ocx --format json env`.
3. The exported `OCX_<NAME>_RUN` variables are plain CMake command lists.
   They re-enter `ocx run` or `ocx package exec`, so no wrapper scripts are needed and generator expressions compose.
4. Content materializes lazily on first execution into the shared, content-addressed `OCX_HOME` store.
5. Reconfigures are memoized by input fingerprints.
   With unchanged inputs no `ocx` process starts, and `-DOCX_REFRESH=ON` bypasses the memo once.

## Where to go next

- [Two entry points](entry-points.md) explains which binary runs.
- [Lazy versus eager](lazy-vs-eager.md) explains when the network is touched.
- [Reproducible first](reproducible-first.md) explains why a floating tag is an error.
