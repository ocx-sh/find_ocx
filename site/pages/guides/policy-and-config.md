---
title: Apply organisation-wide download rules
description: Make every build follow the same ocx config file, signature and yank policy, and patch snapshot, whatever machine runs it.
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

Your organisation sets rules for what a build may download.
Examples are a mirror, a corporate CA, signed packages only, no withdrawn tags and a patch for the internal TLS setup.
`ocx` reads those rules from config files in the system, user and home directories, so a laptop and a CI runner can resolve the same `ocx.toml` differently.
CMake has no layer for this, because `file(DOWNLOAD)` and `FetchContent` verify a hash you write but cannot require a signature or a mirror.

This page makes every build read the same rules, wherever it runs.
It assumes a project that already calls `ocx_project`, as in the [tutorial](../tutorial.md).

## Pick where a rule lives {#where-a-rule-lives}

find_ocx sorts the `ocx` environment variables into four classes.
The class decides who can change a value.

| Class | Variables | Behavior |
| --- | --- | --- |
| Site | `OCX_MIRRORS`, `OCX_INSECURE_REGISTRIES`, `OCX_OFFLINE`, `OCX_FROZEN`, `OCX_REMOTE`, `OCX_JOBS`, `OCX_INDEX`, `OCX_DEFAULT_REGISTRY`, `OCX_MANAGED_CONFIG`, `OCX_PATCHES`, `OCX_EXTRA_CA_CERTS`, `OCX_HOME` | The environment value at the first configure is stored in the cache and forwarded to every `ocx` call. |
| Per call | `OCX_CONFIG`, `OCX_NO_CONFIG`, `OCX_PATCH_SNAPSHOT`, `OCX_SIGSTORE_TRUSTED_ROOT` | A keyword on the command overrides the environment value. |
| Explicit | `OCX_NO_VERIFY`, `OCX_ALLOW_YANKED` | Only `ocx_policy` sets them. An exported value is ignored. |
| Pinned | `OCX_QUIET`, `OCX_GLOBAL`, `OCX_NO_PROJECT`, `OCX_NO_CONSENT` and similar | find_ocx sets them on every call, so a developer's shell cannot change the output that CMake parses. |

`OCX_AUTH_<REGISTRY>_*` credentials belong to none of these classes, because find_ocx never stores them.
See [Environment and config](../concepts/env-and-config.md) for the full table.

## Commit one config file {#config}

Put the rules in a file that you commit, and name it with `CONFIG`.
`NO_CONFIG` tells ocx to ignore the config files of the machine, so only your file and the locked sections of `/etc/ocx/config.toml` apply.

<!-- snippet: examples/policy/CMakeLists.txt#config -->

The file uses the `ocx` config format.
This one only sets the default registry.

<!-- snippet: examples/policy/ocx-config.toml#config -->

A real file carries your mirror, your CA and your trust policy.
A relative `extra_ca_certs` path resolves against the directory of the file.

<!-- doc-norun: the hosts, the identity and the issuer are placeholders for your organisation -->
```toml
extra_ca_certs = "corp-ca.pem"

[mirrors]
"ocx.sh" = "https://mirror.corp/ocx"

[[trust.policy]]
scope = "ocx.sh/acme/*"
signers = [
  { kind = "keyless", identity = "https://github.com/acme/release/.github/workflows/release.yml@refs/heads/main",
                      oidc_issuer = "https://token.actions.githubusercontent.com" },
]
```
<!-- /doc-norun -->

Check a file before you commit it with `ocx config test <file>`.
The command previews the configuration that the file produces.
find_ocx adds the config files that exist to `CMAKE_CONFIGURE_DEPENDS`, so editing one reruns the configure.

## Set the signature and yank policy {#policy}

`ocx_policy` loosens what `ocx` accepts, and it never tightens.
Signature checks start only when a `[[trust.policy]]` in your config covers a package.

<!-- doc-norun: the trusted root file is a placeholder for your private Sigstore deployment -->
```cmake
ocx_policy(
  ALLOW_YANKED
  SIGSTORE_TRUSTED_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/trusted_root.json")
```
<!-- /doc-norun -->

- `ALLOW_UNVERIFIED` skips the signature check for covered packages. `ocx` prints a warning on every call that skips it.
- `ALLOW_YANKED` resolves tags that the public index marked as withdrawn.
- `SIGSTORE_TRUSTED_ROOT` names the trust root of a private Sigstore deployment, for air-gapped checks.

Call `ocx_policy` once, in the top-level `CMakeLists.txt`, before the first `ocx_project` or `ocx_package`.
A second call with different arguments is a configure error.
`OCX_NO_VERIFY` and `OCX_ALLOW_YANKED` in the environment have no effect, which keeps a CI variable from switching verification off.

## Freeze patches {#patches}

A patch is a companion package that your config adds to the environment of every matching package, for example a CA bundle for a JDK.
`ocx lock --check` does not cover patches, so freeze them next to the lock file.
Run `ocx patch freeze`, commit `patches.snapshot.json`, and name it with `PATCH_SNAPSHOT`.

<!-- doc-norun: the snapshot is written by ocx patch freeze against your own patch descriptor -->
```cmake
ocx_project(NAME TOOLS BINS jq
  CONFIG "${CMAKE_CURRENT_SOURCE_DIR}/ocx-config.toml"
  NO_CONFIG
  PATCH_SNAPSHOT "${CMAKE_CURRENT_SOURCE_DIR}/patches.snapshot.json")
```
<!-- /doc-norun -->

With a snapshot, every call uses the pinned digests and does no live tag lookup.
Only `ocx patch sync` refreshes the snapshot, and it needs the network.

## Handle a managed config {#managed}

A `[managed]` block in a config file points at a configuration package in your registry.
If the block is required and a machine never synced it, every `ocx` command there exits with 78.
The error names the fix: run `ocx config update` once on that machine.
find_ocx never runs it for you.
Adopting a managed config is a deliberate step.
`NO_CONFIG` opts a build out of the managed tier.

## Next steps {#next-steps}

- [Route package pulls through a mirror](mirror-packages.md) for the mirror and credential variables.
- [Environment and config](../concepts/env-and-config.md) for the four classes in detail.
- [Exit codes](../troubleshooting/exit-codes.md) for code 78 and the other configuration errors.
