---
title: Pin digests instead of a snapshot
description: Fix a floating package tag with an image index digest or one manifest digest per platform, with no snapshot directory in the repository.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

# Pin digests instead of a snapshot

A configure stopped on a floating tag, and you want no `.ocx/` snapshot directory in the repository.
A digest fixes what the tag means, so the same bytes come back on every machine.
This page pins the image index digest, or one manifest digest per platform.

## Pin the image index digest {#index-digest}

A digest of the image index fixes every platform at once, so write it into `PACKAGE` as `ocx.sh/jqlang/jq@sha256:<index digest>`.
After an `index update`, the index digest is the file name under `.ocx/ocx.sh/p/jqlang/jq/o/sha256/`.

## Pin one manifest digest per platform {#pins}

`PINS` fixes one manifest digest per platform instead.
A pin applies only to the platform of the call, which is `PLATFORM` when set and the host otherwise.
A pin for another platform is ignored, and a tag with no matching pin stays floating.
Nothing downloads until the first build-time execution.

<!-- snippet: examples/package/CMakeLists.txt#pins -->

A project's `ocx.lock` lists these per-platform digests under each tool.
Without a project, an eager configure of the floating tag with `-DOCX_ALLOW_FLOATING=ON -DOCX_PULL=ON` logs the line to copy:

```text
-- find_ocx: DRIFTY resolved floating - pin it with PINS "linux/amd64=sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
```

The line names one platform only, so repeat the step for each platform you build for.
`ocx --format json package install -p <platform> <package>` prints the digest in the `identifier` field, which reads `<ref>@sha256:<digest>`.
Take the part after `@`, which is the manifest digest for that platform, and not the whole field.
The plain table output omits it.

## Next steps {#next-steps}

- [Pin and freeze tag resolution](pin-and-freeze.md) covers the index snapshot and the frozen configure.
- [Add or change a pinned tool](add-a-tool.md) covers `ocx_project`, whose `ocx.lock` records these digests for you.
- [`ocx_package`](../reference/commands/ocx_package.md) lists every keyword.
