# Mirror downloads assume anonymous read

`OCX_INSTALL_DIST_URL` / `OCX_INSTALL_MIRROR_URL` let a corporate operator
point `ocx.cmake` at an internal mirror (Artifactory generic repo, static
host). Today that mirror **must allow anonymous read** — `file(DOWNLOAD)` is
called with no credentials.

- Document the constraint; a mirror locked down later breaks this path
  silently, and the failure looks like a network error.
- Future support (not now): CMake `file(DOWNLOAD)` already offers
  `HTTPHEADER "Authorization: Bearer …"` and `NETRC <level>` / `NETRC_FILE`.
  Either is a small change — no new fetch machinery needed.
- Same gap exists in `rules_ocx` (`ctx.download`) and in the five installers
  in `www-setup`. Keep the knob naming aligned across all three if it lands.
- The sha256 in the snapshot stays the security boundary either way — auth
  controls access, never trust.
