---
title: Route package pulls through a mirror
description: Map the registry hosts of a package to your mirror with OCX_MIRRORS, add the corporate CA, and pass mirror credentials that stay out of CMakeCache.txt.
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

# Route package pulls through a mirror

The `ocx` binary comes from your mirror, but the packages still come from `ghcr.io` and `index.ocx.sh`, which your firewall blocks.
This page maps those hosts to your mirror with `OCX_MIRRORS`, covers the corporate CA, and passes mirror credentials that stay out of `CMakeCache.txt`.
It continues [Build behind a mirror or offline](mirror.md), which routes the download of `ocx` itself.

## Map the registry hosts to the mirror {#mirrors}

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

The path is checked on every configure that provisions or runs `ocx`, so a wrong path fails even when nothing is downloaded and the bootstrap cache is warm.

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

## Next steps {#next-steps}

- [Build behind a mirror or offline](mirror.md) routes the `ocx` download and covers a build with no network.
- [Apply organisation-wide download rules](policy-and-config.md) to share one config file across builds.
- [Exit codes](../troubleshooting/exit-codes.md) to map a failed configure to its cause.
