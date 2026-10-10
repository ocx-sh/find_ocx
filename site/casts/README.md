# Cast scripts

Each `*.sh` here is one docs terminal cast and, through `tests/casts.cmake`, the ctest `doc/<key>`.
Pages embed a cast with `<!-- cast: <key> -->`; `site/scripts/record-casts.mjs` records it at build.

- The `cast` region is what the page shows and the recording types. `setup` and the verification
  after it run silently.
- Project files live in `fixtures/<script>/` and are copied into the empty work directory, so pages
  can show them with `<!-- snippet: site/casts/fixtures/<script>/CMakeLists.txt -->`.
- Headers (`# cast`, `# doc`, `# title`, `# description`, optional `# dir`) come first, then a blank line.

Run one script: `ocx exec -- site/scripts/run-cast-script.sh site/casts/<script>.sh`.
The wrapper gives the script an empty cwd, a fresh `HOME` and `OCX_HOME`, `FIND_OCX_ROOT` and a
`PATH` with cmake and ninja but never ocx (a host ocx would short-circuit the bootstrap; it stays
reachable as `$CAST_OCX`). Environment knobs:

- `CAST_TMP=<dir>`: use and keep this directory instead of a throwaway one.
- `CAST_OCX_HOME=<dir>`: reuse a warm `OCX_HOME` for faster ctest runs; a recording always starts cold.
- `CAST_OCX_EXECUTABLE=<path>`: run the module through this ocx (becomes `OCX_EXECUTABLE`) instead of
  the pinned bootstrap, for proving a script while the pin lags the CLI.

Record all casts with `task site:casts`; it needs asciinema (`ocx.toml`), cmake, ninja and network.
