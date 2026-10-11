# Cast pipeline for the docs site (S2 spike)

Status: proven end to end on 2026-10-10 with ocx 0.6.5, asciinema 3.2.1, `@ocx-sh/theme` 0.1.1 (asciinema-player 3.15.1).
Recorded a real `cmake -S . -B build` and `cmake --build build` of a tiny `include(ocx)` project, played it back in headless Chromium through the theme's `<Terminal>` (duration 0:05, no console errors).

## Files written

| File | Role |
|---|---|
| `site/casts/tutorial__first-configure.sh` | Example cast script. Doubles as the ctest. |
| `site/scripts/run-cast-script.sh` | The one environment contract. ctest runs scripts through it, the recorder runs its generated driver through it. |
| `site/scripts/record-casts.mjs` | Recorder: parse headers, build driver, `asciinema rec --headless`, sanitize, write `site/public/casts/<doc>.cast`. |
| `site/scripts/record-casts.test.mjs` | 3 unit tests (parse, driver, sanitize). Added to `pnpm run test`. |
| `ocx.toml`, `ocx.lock` | `asciinema = "ocx.sh/asciinema/asciinema:3.2"` added, `ocx lock` run (additive diff only). |
| `.gitignore` | `site/public/casts/` (DOC-EX-13). |
| `site/package.json` | `test` script lists the new test file. |

## What is proven

- **Headless works.** `asciinema rec --headless --overwrite --return --quiet --window-size 100x40 --command <cmd> out.cast` runs with stdin `/dev/null` and no controlling TTY (this agent's shell has none). asciinema allocates its own PTY, so cmake and ocx see a TTY and colour on. `--return` propagates the command's exit code (checked: exit 3 gives rc 3), so a failing script fails the recording.
- **Via ocx.** `ocx package exec ocx.sh/asciinema/asciinema:3.2 -- asciinema ...` works; with the `ocx.toml` entry it is `ocx exec -- asciinema ...`. The package has no Windows platform (darwin amd64/arm64, linux amd64/arm64 only), so recording is Linux/macOS; Windows skips casts.
- **Format.** asciinema 3 writes asciicast v3 (relative timestamps, header `term.{cols,rows}`, `idle_time_limit`). The pinned player has `parseAsciicastV3` and played it (DOC-EX-14). No `--output-format` needed.
- **Embedding.** `import Terminal from '@ocx-sh/theme/components/Terminal.astro'` works in `.mdx`. A `.md` page prints the import as text and renders no player. Under `base: '/integrations/cmake/'` the component prefixes the base itself (`withBase`): `src="/casts/tutorial/first-configure.cast"` becomes `data-src="/integrations/cmake/casts/tutorial/first-configure.cast"` and the file is served from `site/public/casts/tutorial/first-configure.cast`. Starlight bundles `@astrojs/mdx`, so no new dependency. `ocx-site check` and `check-anchors.mjs` stay green with a Terminal in the page.
- **Terminal props** (`Terminal.astro`): `src` (required, base-relative), `title`, `cols`, `rows`, `autoPlay` (default false, DOC-EX-15), `speed`, `idleTimeLimit` (2), `loop`, `fit` ('width'), `collapsed`. Omit `cols`/`rows`: the player then uses the cast header size, which the recorder sets to the used rows. Passing a smaller `rows` crops the cast (seen with `rows={12}` on a 30-row cast).
- **ocx exemplar differs.** ocx synthesizes its own v2 casts with pexpect (`test/recordings/cast_recorder.py`). Here asciinema records the real session; only the typed command line is simulated by the driver.

## How a script runs

Header keys (ocx style): `# cast: true`, `# doc: <key>`, `# title:`, `# description:`, `# expect_exit:`. File name is `<doc with / as __>.sh`. Three zones:

1. Everything outside `# region cast` (setup, verification) runs silently in the recording and for real in the test.
2. `# region cast ... # endregion cast` is what the page shows. Blank lines split it into commands; each is typed at 40 ms per character, run with `eval` in the same shell, then 1 s pause.
3. Driver = `exec >/dev/null` around pre and post, so setup output never reaches the cast.

Environment contract (`run-cast-script.sh`, `env -i` plus a short allow-list): cwd is an empty directory; `HOME` and `OCX_HOME` are throwaway (a recording always starts cold; `CAST_OCX_HOME` reuses a warm one for ctest); `FIND_OCX_ROOT` is the repo; `PATH`, proxy and `SSL_CERT_FILE` variables pass through; `TERM=xterm-256color`, `LANG=C.UTF-8`. PATH must hold `cmake`, `ocx`, `ninja` (`ocx exec --` provides all three).

Sanitizer (`sanitize()` in `record-casts.mjs`): merge events less than 10 ms apart so a path or digest is never split (typing events are 40 ms and survive); rewrite `<tmp>/work` to `~/hello-jq`, `<tmp>/home/.ocx` to `~/.ocx`, the real home to `~`; `sha256:<64 hex>` to first 12 hex; `(0.0123s)` to `(0.1s)`; stray `/tmp/...` to `/tmp/build`; header keeps only `version, term, idle_time_limit, title` (drops timestamp, command, `SHELL`); first event delay capped at 0.3 s (silent setup ran before it); rows set to wrapped output lines + 1. Idle compression is `idle_time_limit: 2` in the header, which the player honours (and `Terminal` passes `idleTimeLimit=2`).

## Real output and failures seen

- With `ocx` on PATH the module uses it (`find_ocx: using ocx from PATH`), so the cast never shows the bootstrap download. The tutorial text says the first configure downloads the pinned `ocx`. D2 must pick: reword the tutorial, or run setup with `ocx` by absolute path and drop it from PATH for the cast region.
- Module still emits `warning: \`ocx run\` is renamed to \`ocx exec\` and is removed in 0.7` at build time (stale ocx 0.3.11-era verb). It is in the recording today and disappears when I1/I2 land. Re-record after P2.
- With `ocx` off PATH the module bootstraps the pinned 0.3.11, which fails on a 0.6.5-written project (`[group.lint.tools]` "invalid type: map, expected a string", then "no ocx.lock"). Confirms the pin bump is needed before any bootstrap cast.
- `ocx lock` prints `warning: add ocx.lock merge=union to .gitattributes` (silent in the cast, it is in setup).
- `astro build` warns `[MODULE_LEVEL_DIRECTIVE] use astro:head-inject` for an `.mdx` page. Build still completes. Not investigated further.

## Wiring into the build (proposed, not applied)

`taskfile.yml`:

```yaml
  site:casts:
    desc: Record the docs terminal casts from site/casts/*.sh (real runs, sanitized, gitignored)
    dir: site
    cmds:
      - ocx exec -- node scripts/record-casts.mjs

  site:build:
    deps: [site:install, site:casts]   # was [site:install]; casts only need ocx exec, not node_modules
  site:dev:
    deps: [site:install, site:casts]
```

`site.yml` and `deploy.yml` both run `ocx exec -- task site:check`, whose dep chain reaches `site:build`, so recording happens in both with no workflow edit. Needs: network to ocx.sh (jq, lock), the `ocx` on PATH from `setup-ocx` (already there), cmake/ninja/asciinema from `ocx exec`. No new action, secret or permission. Failure policy: a failed recording fails the site build (the ctest is the correctness gate; a broken cast on a daily deploy is a visible, wanted failure). `site:lighthouse` also depends on `site:build`, so the lighthouse job records a second time (about 10 s); acceptable. The workflows' `paths:` already include `site/**`, `ocx.cmake`, `ocx.toml`, `ocx.lock`.

`astro.config.mjs` (verified: removes the "language could not be found" warning and highlights as bash):

```js
starlight({ /* ... */ expressiveCode: { shiki: { langAlias: { 'bash-run': 'bash', 'cmake-run': 'cmake' } } } })
```

`port-docs.mjs` changes (D1):

1. New directive `<!-- cast: tutorial/first-configure -->` in `site/pages/*.md`. It expands to the binding comment, a `bash-run` fence holding the script's `region cast` body, and the `<Terminal src="/casts/<key>.cast" title="<# title>" collapsed />`. The source page stays `.md` (the docs checks read it); the cast script is the single source of the displayed commands.
2. A page that used the directive is written as `.mdx`: add `import Terminal from '@ocx-sh/theme/components/Terminal.astro';` after the front matter and rewrite `<!-- doc_type: x -->` / `<!-- doc: key -->` comments to `{/* ... */}` (HTML comments are a syntax error in MDX; verified by converting `tutorial.md` by hand, build and `pnpm run check` pass). Every other page stays `.md`: reference pages carry `${VAR}` and `<name>` text that MDX would reject.
3. Fail the port when a directive names a key with no script, or a script with `cast: true` is cited by no page (the DOC-EX-02 set-diff, early).
4. `rewriteLinks`, `frontMatter` and `checkCoverage` need no change; only the `dest` extension and the `walk(...).filter('.md')` output name.

## Cast script as ctest (binding contract from `docs-quality/examples.md`)

Contract per rule:

- DOC-EX-01/02: each cast script declares `# doc: <key>` in its first 10 lines; the page cites the same key as `<!-- doc: <key> -->` on the line directly above a `bash-run` fence (`doc_examples.py` reads the key from the fence body's first 3 lines or the previous line). `doc_examples.py --root site/pages --tests site/casts` must report no key on one side only.
- DOC-EX-04: one file runs every script as a subprocess. Ours is `run-cast-script.sh` via ctest, not `doc_examples.py --harness`, because the generic harness runs bare `bash file` in the caller's cwd and the scripts need `FIND_OCX_ROOT` and an empty cwd.
- DOC-EX-07: ctest name is `doc/<key>`, so a failure names the page key (`doc/tutorial/first-configure`).
- DOC-EX-11: the recorder is not in ctest; the suite passes with asciinema absent.
- DOC-EX-12: every recorded byte except the typed command line is real output. No mockup mode exists.
- DOC-EX-13: casts are gitignored and regenerated by `site:casts`; nothing under `site/public/casts` is tracked.
- DOC-EX-14: cast v3 written, player 3.15.1 pinned by the theme, `parseAsciicastV3` present, playback verified.
- DOC-EX-15/16/17: `autoPlay` defaults false in `Terminal.astro`; it ships its own labelled controls; it checks `prefers-reduced-motion` (`reducedMotion()` in `terminal.mjs`). Pages must not pass `autoPlay`.
- DOC-EX-08: sanitizing changes paths, digests and timings, so a page must not say the output is identical to what the reader sees. Say "similar to".
- DOC-EX-18: no `.tape` files.

Root `CMakeLists.txt` snippet (I4 owns the file; verified in a scratch project, 1/1 passed in 1.35 s):

```cmake
if(NOT WIN32)  # bash, asciinema and the casts are POSIX only
  file(GLOB casts CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/site/casts/*.sh")
  foreach(script IN LISTS casts)
    file(STRINGS "${script}" doc_line LIMIT_COUNT 1 REGEX "^# doc: ")
    string(REGEX REPLACE "^# doc: " "" doc "${doc_line}")
    add_test(NAME "doc/${doc}"
      COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/site/scripts/run-cast-script.sh" "${script}")
    set_tests_properties("doc/${doc}" PROPERTIES LABELS docs TIMEOUT 300)
  endforeach()
endif()
```

The test inherits `PATH`, so `task test` must run under `ocx exec --` (it does) to have cmake, ocx and ninja. Scripts must stay idempotent in an empty cwd and must not read anything outside `$FIND_OCX_ROOT`.

## Open items for D2 / owner

- Tutorial project duplication: the setup heredocs repeat what the tutorial page shows. Better: add `examples/tutorial/` (tested by `test:examples`), have the page include snippets from it, and have the cast script `cp -r` it. One source for page, ctest and cast.
- Decide the PATH-ocx question above before writing the tutorial's configure paragraph.
- Re-record after P2 lands (the `ocx run` warning, the bootstrap line text).
- `ocx-site check` was not shown to verify that a `Terminal` `src` exists in `dist`; add a check in `check-anchors.mjs` (every `data-src` under the base resolves to a file in `dist`).
