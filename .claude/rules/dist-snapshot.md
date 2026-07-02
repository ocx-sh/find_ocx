# Embedded dist.json snapshot procedure

`ocx.cmake` embeds a snapshot of `https://setup.ocx.sh/dist.json` (the OCX
release manifest: rows of `{version, channel, tag, target, filename,
sha256, url}`) between the `BEGIN/END OCX DIST SNAPSHOT` markers.

- Refresh: `task dist:update` (`scripts/update_dist.py` splices + sanity
  checks). CI `update-dist.yml` opens a PR on a schedule.
- **Always bump `__OCX_PIN_VERSION` together with the snapshot** — the
  pinned version must exist in the snapshot for all 8 targets
  (`task dist:check` verifies). The refresh automation never bumps the pin.
- Never edit the embedded JSON by hand; the sha256 values are the security
  boundary (mirrors can relocate artifacts, never alter them).
- Releases: tag `vX.Y.Z` must equal `__OCX_MODULE_VERSION` in `ocx.cmake`;
  the release workflow ships exactly `Findocx.cmake`, `ocx.cmake`, and
  `SHA256SUMS`.
