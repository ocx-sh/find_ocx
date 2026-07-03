# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

#[=[.rst:
ocx
---

CMake support for `OCX <https://ocx.sh>`_ — the OCI-backed package manager.
Bootstraps the pinned ``ocx`` CLI (sha256-enforced, corporate-mirror aware)
and provisions tools through it. find_ocx deliberately never re-implements
OCX internals in CMake: all resolution goes through the ``ocx`` binary; the
durable contracts are ``ocx.lock`` digests and the OCI manifests.

Vendor this file together with ``Findocx.cmake`` into your project (e.g.
``cmake/``), then::

  list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
  include(ocx)

  ocx_project()                    # toolchain from ./ocx.toml + ./ocx.lock
  ocx_package(NAME jq PACKAGE ocx.sh/jq:latest)   # frozen via ./.ocx snapshot

Requires CMake 3.19 (``string(JSON)``, ``file(ARCHIVE_EXTRACT)``).
Include after ``project()``.

Resolution is reproducible-first: a floating tag resolves through a
committed index snapshot (the nearest ``.ocx/`` directory, discovered
like ``ocx.toml``; create it with ``ocx --index .ocx index update
<package>``) or through digest pins — with neither, the configure fails
(:variable:`OCX_ALLOW_FLOATING` is the explicit escape hatch).

``include(ocx)`` itself is passive — it only defines commands and snapshots
the ``OCX_*`` knobs. The first provisioning call (:command:`ocx_project`,
:command:`ocx_package`, or an explicit :command:`ocx_bootstrap`) resolves
the CLI: ``OCX_EXECUTABLE`` when set, else an ``ocx`` on ``PATH``, else it
downloads the pinned, sha256-verified CLI into the per-machine cache.
``OCX_BOOTSTRAP=ALWAYS`` skips the ``PATH`` search (hermeticity: every
machine runs the identical pinned binary); ``OCX_BOOTSTRAP=OFF`` forbids
the implicit download entirely. An explicit :command:`ocx_bootstrap` call
always provisions the pin.

Corporate mirrors and behavior knobs are plain ``OCX_*`` variables. Each one
follows the snapshot pattern: if the CMake variable is unset but the
environment variable is set at the *first* configure, the value is
snapshotted into the cache and stays sticky for the build directory
(override with ``-DVAR=...``, clear with ``-DVAR=``).

.. variable:: OCX_EXECUTABLE

  Path to the ocx CLI to run everything through. Snapshotted from the
  environment like every other knob (CI: ``export OCX_EXECUTABLE=$(which
  ocx)`` needs no ``-D``); when unset, the first provisioning call
  bootstraps the pin.

.. variable:: OCX_INSTALL_DIST_URL

  Fetch the ocx release manifest (dist.json) from a mirror instead of the
  snapshot embedded in this file.

.. variable:: OCX_INSTALL_MIRROR_URL

  Rewrite the ocx binary download to ``<mirror>/<tag>/<filename>``. The
  manifest sha256 is still enforced — a mirror can move bytes, not change
  them.

.. variable:: OCX_INSTALL_VERSION

  ocx CLI version to bootstrap (default: the version pinned with this
  find_ocx release). Same knob as the setup.ocx.sh installer.

.. variable:: OCX_BOOTSTRAP

  Implicit-bootstrap policy for the first provisioning call when
  ``OCX_EXECUTABLE`` is not set. Unset or ``ON`` (default): use an ``ocx``
  found on ``PATH``, bootstrap the pinned CLI when there is none.
  ``ALWAYS``: skip the ``PATH`` search — every machine runs the identical
  pinned binary (hermetic mode; pair with ``OCX_INSTALL_VERSION``).
  ``OFF``: never download — ``OCX_EXECUTABLE`` or a ``PATH`` ocx is
  required, anything else is a hard configure error (for environments
  that forbid configure-time downloads). Inside ``Findocx.cmake`` the
  same variable is the opt-*in* for the bootstrap fallback (find modules
  discover by default).

.. variable:: OCX_DEFAULT_PLATFORM

  Default ``PLATFORM`` for :command:`ocx_project` / :command:`ocx_package`
  (empty = host).

.. variable:: OCX_INDEX

  Committed index snapshot directory freezing tag resolution for every
  :command:`ocx_package` without an explicit ``INDEX``. When unset, each
  call discovers the nearest ``.ocx/`` directory between its calling
  directory and the last ``project()`` source dir instead
  (:command:`ocx_index` ``FIND`` runs that discovery once and locks the
  result into this variable). Clearing with ``-DOCX_INDEX=`` neutralizes
  a value inherited from an outer ocx launcher without vetoing the
  project's own committed snapshot.

.. variable:: OCX_ALLOW_FLOATING

  Reproducibility escape hatch. By default a floating tag with no index
  snapshot in effect and no digest pin is a hard configure error — ocx is
  reproducible-first. ``ON`` downgrades that to the pre-0.3 behavior
  (live resolution, drift warning); useful transiently to print the
  digests that seed ``PINS``.

.. variable:: OCX_BOOTSTRAP_CACHE

  Cache directory for bootstrapped ocx binaries. Default: per-machine —
  ``%LOCALAPPDATA%/find_ocx`` (Windows), ``$XDG_CACHE_HOME/find_ocx``,
  ``~/.cache/find_ocx``, falling back to ``<build>/_ocx/cache`` when no
  home directory exists. Point it into the workspace on CI runners where
  the home directory is unreliable (and restore it with your CI cache).

.. variable:: OCX_PROJECT_FILE

  Default ocx.toml for :command:`ocx_project` when no ``TOML`` argument is
  given.

.. variable:: OCX_PULL

  Force eager materialization (``PULL``) for every ocx_project/ocx_package
  call — useful in CI to fail fast and warm caches.

.. variable:: OCX_REFRESH

  One-shot: bypass the reconfigure memoization and re-execute ocx.

.. variable:: OCX_SELF_UPDATE_VERSION

  find_ocx release tag to self-update the vendored ``ocx.cmake`` and
  ``Findocx.cmake`` to (``vX.Y.Z``; the ``v`` is optional). Default: the
  latest release, discovered via the GitHub releases API. Script mode
  only::

    cmake [-DOCX_SELF_UPDATE_VERSION=v0.3.0] -P cmake/ocx.cmake

  replaces this file (and a sibling ``Findocx.cmake`` when present) in
  place, verified against the release ``SHA256SUMS``.

.. variable:: OCX_SELF_UPDATE_URL

  Fetch the find_ocx release files from ``<url>/<tag>/<filename>`` instead
  of GitHub — same rewrite shape as ``OCX_INSTALL_MIRROR_URL``. Requires an
  explicit ``OCX_SELF_UPDATE_VERSION`` (mirrors do not serve the releases
  API); the mirrored ``SHA256SUMS`` stays the trust root.

Passthrough variables forwarded to every ocx invocation when set (same set
as rules_ocx): ``OCX_HOME``, ``OCX_MIRRORS``, ``OCX_INSECURE_REGISTRIES``,
``OCX_OFFLINE``, ``OCX_FROZEN``, ``OCX_REMOTE``, ``OCX_JOBS``,
``OCX_INDEX``, ``OCX_DEFAULT_REGISTRY``. Clearing a knob with ``-DVAR=``
actively removes it from the environment of every ocx invocation. That is
the opt-out for launcher inheritance: ocx launchers (``ocx run``, frozen
``package exec`` — including the ``OCX_<NAME>_RUN`` command lists this
module exports) export ``OCX_FROZEN`` and ``OCX_INDEX`` into child
processes, so a find_ocx configure nested inside one (ExternalProject,
test harnesses) inherits the outer resolution mode unless it is given
``-DOCX_FROZEN=`` ``-DOCX_INDEX=``.

``OCX_AUTH_<REGISTRY>_{TYPE,USER,TOKEN}`` credentials are deliberately
**never** snapshotted into the cache — export them in the environment and
reconfigure after changing them.
#]=]

if(CMAKE_VERSION VERSION_LESS 3.19)
  message(FATAL_ERROR
    "find_ocx: ocx.cmake requires CMake >= 3.19 "
    "(string(JSON), file(ARCHIVE_EXTRACT)); this is CMake ${CMAKE_VERSION}")
endif()

include_guard(GLOBAL)

# Function definitions capture the policy settings of their definition
# point: pin them to this module's baseline so includers that never ran
# cmake_minimum_required (script mode, exotic embeddings) get identical
# behavior. Balanced by cmake_policy(POP) at the end of this file.
cmake_policy(PUSH)
cmake_policy(VERSION 3.19)

set(__OCX_MODULE_VERSION "0.3.0")

# The ocx CLI declares no stability for its command-line surface across
# versions; find_ocx therefore pins an exact version and is tested against
# exactly that version. Bump deliberately, together with the dist snapshot.
set(__OCX_PIN_VERSION "0.3.11")

# --- BEGIN OCX DIST SNAPSHOT (generated by scripts/update_dist.py - do not edit) ---
set(__OCX_DIST_JSON [=[
{
  "schema": 1,
  "latest": {"version":"0.3.11","channel":"stable"},
  "latest_next": null,
  "releases": [
    {"version":"0.3.11","channel":"stable","tag":"v0.3.11","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"1fddca752b79fabaebe196d72caf593d727af08c41a8dc0f3fcfe93346346513","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.11","channel":"stable","tag":"v0.3.11","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"d1f5ae414d0d88f069f4a0941c51ddc76df72421f87d92fea61a74485c669bdb","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.11","channel":"stable","tag":"v0.3.11","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"2b48c596597fba88e2ec878339cd9caa1dda9893d7af96fd9ab8bcf4306162e3","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.11","channel":"stable","tag":"v0.3.11","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"8f91d9109b823365b395acba69a7a57905ebd23c0e9259ae16e7bb56c8397dfb","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.11","channel":"stable","tag":"v0.3.11","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"77fda50fb6e7dc3492f766a90b8cb40670f9943d7b51ce87e99a4e26ba422480","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.11","channel":"stable","tag":"v0.3.11","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"3c59f0f34d43f0c51f420bb59b5be2d4e836183b549635e44b812057a433f1c5","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.11","channel":"stable","tag":"v0.3.11","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"44fc65490cf3a9dbdb9a364b4f67e30c6d31363a5927de351a465856b6ebd0b7","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.11","channel":"stable","tag":"v0.3.11","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"29cff0027a070f3bf85ef9e7616ada5e54e9fc3471988513eb9087c80f79d278","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.11/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.10","channel":"stable","tag":"v0.3.10","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"ed0c29a6cfc92db7eb1d8dca9aa7377ccbd7f1b098ab8c5733a65f580e8346e0","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.10/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.10","channel":"stable","tag":"v0.3.10","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"c5c0abd5a5bc50059238caa352445412c7df03d83afe2319b1686cb3ddaf8981","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.10/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.10","channel":"stable","tag":"v0.3.10","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"030d615ae918725f600e151846de319548a0c85bfa1dfd767e4b815843c947b5","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.10/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.10","channel":"stable","tag":"v0.3.10","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"82333027ba2a4369aca2f301e600f7bd5fd92eb9d77d498c6b6df6868228b65f","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.10/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.10","channel":"stable","tag":"v0.3.10","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"4923c61cebf37ffb3d776c84644c5fc1d452393f71b2ee96cb330f31dcdffdb0","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.10/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.10","channel":"stable","tag":"v0.3.10","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"78fb2191c13cca244108c83f19b589fbe089efe67d8b266396718b95ef036429","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.10/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.10","channel":"stable","tag":"v0.3.10","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"11256eed773fa6bad998662b86279da3093c583ece11b7de8b11a7c43d8ecc69","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.10/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.10","channel":"stable","tag":"v0.3.10","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"8303516985f0f98fce04379a29ee5876a08f8a700adc7c82ccc5c9ac5fa0e002","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.10/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.9","channel":"stable","tag":"v0.3.9","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"fd926d5f24fea3772faf399f2a15f6038288755533db15a63cc264c04ec404a0","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.9/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.9","channel":"stable","tag":"v0.3.9","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"38da7da497f77aaf4402475b717b0663361d25516cf56794a06e76899a185b98","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.9/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.9","channel":"stable","tag":"v0.3.9","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"858395f10a5a4771d2957460834c8a19a8e2d2350ba8803a6d86de35026f9825","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.9/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.9","channel":"stable","tag":"v0.3.9","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"f8dbaf16f55f333a7ac9844b71321573a1b3d9060183c7d3c9a7e36fcc31852e","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.9/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.9","channel":"stable","tag":"v0.3.9","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"57bcce8e22037144874db3101677de87cb3362dc8232292c41904a621a475a27","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.9/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.9","channel":"stable","tag":"v0.3.9","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"e76600633e1d36512bc39eb5ac99e69c14a3fdf52320efc4c73b8e514850b2e4","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.9/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.9","channel":"stable","tag":"v0.3.9","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"525ab935d3d4accaeca9e7b415fa0ea42923e01a20aeea8a6f440a1cba56ab4c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.9/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.9","channel":"stable","tag":"v0.3.9","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"03dad2be00ba9ba873449c756cb44a62497fc1902a9ce5c1c5bb9209adb97f90","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.9/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.8","channel":"stable","tag":"v0.3.8","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"82ebf459841486f95858198104ee3e165be853a589e8681343c9b14ec8fdd6bb","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.8/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.8","channel":"stable","tag":"v0.3.8","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"8091a05024aeea6a99beee9a8253cf007888477ff12094ded2ee3900eaac3ff2","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.8/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.8","channel":"stable","tag":"v0.3.8","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"68ba62c18dcfec05388ed6ec696b7d496c8138dd57a1daf6caa0c4e1478251fc","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.8/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.8","channel":"stable","tag":"v0.3.8","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"f55783ae3b7f11d501d4702124688938a828d8f21a6bb83732b8d712f3d63a1f","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.8/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.8","channel":"stable","tag":"v0.3.8","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"2a07063f2c03bcd5d5dbceee7e7cfb86f830c2dc3f7531e2bf7aff4b2f76b462","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.8/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.8","channel":"stable","tag":"v0.3.8","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"3633810940440c2e32f991ffff2d61f1fe483b7613f859fe7c52229958d93935","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.8/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.8","channel":"stable","tag":"v0.3.8","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"e37476d4064ee32aa53959809278427a3560a71e8048868f061996b9f41307ff","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.8/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.8","channel":"stable","tag":"v0.3.8","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"9bce5a930098af09295c090c31f0ec57220821437fccd0ae3242b4fba5b8ae0d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.8/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.7","channel":"stable","tag":"v0.3.7","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"6699bc6fe23ec2d5136345bab9da2cd067a5ca8727e98584ebf572affffe9ff1","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.7/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.7","channel":"stable","tag":"v0.3.7","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"a8ae6f99fa478cce0320204eafb4cf9ab9835e6a0116acf76e35afde245c2500","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.7/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.7","channel":"stable","tag":"v0.3.7","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"df0216aa2999f4dbfb82ac44e8387a51d66621c58b4d7725355bf454ae4f5c40","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.7/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.7","channel":"stable","tag":"v0.3.7","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"f5204e4afd94588d83807041a17517a8bc818851a86cefe4a3cea0b1e04599ca","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.7/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.7","channel":"stable","tag":"v0.3.7","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"cd85632ce9858e8b442c11f5c0ddff811625c363058672d8ce525bc2d29369d3","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.7/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.7","channel":"stable","tag":"v0.3.7","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"9caa8d5bae17ddde0c88d359513455983a3fa039b2132cbba53ed62e19b137c9","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.7/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.7","channel":"stable","tag":"v0.3.7","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"7ea3ae072deaa0afb1d0b64ee1c14833cf59cd7d515809d2ebd4a8ff6344520e","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.7/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.7","channel":"stable","tag":"v0.3.7","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"46773c6c42affd5491374d459c656c8f5b6d6ec98ac024026aa280ba897adeea","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.7/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.6","channel":"stable","tag":"v0.3.6","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"e641595430f103110f567a653cf31487468570c8f64156f9f20c35476f3e4f41","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.6/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.6","channel":"stable","tag":"v0.3.6","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"940b03b3cf258fde47250516cbe081f0bae3a029da23b0196fc230277392245c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.6/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.6","channel":"stable","tag":"v0.3.6","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"37a5474c1a89011e22cf94a18ce328087fc65a00c3e8cc41b153111887e9ab29","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.6/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.6","channel":"stable","tag":"v0.3.6","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"d89beee2c508e8d1a0c79feba146f2449a581ce24d648dd41c54f03b2a01b5eb","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.6/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.6","channel":"stable","tag":"v0.3.6","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"46a489513e7fcc3cfca9595694d435b665f61ffa0090e425f0a65b37014efbe2","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.6/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.6","channel":"stable","tag":"v0.3.6","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"dbfaea8d84be01494ae2ef8c7e73821fa74c5f4cfe8faa751e8864a92bfe13dd","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.6/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.6","channel":"stable","tag":"v0.3.6","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"d4ab46e226e029f57796953cfe9cfbc081bbcd22ecb6abf69f14b96833f6cde5","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.6/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.6","channel":"stable","tag":"v0.3.6","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"84be1df7dce2a014ca535f64e711b65ef2f27103b350f76958f688679e69f480","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.6/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.5","channel":"stable","tag":"v0.3.5","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"1b8f282659ae6d7c24e2d505ff2d16e4be858ab3f9614753f2b4a78de825bf42","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.5/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.5","channel":"stable","tag":"v0.3.5","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"621cde3b5000d73487f03252dbf6a1e43525d27ec1b0c9c5749f76d1846e411f","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.5/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.5","channel":"stable","tag":"v0.3.5","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"11c9bbe833cac538f862ce9eee0c9d0b2c4e7a765ef7fadce18fe767d6aa83ea","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.5/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.5","channel":"stable","tag":"v0.3.5","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"c31be7b8836a7f811aedc37a2370a7dcb638ef9814a584ed084bdf4d59dd132c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.5/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.5","channel":"stable","tag":"v0.3.5","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"c5b885f3f7f0d761cb62ce3e15d35d2a85a892ac5619664a65dda8ef07017024","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.5/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.5","channel":"stable","tag":"v0.3.5","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"f8a29d280f419718cf6827b255ea61c830a31821793679ebd09a0ee02633533f","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.5/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.5","channel":"stable","tag":"v0.3.5","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"54d637171c9cc43dfb6bb36ff7853dbb68473563a5c8c7958d39e8133bfe8eef","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.5/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.5","channel":"stable","tag":"v0.3.5","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"a0321fcba8e2155c81c91da99d0061005037c204e8ec15fe798979d545205384","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.5/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.4","channel":"stable","tag":"v0.3.4","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"d7e578d2033a3c1826cc3ffb3a65cd943b262544e6053e75a9e4d065307acf51","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.4/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.4","channel":"stable","tag":"v0.3.4","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"24133e64f1fec32b3e5fefe13558f42b6894dcac3edbfcf00a1512fbc64c733c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.4/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.4","channel":"stable","tag":"v0.3.4","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"bf59f2a20730322fcfa8a4f4e986ae6de5fccc2873e77dc532b287cbfecef150","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.4/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.4","channel":"stable","tag":"v0.3.4","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"f8b6b59fe5dda7a396aa95fd21b71fdffe12bcf38c013986984dccf50bf32b72","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.4/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.4","channel":"stable","tag":"v0.3.4","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"bfd3e85269edca0139144d13780d2bc33b6c583a1c559b536a1439d5061fd00d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.4/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.4","channel":"stable","tag":"v0.3.4","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"1912611f8951cd43bdccba7617210ffa8f36901b23ad78aa135c655ef4458552","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.4/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.4","channel":"stable","tag":"v0.3.4","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"154cc74e91324e2d6d438e84c18ec95dddc6f6b750dd4e154f55913c54664c1b","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.4/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.4","channel":"stable","tag":"v0.3.4","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"c5da953379eff8ad88606f81afa49360516c9d42dd4df0ecf7e7fe73c77d03ba","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.4/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.3","channel":"stable","tag":"v0.3.3","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"5d7ee9a13f605b0052d150d023a48bb49c30333945a9889bc19a0e3760e3c758","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.3/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.3","channel":"stable","tag":"v0.3.3","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"2187720b732838845e71aa83b2344bdd5fd372b7a1ec04d94cb86e0a2b405917","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.3/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.3","channel":"stable","tag":"v0.3.3","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"21159c32cc7c18a989d877954692f765ba4a1cfe834615ed073168ba04a4a8f5","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.3/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.3","channel":"stable","tag":"v0.3.3","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"262a0bd676676b88d62cb5add8ed4ae355e578185ee797b7165c8447981d3032","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.3/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.3","channel":"stable","tag":"v0.3.3","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"7655310f068ccec448bb30acfb601506c279f6658e460b95a2cf1a39eefca747","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.3/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.3","channel":"stable","tag":"v0.3.3","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"3852d1311c449e5e34859332df973ba678dc4ceb0a896efac8b50c6d8e5d716d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.3/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.3","channel":"stable","tag":"v0.3.3","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"430d113d8552c1045573705cbde2d8d895b3c68e200aad0056e1cac0540c1a68","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.3/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.3","channel":"stable","tag":"v0.3.3","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"d4e360d6a333ab7fb336d283c7fdb93a1a801795528d796a12221d84af6573c3","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.3/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.2","channel":"stable","tag":"v0.3.2","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"29b35814263c267ce5c28a70c880f6d94dc79f1c7fe67f0fdd40bebe050efcf2","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.2/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.2","channel":"stable","tag":"v0.3.2","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"82019ea49e917a44e0c45e54c40d672389a6a5b4177f675e9e7f02edb7378791","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.2/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.2","channel":"stable","tag":"v0.3.2","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"d7485ab2bb52d217570f88d7479acbecaede216b62b659409c731d856961a897","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.2/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.2","channel":"stable","tag":"v0.3.2","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"46b42e3883ecf3e14a0ffcdd7061b0aef582fb886ac1983c7a3ec1826d06dd9c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.2/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.2","channel":"stable","tag":"v0.3.2","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"d4505e6bd3b067bc8b7b5055670054060e2eeeb69b6fbe88fcadb82e6eebeddb","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.2/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.2","channel":"stable","tag":"v0.3.2","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"a1d3d0a01c363cc0f436e7c521d88a0119389efb0506bdd22cdf34b9d1a5ede0","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.2/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.2","channel":"stable","tag":"v0.3.2","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"115dc5ac3146f99f5d0fc7c07709b203e88d2e45dd697ec6f73b8f30c83c5b90","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.2/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.2","channel":"stable","tag":"v0.3.2","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"0f2b6e92848a36dd1d7c712d0bac8bd352d7b78be275624f81ecd6633013ddbd","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.2/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.1","channel":"stable","tag":"v0.3.1","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"5f2f562898ea2f8be0c3d45a589de55b80fac4d5e3a16c5de426112fd2a88f3f","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.1/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.1","channel":"stable","tag":"v0.3.1","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"4dbbd2f1473ea0597951b6dd3fa36f2bbd2dd596f7c2fdde9652e27ec99da2d6","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.1/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.1","channel":"stable","tag":"v0.3.1","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"e68a9470605385ff8b0e59941cda5acc823b0e6eda36ecda3b5ea83f37c23d42","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.1/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.1","channel":"stable","tag":"v0.3.1","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"e675e1b516cce5b9f1dd87436c735f48f2a8665aedda2a6d97b7125860920f4d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.1/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.1","channel":"stable","tag":"v0.3.1","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"232ec3e97882fb5c7c69ade2597b89d0192ea567be035a1fb599af51c59914e1","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.1/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.1","channel":"stable","tag":"v0.3.1","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"5946990d9b1566048904892378775dd842ced829616281ccdc58c98acd5968ca","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.1/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.1","channel":"stable","tag":"v0.3.1","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"0d0d0c26cb7c658b4abcc4e09d94ca7a7ba859c01e49ffbedc3ca897499d7aa4","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.1/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.1","channel":"stable","tag":"v0.3.1","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"e2c88edcfe6257967c759902c62e9cd9ebb1a9e4d01071c1b60a97be53d4dc58","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.1/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.0","channel":"stable","tag":"v0.3.0","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"b64e44c32fbc83bf6927699f7b95ae4ce5e1f1e79916fc449bd505a7a21b85e7","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.0/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.0","channel":"stable","tag":"v0.3.0","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"1580413b9c5cde815f19ad8fdfb805fea9bd6d764d56b22761c14498cde25535","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.0/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.0","channel":"stable","tag":"v0.3.0","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"6edecaa060891cc517c295c9398149806b5e090070a8c6aca88e3b3250599ab5","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.0/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.0","channel":"stable","tag":"v0.3.0","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"338adc46a904a1bfed50cb056adb20bfd457e71db80ecc3cc55af9a5287c76b8","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.0/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.0","channel":"stable","tag":"v0.3.0","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"a561332347d8025e6023e8d91f4e8f01c761c1dd2044afbf26b61cae4906e592","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.0/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.0","channel":"stable","tag":"v0.3.0","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"41ec66f2cb5dc0ad43e26ba564bfa3ec3e5a526d814e39a40ea7af61e863c2e2","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.0/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.0","channel":"stable","tag":"v0.3.0","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"c73f40031889256f523589d1dceaad1212fc36c52cc61d941bb24957bba44e30","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.0/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.0","channel":"stable","tag":"v0.3.0","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"63eab66442f780f64041a6298e420ebfbc34b2de5da17b83e198689b840d32fd","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.0/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.2.1","channel":"stable","tag":"v0.2.1","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"031c4d2d06992d9e5c3ed196f4e61c3b47d83df8dd192b6b18f8f36c551c50ce","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.1/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.2.1","channel":"stable","tag":"v0.2.1","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"62e393115f57f8421f25497d6b63eed63c05a8d94f2e83edda6a3f979a2e047d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.1/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.2.1","channel":"stable","tag":"v0.2.1","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"58a377c9fd7a61efb9e61e74f6030d81dc55fae7275dd5c86f306bceafa7ac5a","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.1/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.2.1","channel":"stable","tag":"v0.2.1","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"0d027a670e72a8f5fdd0164eb41834add0d071e55b8d642c18107bec094640eb","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.1/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.2.1","channel":"stable","tag":"v0.2.1","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"c81ab1309ad5cc50de385871b2431d8fe5a9e99d0d858717c0a63a3a7114aa6d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.1/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.2.1","channel":"stable","tag":"v0.2.1","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"63ea0bd39000180bf337f630065d65cac06dbbbfd3a22635039077619053983a","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.1/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.2.1","channel":"stable","tag":"v0.2.1","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"3cf44dd0b03224d8521e929344ad64518352b14b54f686a4e970807f35d88915","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.1/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.2.1","channel":"stable","tag":"v0.2.1","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"6d6dc2892c34c6f3488a280182e6f98968ba75a84c3fd42004eb7537523f4103","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.1/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.2.0","channel":"stable","tag":"v0.2.0","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"97e3db904dbc947ffe9c2e0cc21e23f9ba8fea11fb18b1bc33d07c1d8715a13d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.0/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.2.0","channel":"stable","tag":"v0.2.0","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"1100b2bfaf198654f9d7d35a57778e617a4ea8aaff1b43aaa29771a2355f4bd9","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.0/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.2.0","channel":"stable","tag":"v0.2.0","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"dec16de83d9f8b6b984ab55feb4a76ec4dd68ad7658a16dc766cf330bb09f804","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.0/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.2.0","channel":"stable","tag":"v0.2.0","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"5e82a82a27371d7de2c3d36dc723fb79d2eaeff005cafc1dba63bb71f49f0b28","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.0/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.2.0","channel":"stable","tag":"v0.2.0","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"e3a71f7da5448aaca8d63d273abbf5ef5a4d52ad4252db903f4d0ae8cf47ec4b","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.0/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.2.0","channel":"stable","tag":"v0.2.0","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"d883b9ba36dfb70f58a5aec2c9b04472ecb493577fb1ad2811cc528461e41f70","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.0/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.2.0","channel":"stable","tag":"v0.2.0","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"a5fc05a43f9e767f7de1289613899c80470ea671c9bba96b276e37f61732b81a","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.0/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.2.0","channel":"stable","tag":"v0.2.0","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"975149a28168b3e42b4a0682005a3c34fbb75ad4c07d2e218a578b786f028887","url":"https://github.com/ocx-sh/ocx/releases/download/v0.2.0/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.1.0","channel":"stable","tag":"v0.1.0","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"d308d7605ea6ecce18b1934fc5a52f22c1b50101dd3029967fe47e63d8073ddc","url":"https://github.com/ocx-sh/ocx/releases/download/v0.1.0/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.1.0","channel":"stable","tag":"v0.1.0","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"a7d4a82be860b3a485c67d6bff9ecdfaff0f68186411490baa7f15095b977aca","url":"https://github.com/ocx-sh/ocx/releases/download/v0.1.0/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.1.0","channel":"stable","tag":"v0.1.0","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"b21b0d6f2e36f5f64bbf799b165ae6c94ac603714d18fcc92e916187f5cc7490","url":"https://github.com/ocx-sh/ocx/releases/download/v0.1.0/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.1.0","channel":"stable","tag":"v0.1.0","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"c0da48e8991956ecb5419a811d8220fc23bc9612dd9fd162604cd0314912f541","url":"https://github.com/ocx-sh/ocx/releases/download/v0.1.0/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.1.0","channel":"stable","tag":"v0.1.0","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"3bee03099bfa89550dd3c89c04c1d25b5b4e1526eeedad6956e4497431f3dadf","url":"https://github.com/ocx-sh/ocx/releases/download/v0.1.0/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.1.0","channel":"stable","tag":"v0.1.0","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"7daa31fb8e6be8688dc9331a204b6fa0e3d35beaa441c4c0f149e1358141654c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.1.0/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.1.0","channel":"stable","tag":"v0.1.0","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"b2c344c44ec3d24a42f962d16653a61c4276034b6dfb5d805405a0b32b697caf","url":"https://github.com/ocx-sh/ocx/releases/download/v0.1.0/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.1.0","channel":"stable","tag":"v0.1.0","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"01cfdbd80bd7cf3c180e02e816b1b0b3a4914de78a9fd238b8250e0180686489","url":"https://github.com/ocx-sh/ocx/releases/download/v0.1.0/ocx-x86_64-unknown-linux-musl.tar.xz"}
  ]
}
]=])
# --- END OCX DIST SNAPSHOT ---

# ---------------------------------------------------------------------------
# Environment snapshotting
# ---------------------------------------------------------------------------

function(__ocx_snapshot_env var)
  if(NOT DEFINED ${var} AND DEFINED ENV{${var}})
    set(${var} "$ENV{${var}}" CACHE STRING
      "find_ocx: snapshotted from the environment at first configure")
  endif()
endfunction()

# Passthrough set forwarded to every ocx invocation when set. Mirrors
# rules_ocx OCX_PASSTHROUGH_ENV. OCX_AUTH_* is intentionally absent:
# secrets must never land in CMakeCache.txt.
set(__OCX_PASSTHROUGH_VARS
  OCX_HOME
  OCX_MIRRORS
  OCX_INSECURE_REGISTRIES
  OCX_OFFLINE
  OCX_FROZEN
  OCX_REMOTE
  OCX_JOBS
  OCX_INDEX
  OCX_DEFAULT_REGISTRY
)
set_property(GLOBAL PROPERTY __OCX_PASSTHROUGH_VARS "${__OCX_PASSTHROUGH_VARS}")

foreach(__ocx_var IN ITEMS
    OCX_EXECUTABLE
    OCX_INSTALL_DIST_URL
    OCX_INSTALL_MIRROR_URL
    OCX_INSTALL_VERSION
    OCX_DEFAULT_PLATFORM
    OCX_BOOTSTRAP
    OCX_BOOTSTRAP_CACHE
    OCX_PROJECT_FILE
    OCX_ALLOW_FLOATING
    ${__OCX_PASSTHROUGH_VARS})
  __ocx_snapshot_env(${__ocx_var})
endforeach()
unset(__ocx_var)
unset(__OCX_PASSTHROUGH_VARS)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Command prefix applied to every ocx invocation (configure-time and inside
# the exported *_RUN command lists). OCX_PROJECT is always neutralized
# (pure launcher transport: an outer `ocx run` must not hijack this
# build). Passthrough knobs pin the snapshotted value; a knob cleared with
# -DVAR= is actively removed - `cmake -E env VAR=` would not do, the CLI
# reads an empty OCX_INDEX as "index at the current directory" and writes
# resolved tags there. Undefined knobs inherit the execution environment.
function(__ocx_env_prefix out_var)
  set(prefix "${CMAKE_COMMAND}" -E env "OCX_PROJECT=")
  get_property(vars GLOBAL PROPERTY __OCX_PASSTHROUGH_VARS)
  foreach(var IN LISTS vars)
    if(NOT DEFINED ${var})
      continue()
    endif()
    if("${${var}}" STREQUAL "")
      list(APPEND prefix "--unset=${var}")
    else()
      list(APPEND prefix "${var}=${${var}}")
    endif()
  endforeach()
  set(${out_var} "${prefix}" PARENT_SCOPE)
endfunction()

function(__ocx_default_hint code out_var)
  set(hint "")
  if(code EQUAL 64)
    set(hint "the pinned ocx and find_ocx disagree on the CLI surface - check OCX_INSTALL_VERSION against the find_ocx pin (${__OCX_PIN_VERSION})")
  elseif(code EQUAL 65)
    set(hint "declarations changed since ocx.lock was written - run 'ocx lock' and commit the result")
  elseif(code EQUAL 69)
    set(hint "registry unreachable - check the network, OCX_MIRRORS, and registry credentials (OCX_AUTH_*)")
  elseif(code EQUAL 78)
    set(hint "expected configuration missing - is ocx.toml/ocx.lock where find_ocx expects it?")
  endif()
  set(${out_var} "${hint}" PARENT_SCOPE)
endfunction()

# __ocx_run(WHAT <description> COMMAND <ocx args...>
#           [OUTPUT_VARIABLE <var>] [RETRIES <n>] [HINTS "<code>=<hint>" ...])
# Runs the ocx CLI through the env prefix; fails the configure with an
# actionable hint on nonzero exit (sysexits convention, same as rules_ocx).
function(__ocx_run)
  cmake_parse_arguments(arg "" "WHAT;OUTPUT_VARIABLE;RETRIES" "COMMAND;HINTS" ${ARGN})
  __ocx_env_prefix(prefix)
  set(attempts 1)
  if(arg_RETRIES)
    math(EXPR attempts "${arg_RETRIES} + 1")
  endif()
  foreach(attempt RANGE 1 ${attempts})
    execute_process(
      COMMAND ${prefix} "${OCX_EXECUTABLE}" ${arg_COMMAND}
      RESULT_VARIABLE rc
      OUTPUT_VARIABLE stdout
      ERROR_VARIABLE stderr
    )
    if(rc EQUAL 0)
      if(arg_OUTPUT_VARIABLE)
        set(${arg_OUTPUT_VARIABLE} "${stdout}" PARENT_SCOPE)
      endif()
      return()
    endif()
  endforeach()
  set(hint "")
  foreach(entry IN LISTS arg_HINTS)
    if(entry MATCHES "^([0-9]+)=(.*)$" AND CMAKE_MATCH_1 EQUAL rc)
      set(hint "${CMAKE_MATCH_2}")
      break()
    endif()
  endforeach()
  if(hint STREQUAL "")
    __ocx_default_hint(${rc} hint)
  endif()
  if(NOT hint STREQUAL "")
    set(hint "\nhint: ${hint}")
  endif()
  list(JOIN arg_COMMAND " " pretty)
  message(FATAL_ERROR
    "find_ocx: ${arg_WHAT} failed (exit ${rc}): ocx ${pretty}\n${stderr}${hint}")
endfunction()

# Host detection -> cargo-dist release triple, ocx platform key, exe suffix.
# Linux maps to musl, same as rules_ocx.
function(__ocx_host_info out_triple out_platform out_ext)
  cmake_host_system_information(RESULT raw_arch QUERY OS_PLATFORM)
  string(TOLOWER "${raw_arch}" raw_arch)
  if(raw_arch MATCHES "^(x86_64|amd64|x64)$")
    set(arch "x86_64")
    set(parch "amd64")
  elseif(raw_arch MATCHES "^(aarch64|arm64)$")
    set(arch "aarch64")
    set(parch "arm64")
  else()
    message(FATAL_ERROR "find_ocx: unsupported host architecture '${raw_arch}'")
  endif()
  if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    set(${out_triple} "${arch}-unknown-linux-musl" PARENT_SCOPE)
    set(${out_platform} "linux/${parch}" PARENT_SCOPE)
    set(${out_ext} "" PARENT_SCOPE)
  elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
    set(${out_triple} "${arch}-apple-darwin" PARENT_SCOPE)
    set(${out_platform} "darwin/${parch}" PARENT_SCOPE)
    set(${out_ext} "" PARENT_SCOPE)
  elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
    set(${out_triple} "${arch}-pc-windows-msvc" PARENT_SCOPE)
    set(${out_platform} "windows/${parch}" PARENT_SCOPE)
    set(${out_ext} ".exe" PARENT_SCOPE)
  else()
    message(FATAL_ERROR "find_ocx: unsupported host OS '${CMAKE_HOST_SYSTEM_NAME}'")
  endif()
endfunction()

# Finds the manifest row for an exact version and target triple.
# The manifest is the setup.ocx.sh dist.json (schema 1, flat rows).
function(__ocx_select_release manifest version target out_url out_sha out_tag out_filename)
  string(JSON schema ERROR_VARIABLE err GET "${manifest}" schema)
  if(err OR NOT schema EQUAL 1)
    message(FATAL_ERROR "find_ocx: unsupported dist.json schema '${schema}' ${err}")
  endif()
  string(JSON count LENGTH "${manifest}" releases)
  if(count GREATER 0)
    math(EXPR last "${count} - 1")
    foreach(i RANGE 0 ${last})
      string(JSON row_version GET "${manifest}" releases ${i} version)
      if(NOT row_version STREQUAL version)
        continue()
      endif()
      string(JSON row_target GET "${manifest}" releases ${i} target)
      if(NOT row_target STREQUAL target)
        continue()
      endif()
      string(JSON url GET "${manifest}" releases ${i} url)
      string(JSON sha GET "${manifest}" releases ${i} sha256)
      string(JSON tag GET "${manifest}" releases ${i} tag)
      string(JSON filename GET "${manifest}" releases ${i} filename)
      set(${out_url} "${url}" PARENT_SCOPE)
      set(${out_sha} "${sha}" PARENT_SCOPE)
      set(${out_tag} "${tag}" PARENT_SCOPE)
      set(${out_filename} "${filename}" PARENT_SCOPE)
      return()
    endforeach()
  endif()
  message(FATAL_ERROR
    "find_ocx: ocx ${version} for ${target} not found in the dist manifest - "
    "refresh the vendored snapshot (task dist:update) or point "
    "OCX_INSTALL_DIST_URL at a manifest that contains it")
endfunction()

# Version of the ocx CLI at OCX_EXECUTABLE ('ocx version' prints a bare
# semver). Memoized per configure run in a GLOBAL property.
function(__ocx_cli_version out_var)
  get_property(cached GLOBAL PROPERTY __OCX_CLI_VERSION)
  get_property(cached_path GLOBAL PROPERTY __OCX_CLI_VERSION_PATH)
  if(cached AND cached_path STREQUAL "${OCX_EXECUTABLE}")
    set(${out_var} "${cached}" PARENT_SCOPE)
    return()
  endif()
  execute_process(
    COMMAND "${OCX_EXECUTABLE}" version
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
  )
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR
      "find_ocx: '${OCX_EXECUTABLE} version' failed (exit ${rc})\n${err}")
  endif()
  string(STRIP "${out}" out)
  if(NOT out MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+")
    message(FATAL_ERROR
      "find_ocx: unexpected 'ocx version' output '${out}' from ${OCX_EXECUTABLE}")
  endif()
  set_property(GLOBAL PROPERTY __OCX_CLI_VERSION "${out}")
  set_property(GLOBAL PROPERTY __OCX_CLI_VERSION_PATH "${OCX_EXECUTABLE}")
  set(${out_var} "${out}" PARENT_SCOPE)
endfunction()

# Ensures OCX_EXECUTABLE is usable: explicit setting, else PATH, else the
# pinned bootstrap (OCX_BOOTSTRAP: ALWAYS skips PATH, OFF forbids the
# download).
macro(__ocx_require_cli)
  if(NOT DEFINED OCX_EXECUTABLE OR NOT EXISTS "${OCX_EXECUTABLE}")
    if(NOT "${OCX_BOOTSTRAP}" STREQUAL "ALWAYS")
      find_program(OCX_EXECUTABLE NAMES ocx DOC "Path to the ocx CLI")
    endif()
    if(OCX_EXECUTABLE AND EXISTS "${OCX_EXECUTABLE}")
      message(STATUS
        "find_ocx: using ocx from PATH (${OCX_EXECUTABLE}) - "
        "OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead")
    elseif(DEFINED OCX_BOOTSTRAP AND NOT OCX_BOOTSTRAP)
      message(FATAL_ERROR
        "find_ocx: no ocx on PATH, OCX_EXECUTABLE is not set, and implicit "
        "bootstrap is disabled (OCX_BOOTSTRAP=OFF)\n"
        "hint: install ocx on PATH or set OCX_EXECUTABLE to an ocx binary")
    else()
      ocx_bootstrap()
    endif()
  endif()
endmacro()

# Registers a provisioning NAME; duplicate names across the whole configure
# are an error (GLOBAL property, so add_subdirectory cannot shadow).
function(__ocx_register_name name caller)
  get_property(names GLOBAL PROPERTY __OCX_NAMES)
  if(name IN_LIST names)
    message(FATAL_ERROR "find_ocx: duplicate ${caller} NAME '${name}'")
  endif()
  set_property(GLOBAL APPEND PROPERTY __OCX_NAMES "${name}")
endfunction()

function(__ocx_set_result var)
  set(${var} "${ARGN}" CACHE INTERNAL "find_ocx result (recomputed each configure)")
endfunction()

# Reconfigure memoization: returns TRUE in out_var when the stored
# fingerprint for <name> matches AND every guard path still exists (store
# GC protection). OCX_REFRESH bypasses (one-shot: cleared at the end of the
# top-level directory via cmake_language(DEFER)).
function(__ocx_memo_hit name fingerprint out_var)
  set(${out_var} FALSE PARENT_SCOPE)
  if(OCX_REFRESH)
    return()
  endif()
  if(NOT "$CACHE{__OCX_R_${name}_FP}" STREQUAL "${fingerprint}")
    return()
  endif()
  foreach(path IN LISTS __OCX_R_${name}_GUARD)
    if(NOT EXISTS "${path}")
      return()
    endif()
  endforeach()
  set(${out_var} TRUE PARENT_SCOPE)
endfunction()

function(__ocx_memo_store name fingerprint)
  __ocx_set_result(__OCX_R_${name}_FP "${fingerprint}")
  __ocx_set_result(__OCX_R_${name}_GUARD "${ARGN}")
endfunction()

function(__ocx_clear_refresh)
  unset(OCX_REFRESH CACHE)
endfunction()
if(OCX_REFRESH AND NOT CMAKE_SCRIPT_MODE_FILE)
  cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL __ocx_clear_refresh)
endif()

# Parses `ocx --format json env` output ({"entries":[{key,value,type}]},
# ordered; type "path" = prepend directory, "constant" = replace) into
# OCX_<name>_PATHS and OCX_<name>_ENV_<KEY> result variables.
function(__ocx_export_env name json)
  string(JSON count LENGTH "${json}" entries)
  set(paths "")
  set(keys "")
  if(count GREATER 0)
    math(EXPR last "${count} - 1")
    foreach(i RANGE 0 ${last})
      string(JSON key GET "${json}" entries ${i} key)
      string(JSON value GET "${json}" entries ${i} value)
      string(JSON type GET "${json}" entries ${i} type)
      if(type STREQUAL "path")
        list(APPEND paths "${value}")
      else()
        __ocx_set_result(OCX_${name}_ENV_${key} "${value}")
        list(APPEND keys "${key}")
      endif()
    endforeach()
  endif()
  __ocx_set_result(OCX_${name}_PATHS "${paths}")
  __ocx_set_result(OCX_${name}_ENV_KEYS "${keys}")
endfunction()

# ---------------------------------------------------------------------------
# ocx_bootstrap
# ---------------------------------------------------------------------------

#[=[.rst:
.. command:: ocx_bootstrap

  Downloads a pinned ocx CLI release for the host and sets
  ``OCX_EXECUTABLE``::

    ocx_bootstrap([VERSION <version>] [TRIPLE <target-triple>])

  No-op when ``OCX_EXECUTABLE`` already points at a binary of the requested
  version. The release row (URL + sha256) comes from the dist.json snapshot
  embedded in this file; ``OCX_INSTALL_DIST_URL`` fetches a mirrored
  manifest instead, ``OCX_INSTALL_MIRROR_URL`` rewrites the artifact
  download to ``<mirror>/<tag>/<filename>``. The manifest sha256 is
  enforced either way. Binaries land in the per-machine
  ``OCX_BOOTSTRAP_CACHE`` (downloaded once per machine, shared by all build
  trees).
#]=]
function(ocx_bootstrap)
  cmake_parse_arguments(arg "" "VERSION;TRIPLE" "" ${ARGN})

  set(version "${__OCX_PIN_VERSION}")
  if(DEFINED OCX_INSTALL_VERSION AND NOT "${OCX_INSTALL_VERSION}" STREQUAL "")
    set(version "${OCX_INSTALL_VERSION}")
  endif()
  if(arg_VERSION)
    set(version "${arg_VERSION}")
  endif()

  if(DEFINED OCX_EXECUTABLE AND EXISTS "${OCX_EXECUTABLE}")
    __ocx_cli_version(have)
    if(have VERSION_EQUAL version)
      return()
    endif()
    message(STATUS
      "find_ocx: OCX_EXECUTABLE is ocx ${have}, want ${version} - bootstrapping")
    set_property(GLOBAL PROPERTY __OCX_CLI_VERSION "")
  endif()

  __ocx_host_info(host_triple host_platform exe_ext)
  set(triple "${host_triple}")
  if(arg_TRIPLE)
    set(triple "${arg_TRIPLE}")
  endif()

  if(DEFINED OCX_BOOTSTRAP_CACHE AND NOT "${OCX_BOOTSTRAP_CACHE}" STREQUAL "")
    set(cache_root "${OCX_BOOTSTRAP_CACHE}")
  elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows" AND NOT "$ENV{LOCALAPPDATA}" STREQUAL "")
    set(cache_root "$ENV{LOCALAPPDATA}/find_ocx")
  elseif(NOT "$ENV{XDG_CACHE_HOME}" STREQUAL "")
    set(cache_root "$ENV{XDG_CACHE_HOME}/find_ocx")
  elseif(NOT "$ENV{HOME}" STREQUAL "")
    set(cache_root "$ENV{HOME}/.cache/find_ocx")
  else()
    # No usable home (some CI containers): fall back to the build tree -
    # correctness over sharing.
    set(cache_root "${CMAKE_BINARY_DIR}/_ocx/cache")
  endif()
  set(binary "${cache_root}/${version}/${triple}/ocx${exe_ext}")

  # Warm machine cache: no manifest work, no network - not even the
  # OCX_INSTALL_DIST_URL fetch (air-gapped reconfigures stay offline).
  if(NOT EXISTS "${binary}")
    if(DEFINED OCX_INSTALL_DIST_URL AND NOT "${OCX_INSTALL_DIST_URL}" STREQUAL "")
      set(dist_file "${CMAKE_BINARY_DIR}/_ocx/dist.json")
      file(DOWNLOAD "${OCX_INSTALL_DIST_URL}" "${dist_file}" STATUS status)
      list(GET status 0 status_code)
      if(NOT status_code EQUAL 0)
        list(GET status 1 status_msg)
        message(FATAL_ERROR
          "find_ocx: failed to fetch the dist manifest from "
          "OCX_INSTALL_DIST_URL='${OCX_INSTALL_DIST_URL}': ${status_msg}")
      endif()
      file(READ "${dist_file}" manifest)
    else()
      set(manifest "${__OCX_DIST_JSON}")
    endif()

    __ocx_select_release("${manifest}" "${version}" "${triple}" url sha tag filename)

    if(DEFINED OCX_INSTALL_MIRROR_URL AND NOT "${OCX_INSTALL_MIRROR_URL}" STREQUAL "")
      string(REGEX REPLACE "/+$" "" mirror "${OCX_INSTALL_MIRROR_URL}")
      set(url "${mirror}/${tag}/${filename}")
    endif()

    set(scratch "${CMAKE_BINARY_DIR}/_ocx")
    set(archive "${scratch}/${filename}")
    message(STATUS "find_ocx: downloading ocx ${version} (${triple}) from ${url}")
    message(STATUS
      "find_ocx:   version knob: OCX_INSTALL_VERSION (pin: "
      "${__OCX_PIN_VERSION}); cache: ${cache_root}; opt out: "
      "OCX_BOOTSTRAP=OFF + OCX_EXECUTABLE")
    file(DOWNLOAD "${url}" "${archive}" EXPECTED_HASH SHA256=${sha} STATUS status)
    list(GET status 0 status_code)
    if(NOT status_code EQUAL 0)
      list(GET status 1 status_msg)
      message(FATAL_ERROR
        "find_ocx: download of ${url} failed: ${status_msg}\n"
        "hint: corporate networks - set OCX_INSTALL_MIRROR_URL (artifacts) "
        "and/or OCX_INSTALL_DIST_URL (manifest)")
    endif()
    set(extract_dir "${scratch}/extract-${version}-${triple}")
    file(REMOVE_RECURSE "${extract_dir}")
    file(ARCHIVE_EXTRACT INPUT "${archive}" DESTINATION "${extract_dir}")
    set(nested "${extract_dir}/ocx-${triple}/ocx${exe_ext}")
    set(flat "${extract_dir}/ocx${exe_ext}")
    if(EXISTS "${nested}")
      set(source "${nested}")
    elseif(EXISTS "${flat}")
      set(source "${flat}")
    else()
      message(FATAL_ERROR
        "find_ocx: 'ocx${exe_ext}' not found in the extracted archive from ${url}")
    endif()
    file(COPY "${source}" DESTINATION "${cache_root}/${version}/${triple}")
    file(REMOVE_RECURSE "${extract_dir}")
    file(REMOVE "${archive}")
  endif()

  set(OCX_EXECUTABLE "${binary}" CACHE FILEPATH "Path to the ocx CLI" FORCE)
  set_property(GLOBAL PROPERTY __OCX_CLI_VERSION "")
  message(STATUS "find_ocx: using bootstrapped ocx ${version} (${binary})")
endfunction()

# ---------------------------------------------------------------------------
# ocx_project
# ---------------------------------------------------------------------------

# Default ocx.toml: OCX_PROJECT_FILE, else walk up from the calling
# directory to PROJECT_SOURCE_DIR (inclusive). Deliberately NOT driven by
# the OCX_PROJECT env var: that one belongs to the ocx CLI itself and is
# neutralized in every invocation.
function(__ocx_default_toml out_var)
  if(DEFINED OCX_PROJECT_FILE AND NOT "${OCX_PROJECT_FILE}" STREQUAL "")
    set(${out_var} "${OCX_PROJECT_FILE}" PARENT_SCOPE)
    return()
  endif()
  # Bounded by the most recent project() scope; in script mode (cmake -P)
  # there is no project(), so the search walks to the filesystem root.
  set(bound "")
  if(DEFINED PROJECT_SOURCE_DIR)
    set(bound "${PROJECT_SOURCE_DIR}")
  endif()
  set(dir "${CMAKE_CURRENT_SOURCE_DIR}")
  while(TRUE)
    if(EXISTS "${dir}/ocx.toml")
      set(${out_var} "${dir}/ocx.toml" PARENT_SCOPE)
      return()
    endif()
    if(dir STREQUAL "${bound}")
      break()
    endif()
    get_filename_component(parent "${dir}" DIRECTORY)
    if(parent STREQUAL "${dir}")
      break()
    endif()
    set(dir "${parent}")
  endwhile()
  message(FATAL_ERROR
    "find_ocx: no ocx.toml found searching upward from "
    "${CMAKE_CURRENT_SOURCE_DIR} - pass TOML <path>, set OCX_PROJECT_FILE, "
    "or create an ocx.toml")
endfunction()

#[=[.rst:
.. command:: ocx_project

  Provisions the toolchain of a workspace ``ocx.toml`` + ``ocx.lock``::

    ocx_project([NAME <name>] [TOML <ocx.toml>] [LOCK <ocx.lock>]
                [GROUPS <group>...] [BINS <tool>...]
                [PLATFORM <ocx-platform>] [PULL])

  ``NAME`` (default ``PROJECT``) prefixes the exported result variables,
  which are global cache-internal values usable from any directory:

  ``OCX_<NAME>_RUN``
    Command-list prefix that composes the project environment and runs any
    tool on it (lazy: content materializes on first execution)::

      add_custom_command(... COMMAND ${OCX_PROJECT_RUN} jq . in > out)

  ``OCX_<NAME>_RUN_<BIN>``
    Per-tool convenience command for every name in ``BINS``. Entries are
    executable names on the composed environment (a package may ship
    several tools), not package references.

  ``TOML`` defaults to ``OCX_PROJECT_FILE`` or the nearest ``ocx.toml``
  between the calling directory and the last ``project()`` source dir;
  ``LOCK`` defaults to the sibling ``ocx.lock``. ``ocx lock --check``
  always runs (offline staleness gate); ``PULL`` (or the global
  ``OCX_PULL``) materializes eagerly at configure time.

  A foreign ``PLATFORM`` (default ``OCX_DEFAULT_PLATFORM``) pulls that
  platform's content from the same ocx.lock and exports
  ``OCX_<NAME>_PATHS`` / ``OCX_<NAME>_ENV_<KEY>`` instead of RUN commands
  (foreign binaries cannot execute; ``BINS`` is an error).
#]=]
function(ocx_project)
  cmake_parse_arguments(arg "PULL" "NAME;TOML;LOCK;PLATFORM" "GROUPS;BINS" ${ARGN})
  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "find_ocx: ocx_project: unknown arguments '${arg_UNPARSED_ARGUMENTS}'")
  endif()

  if(NOT arg_NAME)
    set(arg_NAME "PROJECT")
  endif()
  string(TOUPPER "${arg_NAME}" name)
  string(MAKE_C_IDENTIFIER "${name}" name)
  __ocx_register_name("${name}" "ocx_project")

  if(arg_TOML)
    set(toml "${arg_TOML}")
  else()
    __ocx_default_toml(toml)
  endif()
  get_filename_component(toml "${toml}" ABSOLUTE)
  if(NOT EXISTS "${toml}")
    message(FATAL_ERROR "find_ocx: ocx_project: '${toml}' does not exist")
  endif()
  if(arg_LOCK)
    set(lock "${arg_LOCK}")
    get_filename_component(lock "${lock}" ABSOLUTE)
  else()
    get_filename_component(lock_dir "${toml}" DIRECTORY)
    set(lock "${lock_dir}/ocx.lock")
  endif()

  set(platform "${arg_PLATFORM}")
  if(NOT arg_PLATFORM AND DEFINED OCX_DEFAULT_PLATFORM)
    set(platform "${OCX_DEFAULT_PLATFORM}")
  endif()
  if(platform AND arg_BINS)
    message(FATAL_ERROR
      "find_ocx: ocx_project: PLATFORM is incompatible with BINS - foreign "
      "binaries cannot execute on this host")
  endif()

  set(pull ${arg_PULL})
  if(OCX_PULL OR platform)
    set(pull TRUE)  # foreign platforms: the pulled content IS the product
  endif()

  __ocx_require_cli()

  # Edits to the declaration or the lock retrigger the configure
  # (project mode only; script mode has no configure to retrigger).
  if(NOT CMAKE_SCRIPT_MODE_FILE)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${toml}")
    if(EXISTS "${lock}")
      set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${lock}")
    endif()
  endif()

  __ocx_cli_version(cli_version)
  file(SHA256 "${toml}" toml_sha)
  set(lock_sha "missing")
  if(EXISTS "${lock}")
    file(SHA256 "${lock}" lock_sha)
  endif()
  __ocx_env_prefix(prefix)
  string(SHA256 fingerprint
    "project|${__OCX_MODULE_VERSION}|${cli_version}|${OCX_EXECUTABLE}|${toml}|${toml_sha}|${lock_sha}|${arg_GROUPS}|${arg_BINS}|${platform}|${pull}|${prefix}")
  __ocx_memo_hit("${name}" "${fingerprint}" hit)
  if(hit)
    message(STATUS "find_ocx: ${name} up to date (memoized)")
    return()
  endif()

  set(groups_args "")
  if(arg_GROUPS)
    list(JOIN arg_GROUPS "," groups_csv)
    set(groups_args -g "${groups_csv}")
  endif()
  set(platform_args "")
  if(platform)
    set(platform_args -p "${platform}")
  endif()

  __ocx_run(
    WHAT "checking ${toml} against its lockfile"
    COMMAND --project "${toml}" lock --check
    HINTS
      "65=run 'ocx lock' next to ${toml} and commit the updated ocx.lock"
      "78=no ocx.lock next to ${toml} - run 'ocx lock' and commit it"
  )

  if(pull)
    __ocx_run(
      WHAT "pulling packages for ${toml}"
      COMMAND --project "${toml}" pull ${platform_args} ${groups_args}
      HINTS "78=a tool in scope ships no '${platform}' leaf in ocx.lock - narrow GROUPS or drop the platform"
    )
  endif()

  set(guard_paths "")
  if(platform)
    __ocx_run(
      WHAT "composing the ${platform} environment of ${toml}"
      COMMAND --format json --project "${toml}" env ${platform_args} ${groups_args}
      OUTPUT_VARIABLE env_json
      HINTS "78=a tool in scope ships no '${platform}' leaf in ocx.lock - narrow GROUPS or drop the platform"
    )
    __ocx_export_env("${name}" "${env_json}")
    set(guard_paths "${OCX_${name}_PATHS}")
  else()
    set(run ${prefix} "${OCX_EXECUTABLE}" --project "${toml}" run ${groups_args} --)
    __ocx_set_result(OCX_${name}_RUN "${run}")
    foreach(bin IN LISTS arg_BINS)
      string(TOUPPER "${bin}" bin_id)
      string(MAKE_C_IDENTIFIER "${bin_id}" bin_id)
      __ocx_set_result(OCX_${name}_RUN_${bin_id} "${run}" "${bin}")
    endforeach()
  endif()

  __ocx_memo_store("${name}" "${fingerprint}" ${guard_paths})
endfunction()

# ---------------------------------------------------------------------------
# ocx_package
# ---------------------------------------------------------------------------

# Nearest committed `.ocx/` index snapshot: walk up from the calling
# directory, bounded by the most recent project() scope (same bound as the
# ocx.toml search). No project() bound (script mode, include before
# project()) -> no discovery: an unbounded walk could reach $HOME/.ocx,
# which is the ocx store, not a snapshot.
function(__ocx_find_index out_var)
  set(${out_var} "" PARENT_SCOPE)
  if(CMAKE_SCRIPT_MODE_FILE OR NOT DEFINED PROJECT_SOURCE_DIR)
    return()
  endif()
  set(dir "${CMAKE_CURRENT_SOURCE_DIR}")
  while(TRUE)
    if(IS_DIRECTORY "${dir}/.ocx")
      set(${out_var} "${dir}/.ocx" PARENT_SCOPE)
      return()
    endif()
    if(dir STREQUAL "${PROJECT_SOURCE_DIR}")
      break()
    endif()
    get_filename_component(parent "${dir}" DIRECTORY)
    if(parent STREQUAL "${dir}")
      break()
    endif()
    set(dir "${parent}")
  endwhile()
endfunction()

#[=[.rst:
.. command:: ocx_package

  Provisions a single OCX package from an OCI registry::

    ocx_package(NAME <name> PACKAGE <registry/repo[:tag][@sha256:...]>
                [PINS <platform>=sha256:<digest> ...]
                [INDEX <dir> | NO_INDEX] [BINS <tool>...]
                [PLATFORM <ocx-platform>] [PULL] [NO_ROOT])

  Exports the same ``OCX_<NAME>_RUN`` / ``OCX_<NAME>_RUN_<BIN>`` command
  lists as :command:`ocx_project` (re-entering ``ocx package exec``, lazy
  by default). ``PINS`` maps ocx platform keys to per-platform manifest
  digests (as reported by ``ocx package install -p <platform>``); the
  matching platform installs ``registry/repo@<digest>``. ``BINS`` entries
  are executable names on the composed environment (a package may ship
  several tools), not package references.

  Tag resolution is frozen against the first index snapshot in effect:
  the explicit ``INDEX <dir>``, else the :variable:`OCX_INDEX` knob, else
  the nearest committed ``.ocx/`` directory between the calling directory
  and the last ``project()`` source dir. ``NO_INDEX`` skips all three.
  A floating tag with no index in effect and no digest pin is a hard
  error unless :variable:`OCX_ALLOW_FLOATING` is set — reproducible
  first. Snapshots are created and refreshed deliberately
  (``ocx --index <dir> index update <package>``; see
  :command:`ocx_index` for the composed refresh command).

  With an index in effect the exported launchers run
  ``ocx --index <dir> --frozen`` and export both knobs into child
  processes: a find_ocx configure nested under such a launcher inherits
  the outer resolution mode unless it is given ``-DOCX_FROZEN=``
  ``-DOCX_INDEX=``.

  With ``PULL`` (or the global ``OCX_PULL``) the package is installed at
  configure time and ``<name>_ROOT`` (original case, CMP0074) is set to the
  package content root so a following ``find_package(<name>)`` /
  ``find_library`` searches the OCX-provisioned content — suppress with
  ``NO_ROOT``. A foreign ``PLATFORM`` exports
  ``OCX_<NAME>_PATHS`` / ``OCX_<NAME>_ENV_<KEY>`` instead of RUN commands.
#]=]
function(ocx_package)
  cmake_parse_arguments(arg "PULL;NO_ROOT;NO_INDEX" "NAME;PACKAGE;INDEX;PLATFORM" "PINS;BINS" ${ARGN})
  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "find_ocx: ocx_package: unknown arguments '${arg_UNPARSED_ARGUMENTS}'")
  endif()
  if(NOT arg_NAME OR NOT arg_PACKAGE)
    message(FATAL_ERROR "find_ocx: ocx_package: NAME and PACKAGE are required")
  endif()
  string(TOUPPER "${arg_NAME}" name)
  string(MAKE_C_IDENTIFIER "${name}" name)
  __ocx_register_name("${name}" "ocx_package")

  set(platform "${arg_PLATFORM}")
  if(NOT arg_PLATFORM AND DEFINED OCX_DEFAULT_PLATFORM)
    set(platform "${OCX_DEFAULT_PLATFORM}")
  endif()
  if(platform AND arg_BINS)
    message(FATAL_ERROR
      "find_ocx: ocx_package: PLATFORM is incompatible with BINS - foreign "
      "binaries cannot execute on this host")
  endif()

  __ocx_require_cli()
  __ocx_host_info(host_triple host_platform exe_ext)
  set(pin_platform "${platform}")
  if(NOT pin_platform)
    set(pin_platform "${host_platform}")
  endif()

  # Apply the per-platform manifest pin: replace everything after '@'.
  set(ref "${arg_PACKAGE}")
  foreach(entry IN LISTS arg_PINS)
    if(NOT entry MATCHES "^([^=]+)=(sha256:[0-9a-f]+)$")
      message(FATAL_ERROR
        "find_ocx: ocx_package ${arg_NAME}: PINS entry '${entry}' is not "
        "'<platform>=sha256:<digest>'")
    endif()
    if(CMAKE_MATCH_1 STREQUAL "${pin_platform}")
      set(digest "${CMAKE_MATCH_2}")  # the REPLACE below clobbers CMAKE_MATCH_*
      string(REGEX REPLACE "@.*$" "" ref "${ref}")
      set(ref "${ref}@${digest}")
    endif()
  endforeach()

  # Index resolution ladder: explicit INDEX, else the OCX_INDEX knob, else
  # the nearest committed `.ocx/` snapshot; NO_INDEX skips all three. An
  # empty OCX_INDEX (-DOCX_INDEX=) neutralizes a launcher-inherited value
  # but does not veto the project's own committed snapshot.
  set(index_dir "")
  if(arg_INDEX AND arg_NO_INDEX)
    message(FATAL_ERROR
      "find_ocx: ocx_package ${arg_NAME}: INDEX and NO_INDEX are mutually exclusive")
  elseif(arg_INDEX)
    get_filename_component(index_dir "${arg_INDEX}" ABSOLUTE)
  elseif(NOT arg_NO_INDEX)
    if(DEFINED OCX_INDEX AND NOT "${OCX_INDEX}" STREQUAL "")
      get_filename_component(index_dir "${OCX_INDEX}" ABSOLUTE)
    else()
      __ocx_find_index(index_dir)
    endif()
  endif()

  # Reproducible-first: a floating tag with no index in effect and no
  # digest pin would resolve differently over time - fail instead.
  if(NOT index_dir AND NOT ref MATCHES "@sha256:" AND NOT OCX_ALLOW_FLOATING)
    message(FATAL_ERROR
      "find_ocx: ocx_package ${arg_NAME}: '${ref}' is floating and no "
      "index snapshot is in effect - resolution is not reproducible\n"
      "fix (pick one): commit a snapshot ('ocx --index .ocx index update "
      "${arg_PACKAGE}' next to your CMakeLists, or set OCX_INDEX); pin "
      "digests with PINS or @sha256:; or accept drift explicitly with "
      "-DOCX_ALLOW_FLOATING=ON")
  endif()

  set(index_args "")
  set(index_leaf_sha "")
  if(index_dir)
    set(index_args --index "${index_dir}" --frozen)
    # repo without :tag/@digest - the argument `ocx index update` expects.
    # Registered before the memo gate: GLOBAL properties do not survive
    # reconfigures, so ocx_index(UPDATE_COMMAND) must see memoized
    # packages too.
    string(REGEX REPLACE "@.*$" "" index_repo "${arg_PACKAGE}")
    string(REGEX REPLACE ":[^:/]*$" "" index_repo "${index_repo}")
    set_property(GLOBAL APPEND PROPERTY __OCX_INDEX_REFRESH "${index_dir}|${index_repo}")
    # The flag string alone would memoize across snapshot refreshes: hash
    # the <repo>.json leaf into the fingerprint and retrigger on edits.
    set(index_leaf "${index_dir}/${index_repo}.json")
    if(EXISTS "${index_leaf}")
      file(SHA256 "${index_leaf}" index_leaf_sha)
      if(NOT CMAKE_SCRIPT_MODE_FILE)
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${index_leaf}")
      endif()
    endif()
  endif()
  set(platform_args "")
  if(platform)
    set(platform_args -p "${platform}")
  endif()

  set(pull ${arg_PULL})
  if(OCX_PULL OR platform)
    set(pull TRUE)
  endif()

  __ocx_cli_version(cli_version)
  __ocx_env_prefix(prefix)
  string(SHA256 fingerprint
    "package|${__OCX_MODULE_VERSION}|${cli_version}|${OCX_EXECUTABLE}|${ref}|${arg_PINS}|${arg_BINS}|${platform}|${index_args}|${index_leaf_sha}|${pull}|${arg_NO_ROOT}|${prefix}")
  __ocx_memo_hit("${name}" "${fingerprint}" hit)
  if(hit)
    message(STATUS "find_ocx: ${name} up to date (memoized)")
    return()
  endif()

  if(index_dir)
    set(index_hint
      "81=package not in the committed index snapshot - refresh it with 'ocx --index ${index_dir} index update ${index_repo}'")
  else()
    set(index_hint
      "81=frozen resolution refused the floating tag - is OCX_FROZEN set without a usable index?")
  endif()

  set(guard_paths "")
  if(pull)
    __ocx_run(
      WHAT "installing ${ref}"
      COMMAND ${index_args} --format json package install ${platform_args} "${ref}"
      OUTPUT_VARIABLE install_json
      RETRIES 2
      HINTS "${index_hint}"
    )
    string(JSON member MEMBER "${install_json}" 0)
    string(JSON identifier GET "${install_json}" "${member}" identifier)
    if(NOT identifier MATCHES "@sha256:" )
      message(STATUS
        "find_ocx: ${arg_NAME} resolved floating - pin it with PINS "
        "\"${pin_platform}=<digest>\" (see 'ocx package install' output)")
    endif()
    __ocx_run(
      WHAT "locating ${ref} in the store"
      COMMAND ${index_args} --format json package which ${platform_args} "${ref}"
      OUTPUT_VARIABLE which_json
      HINTS "${index_hint}"
    )
    string(JSON member MEMBER "${which_json}" 0)
    string(JSON store_root GET "${which_json}" "${member}")
    set(content "${store_root}/content")
    __ocx_set_result(OCX_${name}_CONTENT "${content}")
    list(APPEND guard_paths "${content}")
    if(NOT arg_NO_ROOT)
      set(${arg_NAME}_ROOT "${content}" CACHE PATH
        "find_ocx: content root of ${ref} (CMP0074 search hint)" FORCE)
    endif()
  elseif(NOT ref MATCHES "@sha256:" AND NOT index_dir)
    # only reachable with OCX_ALLOW_FLOATING (the gate above fails otherwise)
    message(WARNING
      "find_ocx: ocx_package ${arg_NAME}: '${ref}' is lazy AND floating - "
      "the tag resolves on first execution and can drift; add PINS, an "
      "index snapshot, or an @sha256: digest (or PULL to resolve now)")
  endif()

  if(platform)
    __ocx_run(
      WHAT "composing the ${platform} environment of ${ref}"
      COMMAND ${index_args} --format json package env ${platform_args} "${ref}"
      OUTPUT_VARIABLE env_json
      HINTS "${index_hint}"
    )
    __ocx_export_env("${name}" "${env_json}")
    list(APPEND guard_paths ${OCX_${name}_PATHS})
  else()
    set(run ${prefix} "${OCX_EXECUTABLE}" ${index_args} package exec "${ref}" --)
    __ocx_set_result(OCX_${name}_RUN "${run}")
    foreach(bin IN LISTS arg_BINS)
      string(TOUPPER "${bin}" bin_id)
      string(MAKE_C_IDENTIFIER "${bin_id}" bin_id)
      __ocx_set_result(OCX_${name}_RUN_${bin_id} "${run}" "${bin}")
    endforeach()
  endif()

  __ocx_memo_store("${name}" "${fingerprint}" ${guard_paths})
endfunction()

# ---------------------------------------------------------------------------
# ocx_index
# ---------------------------------------------------------------------------

#[=[.rst:
.. command:: ocx_index

  Operations on committed index snapshots — the reproducibility mechanism
  for floating tags, next to ``PINS`` and ``@sha256:`` digests. The first
  argument selects the operation:

  .. parsed-literal::

    ocx_index(`FIND`_ [REQUIRED])
    ocx_index(`UPDATE_COMMAND`_ <out-var> [INDEX <dir>] [PACKAGES <ref>...])

  A snapshot is a CLI-owned directory of ``<registry>/<repo>.json`` leaves
  mapping tags to digests, created and refreshed with
  ``ocx --index <dir> index update <package>...``. Committing one next to
  your ``CMakeLists.txt`` as ``.ocx/`` freezes every
  :command:`ocx_package` tag resolution against it — see the discovery
  ladder there.

  .. signature::
    ocx_index(FIND [REQUIRED])

    Runs the ``.ocx/`` discovery once — upward from the calling directory,
    bounded by the last ``project()`` source dir — and locks the result
    into :variable:`OCX_INDEX` for the current directory and below.
    ``REQUIRED`` turns "no snapshot found" into a hard error (fail-fast at
    the top of a CMakeLists instead of per package). Without it, finding
    nothing is a quiet no-op. Not available in script mode (no search
    bound): set :variable:`OCX_INDEX` there instead.

  .. signature::
    ocx_index(UPDATE_COMMAND <out-var> [INDEX <dir>] [PACKAGES <ref>...])

    Composes the command list that refreshes a snapshot:
    ``ocx --index <dir> index update <package>...`` under the module's
    composed environment. ``INDEX`` defaults to the index in effect
    (:variable:`OCX_INDEX`, else the ``.ocx/`` discovery). Without
    ``PACKAGES`` the packages are collected from the preceding
    :command:`ocx_package` calls frozen against that directory;
    ``PACKAGES`` overrides the collection (full references are accepted —
    ``:tag`` / ``@sha256:`` are stripped). Works in project and script
    mode.

    How the command runs is the caller's choice — build target, test
    fixture, or script mode::

      ocx_index(UPDATE_COMMAND refresh)
      add_custom_target(index-update COMMAND ${refresh} VERBATIM)
      # or, in script mode:
      execute_process(COMMAND ${refresh} COMMAND_ERROR_IS_FATAL ANY)

    Deliberately no built-in target or ctest wiring: a "test" that
    rewrites a committed file would let CI paper over drift instead of
    failing. The freshness gate is the frozen configure itself — a tag
    missing from the snapshot fails with the exit-81 refresh hint. Run
    the command, review the diff, commit.
#]=]
function(ocx_index op)
  if(op STREQUAL "FIND")
    cmake_parse_arguments(arg "REQUIRED" "" "" ${ARGN})
    if(arg_UNPARSED_ARGUMENTS)
      message(FATAL_ERROR
        "find_ocx: ocx_index(FIND): unknown arguments '${arg_UNPARSED_ARGUMENTS}'")
    endif()
    if(CMAKE_SCRIPT_MODE_FILE)
      message(FATAL_ERROR
        "find_ocx: ocx_index(FIND) needs a project() search bound and "
        "script mode has none - set OCX_INDEX instead")
    endif()
    __ocx_find_index(dir)
    if(NOT dir)
      if(arg_REQUIRED)
        message(FATAL_ERROR
          "find_ocx: ocx_index(FIND REQUIRED): no .ocx index snapshot "
          "between ${CMAKE_CURRENT_SOURCE_DIR} and ${PROJECT_SOURCE_DIR}\n"
          "hint: create one with 'ocx --index .ocx index update "
          "<package>...' and commit it")
      endif()
      return()
    endif()
    set(OCX_INDEX "${dir}" PARENT_SCOPE)
    message(STATUS "find_ocx: index snapshot: ${dir}")

  elseif(op STREQUAL "UPDATE_COMMAND")
    set(args ${ARGN})
    if(NOT args)
      message(FATAL_ERROR
        "find_ocx: ocx_index(UPDATE_COMMAND) requires an <out-var>")
    endif()
    list(POP_FRONT args out_var)
    cmake_parse_arguments(arg "" "INDEX" "PACKAGES" ${args})
    if(arg_UNPARSED_ARGUMENTS)
      message(FATAL_ERROR
        "find_ocx: ocx_index(UPDATE_COMMAND): unknown arguments '${arg_UNPARSED_ARGUMENTS}'")
    endif()

    if(arg_INDEX)
      get_filename_component(dir "${arg_INDEX}" ABSOLUTE)
    elseif(DEFINED OCX_INDEX AND NOT "${OCX_INDEX}" STREQUAL "")
      get_filename_component(dir "${OCX_INDEX}" ABSOLUTE)
    else()
      __ocx_find_index(dir)
    endif()
    if(NOT dir)
      message(FATAL_ERROR
        "find_ocx: ocx_index(UPDATE_COMMAND): no index in effect - pass "
        "INDEX <dir>, set OCX_INDEX, or commit a .ocx snapshot")
    endif()

    set(repos "")
    foreach(pkg IN LISTS arg_PACKAGES)
      # full references accepted: strip @digest, then :tag
      string(REGEX REPLACE "@.*$" "" pkg "${pkg}")
      string(REGEX REPLACE ":[^:/]*$" "" pkg "${pkg}")
      list(APPEND repos "${pkg}")
    endforeach()
    if(NOT repos)
      get_property(entries GLOBAL PROPERTY __OCX_INDEX_REFRESH)
      foreach(entry IN LISTS entries)
        string(REGEX REPLACE "^(.*)\\|([^|]+)$" "\\1" entry_dir "${entry}")
        string(REGEX REPLACE "^(.*)\\|([^|]+)$" "\\2" entry_repo "${entry}")
        if(entry_dir STREQUAL dir)
          list(APPEND repos "${entry_repo}")
        endif()
      endforeach()
      list(REMOVE_DUPLICATES repos)
      if(NOT repos)
        message(FATAL_ERROR
          "find_ocx: ocx_index(UPDATE_COMMAND): no ocx_package call is "
          "frozen against '${dir}' - pass PACKAGES <ref>... explicitly")
      endif()
    endif()

    __ocx_require_cli()
    __ocx_env_prefix(prefix)
    set(${out_var}
      ${prefix} "${OCX_EXECUTABLE}" --index "${dir}" index update ${repos}
      PARENT_SCOPE)

  else()
    message(FATAL_ERROR
      "find_ocx: ocx_index: unknown operation '${op}' "
      "(expected FIND or UPDATE_COMMAND)")
  endif()
endfunction()

cmake_policy(POP)

# ---------------------------------------------------------------------------
# Self-update (script mode)
# ---------------------------------------------------------------------------

# Replaces this file (and a sibling Findocx.cmake when present) with a
# released version, verified against the release SHA256SUMS. Only reachable
# via `cmake -P ocx.cmake` (guard below) - never during a configure. Knobs:
# OCX_SELF_UPDATE_VERSION (tag; default: latest via the GitHub API) and
# OCX_SELF_UPDATE_URL (mirror base; requires an explicit version).
function(__ocx_self_update)
  set(tag "")
  if(DEFINED OCX_SELF_UPDATE_VERSION AND NOT "${OCX_SELF_UPDATE_VERSION}" STREQUAL "")
    set(tag "${OCX_SELF_UPDATE_VERSION}")
    if(NOT tag MATCHES "^v")
      set(tag "v${tag}")
    endif()
  elseif(DEFINED OCX_SELF_UPDATE_URL AND NOT "${OCX_SELF_UPDATE_URL}" STREQUAL "")
    message(FATAL_ERROR
      "find_ocx: OCX_SELF_UPDATE_URL is set but OCX_SELF_UPDATE_VERSION is "
      "not - a mirror cannot serve the GitHub releases API, pass the tag "
      "explicitly (-DOCX_SELF_UPDATE_VERSION=vX.Y.Z)")
  endif()

  # Sibling temp dir: same filesystem, so the final file(RENAME) is atomic.
  set(tmp "${CMAKE_CURRENT_LIST_DIR}/.ocx-self-update-tmp")
  file(REMOVE_RECURSE "${tmp}")

  if(tag STREQUAL "")
    file(DOWNLOAD "https://api.github.com/repos/ocx-sh/find_ocx/releases/latest"
      "${tmp}/latest.json" STATUS status)
    list(GET status 0 status_code)
    if(NOT status_code EQUAL 0)
      list(GET status 1 status_msg)
      file(REMOVE_RECURSE "${tmp}")
      message(FATAL_ERROR
        "find_ocx: failed to discover the latest release from the GitHub "
        "API: ${status_msg}\n"
        "hint: pass -DOCX_SELF_UPDATE_VERSION=vX.Y.Z (plus "
        "-DOCX_SELF_UPDATE_URL=<mirror> on restricted networks)")
    endif()
    file(READ "${tmp}/latest.json" api_json)
    string(JSON tag GET "${api_json}" tag_name)
  endif()

  set(base "https://github.com/ocx-sh/find_ocx/releases/download")
  if(DEFINED OCX_SELF_UPDATE_URL AND NOT "${OCX_SELF_UPDATE_URL}" STREQUAL "")
    string(REGEX REPLACE "/+$" "" base "${OCX_SELF_UPDATE_URL}")
  endif()

  file(DOWNLOAD "${base}/${tag}/SHA256SUMS" "${tmp}/SHA256SUMS" STATUS status)
  list(GET status 0 status_code)
  if(NOT status_code EQUAL 0)
    list(GET status 1 status_msg)
    file(REMOVE_RECURSE "${tmp}")
    message(FATAL_ERROR
      "find_ocx: failed to fetch ${base}/${tag}/SHA256SUMS: ${status_msg}")
  endif()

  file(READ "${tmp}/SHA256SUMS" sums)
  set(module_sha "")
  set(find_sha "")
  string(REGEX REPLACE "\r?\n" ";" sum_lines "${sums}")
  foreach(line IN LISTS sum_lines)
    if(line MATCHES "^([0-9a-f]+)[ \t*]+(.+)$")
      if(CMAKE_MATCH_2 STREQUAL "ocx.cmake")
        set(module_sha "${CMAKE_MATCH_1}")
      elseif(CMAKE_MATCH_2 STREQUAL "Findocx.cmake")
        set(find_sha "${CMAKE_MATCH_1}")
      endif()
    endif()
  endforeach()
  if(module_sha STREQUAL "" OR find_sha STREQUAL "")
    file(REMOVE_RECURSE "${tmp}")
    message(FATAL_ERROR
      "find_ocx: ${base}/${tag}/SHA256SUMS lacks hashes for ocx.cmake and "
      "Findocx.cmake - not a find_ocx release?")
  endif()

  # Both-or-neither: nothing is renamed until both verified downloads exist.
  set(names ocx.cmake Findocx.cmake)
  set(shas "${module_sha}" "${find_sha}")
  foreach(name sha IN ZIP_LISTS names shas)
    file(DOWNLOAD "${base}/${tag}/${name}" "${tmp}/${name}"
      EXPECTED_HASH SHA256=${sha} STATUS status)
    list(GET status 0 status_code)
    if(NOT status_code EQUAL 0)
      list(GET status 1 status_msg)
      file(REMOVE_RECURSE "${tmp}")
      message(FATAL_ERROR
        "find_ocx: download of ${base}/${tag}/${name} failed: ${status_msg}")
    endif()
  endforeach()

  file(READ "${tmp}/ocx.cmake" new_content)
  set(new_version "unknown")
  if(new_content MATCHES "__OCX_MODULE_VERSION \"([^\"]+)\"")
    set(new_version "${CMAKE_MATCH_1}")
  endif()
  # No downgrade refusal: an explicit version is the operator's choice
  # (rollbacks are legitimate); the direction is visible in this line.
  message(STATUS "find_ocx: ${__OCX_MODULE_VERSION} -> ${new_version} (${tag})")

  # Replacing the running script is safe: CMake parses the whole listfile
  # before executing it.
  file(RENAME "${tmp}/ocx.cmake" "${CMAKE_CURRENT_LIST_FILE}")
  set(findocx "${CMAKE_CURRENT_LIST_DIR}/Findocx.cmake")
  if(EXISTS "${findocx}")
    file(RENAME "${tmp}/Findocx.cmake" "${findocx}")
  else()
    message(STATUS
      "find_ocx: no Findocx.cmake next to this file - skipped "
      "(ocx.cmake-only vendoring is supported)")
  endif()
  file(REMOVE_RECURSE "${tmp}")
endfunction()

# `cmake -P ocx.cmake` runs the self-update; `include(ocx)` from another
# script keeps CMAKE_SCRIPT_MODE_FILE pointing at the outer script, so a
# plain include never triggers it.
if(CMAKE_SCRIPT_MODE_FILE AND CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
  __ocx_self_update()
endif()
