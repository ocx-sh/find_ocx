---
title: Build behind a mirror or offline
description: Configure find_ocx behind a corporate mirror or with no network, with registry credentials kept out of CMakeCache.txt.
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

Your build machines reach an internal artifact host and nothing else, or they reach nothing.
A configure that downloads `ocx` from GitHub and tools from a public registry stops at the firewall.
`FetchContent` and CPM do not help, because they also fetch from the public internet at configure time.

This page routes every download that find_ocx causes through your mirror and keeps credentials out of `CMakeCache.txt`.
It ends with a build that needs no network at all.
It assumes a committed `ocx.lock`, written once on a machine with network access.
The lock records the upstream host and digest of each tool, so it stays valid behind a mirror.

## Know what leaves the network {#what-leaves-the-network}

A configure causes four kinds of traffic.
Allow these hosts through the firewall, or mirror them as described below.

| Traffic | Default host | Variable |
| --- | --- | --- |
| Release manifest `dist.json` | `setup.ocx.sh` | `OCX_INSTALL_DIST_URL` |
| `ocx` archive | `github.com` | `OCX_INSTALL_MIRROR_URL` |
| Package blobs | `ghcr.io` | `OCX_MIRRORS` |
| Package index | `index.ocx.sh` | `OCX_MIRRORS` |

The module files themselves (`ocx.cmake` and `Findocx.cmake`) come from GitHub only when you run the [self-update](update-vendored.md).

## Put the ocx files on the mirror {#host-the-cli}

1. Copy `https://setup.ocx.sh/dist.json` to your mirror.
2. For every platform that builds on the mirror, copy the archive named in the manifest to `<mirror>/<tag>/<filename>`.

Linux hosts use the `x86_64-unknown-linux-musl` or `aarch64-unknown-linux-musl` archive, not the `gnu` one.
Archives are `.tar.gz` on Linux and macOS and `.zip` on Windows.
Every ocx version you set with `OCX_INSTALL_VERSION` needs its own archives and a row in the manifest.

Both files must allow anonymous read.
find_ocx downloads them without credentials, and the sha256 in the manifest is the security boundary, not the mirror.
A mirror locked down later breaks the download with an error that looks like a network failure.
A missing or locked manifest fails like this, and the message names the URL that was requested:

```text
find_ocx: failed to fetch the dist manifest from OCX_INSTALL_DIST_URL='<url>/dist.json': "HTTP response code said error"
hint: the mirror must allow anonymous read; a manifest named <sha256>.json must match that digest
```

A missing archive ends with `find_ocx: download of <url> failed` and a hint that names both variables.
CMake does not print the HTTP status, so check the access log of the mirror for it.

## Point the configure at the mirror {#point-the-configure}

Pass the two variables on the first configure of a build directory.
This example serves the files from a local HTTP server that stands in for your mirror.

<!-- snippet: site/casts/guides-mirror__bootstrap.sh#cast -->

The recording shows the download going to the mirror instead of GitHub.

<!-- cast: guides-mirror/bootstrap -->

`OCX_INSTALL_DIST_URL` replaces the manifest embedded in `ocx.cmake`.
`OCX_INSTALL_MIRROR_URL` rewrites every archive URL to `<mirror>/<tag>/<filename>`.
The sha256 from the manifest is still enforced, so a mirror can move bytes but not change them.

Each variable is stored in `CMakeCache.txt` at the first configure and stays there.
To change one later, pass it again with `-D` or use a fresh build directory.

## Route package pulls through the mirror {#mirrors}

Set `OCX_MIRRORS` to a JSON map from the host that carries the traffic to the mirror that replaces it.
A package from `ocx.sh` is fetched from two hosts, so the map names both.
Naming `ocx.sh` has no effect, because `ocx.sh` is only the alias that resolves to these hosts.

<!-- doc-norun: the host names are placeholders for your own mirror -->

```sh
export OCX_MIRRORS='{
  "ghcr.io": "https://mirror.corp/ghcr-remote",
  "index.ocx.sh": {"index": "https://mirror.corp/ocx-index"}
}'
```

<!-- /doc-norun -->

The `ghcr.io` entry serves the package blobs, for example from an Artifactory remote repository in front of GitHub's container registry.
The `index.ocx.sh` entry serves the package index, which the mirror must copy from `https://index.ocx.sh/`.
The digests in `ocx.lock` still verify every blob.
There is no fallback to the origin, so an unreachable mirror is a hard error that names the mirror.

Run one configure and read the mirror's access log.
A request that went to any other host names one more key for the map.

To mirror only the pulls and keep the public index out of the picture, the config file offers a `[mirrors]` entry for `ocx.sh`.
That turns `ocx.sh` into a plain registry on your mirror and drops the index with a warning.
You give up the index's digest verification and yank gate.
[Apply organisation-wide download rules](policy-and-config.md#config) shows the file.
`OCX_MIRRORS` cannot suppress the index, so the environment variable does not offer that route.

Three more variables cover the usual corporate network:

- `OCX_INSECURE_REGISTRIES` takes a comma list of hosts that speak plain HTTP.
- `OCX_EXTRA_CA_CERTS` adds the corporate root to the trust of every `ocx` call. It takes a path to a PEM file or the PEM text.
- `OCX_INSTALL_CA_BUNDLE` names a PEM file that the download of the `ocx` binary and its manifest trusts instead of the system store. CMake performs that download itself, so `OCX_EXTRA_CA_CERTS` does not cover it.

Set all three in the environment of the first configure, like the mirror variables.
`OCX_INSTALL_CA_BUNDLE` also reaches every `ocx` call as `OCX_EXTRA_CA_CERTS`, unless you set `OCX_EXTRA_CA_CERTS` yourself.
So one corporate bundle covers the whole configure, and the `ocx` installers at setup.ocx.sh read the same variable.
A value that is not a file stops the download with this message:

```text
find_ocx: OCX_INSTALL_CA_BUNDLE='<path>' is not a readable file
hint: point it at a PEM bundle, or clear it with -DOCX_INSTALL_CA_BUNDLE=
```

The check runs only when the configure downloads the binary, so a warm bootstrap cache hides a wrong path until the next download.

## Pass credentials {#credentials}

Authenticate against the mirror host, not the upstream.
Export `OCX_AUTH_<REGISTRY>_TYPE`, `OCX_AUTH_<REGISTRY>_USER` and `OCX_AUTH_<REGISTRY>_TOKEN`.
In `<REGISTRY>`, every character of the host name that is not a letter or a digit becomes an underscore, and the case stays as it is.
The host `mirror.corp` becomes `mirror_corp`.

<!-- doc-norun: the token is a secret that only exists on your machine -->

```sh
export OCX_AUTH_mirror_corp_TYPE=bearer
export OCX_AUTH_mirror_corp_TOKEN="<token>"
```

<!-- /doc-norun -->

find_ocx never stores these variables in `CMakeCache.txt`.
Search the file for your token to confirm that, and reconfigure after you change a credential.
The mirror's access log shows whether a request arrived with credentials, which confirms that ocx used the variable.

`ocx` also reads your Docker credential helpers.
A helper that is configured but not installed prints a warning, and ocx then continues with the credentials from the variables or anonymously.

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

- [Apply organisation-wide rules](policy-and-config.md) to share one config file across builds.
- [Exit codes](../troubleshooting/exit-codes.md) to map a failed configure to its cause.
- [Environment and config](../concepts/env-and-config.md) for which variables are forwarded to every `ocx` call.
