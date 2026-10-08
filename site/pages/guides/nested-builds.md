<!-- doc_type: troubleshooting -->
<!-- doc_tier: integration -->
<!-- description: Fixes for a find_ocx configure that fails inside another ocx launcher, on a floating tag, or on a stale lock. -->
# Fix a failing configure

## Error: a nested configure fails with the exit-81 refresh hint

This issue occurs when a find_ocx configure runs inside an ocx launcher, such as an `ExternalProject`, `ctest --build-and-test` or a superbuild.
Launchers like `ocx run` and the `OCX_<NAME>_RUN` command lists export `OCX_FROZEN` and `OCX_INDEX` into child processes.
The inner configure stores those values as if you had set them.
The outer index does not contain the inner packages.

Pass both variables empty to the nested configure:

```console
cmake -DOCX_FROZEN= -DOCX_INDEX= ...
```

## Error: a floating tag stops the configure

This issue occurs when a package uses a floating tag such as `:latest`.
No index snapshot is in effect, and no digest is pinned.
find_ocx is reproducible first, so it refuses to resolve the tag live.

Commit an index snapshot or add `PINS`: see [Pin and freeze tag resolution](pin-and-freeze.md).
To print the digests once, set `OCX_ALLOW_FLOATING` for a single run.

## Error: the lock check fails

This issue occurs when `ocx.lock` no longer matches `ocx.toml`.
`ocx_project` always runs `ocx lock --check`, which is an offline staleness gate.

Run `ocx lock`, review the diff and commit it.

