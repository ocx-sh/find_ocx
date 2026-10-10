---
title: Pin an image index digest
description: Fix a floating package tag with the digest of its image index, with no snapshot directory in the repository.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

# Pin an image index digest

A configure stopped on a floating tag, and you want no `.ocx/` snapshot directory in the repository.
A digest fixes what the tag means, so the same bytes come back on every machine.
This page pins the digest of the image index, which covers every platform with one value.

## Read the index digest {#read-digest}

Run `ocx package inspect` on the tag.
The first line of the output is the reference with its image index digest, and the tree below it lists the leaf manifests.

<!-- doc-norun: needs network access to the registry, and the digest is the one that ocx 0.6.5 printed for this tag -->
```bash-norun
$ ocx package inspect ocx.sh/jqlang/jq:1.8.2
ocx.sh/jqlang/jq:1.8.2@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
└── candidates
    ├── darwin/amd64 · sha256:f750c91d28769d12298ba9a4c10340152fcbdd48c48102bf275c21d736cc72a2 · 451 B
    ├── linux/amd64 · sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae · 451 B
    └── ...
```
<!-- /doc-norun -->

With `ocx --format json package inspect <ref>`, the same digest is the `pinned_digest` field of each package.
Copy the index digest from the first line, and not a digest from the candidates below it.
After an `ocx index update` into a snapshot, the index digest is also the file name under `.ocx/ocx.sh/p/jqlang/jq/o/sha256/`.

## Write it into `PACKAGE` {#package}

Append the index digest to the reference as `@sha256:<index digest>`.
Keep the tag in front of it, so a reader sees which version the digest stands for.
Nothing downloads until the first build-time execution.

<!-- snippet: examples/package/CMakeLists.txt#pinned-lazy -->

`ocx` selects the leaf manifest for the platform of the call, which is `PLATFORM` when set and the host otherwise.
A project's `ocx.lock` records the leaf digests per platform under each tool, so an `ocx_project` build needs no pin of this kind.

## Why the index digest {#why}

The index digest fixes the whole tag.
`ocx` still matches the full platform, including `+features` such as `libc.musl`, and verifies the leaf against the index.
A digest of a single leaf bypasses that selection.
`ocx` never checks that the leaf fits the platform, so a wrong digest installs the wrong binary silently.
One index digest also replaces a list of per-platform digests that you would otherwise keep in step by hand.

## Next steps {#next-steps}

- [Pin and freeze tag resolution](pin-and-freeze.md) covers the index snapshot and the frozen configure.
- [Add or change a pinned tool](add-a-tool.md) covers `ocx_project`, whose `ocx.lock` records these digests for you.
- [Move from 0.3 to 0.4](migrate-04.md#pins) shows the change from the removed `PINS` keyword.
- [`ocx_package`](../reference/commands/ocx_package.md) lists every keyword.
