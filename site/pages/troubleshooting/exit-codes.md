<!-- doc_type: troubleshooting -->
<!-- description: Each ocx exit code that a find_ocx configure can report, with its cause and its fix. -->
# Exit codes

When an `ocx` call fails, find_ocx stops the configure and reports the exit status of that call.
This page maps each status to its cause and its fix.
The table matches the hint table in `ocx.cmake`, and a test compares the two.

The message has this shape:

```text
find_ocx: <what failed> failed (exit <code>): ocx <arguments>
<the error text of ocx>
hint: <the fix for this code>
```

ocx follows the BSD sysexits convention for 64 to 78.
It uses 79 to 87 for its own cases.
find_ocx retries only the content download of a `PULL` call, and only when it exits 75, twice.
It never retries another code.
Every other call fails on its first 75.
A code such as 69, 65 or 81 means that a rerun changes nothing.

| Exit | Name | Cause | Fix |
|---|---|---|---|
| 64 | UsageError | ocx rejected the command line. The usual cause is an `ocx` that does not match find_ocx, such as a `PATH` binary older than 0.6.0 or an old `OCX_INSTALL_VERSION`. An unknown `PLATFORM` string lands here too. | Run the tested binary with `OCX_BOOTSTRAP=ALWAYS`, or pass one valid platform such as `linux/arm64`. |
| 65 | DataError | The data is malformed. In a project, `ocx.lock` is stale against `ocx.toml`. Otherwise it is a malformed reference or digest, a binary that does not resolve in `ocx package exec`, a patch snapshot from an older ocx, or a package layer that ocx refused to extract. | Run `ocx lock` and commit the result. Correct the reference. Check `BINS` and `GROUPS`. Report a refused layer to the publisher. |
| 69 | Unavailable | The registry or index answered, but not usefully. Examples are a TLS certificate that ocx refused behind an intercepting proxy, and `ocx lock` for a name that is not in the index. | Check the name, the network, `OCX_MIRRORS` and `OCX_AUTH_*`. Behind a proxy, set `OCX_EXTRA_CA_CERTS` to its CA file. |
| 74 | IoError | A local read or write failed. Examples are a full disk, a denied operation on `OCX_HOME` or the build directory, and an unreadable CA file. | Free disk space, fix the permissions on `OCX_HOME`, and check that the CA file is readable. |
| 75 | TempFail | A transient failure that can succeed on a retry. Examples are a refused or hung connection, a timeout, an HTTP 408, 429, 502, 503 or 504 answer, and a layer that arrived short. | A `PULL` download was already retried twice. Rerun later, or route the registry through `OCX_MIRRORS`. |
| 77 | PermissionDenied | The operating system refused an operation, such as a write into `OCX_HOME`. | Make `OCX_HOME` writable for the current user, or point `OCX_HOME` at a directory that is. |
| 78 | ConfigError | A configuration problem. Examples are a missing `ocx.lock` or one of format version 2, a `[managed]` config whose snapshot was never synced, invalid TOML, a registry host that the SSRF guard refuses, and a tool with no entry for the requested `PLATFORM`. | Read the message. Run `ocx lock`, run `ocx config update`, fix the TOML at the printed path, add the host to `trusted_hosts`, or narrow `GROUPS`. `NO_CONFIG` opts out of the managed tier. |
| 79 | NotFound | A resource does not exist. Examples are a package or tag that the registry or index lacks, a `CONFIG` file that is missing, and content that a cold store lacks under `OCX_OFFLINE`. | Check the name and tag, fix the `CONFIG` path, or fill the store online first. |
| 80 | AuthError | The registry refused the credentials with a 401 or 403, or none were supplied. | Export `OCX_AUTH_<REGISTRY>_TYPE`, `_USER` and `_TOKEN`, or run `ocx login <registry>`, then reconfigure. |
| 81 | PolicyBlocked | A deliberate local policy refused the call. `OCX_FROZEN` or `OCX_OFFLINE` blocked an unpinned tag or a download. A nested configure that inherits `OCX_FROZEN` and `OCX_INDEX` from an outer launcher hits the same wall. | Add the tag to the snapshot with `ocx_index(UPDATE_COMMAND)`, pin a digest, or drop the flag. For a nested configure, pass `-DOCX_FROZEN= -DOCX_INDEX=`. |
| 83 | TransparencyLogUnavailable | The Rekor transparency log was unreachable while ocx verified a signature that a `[[trust.policy]]` requires. | Rerun later and check access to the log. `ocx_policy(ALLOW_UNVERIFIED)` accepts unverified content, which weakens the build. |
| 84 | ReferrersUnsupported | The registry has no OCI referrers API, so a write cannot attach or copy signatures and attestations. Only publishing commands (`sign`, `attest`, `push`, `copy --referrers`) raise it, so a configure does not reach it. A verify that finds no signatures exits 79. | Use a registry or mirror that implements referrers. A rerun never helps. |
| 85 | UnsupportedKeyBackend | A trust policy names a key backend that ocx recognises but has not implemented, such as `awskms://`. | Point the trust configuration at a file key. A rerun never helps. |
| 86 | ForgeCapabilityUnavailable | A forge refused a write because it lacks a capability that the transport needs. Only publishing commands raise it, so a configure does not reach it. | Ask an administrator of the index project to enable the capability. |
| 87 | RegistryDeleteUnsupported | The registry does not delete tags. Only `ocx package prune` raises it, so a configure does not reach it. | Use a registry that supports tag deletion. A rerun never helps. |

Exit 82 is not in the table because no configure runs the commands that raise it.
Any other status is unexpected, so read the error text of ocx in the message.

Errors that find_ocx raises itself, such as a floating tag or a `BINS` name that does not resolve, carry no ocx status.
[Fix a failing configure](configure-errors.md) and [Fix a module conflict](module-conflicts.md) cover those.
