<!-- doc_type: how-to -->
<!-- doc_tier: integration -->
<!-- description: Configure find_ocx behind a corporate mirror or offline, with registry credentials that stay out of CMakeCache.txt. -->
# Build behind a mirror or offline

Use these variables to run a configure in a corporate or air-gapped environment.
They are the same knobs as the [setup.ocx.sh installer](https://github.com/ocx-sh/setup.ocx.sh) and [rules_ocx](https://github.com/ocx-sh/rules_ocx).

Every variable follows the snapshot pattern.
A CMake cache variable wins, otherwise the environment value at the first configure is stored in the cache and stays for that build directory.

## Mirror the ocx download

1. Set `OCX_INSTALL_DIST_URL` to fetch the release manifest from your mirror instead of the embedded snapshot.
2. Set `OCX_INSTALL_MIRROR_URL` to rewrite the binary download to `<mirror>/<tag>/<filename>`.

The manifest sha256 is still enforced, so a mirror can move bytes but not change them.

## Mirror the packages

Set `OCX_MIRRORS` to a JSON map such as `{"ocx.sh": "https://mirror.corp/ocx"}`.
Package pulls go to the mirror, and lock digests stay keyed to the upstream host.
Set `OCX_INSECURE_REGISTRIES` to a comma list when a mirror speaks plain HTTP.

## Pass credentials

Export `OCX_AUTH_<REGISTRY>_TYPE`, `OCX_AUTH_<REGISTRY>_USER` and `OCX_AUTH_<REGISTRY>_TOKEN` in the environment.
These are never stored in `CMakeCache.txt`, so reconfigure after you change them.

## Forbid configure-time downloads

Set `-DOCX_BOOTSTRAP=OFF` and provide a binary with `OCX_EXECUTABLE` or on `PATH`.
Any other case is a hard configure error with an actionable message.

Set `OCX_OFFLINE` to run without network access once the local store holds the content.

## Clear a knob

Pass `-DVAR=` to remove a value from the environment of every `ocx` call.
The passthrough variables are `OCX_HOME`, `OCX_MIRRORS`, `OCX_INSECURE_REGISTRIES`, `OCX_OFFLINE`, `OCX_FROZEN`, `OCX_REMOTE`, `OCX_JOBS`, `OCX_INDEX` and `OCX_DEFAULT_REGISTRY`.

For the vendored files themselves, see [Update the vendored files](update-vendored.md).
Needs addressed: problem 7 of the [use-case research](https://github.com/ocx-sh/find_ocx/blob/main/.agents/research/docs-use-cases.md).
