<!-- doc_type: explanation -->
<!-- description: The four classes of OCX_* variable that find_ocx forwards, overrides, refuses or pins, and how the ocx config tiers layer. -->
# Environment and config

This page explains which `OCX_*` variables reach the `ocx` binary during a configure, in four classes, and how the ocx config files layer under a build.
It matters because a build should not change with the shell it runs in.

## Why the variables are classified {#why}

ocx reads many environment variables.
Some of them break the module: `OCX_QUIET` empties the JSON that find_ocx parses, and `OCX_GLOBAL` conflicts with the explicit `--project` it passes.
Some weaken a build: `OCX_NO_VERIFY` switches verification off.
Some are legitimate site settings, such as a mirror.

So every `ocx` call gets a deliberate environment, and each variable belongs to exactly one class.
The classes match those of [rules_ocx](https://github.com/ocx-sh/rules_ocx), so a variable behaves the same in both.

## The four classes {#classes}

| Class | Rule | Variables |
|---|---|---|
| [Site](#site) | Forwarded to every call. A CMake variable wins, else the environment value of the first configure is kept. | `OCX_MIRRORS`, `OCX_INSECURE_REGISTRIES`, `OCX_OFFLINE`, `OCX_FROZEN`, `OCX_REMOTE`, `OCX_JOBS`, `OCX_INDEX`, `OCX_DEFAULT_REGISTRY`, `OCX_MANAGED_CONFIG`, `OCX_PATCHES`, `OCX_EXTRA_CA_CERTS`, `OCX_HOME` |
| [Translucent](#translucent) | A call keyword overrides the environment. Without a keyword, the environment value is forwarded. | `OCX_CONFIG`, `OCX_PATCH_SNAPSHOT`, `OCX_SIGSTORE_TRUSTED_ROOT`, `OCX_NO_CONFIG` |
| [Explicit](#explicit) | Never read from the environment. Only `ocx_policy` sets them. | `OCX_NO_VERIFY`, `OCX_ALLOW_YANKED` |
| [Pinned](#pinned) | Fixed value on every call. | `OCX_PROJECT`, `OCX_GLOBAL`, `OCX_QUIET`, `OCX_NO_PROJECT`, `OCX_NO_CONFIG_REFRESH`, `OCX_NO_CONSENT`, `OCX_SELF_UPDATE` |

`OCX_AUTH_<REGISTRY>_{TYPE,USER,TOKEN}` credentials sit outside the table.
They are never written into `CMakeCache.txt`.
Export them in the environment, and reconfigure after changing them.

### Site {#site}

A site variable describes the machine or the organisation, not the project.
The module follows the snapshot pattern for each one.
If the CMake variable is set, it wins.
Otherwise the environment value at the first configure is copied into the cache and stays for the build directory.

Two consequences follow.
Changing the shell variable later does not change an existing build directory, so pass `-DOCX_FROZEN=1` or use a fresh directory.
And `-DOCX_FROZEN=` with an empty value removes the variable from every `ocx` call.
That second form is how a nested configure opts out of what an outer launcher exports, as [Error: a nested configure fails](../troubleshooting/configure-errors.md#nested-configure) shows.

A site value cannot contain `;`, because a CMake list would split it into extra arguments; the module stops with an error that names the value.
The same holds for paths such as `OCX_EXECUTABLE`.

### Translucent {#translucent}

A translucent variable has a call keyword that wins over the environment.
`CONFIG`, `PATCH_SNAPSHOT` and `NO_CONFIG` belong to `ocx_project` and `ocx_package`, and `SIGSTORE_TRUSTED_ROOT` belongs to `ocx_policy`.
With the keyword set, an exported variable cannot change the build.
Without it, the exported value passes through unchanged.

### Explicit {#explicit}

`OCX_NO_VERIFY` and `OCX_ALLOW_YANKED` are never read from the environment.
find_ocx sets them on every call from `ocx_policy` alone, so an inherited export cannot weaken a build.
A CI job that exports `OCX_ALLOW_YANKED` resolves as if it had not.
Move that intent into `ocx_policy(ALLOW_YANKED)`.

A second `ocx_policy` call with different values is an error.
[Apply organisation-wide download rules](../guides/policy-and-config.md) shows the call.

### Pinned {#pinned}

A pinned variable has one right value for a configure, so find_ocx sets it on every call.

| Variable | Value | Why |
|---|---|---|
| `OCX_PROJECT` | empty | The module passes `--project` itself. ocx refuses to combine it with an ambient value. |
| `OCX_GLOBAL` | `0` | `--global` together with `--project` exits 64. |
| `OCX_QUIET` | `0` | Quiet mode prints nothing, and the module parses the JSON report. |
| `OCX_NO_PROJECT` | `1` | No directory walk to an `ocx.toml` the module did not choose. An explicit `--project` still loads. |
| `OCX_NO_CONFIG_REFRESH` | `1` | The managed-config refresh needs a terminal. |
| `OCX_NO_CONSENT` | `1` | `ocx pull` and `ocx exec` would otherwise stamp shell-activation consent for your source tree. |
| `OCX_SELF_UPDATE` | `manual` | No self-update runs during a configure. |

Two ocx settings are flags instead of variables.
Calls that compose an environment pass `--lazy-mode never` and `--pinned`, because those settings change the paths the module records.
`--pinned` also keeps the paths of a foreign `PLATFORM` correct.

## The config tiers {#config-tiers}

ocx layers its configuration, from low to high precedence:

| Tier | Linux | macOS |
|---|---|---|
| System | `/etc/ocx/config.toml` | `/etc/ocx/config.toml` |
| User | `$XDG_CONFIG_HOME/ocx/config.toml`, else `~/.config/ocx/config.toml` | `~/Library/Application Support/ocx/config.toml` |
| OCX home | `$OCX_HOME/config.toml` | `$OCX_HOME/config.toml` |
| Managed | A local snapshot of the `[managed]` source | The same |
| Explicit file | `OCX_CONFIG` or the `CONFIG` keyword | The same |

`OCX_*` environment variables override the files, and command-line flags override both.

By default a configure sees every tier.
So the mirrors, registries and patches of the host apply to the build.
find_ocx adds each tier file that exists to `CMAKE_CONFIGURE_DEPENDS`.
Editing one of them reruns the configure, and a file created later is picked up by the next configure.

## Taking the host out of the loop {#hermetic}

Two keywords decide how much of the host reaches the build:

- `CONFIG <file>` layers a committed config file on top of the discovered tiers. The file must exist, or the call fails with exit 79.
- `NO_CONFIG` skips the user, OCX home and managed tiers. The locked sections of the system file and the explicit file still load. It also blanks an exported `OCX_PATCHES`, `OCX_CONFIG` and `OCX_PATCH_SNAPSHOT`, unless the call names a `CONFIG` or `PATCH_SNAPSHOT` itself.

Together they give every machine the same configuration: commit a config file, pass it with `CONFIG`, and set `NO_CONFIG`.
Add `PATCH_SNAPSHOT` when the config declares patches, so the patches stay pinned.

A `[managed]` block whose snapshot was never synced fails every `ocx` command with exit 78:

```text
error: managed config snapshot required for source 'ocx.sh/corp/config:1' but absent; run `ocx config update`
```

find_ocx never runs `ocx config update`, because adopting a managed config is a human step.
Run the command once on the machine.
`NO_CONFIG` also clears the failure when the block lives in a discovered tier, but not when it sits in the file you pass with `CONFIG`.

## Related pages {#related}

- [Apply organisation-wide download rules](../guides/policy-and-config.md) applies this in a build.
- [Build behind a mirror or offline](../guides/mirror.md) uses the site variables.
- [Exit codes](../troubleshooting/exit-codes.md) lists what each failure means.
