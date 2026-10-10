---
title: Update the vendored files
description: Move the vendored ocx.cmake and Findocx.cmake to another find_ocx release in script mode, verified against the release SHA256SUMS.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

# Update the vendored files

You copied `ocx.cmake` and `Findocx.cmake` into `cmake/`, and a later release has fixes or pins a later `ocx`.
Copying the files by hand gives you no proof of what arrived.
Fetching them at configure time with no hash trusts the network on every build.
The module can update itself in script mode and check both files against the release `SHA256SUMS` before it replaces anything.

You need network access to GitHub, or to a mirror of the release files.
The commands below run in your project root.

## Update to the latest release {#latest}

Run `cmake -P cmake/ocx.cmake`.
Script mode starts no project and writes no build cache.
The module asks the GitHub releases API for the newest tag, downloads the files, verifies them and replaces both.

It prints one line with the old and the new version, for example `0.3.0 -> 0.4.0 (v0.4.0)`.

## Choose a release {#version}

Pass the tag to move to a specific release, or to roll back.
Run `cmake -DOCX_SELF_UPDATE_VERSION=v0.4.0 -P cmake/ocx.cmake`.
The leading `v` is optional, and a lower tag is accepted because the printed line shows the direction.

## Update behind a mirror {#mirror}

Host the release files at `<url>/<tag>/<filename>` for `ocx.cmake`, `Findocx.cmake` and `SHA256SUMS`.
Then run `cmake -DOCX_SELF_UPDATE_VERSION=v0.4.0 -DOCX_SELF_UPDATE_URL=https://mirror.corp/find_ocx -P cmake/ocx.cmake`.

A mirror cannot answer the releases API, so the version is required.
Without it the update stops and names `OCX_SELF_UPDATE_VERSION`.
The mirrored `SHA256SUMS` stays the trust root, so a mirror can serve the files but cannot change them unnoticed.

## Know what is verified {#verified}

The update downloads `SHA256SUMS` first and reads the hashes for both files.
It downloads each file against its hash into a temporary directory next to the module.
Only when both downloads match does it rename the files into place, so a failed update leaves your vendored copy untouched.
A directory without `Findocx.cmake` is updated for `ocx.cmake` alone.

## Review and commit {#commit}

Look at the diff, because the release may pin a different `ocx` or change behaviour.
Commit both files in one change.
Update every vendored copy in the same change, because a configure that loads two copies at different versions stops with an error.

## Next steps {#next-steps}

- [Move from 0.3 to 0.4](migrate-0.4.md) lists the lines a major update breaks.
- [Build behind a mirror or offline](mirror.md) covers the other mirror settings.
- [`OCX_SELF_UPDATE_VERSION`](../reference/variables.md#ocx_self_update_version) and [`OCX_SELF_UPDATE_URL`](../reference/variables.md#ocx_self_update_url) are the two knobs.
