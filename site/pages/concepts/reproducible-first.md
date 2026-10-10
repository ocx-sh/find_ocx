<!-- doc_type: explanation -->
<!-- doc_tier: everyday -->
<!-- description: Why a floating tag without a snapshot or digest is a hard error, and how index snapshots fix it. -->
# Reproducible first

This page explains why find_ocx fails a configure on an unpinned floating tag, and how index snapshots, digest pins and locks keep resolution fixed.

ocx would rather fail than compromise on reproducibility. A floating tag (`:latest`, `:3.31`) with no index snapshot in effect and no digest pin is a hard configure error, not a warning — the escape hatch is the explicit `-DOCX_ALLOW_FLOATING=ON` (useful transiently: the eager install prints the digests that seed `PINS`).

The snapshot is a CLI-owned directory of `<registry>/p/<repo>.json` leaves, committed like a lockfile:

```console
ocx --index .ocx index update ocx.sh/jqlang/jq ocx.sh/kitware/cmake
git add .ocx
```

Every [`ocx_package`](/integrations/cmake/reference/commands/#ocx_package) resolves it through a ladder — explicit `INDEX <dir>`, else the `OCX_INDEX` variable, else the nearest `.ocx/` directory between the calling directory and the last `project()` source dir (a vendored subproject with its own `project()` gets its own bound, so snapshots never leak across projects). `ocx_index(FIND REQUIRED)` runs that discovery once, fails fast when nothing is committed, and locks the result into `OCX_INDEX`.

Snapshots are **never auto-updated**. The refresh is a deliberate act: `ocx_index(UPDATE_COMMAND <var>)` composes the command line, the caller decides how it runs (build target, script, CI job that opens a PR) — review the diff, commit. The freshness gate is the frozen configure itself: a tag missing from the snapshot fails with an actionable refresh hint.

To set this up, see [Pin and freeze tag resolution](../guides/pin-and-freeze.md).
