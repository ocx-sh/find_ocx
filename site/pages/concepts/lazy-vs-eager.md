<!-- doc_type: explanation -->
<!-- doc_tier: everyday -->
<!-- description: When a configure touches the network, what PULL changes, and what a reconfigure costs. -->
# Lazy versus eager

This page explains when a configure touches the network and what a reconfigure costs.

Launchers are lazy by default: `ocx run` / `ocx package exec` materialize content on first execution, so a configure touches the network only for what it actually needs. `PULL` (per call) or `-DOCX_PULL=ON` (global, recommended for CI) materializes at configure time and enables the `<name>_ROOT` export. Reconfigures are memoized: when the inputs are unchanged, no ocx process is spawned at all (`-DOCX_REFRESH=ON` for a one-shot bypass).

To switch a CI job to eager mode, see [Reproduce the build in CI](../guides/ci.md).
