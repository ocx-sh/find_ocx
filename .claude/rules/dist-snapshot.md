# Embedded dist.json snapshot procedure

`ocx.cmake` embeds a snapshot of `https://setup.ocx.sh/dist.json` (the OCX
release manifest: rows of `{version, channel, tag, target, filename,
sha256, url}`) between the `BEGIN/END OCX DIST SNAPSHOT` markers.

- Bump: `task dist:update` runs `scripts/update_dist.py`, one lockstep
  command. It splices the snapshot, moves `__OCX_PIN_VERSION` to the latest
  stable, and repins every `ocx-sh/setup-ocx` `version:` in
  `.github/workflows/*.yml`. CI `update-dist.yml` opens a PR on a schedule
  that runs the same command.
- Guards, all before any write: rows are only added, a committed row is
  immutable, the pin moves forward only, `latest` must be `stable`, each
  `url` is exactly `<ocx release path>/<tag>/<filename>`, and the pinned
  version covers every target the outgoing pin covered (8 at least).
  `--version X.Y.Z` pins by hand and skips the forward and `latest` guards.
- `task dist:check` re-runs the row guards offline over the embedded
  snapshot and requires the CI pins to equal `__OCX_PIN_VERSION`.
  `task dist:test` runs the guards' unit tests (`scripts/update_dist_test.py`).
- Never edit the embedded JSON or a CI pin by hand; the sha256 values are
  the security boundary (mirrors can relocate artifacts, never alter them).
- Releases: tag `vX.Y.Z` must equal `__OCX_MODULE_VERSION` in `ocx.cmake`;
  the release workflow ships exactly `Findocx.cmake`, `ocx.cmake`, and
  `SHA256SUMS`.
