# ocx 0.6.5 CLI contract (what `ocx.cmake` depends on)

Probed 2026-10-10 against the installed `ocx 0.6.5` (release build `26ad03a1`, `x86_64-unknown-linux-musl`,
glibc WSL2 host with qemu-user binfmt for aarch64). Every console block below is a verbatim capture of the
command, its stdout, its stderr and its exit status. Edits made to the captures:

- `$HOME` becomes `~`; the scratch tree becomes `$S`; the isolated store becomes `$OCX_HOME` (`$OCX_HOME2`…`$OCX_HOME5` are further empty stores used to test cold-store
  behavior).
- A single 6 kB `PATH` listing inside one error message is elided (marked).
- `OCX_NO_UPDATE_CHECK=true` was set in the probing shell (the CLI suppresses the check anyway when stderr is not
  a terminal, as it is under `execute_process`).
- Mechanical shortening, applied uniformly: in `package install` JSON the unchanged `"metadata"` object is
  replaced by `{ … elided: identical to section 1 … }` (section 1 keeps it in full); a stdout of more than eight
  lines that repeats an earlier block of the same subsection is replaced by `(stdout identical to the earlier
  block of this section)`; whole blocks that only repeated `--help` text or an already shown JSON were left out
  and are summarised in prose where they matter.
- `ocx` is the real binary (`~/.local/bin/ocx`), not the shell-function wrapper of the interactive shell.

Index digests used throughout (`ocx.sh/jqlang/jq:latest` = `1.8.2` at probe time):

| What | Digest |
|---|---|
| image **index** (`latest`) | `sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6` |
| manifest `linux/amd64` | `sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae` |
| manifest `linux/arm64` | `sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b` |
| manifest `darwin/arm64` | `sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1` |
| manifest `windows/amd64` | `sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989` |

The index digest and the four manifest digests are visible in the committed snapshot
(`ocx.sh/p/jqlang/jq/o/sha256/<index digest>.json`) and in `inspect --closure` `resolution.chain` (section 2).

## Findings that matter to the module and the plan

1. **JSON shapes `ocx.cmake` parses are unchanged.** `package install`, `package which` and `package env`
   (sections 1, 1b) keep `{<ref>: {identifier, metadata, path}}`, `{<ref>: {path, kind:"package"}}` and
   `{entries:[{key,value,type}], binaries, entrypoints, integrations, advisories}`. Extras are additive.
   Foreign-platform `install` reports `"path": null` (no candidate symlink).
2. **Error envelope** (section 3): `--format json` puts
   `{"schema_version":1,"command":…,"exit_code":N,"error":{"kind":…,"message":…,"context":{}}}` on **stdout** *and*
   always prints `error: <message>` on stderr. The envelope is **absent** for clap usage errors (64), for config
   load errors (78/79 incl. `[managed]` snapshot gate, bad TOML, missing `--config`/`OCX_CONFIG`/`--project` file) —
   those are stderr only. `kind` ↔ exit: `usage_error` 64, `data_error` 65, `unavailable` 69, `temp_fail` 75,
   `config_error` 78, `not_found` 79, `permission_denied` **81**. Messages are chain-duplicated
   (the same sentence 2–4×). Stderr is the reliable carrier; the envelope adds only `kind`.
3. **Exit codes reproduced** (section 3): 65 stale lock (`lock --check`, `pull`, `env`, `exec`), 65 binary not
   resolvable in `package exec`, 75 connection refused, 78 missing lock / **v2 lock** / `[managed]` snapshot absent /
   bad TOML, 79 name not in index / uninstalled `which` / missing explicit config or project file, 81 frozen or
   offline refusing an unpinned tag and `index update` under `--frozen`, 64 unknown platform / bad ref / bad group
   / bad binding. **`ocx lock` for a name not in the index exits 69** (not 79), message "registry unreachable …
   not in the index". 77, 80, 82–87 could not be provoked; the table is
   `/home/mherwig/dev/ocx/website/src/docs/reference/command-line.md` lines 298–354.
4. **`-p` is single-valued** (section 6): `a,b` and `a;b` are exit 64 (`unsupported architecture 'amd64,linux'`),
   repeated `-p` is exit 64 (`cannot be used multiple times`). A comma after `+` is the feature list
   (`linux/arm64+libc.glibc,libc.musl`). `linux/arm64/v8` parses. Unknown OS/arch exit 64 and list the valid
   values. There is no `OCX_PLATFORM` variable. `-p any` exists.
5. **An index digest pins every platform** (section 5): `package install ocx.sh/jqlang/jq@<index digest>` resolves
   the host leaf, and with `-p linux/arm64|darwin/arm64|windows/amd64` the matching leaf, also under `--frozen`
   and (once the index object is cached) `--offline`. A per-platform manifest digest installs on **any** `-p`
   without a platform check (an amd64 manifest digest with `-p linux/arm64` installs the amd64 manifest), so a
   `PINS` key that disagrees with the platform is silently honoured by the CLI.
6. **Project tier writes into the source tree and links are platform-stateful** (sections 2e, 3a, 7e): `pull`
   renders `<ocx.toml dir>/.ocx/toolchain/{links,shells,active,.gitignore}`; `env` PATH values go through
   `links/<group>/<entry>`, which point at whatever platform was rendered **last** (`pull`, `exec` and `env` each
   re-render the links for their own platform, section 2e-bis). `OCX_TOOLCHAIN_DIR` cannot move
   this out of `$HOME`/`$OCX_HOME` (exit 78). `--pinned` (or `OCX_TOOLCHAIN_PINNED=1`) yields digest paths and is
   platform-correct. That `.ocx/` directory is what `ocx.cmake` `__ocx_find_index` mistakes for an index snapshot.
7. **Ambient env** (section 4): `OCX_QUIET=1|yes|on|TRUE` → exit 0 with **empty stdout** (JSON parse dies);
   `OCX_GLOBAL=1|true` with `--project` → exit 64; `0` and empty both neutralize both. `OCX_NO_PROJECT` empty or
   invalid prints the "invalid boolean value" warning (4× on `env`) but is otherwise ignored; `0` is silent;
   explicit `--project` still loads under `OCX_NO_PROJECT=1`. `OCX_NO_CONSENT` unset → a consent stamp is
   written for the source tree (`ocx shell state`: `active: yes`). `OCX_LAZY_MODE=always` prepends a shims
   directory to the `env` entries; `OCX_TOOLCHAIN_PINNED=1` switches `env` to digest paths.
8. **Snapshot layout** (section 7): `<registry>/{config.json, c/index.json, p/<repo>.json,
   p/<repo>/o/sha256/<index digest>.json}`. Frozen resolution works with `c/index.json` deleted. A bare
   `index update <repo>` records **every** tag, `<repo>:<tag>` only that tag. `OCX_INDEX=` (empty) means "index
   at the current directory" and writes there.
9. **Verbs** (section 8): `ocx run` still works but prints `warning: `ocx run` is renamed to `ocx exec` and is
   removed in 0.7` on stderr; `package describe` and `package info` are deprecated the same way;
   `package run` is gone (exit 64). `ocx exec -g` default scope is `[tools]` only; `ocx pull` without `-g`
   pulls **all** groups; `env`/`exec`/`inspect` without `-g` use the default group only.
10. **Bootstrap** (section 8b): live `https://setup.ocx.sh/dist.json` is the same `schema: 1` flat-row format,
    280 rows, versions up to 0.6.5, 8 targets, all `channel: "stable"`. Unix archives are `.tar.gz`
    (`ocx-<triple>/ocx` nested), Windows `.zip` (flat `ocx.exe`); 0.3.x/0.4.x were `.tar.xz`.
    The embedded snapshot in `ocx.cmake` tops out at 0.4.2. `ocx self update` only has `--check`
    (no version pin), so a pinned bootstrap cannot use it.

## 1. Package tier, host platform

#### 1. package tier JSON, host platform (fresh OCX_HOME)

```console
$ ocx --format json package install ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "identifier": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": {
      "type": "bundle",
      "version": 1,
      "env": [
        {
          "key": "PATH",
          "type": "path",
          "required": true,
          "value": "${installPath}",
          "visibility": "public"
        }
      ],
      "binaries": [
        "jq"
      ]
    },
    "path": "$OCX_HOME4/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
Downloading layer sha256:88ad916b0507 to $OCX_HOME4/temp/9c13e7a59201751a36e83176bff4a013
# exit: 0
```

```console
$ ocx --format json package which ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "path": "$OCX_HOME4/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e",
    "kind": "package"
  }
}
# exit: 0
```

```console
$ ocx --format json package env ocx.sh/jqlang/jq:latest
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME4/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --format json package exec ocx.sh/jqlang/jq:latest -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

```console
$ ocx package exec ocx.sh/jqlang/jq:latest -- sh -c exit\ 7
# exit: 7
```


## 1b. Foreign platform

`package exec -p linux/arm64` ran here only because this host has qemu-user binfmt registered; `-p darwin/arm64`
fails with `Exec format error` (exit 1, no envelope). The binary lives at `content/jq` (no `bin/`).

#### 1b. foreign platform linux/arm64

```console
$ ocx --format json package install -p linux/arm64 ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "identifier": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b",
    "metadata": { … elided: identical to section 1 … },
    "path": null
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
Downloading layer sha256:e0951c9ef030 to $OCX_HOME/temp/bf81771813cd138d3063d59c256f5006
# exit: 0
```

```console
$ ocx --format json package which -p linux/arm64 ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "path": "$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a",
    "kind": "package"
  }
}
# exit: 0
```

```console
$ ocx --format json package env -p linux/arm64 ocx.sh/jqlang/jq:latest
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --format json package exec -p linux/arm64 ocx.sh/jqlang/jq:latest -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

```console
$ ocx --format json package install -p darwin/arm64 ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "identifier": "ocx.sh/jqlang/jq:latest@sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1",
    "metadata": { … elided: identical to section 1 … },
    "path": null
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
Downloading layer sha256:8230875ada94 to $OCX_HOME/temp/bfcbc1cfc266adb9dbae602e6d3afe62
# exit: 0
```

```console
$ ocx --format json package install -p windows/amd64 ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "identifier": "ocx.sh/jqlang/jq:latest@sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989",
    "metadata": { … elided: identical to section 1 … },
    "path": null
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
Downloading layer sha256:f4517d115132 to $OCX_HOME/temp/5ed714dc9bfdefe6897b31b8addeb4bc
# exit: 0
```

```console
$ ocx --format json package install -p plan9/riscv ocx.sh/jqlang/jq:latest
# stderr
error: invalid value 'plan9/riscv' for '--platform <PLATFORM>': invalid platform 'plan9/riscv': unsupported OS 'plan9'. Possible values are: darwin, linux, windows, wasip1, wasip2

For more information, try '--help'.
# exit: 64
```

#### 1c. foreign exec check

```console
$ ocx package exec -p linux/arm64 ocx.sh/jqlang/jq:latest -- sh -c echo\ \$PATH\ \|\ tr\ :\ \"\\n\"\ \|\ head\ -1\;\ command\ -v\ jq
# stdout
$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content
$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content/jq
# exit: 0
```

```console
$ file -L $OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content/bin/jq
# stdout
$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content/bin/jq: cannot open `$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content/bin/jq' (No such file or directory)
# exit: 0
```

```console
$ file -L $OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content/bin/jq
# stdout
$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content/bin/jq: cannot open `$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content/bin/jq' (No such file or directory)
# exit: 0
```

```console
$ ocx package exec -p darwin/arm64 ocx.sh/jqlang/jq:latest -- jq --version
# stderr
error: failed to run '$OCX_HOME/packages/ocx.sh/sha256/c5/cf10597aacad9b7925f937c966ec72/content/jq': Exec format error (os error 8)
# exit: 1
```


## 1d. `--index <dir> --frozen`

#### 1d. --index <dir> --frozen

```console
$ ocx --index $S/idx --frozen --format json package install ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "identifier": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
# exit: 0
```

```console
$ ocx --index $S/idx --frozen --format json package which ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "path": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e",
    "kind": "package"
  }
}
# exit: 0
```

```console
$ ocx --index $S/idx --frozen --format json package env ocx.sh/jqlang/jq:latest
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --index $S/idx --frozen --format json package env -p linux/arm64 ocx.sh/jqlang/jq:latest
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --index $S/idx --frozen package exec ocx.sh/jqlang/jq:latest -- jq --version
# stdout
jq-1.8.2
# exit: 0
```


## 2. Project tier: lock and `inspect --closure`

`ocx lock` on the 0.6.5 CLI reproduces the committed `examples/project/ocx.lock` byte for byte except
`generated_at` (same `declaration_hash`, `lock_version = 3`).

#### 2. project tier: lock + inspect --closure

```console
$ cat ocx.toml
# stdout
[tools]
jq = "ocx.sh/jqlang/jq:latest"

[group.lint.tools]
shellcheck = "ocx.sh/shellcheck/shellcheck:latest"
# exit: 0
```

```console
$ ocx lock
# stdout
Binding     Group    Digest                                                                 
jq          default  sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
shellcheck  lint     sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379
# stderr
pulling count=2
Downloading layer sha256:794849587f27 to $OCX_HOME/temp/e65c6e61c6a61998d63a31ef4f597d59
warning: add `ocx.lock merge=union` to .gitattributes to avoid merge conflicts
# exit: 0
```

```console
$ cat ocx.lock
# stdout
[metadata]
lock_version = 3
declaration_hash_version = 1
declaration_hash = "sha256:2be7d627f0261dc69e77c4ccf3440f190ea605f5f87eb2b2ada2ae731b55291c"
generated_by = "ocx 0.6.5"
generated_at = "2026-10-10T16:43:55Z"

[[tool]]
name = "jq"
group = "default"
repository = "ocx.sh/jqlang/jq"

[tool.platforms]
"darwin/amd64" = "sha256:f750c91d28769d12298ba9a4c10340152fcbdd48c48102bf275c21d736cc72a2"
"darwin/arm64" = "sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1"
"linux/amd64" = "sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
"linux/arm64" = "sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
"windows/amd64" = "sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989"

[[tool]]
name = "shellcheck"
group = "lint"
repository = "ocx.sh/shellcheck/shellcheck"

[tool.platforms]
"darwin/amd64" = "sha256:3f609d1f8981b9b62804a788fc78c90ec7e8fac8d6a24b5e76b18be14964e08a"
"darwin/arm64" = "sha256:e1dd86d5905f3979d8de0f02b563d53ce051bf5244422a3592a427161d8d75f2"
"linux/amd64" = "sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379"
"linux/arm64" = "sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd"
"windows/amd64" = "sha256:ed1c498bddcc23a95ff99af7d17fa60f34e9d505d1557a1ba0c49e20d6d1d26f"
# exit: 0
```

```console
$ ocx --project . --format json inspect --closure
# stdout
{
  "platform": "linux/amd64+libc.glibc",
  "packages": [
    {
      "name": "jq",
      "identifier": "ocx.sh/jqlang/jq:latest",
      "pinned_identifier": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
      "pinned_digest": "sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
      "metadata": {
        "type": "bundle",
        "version": 1,
        "env": [
          {
            "key": "PATH",
            "type": "path",
            "required": true,
            "value": "${installPath}",
            "visibility": "public"
          }
        ],
        "binaries": [
          "jq"
        ]
      },
      "layers": [
        {
          "digest": "sha256:88ad916b0507fc084f4a638d5acf933da9afcb578b48607483fd7bbebe98d6c2",
          "media_type": "application/vnd.oci.image.layer.v1.tar+xz",
          "size": 790168
        }
      ],
      "closure": {
        "deps": [],
        "surface": {
          "interface": {
            "binaries": [
              {
                "name": "jq",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "integrations": [],
            "binaries_complete": true
          },
          "private": {
            "binaries": [
              {
                "name": "jq",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "integrations": [],
            "binaries_complete": true
          }
        },
        "conflicts": {
          "entrypoints": [],
          "repositories": []
        }
      }
    }
  ],
  "env": []
}
# exit: 0
```

#### 2b. project inspect --closure, group all, foreign platform (surface only)

```console
$ ocx --project . --format json inspect --closure -g all -p linux/arm64
# stdout
{
  "platform": "linux/arm64",
  "packages": [
    {
      "name": "jq",
      "identifier": "ocx.sh/jqlang/jq:latest",
      "pinned_identifier": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b",
      "pinned_digest": "sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b",
      "metadata": {
        "type": "bundle",
        "version": 1,
        "env": [
          {
            "key": "PATH",
            "type": "path",
            "required": true,
            "value": "${installPath}",
            "visibility": "public"
          }
        ],
        "binaries": [
          "jq"
        ]
      },
      "layers": [
        {
          "digest": "sha256:e0951c9ef030b09079b85b7dadaffcdc213f7248dc9804fad1530e23a2906ee7",
          "media_type": "application/vnd.oci.image.layer.v1.tar+xz",
          "size": 642156
        }
      ],
      "closure": {
        "deps": [],
        "surface": {
          "interface": {
            "binaries": [
              {
                "name": "jq",
                "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
              }
            ],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
              }
            ],
            "integrations": [],
            "binaries_complete": true
          },
          "private": {
            "binaries": [
              {
                "name": "jq",
                "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
              }
            ],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
              }
            ],
            "integrations": [],
            "binaries_complete": true
          }
        },
        "conflicts": {
          "entrypoints": [],
          "repositories": []
        }
      }
    },
    {
      "name": "shellcheck",
      "identifier": "ocx.sh/shellcheck/shellcheck:latest",
      "pinned_identifier": "ocx.sh/shellcheck/shellcheck:latest@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd",
      "pinned_digest": "sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd",
      "metadata": {
        "type": "bundle",
        "version": 1,
        "env": [
          {
            "key": "PATH",
            "type": "path",
            "required": true,
            "value": "${installPath}",
            "visibility": "public"
          }
        ],
        "binaries": [
          "shellcheck"
        ]
      },
      "layers": [
        {
          "digest": "sha256:06fc011619a2fe2c1098cdeb53ad7c530111a6e291cc126bd137ca86a670f50e",
          "media_type": "application/vnd.oci.image.layer.v1.tar+xz",
          "size": 7671768
        }
      ],
      "closure": {
        "deps": [],
        "surface": {
          "interface": {
            "binaries": [
              {
                "name": "shellcheck",
                "package": "ocx.sh/shellcheck/shellcheck:latest@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd"
              }
            ],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/shellcheck/shellcheck:latest@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd"
              }
            ],
            "integrations": [],
            "binaries_complete": true
          },
          "private": {
            "binaries": [
              {
                "name": "shellcheck",
                "package": "ocx.sh/shellcheck/shellcheck:latest@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd"
              }
            ],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/shellcheck/shellcheck:latest@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd"
              }
            ],
            "integrations": [],
            "binaries_complete": true
          }
        },
        "conflicts": {
          "entrypoints": [],
          "repositories": []
        }
      }
    }
  ],
  "env": []
}
# exit: 0
```

#### 2c. package inspect --closure

```console
$ ocx --format json package inspect --closure ocx.sh/jqlang/jq:latest
# stdout
{
  "platform": "linux/amd64+libc.glibc",
  "packages": [
    {
      "name": "ocx.sh/jqlang/jq:latest",
      "identifier": "ocx.sh/jqlang/jq:latest",
      "pinned_identifier": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
      "pinned_digest": "sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
      "platform": {
        "architecture": "amd64",
        "os": "linux",
        "os.features": [
          "libc.glibc"
        ]
      },
      "metadata": {
        "type": "bundle",
        "version": 1,
        "env": [
          {
            "key": "PATH",
            "type": "path",
            "required": true,
            "value": "${installPath}",
            "visibility": "public"
          }
        ],
        "binaries": [
          "jq"
        ]
      },
      "layers": [
        {
          "digest": "sha256:88ad916b0507fc084f4a638d5acf933da9afcb578b48607483fd7bbebe98d6c2",
          "media_type": "application/vnd.oci.image.layer.v1.tar+xz",
          "size": 790168
        }
      ],
      "resolution": {
        "pinned": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
        "chain": [
          {
            "digest": "sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6",
            "role": "index",
            "media_type": "application/vnd.oci.image.index.v1+json",
            "size": 1370
          },
          {
            "digest": "sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
            "role": "manifest",
            "media_type": "application/vnd.oci.image.manifest.v1+json",
            "size": 451
          },
          {
            "digest": "sha256:910ade6cfd024a3f8212c6d00417f36e3c3a0cb1cb51de9462e0d24eef510b5e",
            "role": "config",
            "media_type": "application/vnd.sh.ocx.package.v1+json",
            "size": 147
          }
        ]
      },
      "closure": {
        "deps": [],
        "surface": {
          "interface": {
            "binaries": [
              {
                "name": "jq",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "integrations": [],
            "binaries_complete": true
          },
          "private": {
            "binaries": [
              {
                "name": "jq",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "integrations": [],
            "binaries_complete": true
          }
        },
        "conflicts": {
          "entrypoints": [],
          "repositories": []
        }
      }
    }
  ],
  "env": []
}
# exit: 0
```

```console
$ ocx --format json package inspect ocx.sh/jqlang/jq:latest
# stdout
{
  "packages": [
    {
      "name": "ocx.sh/jqlang/jq:latest",
      "identifier": "ocx.sh/jqlang/jq:latest",
      "pinned_identifier": "ocx.sh/jqlang/jq:latest@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6",
      "pinned_digest": "sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6",
      "candidates": [
        {
          "digest": "sha256:f750c91d28769d12298ba9a4c10340152fcbdd48c48102bf275c21d736cc72a2",
          "pinned": "ocx.sh/jqlang/jq:latest@sha256:f750c91d28769d12298ba9a4c10340152fcbdd48c48102bf275c21d736cc72a2",
          "platform": "darwin/amd64",
          "media_type": "application/vnd.oci.image.manifest.v1+json",
          "size": 451
        },
        {
          "digest": "sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1",
          "pinned": "ocx.sh/jqlang/jq:latest@sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1",
          "platform": "darwin/arm64",
          "media_type": "application/vnd.oci.image.manifest.v1+json",
          "size": 451
        },
        {
          "digest": "sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
          "pinned": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
          "platform": "linux/amd64",
          "media_type": "application/vnd.oci.image.manifest.v1+json",
          "size": 451
        },
        {
          "digest": "sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b",
          "pinned": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b",
          "platform": "linux/arm64",
          "media_type": "application/vnd.oci.image.manifest.v1+json",
          "size": 451
        },
        {
          "digest": "sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989",
          "pinned": "ocx.sh/jqlang/jq:latest@sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989",
          "platform": "windows/amd64",
          "media_type": "application/vnd.oci.image.manifest.v1+json",
          "size": 451
        }
      ]
    }
  ],
  "env": []
}
# exit: 0
```

#### 2d. binaries_complete=false candidates

```console
$ ocx --format json package inspect --closure ocx.sh/bazelbuild/bazelisk:latest
# stdout
{
  "platform": "linux/amd64+libc.glibc",
  "packages": [
    {
      "name": "ocx.sh/bazelbuild/bazelisk:latest",
      "identifier": "ocx.sh/bazelbuild/bazelisk:latest",
      "pinned_identifier": "ocx.sh/bazelbuild/bazelisk:latest@sha256:1736f19f619f6ad3d64e37bc214695222884145f25cef13fc0b28338e951b47c",
      "pinned_digest": "sha256:1736f19f619f6ad3d64e37bc214695222884145f25cef13fc0b28338e951b47c",
      "platform": {
        "architecture": "amd64",
        "os": "linux",
        "os.features": [
          "libc.glibc"
        ]
      },
      "metadata": {
        "type": "bundle",
        "version": 1,
        "env": [
          {
            "key": "PATH",
            "type": "path",
            "required": true,
            "value": "${installPath}",
            "visibility": "public"
          }
        ]
      },
      "layers": [
        {
          "digest": "sha256:b39a59bf54b9b4eb4e704a3c788a650e768752cd106a3e6a94e6ce63e69388c8",
          "media_type": "application/vnd.oci.image.layer.v1.tar+xz",
          "size": 2475616
        }
      ],
      "resolution": {
        "pinned": "ocx.sh/bazelbuild/bazelisk:latest@sha256:1736f19f619f6ad3d64e37bc214695222884145f25cef13fc0b28338e951b47c",
        "chain": [
          {
            "digest": "sha256:a6219dce910a84696f7e38fb6e0c27ad7c557869b455cda5fcc67091c1d4997e",
            "role": "index",
            "media_type": "application/vnd.oci.image.index.v1+json",
            "size": -1
          },
          {
            "digest": "sha256:1736f19f619f6ad3d64e37bc214695222884145f25cef13fc0b28338e951b47c",
            "role": "manifest",
            "media_type": "application/vnd.oci.image.manifest.v1+json",
            "size": 452
          },
          {
            "digest": "sha256:993bc95599b35e0437d17e5b21c0affb51d488960cb9fac7a151b3029f9e5f4d",
            "role": "config",
            "media_type": "application/vnd.sh.ocx.package.v1+json",
            "size": 129
          }
        ]
      },
      "closure": {
        "deps": [],
        "surface": {
          "interface": {
            "binaries": [],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/bazelbuild/bazelisk:latest@sha256:1736f19f619f6ad3d64e37bc214695222884145f25cef13fc0b28338e951b47c"
              }
            ],
            "integrations": [],
            "binaries_complete": false
          },
          "private": {
            "binaries": [],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/bazelbuild/bazelisk:latest@sha256:1736f19f619f6ad3d64e37bc214695222884145f25cef13fc0b28338e951b47c"
              }
            ],
            "integrations": [],
            "binaries_complete": false
          }
        },
        "conflicts": {
          "entrypoints": [],
          "repositories": []
        }
      }
    }
  ],
  "env": []
}
# exit: 0
```

#### 2f. inspect --closure offline / default groups

```console
$ ocx --offline --format json --project $S/proj/ocx.toml inspect --closure jq
# stdout
{
  "platform": "linux/amd64+libc.glibc",
  "packages": [
    {
      "name": "jq",
      "identifier": "ocx.sh/jqlang/jq:latest",
      "pinned_identifier": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
      "pinned_digest": "sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
      "metadata": {
        "type": "bundle",
        "version": 1,
        "env": [
          {
            "key": "PATH",
            "type": "path",
            "required": true,
            "value": "${installPath}",
            "visibility": "public"
          }
        ],
        "binaries": [
          "jq"
        ]
      },
      "layers": [
        {
          "digest": "sha256:88ad916b0507fc084f4a638d5acf933da9afcb578b48607483fd7bbebe98d6c2",
          "media_type": "application/vnd.oci.image.layer.v1.tar+xz",
          "size": 790168
        }
      ],
      "closure": {
        "deps": [],
        "surface": {
          "interface": {
            "binaries": [
              {
                "name": "jq",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "integrations": [],
            "binaries_complete": true
          },
          "private": {
            "binaries": [
              {
                "name": "jq",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "entrypoints": [],
            "env": [
              {
                "key": "PATH",
                "type": "path",
                "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
              }
            ],
            "integrations": [],
            "binaries_complete": true
          }
        },
        "conflicts": {
          "entrypoints": [],
          "repositories": []
        }
      }
    }
  ],
  "env": []
}
# exit: 0
```

```console
$ ocx --offline --format json --project $S/proj/ocx.toml inspect --closure
# stdout
{"schema_version":1,"command":"inspect","exit_code":79,"error":{"kind":"not_found","message":"failed to inspect package: ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae — package not found","context":{}}}
# stderr
error: failed to inspect package: ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae — package not found
# exit: 79
```

```console
$ ocx --frozen --format json --project $S/proj/ocx.toml inspect --closure jq
# stdout
(stdout identical to the earlier block of this section)
# exit: 0
```

```console
$ ocx --format json --project $S/proj/ocx.toml inspect --closure nosuchbinding
# stdout
{"schema_version":1,"command":"inspect","exit_code":64,"error":{"kind":"usage_error","message":"binding 'nosuchbinding' not found in selected groups","context":{}}}
# stderr
error: binding 'nosuchbinding' not found in selected groups
# exit: 64
```

```console
$ ocx --format json --project $S/proj/ocx.toml inspect nosuchbinding
# stdout
{"schema_version":1,"command":"inspect","exit_code":64,"error":{"kind":"usage_error","message":"binding 'nosuchbinding' not found in selected groups","context":{}}}
# stderr
error: binding 'nosuchbinding' not found in selected groups
# exit: 64
```

```console
$ ocx --format json --project $S/proj/ocx.toml inspect -g nosuchgroup
# stdout
{"schema_version":1,"command":"inspect","exit_code":64,"error":{"kind":"usage_error","message":"unknown group 'nosuchgroup' in --group filter","context":{}}}
# stderr
error: unknown group 'nosuchgroup' in --group filter
# exit: 64
```

```console
$ ocx --format json --project $S/proj/ocx.toml env -g nosuchgroup
# stdout
{"schema_version":1,"command":"env","exit_code":64,"error":{"kind":"usage_error","message":"unknown group 'nosuchgroup' in --group filter","context":{}}}
# stderr
error: unknown group 'nosuchgroup' in --group filter
# exit: 64
```

```console
$ ocx --format json --project $S/proj/ocx.toml exec -g nosuchgroup -- true
# stdout
{"schema_version":1,"command":"exec","exit_code":64,"error":{"kind":"usage_error","message":"unknown group 'nosuchgroup' in --group filter","context":{}}}
# stderr
error: unknown group 'nosuchgroup' in --group filter
# exit: 64
```


Left out as duplicates of the first block (same shape): `package inspect --closure -p linux/arm64`
(`platform: "linux/arm64"`, `pinned_digest` `sha256:81b771e5…`), and the project `inspect --closure jq` runs under
`--offline` with a warm store and under `--frozen` with a cold store (both exit 0, same JSON). Cold store plus
`--offline` is exit 79 (last block above, `package not found`).

`closure.surface.interface.binaries_complete` is `false` when some admitted node left `binaries` **undeclared**
(`ocx.sh/bazelbuild/bazelisk:latest`, above); a declared-empty list stays `true`. Scan of other common tools
(`package inspect --closure`, host leaf, result of a throwaway loop — not verbatim): `kitware/cmake` →
`ccmake cmake cmake-gui cpack ctest`; `go-task/task` → `task`; `astral-sh/uv` → `uv uvx`; `ninja-build/ninja` →
`ninja`; all `deps: []`, `entrypoints: []`, `binaries_complete: true`. Entrypoint objects have the same
`{name, package}` shape as binaries (command-line.md lines 4343–4408).

Project tier: `packages[].name` is the **binding name**, there is no per-package `platform`/`resolution`.
Package tier: `name` is the identifier, and `platform` + `resolution.chain` (index, manifest, config digests)
are present.

### 2e. Project tier and foreign platforms

#### 2e. project-tier foreign platform: links vs digest paths (fresh project, no host pull)

```console
$ ocx --project $S/proj2/ocx.toml pull -p linux/arm64 -g all
# stdout
Package                                                                                               Kind     Path                                                                                                                                                        
ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b              package  $OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a
ocx.sh/shellcheck/shellcheck@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd  package  $OCX_HOME/packages/ocx.sh/sha256/57/f540d6f5a6f094f7c4e441e2294cb7
# stderr
pulling count=2
# exit: 0
```

```console
$ bash -c ls\ -l\ $S/proj2/.ocx/toolchain/links/\*/\*\ \|\ sed\ \'s#.\*links#links#\'
# stdout
links/default/jq -> $OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a
links/lint/shellcheck -> $OCX_HOME/packages/ocx.sh/sha256/57/f540d6f5a6f094f7c4e441e2294cb7
# exit: 0
```

```console
$ ocx --format json --project $S/proj2/ocx.toml env -p linux/arm64 -g all
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$S/proj2/.ocx/toolchain/links/default/jq/content",
      "type": "path"
    },
    {
      "key": "PATH",
      "value": "$S/proj2/.ocx/toolchain/links/lint/shellcheck/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
    },
    {
      "name": "shellcheck",
      "package": "ocx.sh/shellcheck/shellcheck:latest@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --format json --project $S/proj2/ocx.toml env -p linux/arm64 -g all --pinned
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content",
      "type": "path"
    },
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/57/f540d6f5a6f094f7c4e441e2294cb7/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
    },
    {
      "name": "shellcheck",
      "package": "ocx.sh/shellcheck/shellcheck:latest@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

#### 2e-bis. links are re-rendered by whichever of pull, exec, env ran last (host project already rendered for the host)

```console
$ bash -c readlink\ $S/proj/.ocx/toolchain/links/default/jq
# stdout
$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e
# exit: 0
```

```console
$ ocx --project $S/proj/ocx.toml pull -p linux/arm64
# stdout
Package                                                                                               Kind     Path                                                                                                                                                        
ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b              package  $OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a
ocx.sh/shellcheck/shellcheck@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd  package  $OCX_HOME/packages/ocx.sh/sha256/57/f540d6f5a6f094f7c4e441e2294cb7
# stderr
pulling count=2
# exit: 0
```

```console
$ bash -c readlink\ $S/proj/.ocx/toolchain/links/default/jq
# stdout
$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a
# exit: 0
```

```console
$ bash -c ocx\ --format\ json\ --project\ $S/proj/ocx.toml\ env\ -p\ linux/arm64\ \|\ grep\ -m1\ \'\"value\"\'\;\ realpath\ \$\(ocx\ --format\ json\ --project\ $S/proj/ocx.toml\ env\ -p\ linux/arm64\ \|\ python3\ -I\ -c\ \'import\ json\,sys\;print\(json.load\(sys.stdin\)\[\"entries\"\]\[0\]\[\"value\"\]\)\'\)
# stdout
      "value": "$S/proj/.ocx/toolchain/links/default/jq/content",
$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content
# exit: 0
```

```console
$ bash -c ocx\ --format\ json\ --project\ $S/proj/ocx.toml\ env\ -p\ linux/arm64\ --pinned\ \|\ grep\ -m1\ \'\"value\"\'
# stdout
      "value": "$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content",
# exit: 0
```

```console
$ bash -c ocx\ --project\ $S/proj/ocx.toml\ exec\ --\ sh\ -c\ \'command\ -v\ jq\;\ uname\ -m\;\ jq\ --version\'
# stdout
$S/proj/.ocx/toolchain/links/default/jq/content/jq
x86_64
jq-1.8.2
# exit: 0
```

After the `exec` above, which of the two platforms do the links point at?

```console
$ bash -c readlink\ $S/proj/.ocx/toolchain/links/default/jq
# stdout
$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e
# exit: 0
```

```console
$ ocx --format json --project $S/proj/ocx.toml env -p linux/arm64 -g default
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/default/jq/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ bash -c readlink\ $S/proj/.ocx/toolchain/links/default/jq
# stdout
$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a
# exit: 0
```

```console
$ bash -c ocx\ --project\ $S/proj/ocx.toml\ pull\ -p\ linux/arm64\ \>/dev/null\ 2\>\&1\;\ readlink\ $S/proj/.ocx/toolchain/links/default/jq\;\ ocx\ --format\ json\ --project\ $S/proj/ocx.toml\ env\ -p\ linux/arm64\ \>/dev/null\;\ readlink\ $S/proj/.ocx/toolchain/links/default/jq\;\ ocx\ --project\ $S/proj/ocx.toml\ pull\ \>/dev/null\ 2\>\&1\;\ readlink\ $S/proj/.ocx/toolchain/links/default/jq
# stdout
$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a
$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a
$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e
# exit: 0
```


### 3a. Project commands `ocx.cmake` issues (happy path)

#### 3a. project-tier commands ocx.cmake uses (happy path)

```console
$ ocx --project $S/proj/ocx.toml lock --check
# exit: 0
```

```console
$ ocx --project $S/proj/ocx.toml pull
# stdout
Package                                                                                               Kind     Path                                                                                                                                                        
ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae              package  $OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e
ocx.sh/shellcheck/shellcheck@sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379  package  $OCX_HOME/packages/ocx.sh/sha256/39/81b442fff3f6bf9ae93e4c293e5332
# stderr
pulling count=2
# exit: 0
```

```console
$ ocx --project $S/proj/ocx.toml pull -g lint
# stdout
Package                                                                                               Kind     Path                                                                                                                                                        
ocx.sh/shellcheck/shellcheck@sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379  package  $OCX_HOME/packages/ocx.sh/sha256/39/81b442fff3f6bf9ae93e4c293e5332
# stderr
pulling count=1
# exit: 0
```

```console
$ ocx --project $S/proj/ocx.toml pull -p linux/arm64 -g all
# stdout
Package                                                                                               Kind     Path                                                                                                                                                        
ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b              package  $OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a
ocx.sh/shellcheck/shellcheck@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd  package  $OCX_HOME/packages/ocx.sh/sha256/57/f540d6f5a6f094f7c4e441e2294cb7
# stderr
pulling count=2
Downloading layer sha256:06fc011619a2 to $OCX_HOME/temp/5dd20af6d4a69fdbfc828ab4cf4cfabc
# exit: 0
```

```console
$ ocx --format json --project $S/proj/ocx.toml env
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/default/jq/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --format json --project $S/proj/ocx.toml env -p linux/arm64 -g all
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/default/jq/content",
      "type": "path"
    },
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/lint/shellcheck/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
    },
    {
      "name": "shellcheck",
      "package": "ocx.sh/shellcheck/shellcheck:latest@sha256:57f540d6f5a6f094f7c4e441e2294cb712abb2991d47736f91a56dde2c8025dd"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --project $S/proj/ocx.toml exec -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

```console
$ ocx --project $S/proj/ocx.toml exec -g lint -- shellcheck --version
# stdout
ShellCheck - shell script analysis tool
version: 0.11.0
license: GNU General Public License, version 3
website: https://www.shellcheck.net
# exit: 0
```

```console
$ ocx --project $S/proj/ocx.toml exec -- sh -c exit\ 7
# exit: 7
```


### exec vs the deprecated run, project tier

#### 8. exec vs run

```console
$ ocx --project $S/proj/ocx.toml run -- jq --version
# stdout
jq-1.8.2
# stderr
warning: `ocx run` is renamed to `ocx exec` and is removed in 0.7
# exit: 0
```


## 3. Errors

### Project tier: missing lock, version 2 lock, stale lock

#### 3a. project-tier failures (missing lock / v2 lock / stale lock)

### e1

```console
$ ocx --format json --project $S/e1/ocx.toml lock --check
# stdout
{"schema_version":1,"command":"lock","exit_code":78,"error":{"kind":"config_error","message":"ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it","context":{}}}
# stderr
error: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it
# exit: 78
```

```console
$ ocx --project $S/e1/ocx.toml lock --check
# stderr
error: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it
# exit: 78
```

```console
$ ocx --format json --project $S/e1/ocx.toml pull
# stdout
{"schema_version":1,"command":"pull","exit_code":78,"error":{"kind":"config_error","message":"ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it","context":{}}}
# stderr
error: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it
# exit: 78
```

```console
$ ocx --format json --project $S/e1/ocx.toml env
# stdout
{"schema_version":1,"command":"env","exit_code":78,"error":{"kind":"config_error","message":"ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it","context":{}}}
# stderr
error: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it
# exit: 78
```

```console
$ ocx --project $S/e1/ocx.toml exec -- jq --version
# stderr
error: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it: ocx.lock not found at $S/e1/ocx.lock; run `ocx lock` to create it
# exit: 78
```

### e2

```console
$ ocx --format json --project $S/e2/ocx.toml lock --check
# stdout
{"schema_version":1,"command":"lock","exit_code":78,"error":{"kind":"config_error","message":"$S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: unsupported ocx.lock version 2; regenerate with `ocx lock`","context":{}}}
# stderr
error: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: unsupported ocx.lock version 2; regenerate with `ocx lock`
# exit: 78
```

```console
$ ocx --project $S/e2/ocx.toml lock --check
# stderr
error: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: unsupported ocx.lock version 2; regenerate with `ocx lock`
# exit: 78
```

```console
$ ocx --format json --project $S/e2/ocx.toml pull
# stdout
{"schema_version":1,"command":"pull","exit_code":78,"error":{"kind":"config_error","message":"$S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: unsupported ocx.lock version 2; regenerate with `ocx lock`","context":{}}}
# stderr
error: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: unsupported ocx.lock version 2; regenerate with `ocx lock`
# exit: 78
```

```console
$ ocx --format json --project $S/e2/ocx.toml env
# stdout
{"schema_version":1,"command":"env","exit_code":78,"error":{"kind":"config_error","message":"$S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: unsupported ocx.lock version 2; regenerate with `ocx lock`","context":{}}}
# stderr
error: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: unsupported ocx.lock version 2; regenerate with `ocx lock`
# exit: 78
```

```console
$ ocx --project $S/e2/ocx.toml exec -- jq --version
# stderr
error: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: $S/e2/ocx.lock: unsupported ocx.lock version 2; regenerate with `ocx lock`: unsupported ocx.lock version 2; regenerate with `ocx lock`
# exit: 78
```

### e3

```console
$ ocx --format json --project $S/e3/ocx.toml lock --check
# stdout
{"schema_version":1,"command":"lock","exit_code":65,"error":{"kind":"data_error","message":"ocx.lock is stale (it does not match ocx.toml); run `ocx lock`: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`","context":{}}}
# stderr
error: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`
# exit: 65
```

```console
$ ocx --project $S/e3/ocx.toml lock --check
# stderr
ocx.lock does not match ocx.toml; run `ocx lock` to update it
# exit: 65
```

```console
$ ocx --format json --project $S/e3/ocx.toml pull
# stdout
{"schema_version":1,"command":"pull","exit_code":65,"error":{"kind":"data_error","message":"ocx.lock is stale (it does not match ocx.toml); run `ocx lock`: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`","context":{}}}
# stderr
error: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`
# exit: 65
```

```console
$ ocx --format json --project $S/e3/ocx.toml env
# stdout
{"schema_version":1,"command":"env","exit_code":65,"error":{"kind":"data_error","message":"ocx.lock is stale (it does not match ocx.toml); run `ocx lock`: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`","context":{}}}
# stderr
error: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`
# exit: 65
```

```console
$ ocx --project $S/e3/ocx.toml exec -- jq --version
# stderr
error: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`
# exit: 65
```

### explicit --project under OCX_NO_PROJECT=1

```console
$ env OCX_NO_PROJECT=1 ocx --project $S/proj/ocx.toml lock --check
# exit: 0
```

```console
$ env OCX_NO_PROJECT=1 ocx --format json --project $S/proj/ocx.toml env -g all
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/default/jq/content",
      "type": "path"
    },
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/lint/shellcheck/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    },
    {
      "name": "shellcheck",
      "package": "ocx.sh/shellcheck/shellcheck:latest@sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

### e4: name not in index at lock time

```console
$ ocx --format json --project $S/e4/ocx.toml lock
# stdout
{"schema_version":1,"command":"lock","exit_code":69,"error":{"kind":"unavailable","message":"registry unreachable for 'ocx.sh/nope/nothing:1': registry unreachable for 'ocx.sh/nope/nothing:1': registry unreachable for 'ocx.sh/nope/nothing:1': chained index source walk failed: 'ocx.sh/nope/nothing:1' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries.\"ocx.sh\"] index = \"\"`: 'ocx.sh/nope/nothing:1' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries.\"ocx.sh\"] index = \"\"`","context":{}}}
# stderr
error: registry unreachable for 'ocx.sh/nope/nothing:1': registry unreachable for 'ocx.sh/nope/nothing:1': registry unreachable for 'ocx.sh/nope/nothing:1': chained index source walk failed: 'ocx.sh/nope/nothing:1' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries."ocx.sh"] index = ""`: 'ocx.sh/nope/nothing:1' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries."ocx.sh"] index = ""`
# exit: 69
```


### Package tier: bad refs, not found, unknown platform, exec failures, exit 75

#### 3b. package-tier failures

```console
$ ocx --format json package install not\ a\ ref\!\!
# stderr
error: invalid value 'not a ref!!' for '<PACKAGES>...': invalid identifier 'not a ref!!': invalid format

For more information, try '--help'.
# exit: 64
```

```console
$ ocx --format json package install ocx.sh/jqlang/jq:does-not-exist-9.9
# stdout
{"schema_version":1,"command":"package install","exit_code":79,"error":{"kind":"not_found","message":"failed to install package: ocx.sh/jqlang/jq:does-not-exist-9.9 — chained index source walk failed: 'ocx.sh/jqlang/jq:does-not-exist-9.9' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries.\"ocx.sh\"] index = \"\"`","context":{}}}
# stderr
Installing packages: ocx.sh/jqlang/jq:does-not-exist-9.9
pulling count=1
error: failed to install package: ocx.sh/jqlang/jq:does-not-exist-9.9 — chained index source walk failed: 'ocx.sh/jqlang/jq:does-not-exist-9.9' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries."ocx.sh"] index = ""`
# exit: 79
```

```console
$ ocx --format json package install ocx.sh/nope/nothing:1
# stdout
{"schema_version":1,"command":"package install","exit_code":79,"error":{"kind":"not_found","message":"failed to install package: ocx.sh/nope/nothing:1 — chained index source walk failed: 'ocx.sh/nope/nothing:1' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries.\"ocx.sh\"] index = \"\"`","context":{}}}
# stderr
Installing packages: ocx.sh/nope/nothing:1
pulling count=1
error: failed to install package: ocx.sh/nope/nothing:1 — chained index source walk failed: 'ocx.sh/nope/nothing:1' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries."ocx.sh"] index = ""`
# exit: 79
```

```console
$ ocx --format json package install ocx.sh/jqlang/jq@sha256:deadbeef
# stderr
error: invalid value 'ocx.sh/jqlang/jq@sha256:deadbeef' for '<PACKAGES>...': invalid identifier 'ocx.sh/jqlang/jq@sha256:deadbeef': invalid digest format

For more information, try '--help'.
# exit: 64
```

```console
$ ocx --format json package install ocx.sh/jqlang/jq@sha256:0000000000000000000000000000000000000000000000000000000000000000
# stdout
{"schema_version":1,"command":"package install","exit_code":79,"error":{"kind":"not_found","message":"failed to install package: ocx.sh/jqlang/jq@sha256:0000000000000000000000000000000000000000000000000000000000000000 — chained index source walk failed: 'ocx.sh/jqlang/jq@sha256:0000000000000000000000000000000000000000000000000000000000000000' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries.\"ocx.sh\"] index = \"\"`","context":{}}}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:0000000000000000000000000000000000000000000000000000000000000000
pulling count=1
error: failed to install package: ocx.sh/jqlang/jq@sha256:0000000000000000000000000000000000000000000000000000000000000000 — chained index source walk failed: 'ocx.sh/jqlang/jq@sha256:0000000000000000000000000000000000000000000000000000000000000000' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries."ocx.sh"] index = ""`
# exit: 79
```

```console
$ ocx --format json package install -p linux/riscv64 ocx.sh/jqlang/jq:latest
# stderr
error: invalid value 'linux/riscv64' for '--platform <PLATFORM>': invalid platform 'linux/riscv64': unsupported architecture 'riscv64'. Possible values are: amd64, arm64, wasm

For more information, try '--help'.
# exit: 64
```

```console
$ ocx --format json package install -p linux/amd64+libc.musl ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "identifier": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
# exit: 0
```

```console
$ ocx --format json package which ocx.sh/jqlang/jq:1.8.1
# stdout
{"schema_version":1,"command":"package which","exit_code":79,"error":{"kind":"not_found","message":"failed to find package: ocx.sh/jqlang/jq:1.8.1 — package not found","context":{}}}
# stderr
error: failed to find package: ocx.sh/jqlang/jq:1.8.1 — package not found
# exit: 79
```

```console
$ ocx --format json package exec ocx.sh/jqlang/jq:latest -- nonexistent-binary-xyz
# stdout
{"schema_version":1,"command":"package exec","exit_code":65,"error":{"kind":"data_error","message":"\"nonexistent-binary-xyz\" does not resolve in the composed environment; searched: [\"$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content\", \"~/.ocx/toolchain/active/bin\", \"~/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin\", \"~/.qoder/entry\", \"~/.local/bin\", \"~/.npm-global/bin\", \"~/.cargo/bin\", \"~/.bun/bin\", \"~/.local/bin\", \"/opt/node/bin\", \"~/.vscode-server/data/User/globalStorage/github.copilot-chat/debugCommand\", \"~/.vscode-server/data/User/globalStorage/github.copilot-chat/copilotCli\", \"~/.vscode-server/bin/07f806f999227108933c2e30515b26eecc1fda74/bin/remote-cli\", \"~/.local/bin\", \"~/.npm-global/bin\", \"~/.cargo/bin\", \"~/.bun/bin\", \"~/.local/share/pnpm\", \"~/.local/bin\", \"/opt/node/bin\", \"~/.cargo/bin\", \"/opt/node/bin\", \"/usr/local/sbin\", \"/usr/local/bin\", \"/usr/sbin\", \"/usr/bin\", \"/sbin\", \"/bin\", \"/usr/games\", \"/usr/local/games\", \"/usr/lib/wsl/lib\", \"/opt/zig\", \"/opt/node/bin\", \"/mnt/c/Program Files/Microsoft VS Code/bin\", \"/opt/zig\", \"/opt/node/bin\"]","context":{}}}
# stderr
error: "nonexistent-binary-xyz" does not resolve in the composed environment; searched: ["$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content", "~/.ocx/toolchain/active/bin", "~/.ocx/symlinks/ocx.sh/ocx/cli/current/content/bin", "~/.qoder/entry", "~/.local/bin", "~/.npm-global/bin", "~/.cargo/bin", "~/.bun/bin", "~/.local/bin", "/opt/node/bin", "~/.vscode-server/data/User/globalStorage/github.copilot-chat/debugCommand", "~/.vscode-server/data/User/globalStorage/github.copilot-chat/copilotCli", "~/.vscode-server/bin/07f806f999227108933c2e30515b26eecc1fda74/bin/remote-cli", "~/.local/bin", "~/.npm-global/bin", "~/.cargo/bin", "~/.bun/bin", "~/.local/share/pnpm", "~/.local/bin", "/opt/node/bin", "~/.cargo/bin", "/opt/node/bin", "/usr/local/sbin", "/usr/local/bin", "/usr/sbin", "/usr/bin", "/sbin", "/bin", "/usr/games", "/usr/local/games", "/usr/lib/wsl/lib", "/opt/zig", "/opt/node/bin", "/mnt/c/Program Files/Microsoft VS Code/bin", "/opt/zig", "/opt/node/bin"]
# exit: 65
```

```console
$ ocx --index $S/idx --format json package env ocx.sh/shellcheck/shellcheck:latest
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/39/81b442fff3f6bf9ae93e4c293e5332/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "shellcheck",
      "package": "ocx.sh/shellcheck/shellcheck:latest@sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

#### 3c. exit 75 attempt (connection refused / unresolvable)

```console
$ ocx --format json package install localhost:1/foo/bar:1
# stdout
{"schema_version":1,"command":"package install","exit_code":75,"error":{"kind":"temp_fail","message":"failed to install package: localhost:1/foo/bar:1 — chained index source walk failed: transient registry failure: could not connect to 'localhost:1' over https; if it serves plain HTTP, set insecure = true under [registries.\"localhost:1\"] or add the host to OCX_INSECURE_REGISTRIES: error sending request for url (https://localhost:1/v2/): client error (Connect): tcp connect error: Connection refused (os error 111)","context":{}}}
# stderr
Installing packages: localhost:1/foo/bar:1
pulling count=1
warning: Could not fetch 'localhost:1/foo/bar:1' from chained source: transient registry failure: could not connect to 'localhost:1' over https; if it serves plain HTTP, set insecure = true under [registries."localhost:1"] or add the host to OCX_INSECURE_REGISTRIES
error: failed to install package: localhost:1/foo/bar:1 — chained index source walk failed: transient registry failure: could not connect to 'localhost:1' over https; if it serves plain HTTP, set insecure = true under [registries."localhost:1"] or add the host to OCX_INSECURE_REGISTRIES: error sending request for url (https://localhost:1/v2/): client error (Connect): tcp connect error: Connection refused (os error 111)
# exit: 75
```

```console
$ ocx --format json package install --help
# stdout
Install packages from a local or remote index (no `ocx.toml` touched)

Usage: ocx package install [OPTIONS] <PACKAGES>...

Arguments:
  <PACKAGES>...
          Package identifiers to install

Options:
  -s, --select
          Also set the installed version as current (creates the current symlink)

      --link <PATH>
          Also link the installed package at PATH, which keeps it from `ocx clean` while the link exists.
          
          Takes exactly one package. PATH must be absent or a link an earlier `--link` wrote; anything else is refused (exit 65). Delete the link to release the package. Read it back with `--link` on `package which`, `package env` or `package exec`.

  -p, --platform <PLATFORM>
          Target platform to resolve packages against.
          
          The value is `os/arch[/variant][+feature[,feature...]]`, for example `linux/amd64`, `linux/arm64`, or `linux/amd64+libc.glibc`. The optional `+feature` suffix filters by `os.features`: OCX selects the manifest whose features are a subset of the value you pass, so `+libc.glibc` or `+libc.musl` forces a specific libc variant. WebAssembly targets (`wasip1/wasm`, `wasip2/wasm`) are reachable only by naming them here. Defaults to the host platform. <https://ocx.sh/docs/authoring/multi-platform>

      --verify
          Verify the package's Sigstore signature before installing (default).
          
          When a `[[trust.policy]]` covers the package, its keyless Sigstore signature is verified before the package is installed; a failure aborts the install fail-closed. Overrides an `OCX_NO_VERIFY` opt-out for this invocation.

      --no-verify
          Skip Sigstore signature verification. Equivalent env var: `OCX_NO_VERIFY`

  -h, --help
          Print help (see a summary with '-h')
# exit: 0
```


### 81 on an empty store

#### 3d. 81 paths on an empty OCX_HOME (no local index)

```console
$ ocx --frozen --format json package install ocx.sh/jqlang/jq:latest
# stdout
{"schema_version":1,"command":"package install","exit_code":81,"error":{"kind":"permission_denied","message":"failed to install package: ocx.sh/jqlang/jq:latest — frozen mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:latest'; run `ocx index update` or pin a digest","context":{}}}
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
error: failed to install package: ocx.sh/jqlang/jq:latest — frozen mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:latest'; run `ocx index update` or pin a digest
# exit: 81
```

```console
$ ocx --offline --format json package install ocx.sh/jqlang/jq:latest
# stdout
{"schema_version":1,"command":"package install","exit_code":81,"error":{"kind":"permission_denied","message":"failed to install package: ocx.sh/jqlang/jq:latest — offline mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:latest'; run `ocx index update` or pin a digest","context":{}}}
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
error: failed to install package: ocx.sh/jqlang/jq:latest — offline mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:latest'; run `ocx index update` or pin a digest
# exit: 81
```

```console
$ ocx --offline --format json package install ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
# stdout
{"schema_version":1,"command":"package install","exit_code":79,"error":{"kind":"not_found","message":"failed to install package: ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae — package not found","context":{}}}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
pulling count=1
error: failed to install package: ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae — package not found
# exit: 79
```

```console
$ ocx --frozen --format json package install ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
# stdout
{
  "ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae": {
    "identifier": "ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME3/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
pulling count=1
Downloading layer sha256:88ad916b0507 to $OCX_HOME3/temp/9c13e7a59201751a36e83176bff4a013
# exit: 0
```

```console
$ ocx --offline --index $S/idx --frozen --format json package install ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "identifier": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME3/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
# exit: 0
```


## 4. Ambient environment

#### 4. ambient env on a --project call

Baseline (no ambient env): `ocx --format json --project ocx.toml env` prints the JSON document (see 3a).

```console
$ env OCX_QUIET=1 ocx --format json --project $S/proj/ocx.toml env
# exit: 0
```

```console
$ env OCX_QUIET=0 ocx --format json --project $S/proj/ocx.toml env
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/default/jq/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ env OCX_QUIET= ocx --format json --project $S/proj/ocx.toml env
# stdout
(stdout identical to the earlier block of this section)
# exit: 0
```

```console
$ env OCX_GLOBAL=1 ocx --format json --project $S/proj/ocx.toml env
# stderr
error: --global cannot be combined with an explicit --project / OCX_PROJECT selection
# exit: 64
```

```console
$ env OCX_GLOBAL=0 ocx --format json --project $S/proj/ocx.toml env
# stdout
(stdout identical to the earlier block of this section)
# exit: 0
```

```console
$ env OCX_GLOBAL= ocx --format json --project $S/proj/ocx.toml env
# stdout
(stdout identical to the earlier block of this section)
# exit: 0
```

```console
$ env OCX_GLOBAL=true ocx --format json --project $S/proj/ocx.toml lock --check
# stderr
error: --global cannot be combined with an explicit --project / OCX_PROJECT selection
# exit: 64
```

```console
$ env OCX_GLOBAL=1 ocx --project $S/proj/ocx.toml exec -- jq --version
# stderr
error: --global cannot be combined with an explicit --project / OCX_PROJECT selection
# exit: 64
```

```console
$ env OCX_GLOBAL=0 ocx --project $S/proj/ocx.toml exec -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

```console
$ env OCX_GLOBAL= ocx --project $S/proj/ocx.toml exec -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

```console
$ env OCX_GLOBAL=maybe ocx --project $S/proj/ocx.toml exec -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

```console
$ env OCX_QUIET=maybe ocx --project $S/proj/ocx.toml exec -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

#### 4b. other ambient vars

```console
$ env OCX_QUIET=maybe ocx --format json --project $S/proj/ocx.toml env
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/default/jq/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ env OCX_QUIET=yes ocx --format json --project $S/proj/ocx.toml env
# exit: 0
```

```console
$ env OCX_QUIET=on ocx --format json --project $S/proj/ocx.toml env
# exit: 0
```

```console
$ env OCX_QUIET=TRUE ocx --format json --project $S/proj/ocx.toml env
# exit: 0
```

```console
$ env OCX_QUIET=1 ocx --format json package install ocx.sh/jqlang/jq:latest
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
# exit: 0
```

```console
$ env OCX_QUIET=1 ocx --format json package which ocx.sh/jqlang/jq:latest
# exit: 0
```

```console
$ env OCX_QUIET=1 ocx --format json package env ocx.sh/jqlang/jq:latest
# exit: 0
```

```console
$ env OCX_QUIET=1 ocx package exec ocx.sh/jqlang/jq:latest -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

```console
$ env OCX_QUIET=1 ocx --format json package env ocx.sh/nope/nothing:1
# stdout
{"schema_version":1,"command":"package env","exit_code":79,"error":{"kind":"not_found","message":"failed to find package: ocx.sh/nope/nothing:1 — chained index source walk failed: 'ocx.sh/nope/nothing:1' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries.\"ocx.sh\"] index = \"\"`","context":{}}}
# stderr
error: failed to find package: ocx.sh/nope/nothing:1 — chained index source walk failed: 'ocx.sh/nope/nothing:1' is not in the index at https://index.ocx.sh, which is authoritative for every name in registry 'ocx.sh'; announce it there with `ocx package announce`, or take the namespace off the index with `[registries."ocx.sh"] index = ""`
# exit: 79
```

```console
$ env OCX_PROJECT=$S/proj/ocx.toml ocx --format json env
# stdout
(stdout identical to the earlier block of this section)
# exit: 0
```

```console
$ env OCX_PROJECT= ocx --project $S/proj/ocx.toml exec -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

```console
$ env OCX_PROJECT=/nonexistent/ocx.toml ocx --format json env
# stderr
error: project file not found: /nonexistent/ocx.toml (check --project or OCX_PROJECT)
# exit: 79
```

```console
$ env OCX_PROJECT=/nonexistent/ocx.toml ocx --project $S/proj/ocx.toml exec -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

#### 4c. OCX_NO_PROJECT / OCX_NO_CONSENT / OCX_NO_CONFIG_REFRESH values

```console
$ env OCX_NO_PROJECT=1 ocx --format json env
# stdout
{"schema_version":1,"command":"env","exit_code":64,"error":{"kind":"usage_error","message":"no ocx.toml found in $S/proj or any parent; run `ocx init` to create one","context":{}}}
# stderr
error: no ocx.toml found in $S/proj or any parent; run `ocx init` to create one
# exit: 64
```

```console
$ env OCX_NO_PROJECT=0 ocx --format json env
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/default/jq/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ env OCX_NO_PROJECT= ocx --format json env
# stdout
(stdout identical to the earlier block of this section)
# stderr
warning: Environment variable 'OCX_NO_PROJECT' has invalid boolean value: invalid boolean string '', possible values are: 1, y, yes, true, 0, n, no, false
warning: Environment variable 'OCX_NO_PROJECT' has invalid boolean value: invalid boolean string '', possible values are: 1, y, yes, true, 0, n, no, false
warning: Environment variable 'OCX_NO_PROJECT' has invalid boolean value: invalid boolean string '', possible values are: 1, y, yes, true, 0, n, no, false
warning: Environment variable 'OCX_NO_PROJECT' has invalid boolean value: invalid boolean string '', possible values are: 1, y, yes, true, 0, n, no, false
# exit: 0
```

```console
$ env OCX_NO_PROJECT=true ocx --format json env
# stdout
{"schema_version":1,"command":"env","exit_code":64,"error":{"kind":"usage_error","message":"no ocx.toml found in $S/proj or any parent; run `ocx init` to create one","context":{}}}
# stderr
error: no ocx.toml found in $S/proj or any parent; run `ocx init` to create one
# exit: 64
```

```console
$ env OCX_NO_PROJECT=yes ocx --format json env
# stdout
{"schema_version":1,"command":"env","exit_code":64,"error":{"kind":"usage_error","message":"no ocx.toml found in $S/proj or any parent; run `ocx init` to create one","context":{}}}
# stderr
error: no ocx.toml found in $S/proj or any parent; run `ocx init` to create one
# exit: 64
```

```console
$ env OCX_NO_PROJECT=maybe ocx --format json env
# stdout
(stdout identical to the earlier block of this section)
# stderr
warning: Environment variable 'OCX_NO_PROJECT' has invalid boolean value: invalid boolean string 'maybe', possible values are: 1, y, yes, true, 0, n, no, false
warning: Environment variable 'OCX_NO_PROJECT' has invalid boolean value: invalid boolean string 'maybe', possible values are: 1, y, yes, true, 0, n, no, false
warning: Environment variable 'OCX_NO_PROJECT' has invalid boolean value: invalid boolean string 'maybe', possible values are: 1, y, yes, true, 0, n, no, false
warning: Environment variable 'OCX_NO_PROJECT' has invalid boolean value: invalid boolean string 'maybe', possible values are: 1, y, yes, true, 0, n, no, false
# exit: 0
```

```console
$ env OCX_NO_CONSENT=1 ocx --project $S/proj/ocx.toml lock --check
# exit: 0
```

```console
$ env OCX_NO_CONSENT=0 ocx --project $S/proj/ocx.toml lock --check
# exit: 0
```

```console
$ env OCX_NO_CONSENT= ocx --project $S/proj/ocx.toml lock --check
# exit: 0
```

```console
$ env OCX_NO_CONSENT=yes ocx --project $S/proj/ocx.toml lock --check
# exit: 0
```

```console
$ env OCX_NO_CONSENT=maybe ocx --project $S/proj/ocx.toml lock --check
# exit: 0
```

```console
$ env OCX_NO_CONFIG_REFRESH=1 ocx --project $S/proj/ocx.toml lock --check
# exit: 0
```

```console
$ env OCX_NO_CONFIG_REFRESH=0 ocx --project $S/proj/ocx.toml lock --check
# exit: 0
```

```console
$ env OCX_NO_CONFIG_REFRESH= ocx --project $S/proj/ocx.toml lock --check
# stderr
warning: Environment variable 'OCX_NO_CONFIG_REFRESH' has invalid boolean value: invalid boolean string '', possible values are: 1, y, yes, true, 0, n, no, false
# exit: 0
```

```console
$ env OCX_NO_CONFIG_REFRESH=yes ocx --project $S/proj/ocx.toml lock --check
# exit: 0
```

```console
$ env OCX_NO_CONFIG_REFRESH=maybe ocx --project $S/proj/ocx.toml lock --check
# stderr
warning: Environment variable 'OCX_NO_CONFIG_REFRESH' has invalid boolean value: invalid boolean string 'maybe', possible values are: 1, y, yes, true, 0, n, no, false
# exit: 0
```

#### 4d. toolchain-affecting ambient vars not in the plan's pinned set

```console
$ env OCX_TOOLCHAIN_PINNED=1 ocx --format json --project $S/proj/ocx.toml env
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ env OCX_LAZY_MODE=always ocx --format json --project $S/proj/ocx.toml env
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/shims/ocx.sh/jqlang/jq/sha256/91/3ff41f5e643a73c17a2e560e349d8e/bin",
      "type": "path"
    },
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/default/jq/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ env OCX_LAZY_MODE=always ocx --format json package env ocx.sh/jqlang/jq:latest
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/shims/ocx.sh/jqlang/jq/sha256/91/3ff41f5e643a73c17a2e560e349d8e/bin",
      "type": "path"
    },
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ env OCX_TOOLCHAIN_DIR=$S/tcdir ocx --format json --project $S/proj/ocx.toml env
# stderr
error: OCX_TOOLCHAIN_DIR resolves to $S/tcdir, which is outside both the home directory and $OCX_HOME
# exit: 78
```

```console
$ env OCX_TOOLCHAIN_DIR=$S/tcdir ocx --project $S/proj/ocx.toml pull
# stderr
error: OCX_TOOLCHAIN_DIR resolves to $S/tcdir, which is outside both the home directory and $OCX_HOME
# exit: 78
```

```console
$ env OCX_TOOLCHAIN_DIR=$S/tcdir ocx --format json --project $S/proj/ocx.toml env
# stderr
error: OCX_TOOLCHAIN_DIR resolves to $S/tcdir, which is outside both the home directory and $OCX_HOME
# exit: 78
```

```console
$ bash -c cd\ $S/tcdir\ \&\&\ find\ .\ -maxdepth\ 3\ \|\ head
# stderr
bash: line 1: cd: $S/tcdir: No such file or directory
# exit: 1
```

```console
$ env OCX_TOOLCHAIN_DIR=relative/dir ocx --project $S/proj/ocx.toml pull
# stderr
error: OCX_TOOLCHAIN_DIR is the relative path relative/dir; a toolchain_dir root must be absolute, or one project resolves a different home from every working directory
# exit: 78
```

```console
$ env OCX_TOOLCHAIN_ACTIVATE=1 ocx --format json --project $S/proj/ocx.toml env
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$S/proj/.ocx/toolchain/links/default/jq/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

#### 4f. OCX_NO_CONSENT

```console
$ find $OCX_HOME -maxdepth 2 -iname \*consent\*
# exit: 0
```

```console
$ env OCX_NO_CONSENT=1 ocx --project $S/c1/ocx.toml pull
# stdout
Package                                                                                               Kind     Path                                                                                                                                                        
ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae              package  $OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e
ocx.sh/shellcheck/shellcheck@sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379  package  $OCX_HOME/packages/ocx.sh/sha256/39/81b442fff3f6bf9ae93e4c293e5332
# stderr
pulling count=2
# exit: 0
```

```console
$ bash -c cd\ $S/c1\ \&\&\ ocx\ shell\ state\ 2\>\&1\;\ echo\ rc=\$\?
# stdout
ocx home: $OCX_HOME
project: $S/c1
toolchain: $S/c1/.ocx/toolchain
  bin: $S/c1/.ocx/toolchain/active/bin
  activate: env
  pinned: no

active: no
reason: no consent stamp, and no matching grant
  derived sources:
    - ocx.sh/jqlang
    - ocx.sh/shellcheck
  paths tested:
    - none
  namespaces tested:
    - none
fix: run `ocx shell allow` here, or add this directory to [shell.consent] paths
rc=0
# exit: 0
```

```console
$ ocx --project $S/c2/ocx.toml pull
# stdout
Package                                                                                               Kind     Path                                                                                                                                                        
ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae              package  $OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e
ocx.sh/shellcheck/shellcheck@sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379  package  $OCX_HOME/packages/ocx.sh/sha256/39/81b442fff3f6bf9ae93e4c293e5332
# stderr
pulling count=2
# exit: 0
```

```console
$ bash -c cd\ $S/c2\ \&\&\ ocx\ shell\ state\ 2\>\&1\;\ echo\ rc=\$\?
# stdout
ocx home: $OCX_HOME
project: $S/c2
toolchain: $S/c2/.ocx/toolchain
  bin: $S/c2/.ocx/toolchain/active/bin
  activate: env
  pinned: no

active: yes
  granted by: a consent stamp, present (written just now, 2026-10-10 16:46:11 UTC) - revoke it with `ocx shell revoke`
rc=0
# exit: 0
```

#### 4g. which OCX_* vars a launcher exports into the child (scrubbed parent env, only OCX_HOME set)

```console
$ bash -c $S/fw.sh\ ocx\ package\ exec\ ocx.sh/jqlang/jq:latest\ --\ env\ \|\ grep\ -a\ OCX\ \|\ sort
# stdout
OCX_BINARY_PIN=~/.local/bin/ocx
OCX_HOME=$OCX_HOME
OCX_RECORDS_NAME={time}-{pid}-{rand}.json
# exit: 0
```

```console
$ bash -c $S/fw.sh\ ocx\ --index\ $S/idx\ --frozen\ package\ exec\ ocx.sh/jqlang/jq:latest\ --\ env\ \|\ grep\ -a\ OCX\ \|\ sort
# stdout
OCX_BINARY_PIN=~/.local/bin/ocx
OCX_FROZEN=1
OCX_HOME=$OCX_HOME
OCX_INDEX=$S/idx
OCX_RECORDS_NAME={time}-{pid}-{rand}.json
# exit: 0
```

```console
$ bash -c $S/fw.sh\ ocx\ --project\ $S/proj/ocx.toml\ exec\ --\ env\ \|\ grep\ -a\ OCX\ \|\ sort
# stdout
OCX_BINARY_PIN=~/.local/bin/ocx
OCX_HOME=$OCX_HOME
OCX_PROJECT=$S/proj/ocx.toml
OCX_RECORDS_NAME={time}-{pid}-{rand}.json
# exit: 0
```

```console
$ bash -c $S/fw.sh\ ocx\ --project\ $S/proj/ocx.toml\ --offline\ --frozen\ exec\ --\ env\ \|\ grep\ -a\ OCX\ \|\ sort
# stdout
OCX_BINARY_PIN=~/.local/bin/ocx
OCX_FROZEN=1
OCX_HOME=$OCX_HOME
OCX_OFFLINE=1
OCX_PROJECT=$S/proj/ocx.toml
OCX_RECORDS_NAME={time}-{pid}-{rand}.json
# exit: 0
```


## 5. Digest pinning

#### 5. digest pinning

```console
$ ocx --format json package install ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6": {
    "identifier": "ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
pulling count=1
# exit: 0
```

```console
$ ocx --format json package install -p linux/arm64 ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6": {
    "identifier": "ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b",
    "metadata": { … elided: identical to section 1 … },
    "path": null
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
pulling count=1
# exit: 0
```

```console
$ ocx --format json package install -p darwin/arm64 ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6": {
    "identifier": "ocx.sh/jqlang/jq@sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1",
    "metadata": { … elided: identical to section 1 … },
    "path": null
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
pulling count=1
# exit: 0
```

```console
$ ocx --format json package install -p windows/amd64 ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6": {
    "identifier": "ocx.sh/jqlang/jq@sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989",
    "metadata": { … elided: identical to section 1 … },
    "path": null
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
pulling count=1
# exit: 0
```

```console
$ ocx --format json package which -p linux/arm64 ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6": {
    "path": "$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a",
    "kind": "package"
  }
}
# exit: 0
```

```console
$ ocx --format json package env -p linux/arm64 ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --format json package install ocx.sh/jqlang/jq:1.8.2@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "ocx.sh/jqlang/jq:1.8.2@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6": {
    "identifier": "ocx.sh/jqlang/jq:1.8.2@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/1.8.2"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:1.8.2@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
pulling count=1
# exit: 0
```

#### 5b. per-platform manifest digest (PINS style)

```console
$ ocx --format json package install ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
# stdout
{
  "ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae": {
    "identifier": "ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
pulling count=1
# exit: 0
```

```console
$ ocx --format json package install -p linux/arm64 ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b
# stdout
{
  "ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b": {
    "identifier": "ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b
pulling count=1
# exit: 0
```

```console
$ ocx --format json package install -p linux/arm64 ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
# stdout
{
  "ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae": {
    "identifier": "ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae
pulling count=1
# exit: 0
```

```console
$ ocx --format json package install ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b
# stdout
{
  "ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b": {
    "identifier": "ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b
pulling count=1
# exit: 0
```

```console
$ ocx --format json package install ocx.sh/jqlang/jq@sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1
# stdout
{
  "ocx.sh/jqlang/jq@sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1": {
    "identifier": "ocx.sh/jqlang/jq@sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1
pulling count=1
# exit: 0
```

#### 5c. index-digest under --frozen on an empty OCX_HOME (host + foreign)

```console
$ ocx --frozen --format json package install -p linux/arm64 ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6": {
    "identifier": "ocx.sh/jqlang/jq@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b",
    "metadata": { … elided: identical to section 1 … },
    "path": null
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
pulling count=1
Downloading layer sha256:e0951c9ef030 to $OCX_HOME3/temp/bf81771813cd138d3063d59c256f5006
# exit: 0
```

```console
$ ocx --frozen --format json package install -p darwin/arm64 ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6": {
    "identifier": "ocx.sh/jqlang/jq@sha256:c5cf10597aacad9b7925f937c966ec72145ea6a40f7f7ef4cac11f90c43130b1",
    "metadata": { … elided: identical to section 1 … },
    "path": null
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
pulling count=1
Downloading layer sha256:8230875ada94 to $OCX_HOME3/temp/bfcbc1cfc266adb9dbae602e6d3afe62
# exit: 0
```

```console
$ ocx --frozen --format json package env -p windows/amd64 ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME3/packages/ocx.sh/sha256/ba/b93861d95a25d33163cc9499cb17bb/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq@sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# stderr
Package 'ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6' not found locally, pulling.
Downloading layer sha256:f4517d115132 to $OCX_HOME3/temp/5ed714dc9bfdefe6897b31b8addeb4bc
# exit: 0
```

```console
$ ocx --offline --format json package install -p windows/amd64 ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
{
  "ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6": {
    "identifier": "ocx.sh/jqlang/jq@sha256:bab93861d95a25d33163cc9499cb17bb109028d6537ca55b8427af21c1fdc989",
    "metadata": { … elided: identical to section 1 … },
    "path": null
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
pulling count=1
# exit: 0
```

```console
$ ocx --offline --format json package env -p windows/amd64 ocx.sh/jqlang/jq@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
# stdout
(stdout identical to the earlier block of this section)
# exit: 0
```


## 6. `-p` semantics

#### 6. -p semantics

```console
$ ocx --format json package env -p linux/amd64\,linux/arm64 ocx.sh/jqlang/jq:latest
# stderr
error: invalid value 'linux/amd64,linux/arm64' for '--platform <PLATFORM>': invalid platform 'linux/amd64,linux/arm64': unsupported architecture 'amd64,linux'. Possible values are: amd64, arm64, wasm

For more information, try '--help'.
# exit: 64
```

```console
$ ocx --format json package env -p linux/amd64 -p linux/arm64 ocx.sh/jqlang/jq:latest
# stderr
error: the argument '--platform <PLATFORM>' cannot be used multiple times

Usage: ocx package env [OPTIONS] <PACKAGE>...

For more information, try '--help'.
# exit: 64
```

```console
$ ocx --format json package env -p linux/amd64\;linux/arm64 ocx.sh/jqlang/jq:latest
# stderr
error: invalid value 'linux/amd64;linux/arm64' for '--platform <PLATFORM>': invalid platform 'linux/amd64;linux/arm64': unsupported architecture 'amd64;linux'. Possible values are: amd64, arm64, wasm

For more information, try '--help'.
# exit: 64
```

```console
$ ocx --format json package env -p linux/arm64+libc.glibc\,libc.musl ocx.sh/jqlang/jq:latest
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/81/b771e5c4e9b70cfeb19c825ca2b00a/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:81b771e5c4e9b70cfeb19c825ca2b00a5078c238e7d3175eee9d772cedda006b"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --format json package env -p linux ocx.sh/jqlang/jq:latest
# stderr
error: invalid value 'linux' for '--platform <PLATFORM>': invalid platform 'linux': expected format 'os/arch[/variant][+feature[,feature...]]' or 'any'

For more information, try '--help'.
# exit: 64
```

```console
$ ocx --format json package env -p linux/arm64/v8 ocx.sh/jqlang/jq:latest
# stdout
(stdout identical to the earlier block of this section)
# exit: 0
```

```console
$ ocx --format json package env -p any ocx.sh/jqlang/jq:latest
# stdout
{"schema_version":1,"command":"package env","exit_code":79,"error":{"kind":"not_found","message":"failed to find package: ocx.sh/jqlang/jq:latest — package not found","context":{}}}
# stderr
Package 'ocx.sh/jqlang/jq:latest' not found locally, pulling.
error: failed to find package: ocx.sh/jqlang/jq:latest — package not found
# exit: 79
```

```console
$ env OCX_PLATFORM=linux/arm64 ocx --format json package env ocx.sh/jqlang/jq:latest
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

#### 6b. OCX_PLATFORM is not a CLI variable; removed verbs

```console
$ env OCX_PLATFORM=linux/arm64 ocx package exec ocx.sh/jqlang/jq:latest -- sh -c uname\ -m\;\ command\ -v\ jq
# stdout
x86_64
$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content/jq
# exit: 0
```

```console
$ ocx package describe ocx.sh/jqlang/jq:latest
# stderr
warning: `ocx package describe` is renamed to `ocx package description push` and is removed in 0.7
error: nothing to update - provide at least one of --readme, --logo, --title, --description, or --keywords, or --from to copy a description from another repository
# exit: 1
```

```console
$ ocx package info ocx.sh/jqlang/jq:latest
# stdout
== ocx.sh/jqlang/jq:latest ==
Title:       jq
Description: Command-line JSON processor — slice, filter, map and transform structured data
Keywords:    jq,json,cli,query,filter,jqlang,data
# stderr
warning: `ocx package info` is renamed to `ocx package description pull` and is removed in 0.7
# exit: 0
```

```console
$ ocx --format json package run ocx.sh/jqlang/jq:latest -- jq --version
# stderr
error: unrecognized subcommand 'run'

  tip: a similar subcommand exists: 'prune'

Usage: ocx package <COMMAND>

For more information, try '--help'.
# exit: 64
```


## 7. Index snapshot

#### 7. index snapshot

```console
$ ocx --index $S/idx index update ocx.sh/jqlang/jq
# stderr
Refreshing tags for identifier 'ocx.sh/jqlang/jq'.
# exit: 0
```

```console
$ bash -c cd\ $S/idx\ \&\&\ find\ .\ -type\ f\ \|\ sort\ \|\ head\ -50\ \&\&\ du\ -sh\ .
# stdout
./ocx.sh/c/index.json
./ocx.sh/config.json
./ocx.sh/p/jqlang/jq.json
./ocx.sh/p/jqlang/jq/o/sha256/2695acb88fd1326f1d96fb89700d3e1e90fd8441d3f8024dae86791675a8046e.json
./ocx.sh/p/jqlang/jq/o/sha256/78f384a60a23514cf4e87f7cb2258cf9cc1a5da07933d2a0742efe616b791164.json
./ocx.sh/p/jqlang/jq/o/sha256/c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6.json
24K	.
# exit: 0
```

```console
$ ocx --index $S/idx index list ocx.sh/jqlang/jq
# stdout
Package           Tag           
ocx.sh/jqlang/jq  1             
ocx.sh/jqlang/jq  1.8           
ocx.sh/jqlang/jq  1.8.0         
ocx.sh/jqlang/jq  1.8.0_20260802
ocx.sh/jqlang/jq  1.8.1         
ocx.sh/jqlang/jq  1.8.1_20260802
ocx.sh/jqlang/jq  1.8.2         
ocx.sh/jqlang/jq  1.8.2_20260802
ocx.sh/jqlang/jq  latest        
# exit: 0
```

#### 7b. frozen without c/index.json

```console
$ ocx --index $S/idx2 --frozen --format json package env ocx.sh/jqlang/jq:latest
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --index $S/idx2 --frozen package exec ocx.sh/jqlang/jq:1.8.2 -- jq --version
# stdout
jq-1.8.2
# exit: 0
```

#### 7c. frozen: tag not in snapshot / no snapshot

```console
$ ocx --index $S/idx --frozen --format json package env ocx.sh/jqlang/jq:1.7.1
# stdout
{"schema_version":1,"command":"package env","exit_code":81,"error":{"kind":"permission_denied","message":"failed to find package: ocx.sh/jqlang/jq:1.7.1 — frozen mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:1.7.1'; run `ocx index update` or pin a digest","context":{}}}
# stderr
error: failed to find package: ocx.sh/jqlang/jq:1.7.1 — frozen mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:1.7.1'; run `ocx index update` or pin a digest
# exit: 81
```

```console
$ ocx --index $S/idx --frozen --format json package env ocx.sh/jqlang/jq:1.7.1
# stdout
{"schema_version":1,"command":"package env","exit_code":81,"error":{"kind":"permission_denied","message":"failed to find package: ocx.sh/jqlang/jq:1.7.1 — frozen mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:1.7.1'; run `ocx index update` or pin a digest","context":{}}}
# stderr
error: failed to find package: ocx.sh/jqlang/jq:1.7.1 — frozen mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:1.7.1'; run `ocx index update` or pin a digest
# exit: 81
```

```console
$ ocx --index $S/idx --frozen --format json package env ocx.sh/nope/nothing:1
# stdout
{"schema_version":1,"command":"package env","exit_code":81,"error":{"kind":"permission_denied","message":"failed to find package: ocx.sh/nope/nothing:1 — frozen mode refused to resolve unpinned reference 'ocx.sh/nope/nothing:1'; run `ocx index update` or pin a digest","context":{}}}
# stderr
error: failed to find package: ocx.sh/nope/nothing:1 — frozen mode refused to resolve unpinned reference 'ocx.sh/nope/nothing:1'; run `ocx index update` or pin a digest
# exit: 81
```

```console
$ ocx --index $S/idx --frozen --format json package env ocx.sh/shellcheck/shellcheck:latest
# stdout
{"schema_version":1,"command":"package env","exit_code":81,"error":{"kind":"permission_denied","message":"failed to find package: ocx.sh/shellcheck/shellcheck:latest — frozen mode refused to resolve unpinned reference 'ocx.sh/shellcheck/shellcheck:latest'; run `ocx index update` or pin a digest","context":{}}}
# stderr
error: failed to find package: ocx.sh/shellcheck/shellcheck:latest — frozen mode refused to resolve unpinned reference 'ocx.sh/shellcheck/shellcheck:latest'; run `ocx index update` or pin a digest
# exit: 81
```

```console
$ ocx --frozen --format json package install ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "identifier": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/latest"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:latest
pulling count=1
# exit: 0
```

```console
$ ocx --offline --format json package install ocx.sh/jqlang/jq:1.8.1
# stdout
{"schema_version":1,"command":"package install","exit_code":81,"error":{"kind":"permission_denied","message":"failed to install package: ocx.sh/jqlang/jq:1.8.1 — offline mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:1.8.1'; run `ocx index update` or pin a digest","context":{}}}
# stderr
Installing packages: ocx.sh/jqlang/jq:1.8.1
pulling count=1
error: failed to install package: ocx.sh/jqlang/jq:1.8.1 — offline mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:1.8.1'; run `ocx index update` or pin a digest
# exit: 81
```

#### 7d. sequence: install with --index and --frozen from empty OCX_HOME2 via snapshot

```console
$ ocx --index $S/idx2 --frozen --format json package install ocx.sh/jqlang/jq:1.8.2
# stdout
{
  "ocx.sh/jqlang/jq:1.8.2": {
    "identifier": "ocx.sh/jqlang/jq:1.8.2@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME_2/symlinks/ocx.sh/jqlang/jq/candidates/1.8.2"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:1.8.2
pulling count=1
Downloading layer sha256:88ad916b0507 to $OCX_HOME_2/temp/9c13e7a59201751a36e83176bff4a013
# exit: 0
```

#### 7e. .ocx/ directory shared between project toolchain render and a committed index snapshot

```console
$ ls $S/proj/.ocx
# stdout
toolchain
# exit: 0
```

```console
$ ocx --index $S/proj/.ocx --frozen --format json package env ocx.sh/jqlang/jq:latest
# stdout
{"schema_version":1,"command":"package env","exit_code":81,"error":{"kind":"permission_denied","message":"failed to find package: ocx.sh/jqlang/jq:latest — frozen mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:latest'; run `ocx index update` or pin a digest","context":{}}}
# stderr
error: failed to find package: ocx.sh/jqlang/jq:latest — frozen mode refused to resolve unpinned reference 'ocx.sh/jqlang/jq:latest'; run `ocx index update` or pin a digest
# exit: 81
```

```console
$ ocx --index $S/proj/.ocx --format json package env ocx.sh/jqlang/jq:latest
# stdout
{
  "entries": [
    {
      "key": "PATH",
      "value": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e/content",
      "type": "path"
    }
  ],
  "binaries": [
    {
      "name": "jq",
      "package": "ocx.sh/jqlang/jq:latest@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae"
    }
  ],
  "entrypoints": [],
  "integrations": [],
  "advisories": []
}
# exit: 0
```

```console
$ ocx --index $S/proj/.ocx --format json package install ocx.sh/jqlang/jq:1.8.1
# stdout
{
  "ocx.sh/jqlang/jq:1.8.1": {
    "identifier": "ocx.sh/jqlang/jq:1.8.1@sha256:0ed6b65c63ee44e0d7821ca5cf98eb3b4252011b289dec97bab410dec018df49",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/1.8.1"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:1.8.1
pulling count=1
Downloading layer sha256:50ae7e8ade06 to $OCX_HOME/temp/308c6e5bd07a111bf74bf5a79734a295
# exit: 0
```

```console
$ ls $S/proj/.ocx
# stdout
ocx.sh
toolchain
# exit: 0
```

#### 7f. index update under --frozen / OCX_FROZEN; empty OCX_INDEX; bare vs tagged update

```console
$ ocx --index $S/idx --frozen index update ocx.sh/jqlang/jq
# stderr
error: `ocx index update` discovers new digests and cannot run in frozen mode; re-run it without --frozen
# exit: 81
```

```console
$ env OCX_FROZEN=1 ocx --index $S/idx index update ocx.sh/jqlang/jq
# stderr
error: `ocx index update` discovers new digests and cannot run in frozen mode; re-run it without --frozen
# exit: 81
```

```console
$ env OCX_FROZEN=0 OCX_INDEX= ocx --format json package which ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "path": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e",
    "kind": "package"
  }
}
# exit: 0
```

```console
$ env OCX_INDEX= ocx --format json package install ocx.sh/jqlang/jq:1.8.2
# stdout
{
  "ocx.sh/jqlang/jq:1.8.2": {
    "identifier": "ocx.sh/jqlang/jq:1.8.2@sha256:913ff41f5e643a73c17a2e560e349d8eea255f50b293156e58da15b957baacae",
    "metadata": { … elided: identical to section 1 … },
    "path": "$OCX_HOME/symlinks/ocx.sh/jqlang/jq/candidates/1.8.2"
  }
}
# stderr
Installing packages: ocx.sh/jqlang/jq:1.8.2
pulling count=1
# exit: 0
```

```console
$ find $S/emptyidx -type f
# stdout
$S/emptyidx/ocx.sh/config.json
$S/emptyidx/ocx.sh/c/index.json
$S/emptyidx/ocx.sh/p/jqlang/jq.json
$S/emptyidx/ocx.sh/p/jqlang/jq/o/sha256/c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6.json
# exit: 0
```

```console
$ env OCX_INDEX=$S/idx2 OCX_FROZEN=1 ocx --format json package which ocx.sh/jqlang/jq:1.8.2
# stdout
{
  "ocx.sh/jqlang/jq:1.8.2": {
    "path": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e",
    "kind": "package"
  }
}
# exit: 0
```

```console
$ ocx --index $S/idx3 index update ocx.sh/jqlang/jq:1.8.1
# stderr
Refreshing tags for identifier 'ocx.sh/jqlang/jq:1.8.1'.
# exit: 0
```

```console
$ find $S/idx3 -type f
# stdout
$S/idx3/ocx.sh/config.json
$S/idx3/ocx.sh/c/index.json
$S/idx3/ocx.sh/p/jqlang/jq.json
$S/idx3/ocx.sh/p/jqlang/jq/o/sha256/2695acb88fd1326f1d96fb89700d3e1e90fd8441d3f8024dae86791675a8046e.json
# exit: 0
```


## 8. Verbs, version, self update

#### 8. version / about / self

```console
$ ocx version
# stdout
0.6.5
# exit: 0
```

```console
$ ocx --format json version
# stdout
{
  "version": "0.6.5",
  "commit": {
    "sha": "26ad03a17b34ed85b6d0dabc90a2eced7c403f7c",
    "short": "26ad03a1",
    "describe": "v0.6.5",
    "dirty": false,
    "timestamp": "2026-10-07T13:00:39.000000000Z"
  },
  "build": {
    "timestamp": "2026-10-07T13:04:40.684735276Z",
    "profile": "release",
    "target": "x86_64-unknown-linux-musl",
    "rustc": "1.95.0"
  },
  "ci": {
    "provider": "github-actions",
    "run_url": "https://github.com/ocx-sh/ocx/actions/runs/37625223215",
    "workflow": "Release",
    "ref": "refs/tags/v0.6.5",
    "sha": "26ad03a17b34ed85b6d0dabc90a2eced7c403f7c"
  }
}
# exit: 0
```

```console
$ ocx --format json about
# stdout
{
  "version": "0.6.5",
  "registry": "ocx.sh",
  "platforms": [
    "linux/amd64+libc.glibc"
  ],
  "features": [
    "libc.glibc"
  ],
  "libc": [
    "libc.glibc"
  ],
  "shell": "Bash",
  "home": "$OCX_HOME",
  "commit": {
    "sha": "26ad03a17b34ed85b6d0dabc90a2eced7c403f7c",
    "short": "26ad03a1",
    "describe": "v0.6.5",
    "dirty": false,
    "timestamp": "2026-10-07T13:00:39.000000000Z"
  },
  "build": {
    "timestamp": "2026-10-07T13:04:40.684735276Z",
    "profile": "release",
    "target": "x86_64-unknown-linux-musl",
    "rustc": "1.95.0"
  },
  "ci": {
    "provider": "github-actions",
    "run_url": "https://github.com/ocx-sh/ocx/actions/runs/37625223215",
    "workflow": "Release",
    "ref": "refs/tags/v0.6.5",
    "sha": "26ad03a17b34ed85b6d0dabc90a2eced7c403f7c"
  }
}
# exit: 0
```

```console
$ ocx self --help
# stdout
Manage the OCX installation itself (PATH activation, completions, self-update)

Usage: ocx self <COMMAND>

Commands:
  activate  Sourced from `$OCX_HOME/env.sh` at shell startup to activate ocx in the current shell. Prepends `$OCX_HOME/symlinks/.../bin` to `PATH`, injects completions (unless `OCX_NO_COMPLETIONS=1`), and evaluates the global toolchain env. Safe to re-source: the PATH updates are idempotent (move-to-front), so a re-source never duplicates an entry
  setup     Create or refresh ocx shell integration
  update    Update ocx itself to the latest released version. Without `--check`, downloads the newest release and activates it. With `--check`, reports the result without installing

Options:
  -h, --help  Print help
# exit: 0
```

```console
$ ocx self update --help
# stdout
Update ocx itself to the latest released version. Without `--check`, downloads the newest release and activates it. With `--check`, reports the result without installing.

Downloading and activating are two separate steps: the newest release is pulled first, then the new binary activates itself by running its own `ocx self setup`. If that inner setup cannot finish - for example a shell profile carries edits it refuses to overwrite - the download stands but nothing is activated: exit 75 reports this as pulled rather than installed, and running `ocx self setup` again finishes the job.

The latest version is looked up live from the published index rather than your local index, so the freshest release is always found; `--offline` skips the check. Both forms always bypass the auto-check throttle.

Usage: ocx self update [OPTIONS]

Options:
      --check
          Check for a newer ocx version without installing it.
          
          Behaviour:
          
          * Looks up the latest published version live rather than from your local index. Under `--offline` the check is skipped (exit 75). * Always bypasses the 24h auto-check throttle (explicit user intent). * Exit status: 0 if the lookup succeeded (whether or not a newer version was found); 75 (`EX_TEMPFAIL`) if the check was skipped. * Output: status, identifier (when an update is available), and structured skip reason. JSON shape: `{"status":"update_available","identifier":"ocx.sh/ocx/cli:1.2.3"}` or `{"status":"skipped","skipped_reason":{"reason":"offline"}}`.
          
          Pair with `--format json` for programmatic consumption.

  -h, --help
          Print help (see a summary with '-h')
# exit: 0
```


### Flag surface (option lines only)

#### A. flag surface (option lines only; full --help text omitted)

```console
$ bash -c OCXB=ocx\;\ \$OCXB\ pull\ --help\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'\ 
# stdout
      --dry-run
  -g, --group <GROUPS>
  -p, --platform <PLATFORM>
      --lazy-mode <MODE>
      --consent
      --no-consent
  -h, --help
# exit: 0
```

```console
$ bash -c OCXB=ocx\;\ \$OCXB\ env\ --help\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'\ 
# stdout
  -g, --group <GROUPS>
      --env <NAME|KEY[:TYPE[:SEP]]=VALUE>
      --shell[=<SHELL>]
      --ci[=<PROVIDER>]
      --export-file <PATH>
  -p, --platform <PLATFORM>
      --pull
      --no-pull
      --lazy-mode <MODE>
      --pinned
      --no-pinned
      --show-patches
  -h, --help
# exit: 0
```

```console
$ bash -c OCXB=ocx\;\ \$OCXB\ exec\ --help\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'\ 
# stdout
  -g, --group <GROUPS>
      --clean
      --env <NAME|KEY[:TYPE[:SEP]]=VALUE>
      --lazy-mode <MODE>
      --pinned
      --no-pinned
      --records-dir <DIRECTORY>
      --records-name <TEMPLATE>
      --consent
      --no-consent
  -h, --help
# exit: 0
```

```console
$ bash -c OCXB=ocx\;\ \$OCXB\ inspect\ --help\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'\ 
# stdout
  -g, --group <GROUPS>
  -p, --platform <PLATFORM>
      --env <NAME|KEY[:TYPE[:SEP]]=VALUE>
      --resolve
      --closure
  -h, --help
# exit: 0
```

```console
$ bash -c OCXB=ocx\;\ \$OCXB\ package\ exec\ --help\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'\ 
# stdout
      --clean
      --self
      --rm
      --env <NAME|KEY[:TYPE[:SEP]]=VALUE>
  -p, --platform <PLATFORM>
      --candidate
      --current
      --link <PATH>
      --lazy-mode <MODE>
      --records-dir <DIRECTORY>
      --records-name <TEMPLATE>
  -h, --help
# exit: 0
```

```console
$ bash -c OCXB=ocx\;\ \$OCXB\ package\ env\ --help\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'\ 
# stdout
      --self
      --env <NAME|KEY[:TYPE[:SEP]]=VALUE>
  -p, --platform <PLATFORM>
      --candidate
      --current
      --link <PATH>
      --lazy-mode <MODE>
      --shell[=<SHELL>]
      --ci[=<PROVIDER>]
      --export-file <PATH>
      --show-patches
  -h, --help
# exit: 0
```

```console
$ bash -c OCXB=ocx\;\ \$OCXB\ package\ which\ --help\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'\ 
# stdout
  -p, --platform <PLATFORM>
      --candidate
      --current
      --link <PATH>
      --lazy-mode <MODE>
  -h, --help
# exit: 0
```

```console
$ bash -c OCXB=ocx\;\ \$OCXB\ package\ install\ --help\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'\ 
# stdout
  -s, --select
      --link <PATH>
  -p, --platform <PLATFORM>
      --verify
      --no-verify
  -h, --help
# exit: 0
```

```console
$ bash -c OCXB=ocx\;\ \$OCXB\ lock\ --help\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'\ 
# stdout
      --check
      --pull
      --no-pull
  -p, --platform <PLATFORM>
  -h, --help
# exit: 0
```

```console
$ bash -c OCXB=ocx\;\ \$OCXB\ index\ update\ --help\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'\ 
# stdout
  -h, --help
# exit: 0
```

```console
$ bash -c ocx\ --help\ \|\ sed\ -n\ \'/\^Options:/\,\$p\'\ \|\ grep\ -E\ \'\^\ +\(-\[A-Za-z\]\,\ \)\?--\?\[a-z\]\'
# stdout
  -c, --config <FILE>
      --project <PATH>
  -g, --global
  -r, --remote
      --offline
      --frozen
      --format <FORMAT>
      --json
  -q, --quiet
      --jobs <N>
      --index <PATH>
  -l, --log-level <LOG_LEVEL>
      --color <WHEN>
  -h, --help
# exit: 0
```


### 8b. Bootstrap manifest and archives

Captured with `rtk proxy curl` (the interactive `curl` is rewritten by a token-saving hook); the archive hash
equals the `sha256` in the manifest row.

```console
$ curl -sSL https://setup.ocx.sh/dist.json | python3 -I -c '<summary>'
# schema: 1; latest: {"version": "0.6.5", "channel": "stable"}; latest_next: null; 280 rows
# versions (last 8): 0.5.7 0.5.8 0.6.0 0.6.1 0.6.2 0.6.3 0.6.4 0.6.5
# targets: aarch64-apple-darwin aarch64-pc-windows-msvc aarch64-unknown-linux-gnu aarch64-unknown-linux-musl
#          x86_64-apple-darwin x86_64-pc-windows-msvc x86_64-unknown-linux-gnu x86_64-unknown-linux-musl
# row keys: channel filename sha256 tag target url version   (identical to the embedded snapshot)
# 0.6.5 x86_64-unknown-linux-musl: ocx-x86_64-unknown-linux-musl.tar.gz bb4d306debca428fdc326ec587047c7efc3f3a2262b06eacfdaca46fa75a4dac
# 0.6.5 x86_64-pc-windows-msvc:    ocx-x86_64-pc-windows-msvc.zip       4cacead7e411929b0a3e655e150ca66323748674ba4d8546745e6638197d3e0a
$ tar tzvf ocx-x86_64-unknown-linux-musl.tar.gz
ocx-x86_64-unknown-linux-musl/
ocx-x86_64-unknown-linux-musl/README.md
ocx-x86_64-unknown-linux-musl/ocx
ocx-x86_64-unknown-linux-musl/LICENSE-THIRD-PARTY.md
ocx-x86_64-unknown-linux-musl/CHANGELOG.md
ocx-x86_64-unknown-linux-musl/LICENSE
$ unzip -l ocx-x86_64-pc-windows-msvc.zip   # (python zipfile listing)
CHANGELOG.md LICENSE LICENSE-THIRD-PARTY.md ocx.exe README.md
$ ocx-x86_64-unknown-linux-musl/ocx version
0.6.5
```

`ocx.cmake` `__ocx_select_release` and the `nested`/`flat` extraction probe already handle both layouts.

## 9. Config tiers

File locations (configuration.md lines 10–60):

| Tier | Linux | macOS | Windows |
|---|---|---|---|
| system | `/etc/ocx/config.toml` | `/etc/ocx/config.toml` | not in the table (docs only say `%SystemRoot%` etc. are refused as toolchain roots) |
| user | `$XDG_CONFIG_HOME/ocx/config.toml` or `~/.config/ocx/config.toml` | `~/Library/Application Support/ocx/config.toml` | not in the table |
| OCX home | `$OCX_HOME/config.toml` (default `~/.ocx/config.toml`) | same | same (leading `~` = `%USERPROFILE%`) |
| `[managed]` snapshot | local snapshot, identity gated | same | same |
| `OCX_CONFIG` / `--config` | explicit file, layered on top; **must exist** (79) | same | same |

Precedence low to high: defaults, system, user, `$OCX_HOME`, `[managed]`, `OCX_CONFIG`, `--config`, `OCX_*` env
(except the five ladder vars `OCX_TOOLCHAIN_ACTIVATE/PINNED/DIR`, `OCX_LAZY_MODE/REPORT`, which sit *under* the file
that states their key), CLI flags. `OCX_NO_CONFIG=1` skips the user and `$OCX_HOME` tiers plus `[managed]`; the locked sections of
`/etc/ocx/config.toml` still load, and explicit paths (`--config`, `OCX_CONFIG`) still load.

#### 9. config tiers

```console
$ cat $S/cfg/managed.toml
# stdout
[managed]
source = "ocx.sh/corp/config:1"
# exit: 0
```

```console
$ ocx --config $S/cfg/managed.toml --format json --project $S/proj/ocx.toml lock --check
# stderr
error: managed config snapshot required for source 'ocx.sh/corp/config:1' but absent; run `ocx config update`
# exit: 78
```

```console
$ ocx --config $S/cfg/managed.toml --format json package which ocx.sh/jqlang/jq:latest
# stderr
error: managed config snapshot required for source 'ocx.sh/corp/config:1' but absent; run `ocx config update`
# exit: 78
```

```console
$ env OCX_CONFIG=$S/cfg/managed.toml ocx --format json package which ocx.sh/jqlang/jq:latest
# stderr
error: managed config snapshot required for source 'ocx.sh/corp/config:1' but absent; run `ocx config update`
# exit: 78
```

```console
$ env OCX_NO_CONFIG=1 OCX_CONFIG=$S/cfg/managed.toml ocx --format json package which ocx.sh/jqlang/jq:latest
# stderr
error: managed config snapshot required for source 'ocx.sh/corp/config:1' but absent; run `ocx config update`
# exit: 78
```

```console
$ env OCX_CONFIG= ocx --format json package which ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "path": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e",
    "kind": "package"
  }
}
# exit: 0
```

```console
$ env OCX_CONFIG=$S/cfg/nope.toml ocx --format json package which ocx.sh/jqlang/jq:latest
# stderr
error: config file not found: $S/cfg/nope.toml (check --config or OCX_CONFIG)
# exit: 79
```

```console
$ env OCX_CONFIG=$S/cfg/bad.toml ocx --format json package which ocx.sh/jqlang/jq:latest
# stderr
error: invalid TOML at $S/cfg/bad.toml: TOML parse error at line 1, column 6  |1 | this is = = not toml  |      ^key with no value, expected `=`
# exit: 78
```

```console
$ env OCX_NO_CONFIG=1 ocx --format json package which ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "path": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e",
    "kind": "package"
  }
}
# exit: 0
```

```console
$ env OCX_NO_CONFIG=0 OCX_CONFIG=$S/cfg/managed.toml ocx --format json package which ocx.sh/jqlang/jq:latest
# stderr
error: managed config snapshot required for source 'ocx.sh/corp/config:1' but absent; run `ocx config update`
# exit: 78
```

#### 9b. managed block placed in $OCX_HOME/config.toml (discovered tier) without synced snapshot

```console
$ ocx --format json package which ocx.sh/jqlang/jq:latest
# stderr
error: managed config snapshot required for source 'ocx.sh/corp/config:1' but absent; run `ocx config update`
# exit: 78
```

```console
$ env OCX_NO_CONFIG=1 ocx --format json package which ocx.sh/jqlang/jq:latest
# stdout
{
  "ocx.sh/jqlang/jq:latest": {
    "path": "$OCX_HOME/packages/ocx.sh/sha256/91/3ff41f5e643a73c17a2e560e349d8e",
    "kind": "package"
  }
}
# exit: 0
```

```console
$ env OCX_NO_CONFIG_REFRESH=1 ocx --format json --project $S/proj/ocx.toml lock --check
# stderr
error: managed config snapshot required for source 'ocx.sh/corp/config:1' but absent; run `ocx config update`
# exit: 78
```

```console
$ ocx --format json --project $S/proj/ocx.toml lock --check
# stderr
error: managed config snapshot required for source 'ocx.sh/corp/config:1' but absent; run `ocx config update`
# exit: 78
```


Observed: a `[managed]` block with no synced snapshot fails **every** command with exit 78 and no JSON envelope
(`managed config snapshot required for source '…' but absent; run `ocx config update``), including when the block
sits in an explicit `--config`/`OCX_CONFIG` file even under `OCX_NO_CONFIG=1`; `OCX_NO_CONFIG=1` alone rescues the
discovered-tier case. `OCX_CONFIG=` (empty) disables an ambient value. `required = false` would degrade to a
warning (docs, not probed).

## A. Where `ocx.cmake` breaks on 0.6.5

Line numbers are `/home/mherwig/dev/find_ocx-ocx06/ocx.cmake` at `9ef970e`.

| # | Where | Break on 0.6.5 | Severity |
|---|---|---|---|
| A1 | L188 `__OCX_PIN_VERSION 0.3.11`; L191– snapshot (`latest` 0.4.2) | Bootstrap cannot produce 0.6.5; `OCX_INSTALL_VERSION=0.6.5` is a FATAL "not found in the dist manifest" until the snapshot is refreshed. | blocker for the bump |
| A2 | L980 `… --project "${toml}" run ${groups_args} --`; docs L156–161 | `ocx run` is deprecated: every execution of `OCX_<NAME>_RUN` prints the rename warning on stderr, and it is removed in 0.7. Must be `exec`. (`ocx exec` takes `-g` before `--`; group `all`/`default` are reserved names.) | high |
| A3 | L1064–1071 doc + parse, L1173–1174 `list(JOIN platform "," platform_csv)` → `-p a,b,c`, L1247; `OCX_DEFAULT_PLATFORM` list | Any list of 2+ entries exits 64 on `install`, `which`, `env`. Single entries work. | high (documented feature of [#2](https://github.com/ocx-sh/find_ocx/pull/2) is dead) |
| A4 | L1001–1021 `__ocx_find_index` (any `IS_DIRECTORY ".ocx"`) | After `ocx_project` runs `pull`, `<dir>/.ocx/toolchain` exists; a later `ocx_package` in the same tree adopts it as the index, runs `--index <dir>/.ocx --frozen` and fails 81 ("frozen mode refused to resolve unpinned reference"). A real snapshot and the toolchain dir can coexist (`.ocx/ocx.sh` + `.ocx/toolchain`), so detection must look for `<registry>/p/`. | high |
| A5 | L973 project foreign `env` (no `--pinned`) | PATH goes through `links/<group>/<entry>`, which hold the platform of whichever of `pull`/`exec`/`env` rendered last. The recorded `OCX_<NAME>_PATHS` (foreign) are link paths, so the first host `exec` (any `OCX_<NAME>_RUN` command in the build, or a second `ocx_project(NAME … )` on the same toml) re-points them and they silently resolve to **host** binaries. Pass `--pinned` (digest paths). | high (silent wrong binaries) |
| A6 | L409 `__ocx_env_prefix` pins only `OCX_PROJECT=` | Ambient `OCX_QUIET=1` → empty JSON stdout → `string(JSON … GET "" …)` at L650/L1209/L1222 errors; `OCX_GLOBAL=1` → exit 64 on every `--project` call; `OCX_LAZY_MODE=always` adds a shims PATH entry; no `OCX_NO_CONSENT` pin → consent stamps written for the user's source tree during configure; no `OCX_NO_PROJECT`/`OCX_NO_CONFIG_REFRESH` pin. | high |
| A7 | L443–462 `__ocx_run` retry loop (L446–447) | Retries on **any** non-zero rc (only `package install` passes `RETRIES 2`). 0.6.5 has a dedicated retry-safe code (75); retrying 65/78/79/81 is pointless, 69 is documented "rerun will not change that". | medium |
| A8 | L425–435 `__ocx_default_hint` | 69 hint "registry unreachable" is also what `ocx lock` returns for an unknown name; 78 hint "expected configuration missing - is ocx.toml/ocx.lock where find_ocx expects it?" is wrong for v2 lock (`regenerate with ocx lock`), `[managed]` snapshot (`run ocx config update`), bad TOML, `OCX_TOOLCHAIN_DIR`; no 75/79/81/80 defaults; call-site 78 hint at L958 ("no ocx.lock next to …") misdescribes v2 locks and managed config. | medium |
| A9 | L1405–1408 `ocx_index(UPDATE_COMMAND)` through the env prefix | A defined `OCX_FROZEN` (`-DOCX_FROZEN=ON` snapshot) is exported into the refresh command, which then exits 81 (`index update … cannot run in frozen mode`). It also passes a bare repo, so every tag is recorded, not just those used. | medium |
| A10 | L1201–1230 install/which parsing | Works. Note the install `identifier` for an `@<index digest>` ref is rewritten to the **leaf** manifest digest; the `@sha256:` check at L1211 stays true. `which` returns the package root (`…/packages/<reg>/sha256/xx/yyy`), not the candidate symlink. | ok |
| A11 | L1243 `RUN` for a package: `ocx [--index d --frozen] package exec <ref> --` | Still valid. The launcher exports `OCX_FROZEN=1`, `OCX_INDEX=<dir>` (and `OCX_OFFLINE` when set) into the child, plus `OCX_BINARY_PIN`, `OCX_RECORDS_NAME`; project `exec` exports `OCX_PROJECT=<toml>`. Docs L156–161 are right about FROZEN/INDEX, silent about PROJECT. | ok |
| A12 | L652–660 env entries | `type` is `path` or `constant`; unknown types fall to constant, fine. `entries` now sit next to `binaries`/`entrypoints`/`integrations`/`advisories` (ignored). | ok |
| A13 | Everything printing `ocx run` outside the module | `taskfile.yml` L12-13/32-36/60, `.github/workflows/{ci,pages,release}.yml`, `site/pages/**`, `site/src/content/docs/**`, a recorded cast (`site/public/casts/tutorial/first-configure.cast`). | docs/CI |
| A14 | L558–570 `ocx version` | Bare `0.6.5` on stdout, nothing on stderr. Fine. | ok |

## B. Contradictions with the plan's "Target public API" table

Plan: `/home/mherwig/dev/find_ocx-ocx06/.agents/plans/plan_ocx-0.6-family.md`.

| # | Plan says | Probe shows |
|---|---|---|
| B1 | Retry ×2 on **69**/74/75 for every network call | The CLI docs call 69 "answered but not usefully — a rerun will not change that" and reserve **75** for retry-safe failures. Observed 69 for a deterministic unknown name in `ocx lock`; retrying wastes two attempts. 74 is a local I/O error (permissions/disk), also not network-transient. Retry on 75 only. |
| B2 | "message taken from the `--format json` error envelope when present" | Stderr always carries the same message (`error: …`); envelope only exists with `--format json`, only on stdout, and not for usage/config errors. Take stderr; use the envelope solely for `error.kind` if wanted. Messages are chain-duplicated, de-duplicate by `: ` segment. |
| B3 | Pinned set `OCX_PROJECT= OCX_GLOBAL=0 OCX_QUIET=0 OCX_NO_PROJECT=1 OCX_NO_CONFIG_REFRESH=1 OCX_NO_CONSENT=1 OCX_TOOLCHAIN_DIR= OCX_SELF_UPDATE=` | All values accepted silently (`0`/`1`, empty `OCX_PROJECT`/`OCX_GLOBAL`/`OCX_QUIET`). `OCX_NO_PROJECT=1` does not break explicit `--project`. Gaps: `OCX_SELF_UPDATE=` (empty = unset) does not defeat a config-file `apply`, `manual` does (moot under `execute_process`: no TTY). `OCX_TOOLCHAIN_DIR=` cannot override `config.toml`'s `toolchain_dir` (config wins; only `OCX_NO_CONFIG=1` removes it). **Missing from the set:** `OCX_LAZY_MODE` (changes `env` output), `OCX_TOOLCHAIN_PINNED` (changes `env` paths). Prefer per-call flags `--lazy-mode never --pinned` on `env`/`pull`/`exec` over env pins for these two. `OCX_TOOLCHAIN_ACTIVATE=1` had no effect on `env` output. |
| B4 | `ocx_project(… PLATFORM …)` foreign path via `pull -p` + `env -p` | Needs `--pinned` on `env` (A5); `pull -p` + link-based `env -p` is platform-stateful (last renderer wins) and breaks as soon as a host `exec` runs. |
| B5 | `ocx_index(FIND)` keeps `.ocx/` discovery | Collides with `.ocx/toolchain` that `ocx_project` creates (A4); `OCX_TOOLCHAIN_DIR` cannot relocate it outside `$HOME`/`$OCX_HOME`. Discovery must require a registry directory with `p/` (or `config.json`) under `.ocx/`. |
| B6 | `BINS` validated via `inspect --closure` | Shape confirmed: `packages[].closure.surface.interface.{binaries[].name, entrypoints[].name, binaries_complete}`. Project tier: pass `-g <groups>` or only the default group is inspected (`GROUPS` must be forwarded; `all` allowed); names are binding names; `inspect --closure <name>` narrows. Cold cache with `--offline` → exit 79 (`package not found`): run it after `pull`, or tolerate 79 under offline. Foreign `PLATFORM` + `BINS` stays FATAL. |
| B7 | "`ocx_policy` … `OCX_NO_VERIFY OCX_ALLOW_YANKED`" explicit | `--no-verify` exists only on `package install`; `pull`, `lock`, `env`, `exec` have no verify/yank flags, so project tier can only express the policy through `OCX_NO_VERIFY`/`OCX_ALLOW_YANKED` env on that call. Both are listed in environment.md; their effect was not probed. |
| B8 | "Self-update: public `ocx_self_update`" | Unrelated to the CLI: `ocx self update` has only `--check` (exit 75 when skipped under `--offline`), no pinning. The find_ocx self-update stays a pure `file(DOWNLOAD)` of `ocx.cmake`. |
| B9 | "lock v3 regen" in S1 | The committed lock is already v3 and 0.6.5 regenerates it identically (hash, entries). Older v2 locks fail with exit 78 and `unsupported ocx.lock version 2; regenerate with `ocx lock``, so the 78 hint should say "regenerate". |
| B10 | "does an index digest pin all platforms?" | **Yes**, see section 5; docs advice may recommend `PACKAGE …@<index digest>` as the one-line multi-platform pin. `PINS` (per-platform manifest digests) remain valid and are not platform-checked by the CLI. |
| B11 | "index snapshot layout (`c/` not committed)" | Confirmed safe: frozen resolution works with `c/index.json` removed (section 7b). `config.json` and `p/` are what the leaf path `<registry>/p/<repo>.json` (ocx.cmake L1163) needs. |
| B12 | `ocx_package` "single `PLATFORM`" + `pull`/`env` | Confirmed `-p` single-valued. Note `package env -p <foreign>` auto-pulls the content when missing ("not found locally, pulling"), `package which -p` of a never-installed package is 79. |
| B13 | CLI verbs "zero `ocx run`, `package describe/info`" | Confirmed all three deprecated with removal in 0.7; `package run` already gone. `package describe` becomes `package description push`, `package info` becomes `package description pull`. |
