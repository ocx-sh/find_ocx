---
title: Build behind a mirror or offline
description: Download the ocx CLI from a corporate mirror, or configure and build with no network at all.
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

Your build machines reach an internal artifact host and nothing else, or they reach nothing.
A configure that downloads `ocx` from GitHub and tools from a public registry stops at the firewall.
`FetchContent` and CPM do not help, because they also fetch from the public internet at configure time.

This page routes the download of `ocx` itself through your mirror and ends with a build that needs no network at all.
[Route package pulls through a mirror](mirror-packages.md) continues with the registry hosts and the credentials.
It assumes a committed `ocx.lock`, written once on a machine with network access.
The lock records the upstream host and digest of each tool, so it stays valid behind a mirror.

## Know what leaves the network {#what-leaves-the-network}

A configure causes up to four kinds of traffic.
Allow these hosts through the firewall, or mirror them as described here and in [Route package pulls through a mirror](mirror-packages.md).

| Traffic | Default host | Variable |
| --- | --- | --- |
| Release manifest `dist.json` | none by default (`setup.ocx.sh` when `OCX_INSTALL_DIST_URL` is set) | `OCX_INSTALL_DIST_URL` |
| `ocx` archive | `github.com` | `OCX_INSTALL_MIRROR_URL` |
| Package blobs | `ghcr.io` | `OCX_MIRRORS` |
| Package index | `index.ocx.sh` | `OCX_MIRRORS` |

`ocx.cmake` embeds the manifest of the pinned version, so a default configure downloads only the archive.
The module files themselves (`ocx.cmake` and `Findocx.cmake`) come from GitHub only when you run the [self-update](update-vendored.md).

## Put the ocx files on the mirror {#host-the-cli}

1. For every platform that builds on the mirror, copy the archive named in the manifest to `<mirror>/<tag>/<filename>`.
   The embedded manifest names the archives of the pinned version, and `https://setup.ocx.sh/dist.json` lists every release.
2. Copy a manifest only when `OCX_INSTALL_VERSION` names a version that the embedded manifest does not list.
   Publish it as `<sha256>.json`, where the name is the sha256 of the file, so that the module can enforce the digest.

Linux hosts use the `x86_64-unknown-linux-musl` or `aarch64-unknown-linux-musl` archive, not the `gnu` one.
Archives are `.tar.gz` on Linux and macOS and `.zip` on Windows.
Every ocx version you set with `OCX_INSTALL_VERSION` needs its own archives.

All files must allow anonymous read.
find_ocx downloads them without credentials.
A mirror locked down later breaks the download with an error that looks like a network failure.

The sha256 of the manifest row is the security boundary.
It protects only as far as you trust the manifest.

The embedded manifest and a manifest named `<sha256>.json` are trusted.
A manifest under any other name, such as `dist.json`, is fetched unverified.
Then the mirror is the trust root: it can serve a row with the hash of a different archive together with that archive.
Prefer the embedded manifest whenever the pinned version is enough.

A missing or locked manifest fails like this, and the message names the URL that was requested:

```text
find_ocx: failed to fetch the dist manifest from OCX_INSTALL_DIST_URL='<url>/dist.json': "HTTP response code said error"
hint: the mirror must allow anonymous read; a manifest named <sha256>.json must match that digest
```

A missing archive ends with `find_ocx: download of <url> failed` and a hint that names both variables.
CMake does not print the HTTP status, so check the access log of the mirror for it.

## Point the configure at the mirror {#point-the-configure}

Pass `OCX_INSTALL_MIRROR_URL` on the first configure of a build directory.
This example serves the archive from a local HTTP server that stands in for your mirror.

<!-- snippet: site/casts/guides-mirror__bootstrap.sh#cast -->

The recording shows the download going to the mirror instead of GitHub.

<!-- cast: guides-mirror/bootstrap -->

`OCX_INSTALL_MIRROR_URL` rewrites every archive URL to `<mirror>/<tag>/<filename>`.
The sha256 from the embedded manifest is still enforced, so the mirror can move bytes but not change them.
`OCX_INSTALL_DIST_URL` replaces the embedded manifest.
Set it only for a version that the embedded manifest lacks, and name the file `<sha256>.json`, as above.

Each variable is stored in `CMakeCache.txt` at the first configure and stays there.
To change one later, pass it again with `-D` or use a fresh build directory.

## Forbid configure-time downloads {#no-downloads}

Configure with `-DOCX_BOOTSTRAP=OFF` and provide a binary through `OCX_EXECUTABLE` or `PATH`.
Any other case is a configure error that names this setting.

## Work with no network {#offline}

Configure once with network access or a mirror and `-DOCX_PULL=ON`, so the local store holds every tool.
Then set `OCX_OFFLINE=1`.
The next configure, even in a fresh build directory, runs without any request.
The pinned `ocx` binary must be in `OCX_BOOTSTRAP_CACHE` too, or installed, because the download of the binary is not offline-capable.

An offline configure or build against an empty store fails with exit code 79 or 81.
The message says that the package or its manifest is not in the local store or cache.
Restore the store from your CI cache or pull it once online, as in [Reproduce the build in CI](ci.md#offline).

## Next steps {#next-steps}

- [Route package pulls through a mirror](mirror-packages.md) to mirror the registry and pass credentials.
- [Apply organisation-wide download rules](policy-and-config.md) to share one config file across builds.
- [Exit codes](../troubleshooting/exit-codes.md) to map a failed configure to its cause.
- [Environment and config](../concepts/env-and-config.md) for which variables are forwarded to every `ocx` call.
