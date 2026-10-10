---
title: Build behind a mirror or offline
description: Configure find_ocx behind a corporate mirror or with no network, with registry credentials kept out of CMakeCache.txt.
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

# Build behind a mirror or offline {#build-behind-a-mirror-or-offline}

Your build machines reach an internal artifact host and nothing else, or they reach nothing.
A configure that downloads `ocx` from GitHub and tools from a public registry stops at the firewall.
`FetchContent` and CPM do not help, because they also fetch from the public internet at configure time.

This page routes every download that find_ocx causes through your mirror and keeps credentials out of `CMakeCache.txt`.
It ends with a build that needs no network at all.
It assumes a committed `ocx.lock`, written once on a machine with network access.
The lock records the upstream host and digest of each tool, so it stays valid behind a mirror.

## Know what leaves the network {#what-leaves-the-network}

A configure causes three kinds of traffic, and each has its own variable.

| Traffic | Default host | Variable |
| --- | --- | --- |
| Release manifest `dist.json` | `setup.ocx.sh` | `OCX_INSTALL_DIST_URL` |
| `ocx` archive | `github.com` | `OCX_INSTALL_MIRROR_URL` |
| Package index and blobs | the registry hosts behind `ocx.sh` | `OCX_MIRRORS` |

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
When a file is missing, the error names the URL that was requested, so check the mirror's access log for the status code.

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

Set `OCX_MIRRORS` to a JSON map from a registry host to the mirror that serves it.

<!-- doc-norun: the host name is a placeholder for your own mirror -->
```sh
export OCX_MIRRORS='{"ocx.sh": "https://mirror.corp/ocx"}'
```
<!-- /doc-norun -->

With this entry ocx treats `ocx.sh` as a plain registry on your mirror, and it logs a warning that it dropped the public index.
The digests in `ocx.lock` still verify every blob.
There is no fallback to the origin, so an unreachable mirror is a hard error.

Run one configure and read the mirror's access log.
A request that went to any other host names one more key for the map.

Three more variables cover the usual corporate network:

- `OCX_INSECURE_REGISTRIES` takes a comma list of hosts that speak plain HTTP.
- `OCX_EXTRA_CA_CERTS` adds the corporate root to the trust of every `ocx` call. It takes a path to a PEM file or the PEM text.
- `CMAKE_TLS_CAINFO` is the CMake variable that names the CA bundle for the `ocx` download, because CMake performs that download itself.

Set these in the environment of the first configure, like the mirror variables.

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

An offline configure against an empty store fails with a package-not-found error and exit code 79.
Restore the store from your CI cache or pull it once online, as in [Reproduce the build in CI](ci.md#offline).

## Next steps {#next-steps}

- [Apply organisation-wide rules](policy-and-config.md) to share one config file across builds.
- [Exit codes](../troubleshooting/exit-codes.md) to map a failed configure to its cause.
- [Environment and config](../concepts/env-and-config.md) for which variables are forwarded to every `ocx` call.
