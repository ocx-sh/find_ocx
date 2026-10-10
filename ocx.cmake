# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

#[=[.rst:
ocx
---

Overview
^^^^^^^^

CMake support for `OCX <https://ocx.sh>`_, the OCI-backed package manager.
The module installs a pinned ``ocx`` CLI and provisions tools through it.
It never re-implements OCX internals in CMake.
All resolution goes through the ``ocx`` binary, so the durable contracts are the ``ocx.lock`` digests and the OCI manifests.

Vendor ``ocx.cmake`` together with ``Findocx.cmake`` into your project, for example into ``cmake/``.
Include the module after ``project()``.

.. versionchanged:: 0.4
  The module requires CMake 3.25 or later.
  Release 0.3 accepted CMake 3.19.

.. code-block:: cmake

  cmake_minimum_required(VERSION 3.25...4.4)
  project(hello_jq LANGUAGES NONE)

  list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
  include(ocx)

  ocx_project(NAME TOOLS BINS jq)

  add_custom_target(show_jq ALL COMMAND ${OCX_TOOLS_RUN} jq --version VERBATIM)

The project is ``examples/tutorial/CMakeLists.txt``, built by the ``tutorial/first-configure`` cast test.

Synopsis
^^^^^^^^

.. parsed-literal::

  Install the CLI
    `ocx_bootstrap`_([VERSION <version>] [TRIPLE <target-triple>] [DIST_MANIFEST <dist.json>])
    `ocx_self_update`_()

  Provision tools
    `ocx_project`_([NAME <name>] [TOML <ocx.toml>] [LOCK <ocx.lock>] [GROUPS <group>...] [BINS <tool>...] [...])
    `ocx_package`_(NAME <name> PACKAGE <package> [BINS <tool>...] [...])

  Freeze tag resolution
    `ocx_index`_(`FIND`_ [REQUIRED])
    `ocx_index`_(`UPDATE_COMMAND`_ <out-var> [INDEX <dir>] [PACKAGES <ref>...])

  Set the verification policy
    `ocx_policy`_([ALLOW_UNVERIFIED] [ALLOW_YANKED] [SIGSTORE_TRUSTED_ROOT <file>])

Find the CLI
^^^^^^^^^^^^

``include(ocx)`` is passive.
It only defines the commands and snapshots the ``OCX_*`` variables from the environment.
The first provisioning call resolves the CLI.
That call is :command:`ocx_project`, :command:`ocx_package` or an explicit :command:`ocx_bootstrap`.

The module takes ``OCX_EXECUTABLE`` when it is set, else an ``ocx`` on ``PATH``, else the pinned CLI.
It downloads the pinned CLI, verified by sha256, into the per-machine cache.

:variable:`OCX_BOOTSTRAP` changes this order.
``ALWAYS`` skips the ``PATH`` search, so every machine runs the identical pinned binary.
``OFF`` forbids the implicit download.
An explicit :command:`ocx_bootstrap` call always provisions the pin.

Reproducible resolution
^^^^^^^^^^^^^^^^^^^^^^^

Resolution is reproducible first.
A floating tag resolves through a committed index snapshot or through digest pins.
The snapshot is the nearest ``.ocx/`` directory, discovered the way ``ocx.toml`` is.
Create it with ``ocx --index .ocx index update <package>``.
With neither a snapshot nor a pin, the configure fails.

:variable:`OCX_ALLOW_FLOATING` is the explicit escape hatch.
:command:`ocx_index` finds and refreshes a snapshot.

Trust and mirrors
^^^^^^^^^^^^^^^^^

The ``sha256`` column of the dist.json snapshot embedded in ``ocx.cmake`` makes a downloaded ocx CLI trustworthy.
The module checks every archive against its row before extraction, whichever URL served the bytes.
The script ``scripts/update_dist.py`` only ever adds rows to the embedded snapshot.

:variable:`OCX_INSTALL_DIST_URL` and the ``DIST_MANIFEST`` keyword of :command:`ocx_bootstrap` replace the snapshot.
The ``sha256`` column of that manifest is then the trust root, trusted as far as its transport.
A manifest file named ``<sha256>.json`` is the exception.
Its name carries its own digest, and the fetch is verified against it.

The ``SHA256SUMS`` file of a find_ocx release is the trust root of :command:`ocx_self_update`.
The GitHub releases API only names the latest tag.
Every download verifies TLS and is bounded by a timeout.

Anonymous read
^^^^^^^^^^^^^^

The variables :variable:`OCX_INSTALL_DIST_URL`, :variable:`OCX_INSTALL_MIRROR_URL` and :variable:`OCX_SELF_UPDATE_URL` name hosts that find_ocx reads without credentials.
A mirror must therefore allow anonymous read.
A mirror locked down later fails the download, and the failure looks like a network error.
#]=]

if(CMAKE_VERSION VERSION_LESS 3.25)
  message(FATAL_ERROR "find_ocx: ocx.cmake requires CMake >= 3.25; this is CMake ${CMAKE_VERSION}")
endif()

include_guard(GLOBAL)

# Function definitions capture the policy settings of their definition
# point: pin them to this module's baseline so includers that never ran
# cmake_minimum_required (script mode, exotic embeddings) get identical
# behavior. Balanced by cmake_policy(POP) after the last definition.
cmake_policy(PUSH)
cmake_policy(VERSION 3.25...4.4)
# cmake_parse_arguments() defines an empty single-value keyword (NEW) instead
# of dropping it (OLD): the empty-argument checks below depend on seeing it.
# CMP0174 exists from 3.31; the version range above already selects NEW there.
if(POLICY CMP0174)
  cmake_policy(SET CMP0174 NEW)
endif()

set(__OCX_MODULE_VERSION "0.3.0")

# include_guard(GLOBAL) is keyed on the file path, so a second vendored copy
# would run in full and silently win. Record the first copy; a second copy
# at another path with another version is a configure error.
get_filename_component(__ocx_this_file "${CMAKE_CURRENT_LIST_FILE}" REALPATH)
get_property(__ocx_loaded GLOBAL PROPERTY __OCX_MODULE_FILE SET)
if(__ocx_loaded)
  get_property(__ocx_loaded_file GLOBAL PROPERTY __OCX_MODULE_FILE)
  get_property(__ocx_loaded_version GLOBAL PROPERTY __OCX_MODULE_VERSION)
  if(
    NOT __ocx_loaded_file STREQUAL __ocx_this_file
    AND NOT __ocx_loaded_version STREQUAL __OCX_MODULE_VERSION
  )
    message(
      FATAL_ERROR
      "find_ocx: two copies of ocx.cmake with different versions are loaded: "
      "${__ocx_loaded_version} from ${__ocx_loaded_file} and "
      "${__OCX_MODULE_VERSION} from ${__ocx_this_file}\n"
      "hint: vendor one copy and point CMAKE_MODULE_PATH at it"
    )
  endif()
else()
  set_property(GLOBAL PROPERTY __OCX_MODULE_FILE "${__ocx_this_file}")
  set_property(GLOBAL PROPERTY __OCX_MODULE_VERSION "${__OCX_MODULE_VERSION}")
endif()
unset(__ocx_this_file)
unset(__ocx_loaded)
unset(__ocx_loaded_file)
unset(__ocx_loaded_version)

# The ocx CLI declares no stability for its command-line surface across
# versions; find_ocx therefore pins an exact version and is tested against
# exactly that version. Bump deliberately, together with the dist snapshot.
set(__OCX_PIN_VERSION "0.6.5")

# gersemi: off
# --- BEGIN OCX DIST SNAPSHOT (generated by scripts/update_dist.py - do not edit) ---
set(__OCX_DIST_JSON [=[
{
  "schema": 1,
  "latest": {"version":"0.6.5","channel":"stable"},
  "latest_next": null,
  "releases": [
    {"version":"0.6.5","channel":"stable","tag":"v0.6.5","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"270634b7d62067abbfed35331c29ee7b62db6b76e8f307bf5cd14b24c2297ce1","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.6.5","channel":"stable","tag":"v0.6.5","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"f36ea85695e9a546484fc1da5a7cc15b7ab7229fe4f5873b70381fee05901bcd","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.6.5","channel":"stable","tag":"v0.6.5","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"51d71a0465f699a3d2c7da6ef95d77314f77c16c35b978135de7e2a66a7c80e4","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.5","channel":"stable","tag":"v0.6.5","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"9b68d825a5e212877bda7f09f8987cbdced2f5e8361e84eebeb90ea541fb3f25","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.5","channel":"stable","tag":"v0.6.5","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"29e83c3b328acfcc78804517043778802ba2bcbf5b6ea6e8cd060f63adc0dda9","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.6.5","channel":"stable","tag":"v0.6.5","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"4cacead7e411929b0a3e655e150ca66323748674ba4d8546745e6638197d3e0a","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.6.5","channel":"stable","tag":"v0.6.5","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"f8b30fbfb1adec2c9281ed40960d562fcd9d51d39b06b8f65775b9de29505d14","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.5","channel":"stable","tag":"v0.6.5","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"bb4d306debca428fdc326ec587047c7efc3f3a2262b06eacfdaca46fa75a4dac","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.5/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.4","channel":"stable","tag":"v0.6.4","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"3e02302384813fb83158a148b3a441e6c9b8962ac281b6bd0f992b0cfd619109","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.4/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.6.4","channel":"stable","tag":"v0.6.4","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"cad09738310fa03238400c15a92922b1ad57129051c58fd155975f65798961cc","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.4/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.6.4","channel":"stable","tag":"v0.6.4","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"830b36177ebfd178cc9d71fe2c9fe12cd59f4b7cf45022677c27d6833eddd1d1","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.4/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.4","channel":"stable","tag":"v0.6.4","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"049a4df4a19c3f96d43fd797bd7b2fb3e056b43d9792d82078c34d8cbcedf606","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.4/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.4","channel":"stable","tag":"v0.6.4","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"81d33fa07aeb81a94d066fab026eeb74150727f998f61563151b1d4765ee90de","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.4/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.6.4","channel":"stable","tag":"v0.6.4","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"5ca96a1a697847fa4a5c04627d493b599dcf5d502118962d34b7cd09076a328e","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.4/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.6.4","channel":"stable","tag":"v0.6.4","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"5d82d97fac63a51896f32039c142dd2f1f99e00435c2ef526430b359acdd210e","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.4/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.4","channel":"stable","tag":"v0.6.4","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"b1499a9484f4ef3a156afe9fd0cd06c0eafc16bc16e483f4d9fb160b619369ad","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.4/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.3","channel":"stable","tag":"v0.6.3","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"c81ad35e4de88215ff2cc2439f5d10a24ed7ff9e24f7e65e640e8a5251a8ee62","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.3/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.6.3","channel":"stable","tag":"v0.6.3","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"e5788818f534496cdb325b0f93bbcf02179d757b38be44592c349998ba3589e1","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.3/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.6.3","channel":"stable","tag":"v0.6.3","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"dac7a578865a1659b6c8040bd79322bd30bce6577b23f9973dec9fc6022d5dda","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.3/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.3","channel":"stable","tag":"v0.6.3","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"ed3bea53f040e774d6b526852171f519c9a9553581e5839cb632ac66e0a29d89","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.3/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.3","channel":"stable","tag":"v0.6.3","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"69f28ee872da2b1bb606118bf5ba327fc4a613cc29830af5ce919c768141fd19","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.3/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.6.3","channel":"stable","tag":"v0.6.3","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"8fc92d97a4090a5a4b990e10019008c70b5dd09eb8eb9e99bad5deedb3750278","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.3/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.6.3","channel":"stable","tag":"v0.6.3","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"85ff0ea3046128f793344a1c4fde57b4444459844f28cd34651d0ddab17f7692","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.3/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.3","channel":"stable","tag":"v0.6.3","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"fa44d6b0f272e082ba166e30c3a9958f47a8510149c988e68dfa06b6d2acc70c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.3/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.2","channel":"stable","tag":"v0.6.2","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"7fd1dbcd62bbe301bd5fb9e2daaa8aee42c3a2233ca706fe679398aef7d92ca0","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.2/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.6.2","channel":"stable","tag":"v0.6.2","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"caf932dad7c08549df48093400391544cbf72220209a57014da438a7eb95f989","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.2/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.6.2","channel":"stable","tag":"v0.6.2","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"5a180faec59c3ddbd29ec5b6683d495298dfde8121b44e880d6b6a5fd422850d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.2/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.2","channel":"stable","tag":"v0.6.2","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"8b84c746b341d1d97b6ffd5ccdd9fb70d2c0bffc06101b0727faa5e028091aa7","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.2/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.2","channel":"stable","tag":"v0.6.2","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"9b906851f2fa310728325c6987520aa75a49921a18f8d5da5e5180dbdc304b32","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.2/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.6.2","channel":"stable","tag":"v0.6.2","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"05379915bd5b10d39ec15ec253f600809d222c472d13e7e2b231711448040324","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.2/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.6.2","channel":"stable","tag":"v0.6.2","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"cbef6c1e44d9ef7b1a74e4d5dc8a5613296ac11ebdfeac32d2251b0d32c084b2","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.2/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.2","channel":"stable","tag":"v0.6.2","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"33ffef16272bbae6a4d96f4163524f38a549d920b6e6d0a67e2d8a21714ef164","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.2/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.1","channel":"stable","tag":"v0.6.1","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"359674f32c57ccafc0856901e0fa6ae9ce39af09aab9aa29f4b981034f8d7261","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.1/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.6.1","channel":"stable","tag":"v0.6.1","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"929d76cfe78d6dc33519cc17f3569fce99fc1f8fc443c54062e5a6e05277d567","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.1/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.6.1","channel":"stable","tag":"v0.6.1","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"3d41fcd46bf03f5d1018b01da2fb81338682d29ff4b3070e2b5cedb6f73f1ebe","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.1/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.1","channel":"stable","tag":"v0.6.1","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"dc54556c26d762fcf3933989c165cc051c14355302253fab17464a54e0fe3c0d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.1/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.1","channel":"stable","tag":"v0.6.1","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"8ac83edb722ed8fd36d7223896fd9999e8d5208fa155f5cc056b836ff24dcc0a","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.1/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.6.1","channel":"stable","tag":"v0.6.1","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"00a1e3fda8ffcce748db45a593072a97714e75477497e262fb355e30b70114cc","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.1/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.6.1","channel":"stable","tag":"v0.6.1","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"dac58e7ceb87c9f4c8c0880d39adca9e866ab4edea99de29fb4ea338cb859f97","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.1/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.1","channel":"stable","tag":"v0.6.1","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"b970173d7705583bee63b35f32470d56be0199dfac0cccae1f5258c436ccf991","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.1/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.0","channel":"stable","tag":"v0.6.0","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"e48ad96a09762943abfb0fa66f388ac62eef8071f70c55654f3e7c9735580eae","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.0/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.6.0","channel":"stable","tag":"v0.6.0","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"635d48eee02085e039f199ae28ad8573de9dcb7d2e27c99a1d10fcc0611ae7e6","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.0/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.6.0","channel":"stable","tag":"v0.6.0","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"0805a218fee7ad060bc5ffa8bcc20e9bff87881c686b1b42873c302586c51a94","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.0/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.0","channel":"stable","tag":"v0.6.0","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"e8e4d7da3672a635fbd65b74c26af70856f1f444159603898cb90d95ddd33c5c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.0/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.6.0","channel":"stable","tag":"v0.6.0","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"8d587b04f4628519ef95111a92cdf757918aa54218b7be68b781ee85fa8313f8","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.0/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.6.0","channel":"stable","tag":"v0.6.0","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"d21d11180f294b3e2127864d0d5c2eaf7d2ef023c0ac47577b1c94f2ba86f87b","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.0/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.6.0","channel":"stable","tag":"v0.6.0","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"852b31caf71a07e2e84397c05c1016b3fed9388bae5da7b9c4651f7f41e7a3f4","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.0/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.6.0","channel":"stable","tag":"v0.6.0","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"b23eeec96e8ed1f057e24c2d6acb5eac07b0c25427349beb8582204b1b37f0ca","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.0/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.8","channel":"stable","tag":"v0.5.8","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"584c5aeaeeec22acfa8143eb341edbe2f110007c931036badb86d0472a2ebf81","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.8/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.5.8","channel":"stable","tag":"v0.5.8","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"48ec2e5fb65148641fa2c021e26956e92f8ddfa20ee6411f90e8780f2e1a6774","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.8/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.5.8","channel":"stable","tag":"v0.5.8","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"2e6cc2ab4b740d70a9e62c179a41b6e9436cffddc3449e80ea191103cb884071","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.8/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.8","channel":"stable","tag":"v0.5.8","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"5a7a3e8c600d81d930f377d6f195c1ec59a451f27a7e2c3826bfe8a2c00ab63d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.8/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.8","channel":"stable","tag":"v0.5.8","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"f354984a7346c7b718619ef85248e44d1c87fdfcc334303f6a188be0c892193c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.8/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.5.8","channel":"stable","tag":"v0.5.8","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"47c360a0531de99a7f0df7baf63cfd9e0c58b52f664e7303f522edb9a489c096","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.8/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.5.8","channel":"stable","tag":"v0.5.8","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"55f3a3ed63703e0f5edf4e73e4715fbe73808bf0396d1d69e08e7af83eb5b059","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.8/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.8","channel":"stable","tag":"v0.5.8","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"240c7d21945c5de53c84197f2eed325eb4751e5eecdf73a977a612ee1f8e52f8","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.8/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.7","channel":"stable","tag":"v0.5.7","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"277f0ddd6a32ce239fc7586ce7882f2d2e814687cb9ed3254450f612378630c9","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.7/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.5.7","channel":"stable","tag":"v0.5.7","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"38a70cf6eb6b4f7e42e8342afe097e76eaf3dbfbbb80b3940d0264ec7c2cb6c9","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.7/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.5.7","channel":"stable","tag":"v0.5.7","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"f55b99339f9420b2a31a882787fb901a9850bd7ec571d57926ff45d2efa27981","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.7/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.7","channel":"stable","tag":"v0.5.7","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"e34e3b496dad35c1c098764650bfc927c98bcbeb23d95a955f02f0b0201bd96b","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.7/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.7","channel":"stable","tag":"v0.5.7","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"e13c2acf57c8369c9697295ab22398e193b7cdfdcdab93e9ee6b875b8ff05132","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.7/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.5.7","channel":"stable","tag":"v0.5.7","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"ce623da3b04103f037a618190cc762b1a541741954f0ee9a0c11e8e71c61c620","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.7/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.5.7","channel":"stable","tag":"v0.5.7","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"13267ea53db9e228c179269773ecd238efdb059a65e969fa51f3f7011308b24d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.7/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.7","channel":"stable","tag":"v0.5.7","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"9db306ae2ae7a1641fd41bb42f149ba0d3b8a1b02d485f2dace11755f829f88a","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.7/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.6","channel":"stable","tag":"v0.5.6","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"97816072f5313354413e46a96fc5f2d179630fa46fed5f52abf92f05a5e5d69b","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.6/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.5.6","channel":"stable","tag":"v0.5.6","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"60707e409984039ac7ec8d441b315c66b31b264b1628f8a0a65d8d98d1b5cc03","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.6/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.5.6","channel":"stable","tag":"v0.5.6","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"6d49020c5dd130e7cf4e9506441a3e27b3a6ffe79a7cb77a59e9acd6af47ea3e","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.6/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.6","channel":"stable","tag":"v0.5.6","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"4c216f41661edbb7d67f93d075d99b8510f3b820861fb42635dc64e961c95dce","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.6/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.6","channel":"stable","tag":"v0.5.6","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"1c723532a322372fa55c0b5ac6e2894fdff3c1222c2f0370d7e77eaa4f3bb2f0","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.6/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.5.6","channel":"stable","tag":"v0.5.6","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"6af777ac0195959e88fe0539c1439fa3f7b506d2f472023c8b35c4ba4a7a2e30","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.6/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.5.6","channel":"stable","tag":"v0.5.6","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"f87c83ddcc78807bf629ce3d4a02e2e815672483765c1469a4345a30a84bfbfa","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.6/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.6","channel":"stable","tag":"v0.5.6","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"0e2f930e25a041d16c080a40387d455bfe7da0e5d8c54db42b4793fe5dd9ad34","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.6/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.5","channel":"stable","tag":"v0.5.5","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"69e9ea7423186e87ef6d5597d05661da0b548fe99742e5dfec4aa5515aa3345c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.5/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.5.5","channel":"stable","tag":"v0.5.5","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"4442e6475e8c47ef936a040a223dd0671e5ba6df023f1e3d475286c80131ba07","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.5/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.5.5","channel":"stable","tag":"v0.5.5","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"3acb44c57b5e00291af46b96240557acc0f88c51343de3af50719eab2f9a8ade","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.5/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.5","channel":"stable","tag":"v0.5.5","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"5d8b3c141dab4eb0e4e0e259f9bdd9ce950ae775a3d83c4541f20f07069783ec","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.5/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.5","channel":"stable","tag":"v0.5.5","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"1d8cbbea55d180b49b98e526cc1252de84bfd867e782d9de2f64005e481474b6","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.5/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.5.5","channel":"stable","tag":"v0.5.5","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"5affef0f4cea70de94cb4e6bcd6e26600cd1458cc36ddc369c13d6cc8f97e185","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.5/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.5.5","channel":"stable","tag":"v0.5.5","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"10d9b4262f56003ab24c56b998069394f02d6a52c7e251dc7491b781a5a2778f","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.5/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.5","channel":"stable","tag":"v0.5.5","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"f0c5538c18fbb8c8d3e8c7149325420651fd5da65dd9c7cc1f552883b598d0cd","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.5/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.4","channel":"stable","tag":"v0.5.4","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"bdad6a3f596da5bad915e3c2de3b9d4d16c02fbff8864c3aac78f05c0f806d65","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.4/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.5.4","channel":"stable","tag":"v0.5.4","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"cdeb933c57db2c669d47a178ffce9c6db8ffef5edb941df802e0d552f6e754b5","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.4/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.5.4","channel":"stable","tag":"v0.5.4","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"d240d9ee0b8618225ca1641badc42b342fc3f5ddd2afb1c9739f3483312c089d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.4/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.4","channel":"stable","tag":"v0.5.4","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"7fdae5d8f5ea1ceb5f935e30f9ea6c1aaf2e2168cecc2781ec81a0e76fe05329","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.4/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.4","channel":"stable","tag":"v0.5.4","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"89a34f517ffbfe24b1db273691d9359470ed41a463c21d6d0c7f2914cb408552","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.4/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.5.4","channel":"stable","tag":"v0.5.4","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"da31fe2a733902abe92c2e2abd0b2090054ad938914d526674920c23d8eee14d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.4/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.5.4","channel":"stable","tag":"v0.5.4","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"807756334c00117637250bbfefaa8762f7a14b3f080f70e1ba027fb7b191caed","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.4/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.4","channel":"stable","tag":"v0.5.4","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"f0698cef846cfd4c95a058fe1971eee59ec384a785178844992dcb11a8a02149","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.4/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.3","channel":"stable","tag":"v0.5.3","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"449ba9f3451b61b8fad40c31c93f3bdbac660f3bf0e4001cbd71497be49a296f","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.3/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.5.3","channel":"stable","tag":"v0.5.3","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"310c491be8295be2d1dcd9488ce50db0cbb9cc0ef8dd294ad0b59581edfbe778","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.3/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.5.3","channel":"stable","tag":"v0.5.3","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"cd0abebe71f521f0665974d6b90badc0cc556c550942bc338b4c06ce620280d4","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.3/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.3","channel":"stable","tag":"v0.5.3","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"c6841281d6b26de57a5e6775d9cf610e4bbb691e362ee112b87b4505ce6c1a8d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.3/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.3","channel":"stable","tag":"v0.5.3","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"33d2ac6224aff4e917fad0c042f7977ee643732acc3f543114f2cdfc65dd35ca","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.3/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.5.3","channel":"stable","tag":"v0.5.3","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"992733a4d1d6d7bafb0183d1afe2803c10439cdddca78eaa710e33fdb6a7a029","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.3/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.5.3","channel":"stable","tag":"v0.5.3","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"ae3f9e4a42960b50caf15427bf396876646e93b0b7772135e950dcb4192bc971","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.3/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.3","channel":"stable","tag":"v0.5.3","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"f3679ebb1257ac8d4e3fefe9ac171c4ea27561b59bac305a6d30460815460683","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.3/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.2","channel":"stable","tag":"v0.5.2","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"dd912b61bbf66fc15be130a64efd69e7f75a739ac94d26eec557a171badce720","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.2/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.5.2","channel":"stable","tag":"v0.5.2","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"69c9da4c61a2a8aea4246b1ae2cc00d31bf4d606599dacb9de0c918ddf9e4494","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.2/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.5.2","channel":"stable","tag":"v0.5.2","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"3cda34fd009b040743867fadba967fe0a50bb98f5b0cb3b8b707d314594f464b","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.2/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.2","channel":"stable","tag":"v0.5.2","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"c46e64d93de932309ef225f59ee099754afda333e11e6b8761cb1f62be120329","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.2/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.2","channel":"stable","tag":"v0.5.2","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"700c9e96d7ba31e3ba9ced85f50ce54478c983dc636a2353fcd2bf7b942d11c7","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.2/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.5.2","channel":"stable","tag":"v0.5.2","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"4b77098cc4d72c0ccb5cac20985087f51075335f5b766c53fc1585d4f0d4afc3","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.2/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.5.2","channel":"stable","tag":"v0.5.2","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"a903042ce878bf4453f807550f62ec5e94cd1ba2795e8b5c0f6e8ea881d355c9","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.2/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.2","channel":"stable","tag":"v0.5.2","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"d89deb20843efb0acad266f102f50f8b375a36ec675919d96e6b593719b79b55","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.2/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.1","channel":"stable","tag":"v0.5.1","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"ccb0c3026dfa516ce12d353a2b048ab072328b1600b447e1b2544de97c0d8542","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.1/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.5.1","channel":"stable","tag":"v0.5.1","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"ed864a2c90aaa461954eb259fbfdb5dff9bbba42bd3e955c510ac09b10ab36fc","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.1/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.5.1","channel":"stable","tag":"v0.5.1","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"270b7bf22ab7b6be1f4069a809bf785eb0195782a1c594a8243013c386d2749d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.1/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.1","channel":"stable","tag":"v0.5.1","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"caa548b391abf5f024313becff945749c373bb9a2ed3594f83023a5249fda719","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.1/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.1","channel":"stable","tag":"v0.5.1","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"aa9bc3965e43044ebba5203a94b4aca93df733cbb023aef7641507a5f52bf2b3","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.1/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.5.1","channel":"stable","tag":"v0.5.1","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"1de15df94b158e13d038048d15f541af22acda9c027b3260bdaf0131cc1e6dc3","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.1/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.5.1","channel":"stable","tag":"v0.5.1","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"f426bfcf6b6a52622a593eb41e869d11b45bceffafec5f17193c0921b8ca472b","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.1/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.1","channel":"stable","tag":"v0.5.1","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"927364fe4a986ef4fb9de872e383dc242bc8085cfc56c219d73fc89f968e19bc","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.1/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.0","channel":"stable","tag":"v0.5.0","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"dd3870dca0291a5f8b8938a809b61326de39c3c457f83e1f290a6d65e633ab65","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.0/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.5.0","channel":"stable","tag":"v0.5.0","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"812b9e45048ab8e0413c500d3b97bf653f5058a158a9e4c607d1a208967759f7","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.0/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.5.0","channel":"stable","tag":"v0.5.0","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"f0b3101da192365f568acfa7c4bf01fa4ead2625c67181b2af9c996ae23d64b2","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.0/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.0","channel":"stable","tag":"v0.5.0","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"ec6fd104c8d95047ffd7fba81e5e7db552239948f12030ce1ef77247651a7e9c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.0/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.5.0","channel":"stable","tag":"v0.5.0","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"3133a8c82b9c7aab1984f4ea617e06f5bf6a6c662ef3eb4a8613f60e6d35e508","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.0/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.5.0","channel":"stable","tag":"v0.5.0","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"49ca03278afc9bb79ea52104c1a35bf0f4fc9900ea8e9b8b2ccd2c73c4d73884","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.0/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.5.0","channel":"stable","tag":"v0.5.0","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"949b76a0f4765131bc5ea135ceb8ce48fdc52b7fc59a48a10fb61faaef9df3cc","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.0/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.5.0","channel":"stable","tag":"v0.5.0","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"a233e07c9f24d3393495c948878fe3f7eab723007ded66f4638788554b3a8133","url":"https://github.com/ocx-sh/ocx/releases/download/v0.5.0/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.4.3","channel":"stable","tag":"v0.4.3","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.gz","sha256":"472ee017adcd82f09562aec042f72e8c4bd58b99543db751a28cfa9b3d5ebcfe","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.3/ocx-aarch64-apple-darwin.tar.gz"},
    {"version":"0.4.3","channel":"stable","tag":"v0.4.3","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"743445a6af87c31644b3534f0fa38a04c5c222493eb4200979cb2745e17a3534","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.3/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.4.3","channel":"stable","tag":"v0.4.3","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.gz","sha256":"3daa14d3b594895a2416dc7757ac91d83983862b64268c99cafcc09cc1b3d9e0","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.3/ocx-aarch64-unknown-linux-gnu.tar.gz"},
    {"version":"0.4.3","channel":"stable","tag":"v0.4.3","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.gz","sha256":"8086b1df8916c9dbea100e7f9468b64c7523c8dbe83a134317fb8f2489c1caf6","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.3/ocx-aarch64-unknown-linux-musl.tar.gz"},
    {"version":"0.4.3","channel":"stable","tag":"v0.4.3","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.gz","sha256":"c4173d36225e1e0ab10d82e196f97f0381e304f79bec2b3d90bc90d4c16f25c6","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.3/ocx-x86_64-apple-darwin.tar.gz"},
    {"version":"0.4.3","channel":"stable","tag":"v0.4.3","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"c566e5c0ef2539aae6f032dfccbd819abf55156be1618c7748da29554e5410ce","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.3/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.4.3","channel":"stable","tag":"v0.4.3","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.gz","sha256":"48c0df49d9eb2ebc4d711a2a3a2278bce1f857c7e208c3763db7e54ad0b19310","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.3/ocx-x86_64-unknown-linux-gnu.tar.gz"},
    {"version":"0.4.3","channel":"stable","tag":"v0.4.3","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"cfdf9c7a90af9d8706ce1cf3a80bc1147caf6371cff26a39b8216654b57b61ac","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.3/ocx-x86_64-unknown-linux-musl.tar.gz"},
    {"version":"0.4.2","channel":"stable","tag":"v0.4.2","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"88128f8dd68d21e6de171d89ba21a19b4819787a5233431cb786c778f7a6d897","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.2/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.4.2","channel":"stable","tag":"v0.4.2","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"8b281d6e6d05c7a7fbf61ef6a947fd9b42dc066143e2bd6fa58070f77d25170c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.2/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.4.2","channel":"stable","tag":"v0.4.2","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"0bdfc279c9f13bb5408d5a46cbe8364850b747b4b9d8d8493dd66e7d422f3944","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.2/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.4.2","channel":"stable","tag":"v0.4.2","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"1e4f554d4cc62fadb2da316fb84c6b389fe219f3926029501c1bcde5857f089d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.2/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.4.2","channel":"stable","tag":"v0.4.2","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"09141e70293ab2ffef779ba71fad29e66598c3c714f95e0685be969084b09fc2","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.2/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.4.2","channel":"stable","tag":"v0.4.2","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"138d21e9d95c0e796e31f45b52c70fd18c687de8e964bac32a98d2aa57f51975","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.2/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.4.2","channel":"stable","tag":"v0.4.2","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"80994d095654c5a4b0f904e8706f694fefaf8fdb4b1db2cc335013cae0b18382","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.2/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.4.2","channel":"stable","tag":"v0.4.2","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"393ca679fdc6dc2a7fb82a42eb4d9bceff8355026ec11cbe54d792af15214971","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.2/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.4.1","channel":"stable","tag":"v0.4.1","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"5bb90bb2e32f5994200d902e7723b127b9e1eb306e156e0bfa90451a44bae753","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.1/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.4.1","channel":"stable","tag":"v0.4.1","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"f6130fbddab8605fb1be6a0cda26f25b7800db5b2ffdb9e7e98de5f1a1ce39db","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.1/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.4.1","channel":"stable","tag":"v0.4.1","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"4d2cbb3630fbd9fc91a2ed183d63efa0ab06d00dd26c6b435bc77c4632c2026a","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.1/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.4.1","channel":"stable","tag":"v0.4.1","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"2fdb907dcd15dc09a530f0bff714fb184c3166eade42fc29cb3c74f0e0bf6f77","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.1/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.4.1","channel":"stable","tag":"v0.4.1","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"a78493c77a11051bd59d07ed779a417e16a4176935c5f302b5b6a39564784f91","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.1/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.4.1","channel":"stable","tag":"v0.4.1","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"19a6f7c54a908bee76cb9aa02d7063b5d499e9ada2e2bf78d6f7e0d5f527f790","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.1/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.4.1","channel":"stable","tag":"v0.4.1","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"62a8ba1bdc65dfec8f657b3a249b36b47cd6f1bb7796c64121a5eb1c248636bb","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.1/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.4.1","channel":"stable","tag":"v0.4.1","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"5c6d58cbd897a1409a593fc99e5646bc6eb041cf86d099a49759ce46a89924e3","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.1/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.4.0","channel":"stable","tag":"v0.4.0","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"04f7b2b6a7e71823a7c7f129ab207814dd11a4f867997478f667b622006e99ba","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.0/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.4.0","channel":"stable","tag":"v0.4.0","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"5d03bd79acb25c9f538d4fff07f90ae2fc9d218cc204a77d67e626aed79e9b3f","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.0/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.4.0","channel":"stable","tag":"v0.4.0","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"de722ae2194c4b1f14f804be8188e7b291a524628c6bf1b9c5ba6cacf4930047","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.0/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.4.0","channel":"stable","tag":"v0.4.0","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"d3f7a6a05d2e0359a01e39d09ca42f9ffb663b3f39bf448ded8de762f82966b4","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.0/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.4.0","channel":"stable","tag":"v0.4.0","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"b84039d5a31bf2f3d9f5362911ceda59c8ba45cd08b82f319aa783a53262c74c","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.0/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.4.0","channel":"stable","tag":"v0.4.0","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"7cb5cffbcff28837a4b4465e8e81b56b9bb0a7fbd05db57c471f0fa4ce1b3ac9","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.0/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.4.0","channel":"stable","tag":"v0.4.0","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"4ee6fc92243b8ce2a4910a10e730cb3b167e095fd408e5b31751edf7e2b623ea","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.0/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.4.0","channel":"stable","tag":"v0.4.0","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"de8619869aee4e4709246483f011c70d9a107add27e342c53347f3f769e2f4f9","url":"https://github.com/ocx-sh/ocx/releases/download/v0.4.0/ocx-x86_64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.12","channel":"stable","tag":"v0.3.12","target":"aarch64-apple-darwin","filename":"ocx-aarch64-apple-darwin.tar.xz","sha256":"17b0370da1a1b64a60ea457180cf1317a24c531d3880449dfc3151bf2859a32d","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.12/ocx-aarch64-apple-darwin.tar.xz"},
    {"version":"0.3.12","channel":"stable","tag":"v0.3.12","target":"aarch64-pc-windows-msvc","filename":"ocx-aarch64-pc-windows-msvc.zip","sha256":"cbf7c4a73286a734b57b63e28a14777495ca4ddf0882bac2f8f261dffbb7a82f","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.12/ocx-aarch64-pc-windows-msvc.zip"},
    {"version":"0.3.12","channel":"stable","tag":"v0.3.12","target":"aarch64-unknown-linux-gnu","filename":"ocx-aarch64-unknown-linux-gnu.tar.xz","sha256":"b7d530f8ce6976596888a7127fef06506a3cae6657edcd62272429c7cc198933","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.12/ocx-aarch64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.12","channel":"stable","tag":"v0.3.12","target":"aarch64-unknown-linux-musl","filename":"ocx-aarch64-unknown-linux-musl.tar.xz","sha256":"7bf3f9a6dcdac2b6135995ea5c4e3af3615dc8615924c7993b717f3a2d31de8a","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.12/ocx-aarch64-unknown-linux-musl.tar.xz"},
    {"version":"0.3.12","channel":"stable","tag":"v0.3.12","target":"x86_64-apple-darwin","filename":"ocx-x86_64-apple-darwin.tar.xz","sha256":"4489e87fe0bef540511b50c744986c443150ef7dda87a196d81940e0e03645c4","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.12/ocx-x86_64-apple-darwin.tar.xz"},
    {"version":"0.3.12","channel":"stable","tag":"v0.3.12","target":"x86_64-pc-windows-msvc","filename":"ocx-x86_64-pc-windows-msvc.zip","sha256":"a1c3d807073163ee3b5024aab58990a46b72897a721a11901798d9980418ab16","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.12/ocx-x86_64-pc-windows-msvc.zip"},
    {"version":"0.3.12","channel":"stable","tag":"v0.3.12","target":"x86_64-unknown-linux-gnu","filename":"ocx-x86_64-unknown-linux-gnu.tar.xz","sha256":"392752684726968d28222e810af09b418e6181a42e7615611a89fa7a531f6aef","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.12/ocx-x86_64-unknown-linux-gnu.tar.xz"},
    {"version":"0.3.12","channel":"stable","tag":"v0.3.12","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.xz","sha256":"4603f2afd871b3d7b7661362e6462a671019ea8b5daa3eb9d66a21a0a63ba911","url":"https://github.com/ocx-sh/ocx/releases/download/v0.3.12/ocx-x86_64-unknown-linux-musl.tar.xz"},
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
# gersemi: on

# The plain variables above live in the scope that included this file: a
# function that includes it, or a subdirectory, takes them away again. The
# commands read these GLOBAL copies instead.
set_property(GLOBAL PROPERTY __OCX_PIN_VERSION "${__OCX_PIN_VERSION}")
set_property(GLOBAL PROPERTY __OCX_DIST_JSON "${__OCX_DIST_JSON}")

# ---------------------------------------------------------------------------
# Environment classes
# ---------------------------------------------------------------------------

#[=[.rst:
Variables
---------

Setting a variable
^^^^^^^^^^^^^^^^^^

The plain ``OCX_*`` variables below configure mirrors and behavior.
Each one follows the snapshot pattern.
A variable that is unset in CMake but set in the environment at the first configure is copied into the cache.
The cached value then stays for the build directory.
Override it with ``-DVAR=...`` and clear it with ``-DVAR=``.

.. variable:: OCX_EXECUTABLE

  Path of the ocx CLI that runs every command.
  The environment value is snapshotted like every other variable, so CI needs no ``-D``.
  ``export OCX_EXECUTABLE=$(which ocx)`` is enough.
  A path that does not exist is a configure error, and it never falls back to ``PATH``.
  An empty value, as in ``-DOCX_EXECUTABLE=``, counts as unset.

  When the variable is unset, the first provisioning call looks on ``PATH`` and then bootstraps the pinned CLI.
  The module remembers a path that it chose itself and chooses again on every configure.
  A changed :variable:`OCX_INSTALL_VERSION`, a changed pin or ``OCX_BOOTSTRAP=ALWAYS`` therefore reaches an existing build directory.
  A path that you set stays as it is.

  The value must not contain ``;``, which a CMake list cannot carry.

.. variable:: OCX_INSTALL_DIST_URL

  URL of an ocx release manifest (dist.json) that replaces the snapshot embedded in ``ocx.cmake``.
  A manifest not named ``<sha256>.json`` is fetched unverified.
  The ``DIST_MANIFEST`` keyword of :command:`ocx_bootstrap` takes precedence over this variable.

  .. versionchanged:: 0.4
    A manifest named ``<sha256>.json`` is verified against that digest.

.. variable:: OCX_INSTALL_MIRROR_URL

  Base URL that rewrites the ocx binary download to ``<mirror>/<tag>/<filename>``.
  The manifest sha256 is still enforced, so a mirror can move bytes but cannot change them.

.. variable:: OCX_INSTALL_CA_BUNDLE

  Path of a PEM CA bundle that the CLI download trusts instead of the system store.
  Use it for a mirror behind a TLS-intercepting proxy.
  A relative path resolves against the top-level source directory.
  A path that is not a file is a configure error, checked on every configure that provisions or runs the CLI.

  The module passes the bundle as ``TLS_CAINFO`` to the manifest and archive downloads of :command:`ocx_bootstrap` and to :command:`ocx_self_update`.
  Every ocx call also receives it as ``OCX_EXTRA_CA_CERTS``, unless ``OCX_EXTRA_CA_CERTS`` is set.
  An empty ``-DOCX_EXTRA_CA_CERTS=`` counts as set and removes the variable.
  The setup.ocx.sh installer has the same variable.

  .. versionadded:: 0.4

.. variable:: OCX_INSTALL_VERSION

  ocx CLI version to bootstrap.
  The default is the version pinned by this find_ocx release.
  The setup.ocx.sh installer has the same variable.

.. variable:: OCX_BOOTSTRAP

  Policy for the implicit bootstrap of the first provisioning call when ``OCX_EXECUTABLE`` is not set.
  The values are the following, in any case.
  The CMake booleans count as ``ON`` and ``OFF``, and any other value is a configure error.

  ``ON``
    The default, also when the variable is unset or empty.
    Use an ``ocx`` found on ``PATH`` and bootstrap the pinned CLI when there is none.

  ``ALWAYS``
    Skip the ``PATH`` search, so every machine runs the identical pinned binary.
    Pair it with :variable:`OCX_INSTALL_VERSION`.

  ``OFF``
    Never download.
    ``OCX_EXECUTABLE`` or an ``ocx`` on ``PATH`` is required, and anything else is a configure error.
    Use it where configure-time downloads are forbidden.

  Inside ``Findocx.cmake`` the same variable opts in to the bootstrap fallback, because find modules discover by default.
  An empty value counts as unset there too, which means ``OFF``.

.. variable:: OCX_DEFAULT_PLATFORM

  Default ``PLATFORM`` for :command:`ocx_project` and :command:`ocx_package`.
  The value is one ocx platform such as ``linux/arm64``, and the empty default means the host.
  A ``;``-list is a configure error.
  Call the command once per platform under its own ``NAME`` instead.

.. variable:: OCX_INDEX

  Directory of the committed index snapshot that freezes tag resolution for every :command:`ocx_package` without an explicit ``INDEX``.
  When the variable is unset, each call discovers the nearest ``.ocx/`` directory between its calling directory and the last ``project()`` source directory.
  :command:`ocx_index` ``FIND`` runs that discovery once and locks the result into this variable.

  Clearing the variable with ``-DOCX_INDEX=`` neutralizes a value inherited from an outer ocx launcher.
  The project's own committed snapshot is still discovered.

.. variable:: OCX_ALLOW_FLOATING

  Reproducibility escape hatch.
  A floating tag with no index snapshot in effect and no digest pin is a configure error by default.
  ``ON`` downgrades the error to live resolution with a drift warning.
  Use it transiently, then pin the tag with an index snapshot or an ``@sha256:`` image index digest.

.. variable:: OCX_BOOTSTRAP_CACHE

  Cache directory for bootstrapped ocx binaries, where a relative path resolves against the top-level source directory.
  The default is per machine: ``%LOCALAPPDATA%/find_ocx`` on Windows, else ``$XDG_CACHE_HOME/find_ocx``, else ``~/.cache/find_ocx``, else ``<build>/_ocx/cache``.
  Point the variable into the workspace on CI runners where the home directory is unreliable, and restore it with the CI cache.
  The module copies a binary in atomically and runs a cached one once per configure.
  It downloads again a binary that does not run or reports another version.

.. variable:: OCX_PROJECT_FILE

  Default ``ocx.toml`` for :command:`ocx_project` when the call has no ``TOML`` argument.

.. variable:: OCX_PULL

  Forces eager materialization, as the ``PULL`` keyword does, for every :command:`ocx_project` and :command:`ocx_package` call.
  Use it in CI to fail fast and to warm caches.

.. variable:: OCX_REFRESH

  One-shot switch that bypasses the reconfigure memoization and runs ocx again.
  The module clears it at the end of the configure.

.. variable:: OCX_SELF_UPDATE_VERSION

  find_ocx release tag that :command:`ocx_self_update` installs, written ``vX.Y.Z``.
  The leading ``v`` is optional.
  The default is the latest release, found through the GitHub releases API.

.. variable:: OCX_SELF_UPDATE_URL

  Base URL that serves the find_ocx release files as ``<url>/<tag>/<filename>`` instead of GitHub.
  It has the same rewrite shape as :variable:`OCX_INSTALL_MIRROR_URL`.
  It requires an explicit ``OCX_SELF_UPDATE_VERSION``, because mirrors do not serve the releases API.
  The mirrored ``SHA256SUMS`` file stays the trust root.

Environment classes
^^^^^^^^^^^^^^^^^^^

.. versionadded:: 0.4

Every ocx call gets its environment from four classes of ``OCX_*`` variable.
The class decides what an ambient value does, so a variable exported in the shell or by an outer launcher cannot change a build silently.

===========  ================================  =========================================
Class        Variables                         Behavior
===========  ================================  =========================================
site         ``OCX_HOME`` ``OCX_MIRRORS``      Snapshotted from the environment
             ``OCX_INSECURE_REGISTRIES``       at the first configure and
             ``OCX_OFFLINE`` ``OCX_FROZEN``    forwarded to every call.
             ``OCX_REMOTE`` ``OCX_JOBS``       ``-DVAR=`` removes the variable
             ``OCX_INDEX``                     from every call.
             ``OCX_DEFAULT_REGISTRY``
             ``OCX_MANAGED_CONFIG``
             ``OCX_PATCHES``
             ``OCX_EXTRA_CA_CERTS``
translucent  ``OCX_CONFIG``                    The ambient value passes through
             ``OCX_PATCH_SNAPSHOT``            unchanged. A keyword overrides it:
             ``OCX_NO_CONFIG``                 ``CONFIG``, ``PATCH_SNAPSHOT`` and
             ``OCX_SIGSTORE_TRUSTED_ROOT``     ``NO_CONFIG`` of :command:`ocx_project`
                                               and :command:`ocx_package` (per command),
                                               ``SIGSTORE_TRUSTED_ROOT`` of
                                               :command:`ocx_policy`.
explicit     ``OCX_NO_VERIFY``                 Removed from every call. Only
             ``OCX_ALLOW_YANKED``              :command:`ocx_policy` sets them.
pinned       ``OCX_PROJECT`` ``OCX_GLOBAL``    Forced to a fixed value on every
             ``OCX_QUIET`` ``OCX_NO_PROJECT``  call (``OCX_PROJECT`` unset,
             ``OCX_NO_CONFIG_REFRESH``         ``OCX_QUIET=0``,
             ``OCX_NO_CONSENT``                ``OCX_SELF_UPDATE=manual``), so find_ocx
             ``OCX_SELF_UPDATE``               can parse what ocx prints.
===========  ================================  =========================================

The configure-time calls and the exported ``OCX_<NAME>_RUN`` command lists carry the same environment.
A value, a path or a site variable must not contain ``;``, and the module stops the configure when one does.
Changing ``OCX_CONFIG`` or a config file runs ocx again, because their content is part of the reconfigure fingerprint.

ocx launchers export ``OCX_FROZEN`` and ``OCX_INDEX`` into child processes.
Launchers are ``ocx exec`` and the frozen ``package exec``, including the ``OCX_<NAME>_RUN`` lists.
A find_ocx configure nested inside one, such as an ExternalProject or a test harness, inherits the outer resolution mode.
Pass ``-DOCX_FROZEN=`` and ``-DOCX_INDEX=`` to opt out.

``OCX_AUTH_<REGISTRY>_{TYPE,USER,TOKEN}`` credentials are never snapshotted into the cache.
Export them in the environment, and reconfigure after changing them.
#]=]
function(__ocx_snapshot_env var)
  if(NOT DEFINED ${var} AND DEFINED ENV{${var}})
    set(
      ${var}
      "$ENV{${var}}"
      CACHE STRING
      "find_ocx: snapshotted from the environment at first configure"
    )
  endif()
endfunction()

# The OCX_* variables this module controls, one "<class>|<entry>" row each.
# OCX_AUTH_* is in no class: credentials must never reach CMakeCache.txt.
set(
  __ocx_rows
  # site: snapshotted env -> cache at the first configure and forwarded to
  # every call; -DVAR= removes it from every call.
  "site|OCX_HOME"
  "site|OCX_MIRRORS"
  "site|OCX_INSECURE_REGISTRIES"
  "site|OCX_OFFLINE"
  "site|OCX_FROZEN"
  "site|OCX_REMOTE"
  "site|OCX_JOBS"
  "site|OCX_INDEX"
  "site|OCX_DEFAULT_REGISTRY"
  "site|OCX_MANAGED_CONFIG"
  "site|OCX_PATCHES"
  "site|OCX_EXTRA_CA_CERTS"
  # translucent: a command keyword overrides it, else the ambient value is
  # inherited unchanged (__ocx_translucent_env).
  "translucent|OCX_CONFIG"
  "translucent|OCX_PATCH_SNAPSHOT"
  "translucent|OCX_SIGSTORE_TRUSTED_ROOT"
  "translucent|OCX_NO_CONFIG"
  # explicit: set only by ocx_policy; an ambient value is removed.
  "explicit|OCX_NO_VERIFY"
  "explicit|OCX_ALLOW_YANKED"
  # pinned: "VAR=value" forced on every call (empty value = unset).
  "pinned|OCX_PROJECT="
  "pinned|OCX_GLOBAL=0"
  "pinned|OCX_QUIET=0"
  "pinned|OCX_NO_PROJECT=1"
  "pinned|OCX_NO_CONFIG_REFRESH=1"
  "pinned|OCX_NO_CONSENT=1"
  "pinned|OCX_SELF_UPDATE=manual"
)
foreach(__ocx_row IN LISTS __ocx_rows)
  if(NOT __ocx_row MATCHES "^([a-z]+)\\|(.+)$")
    message(FATAL_ERROR "find_ocx: malformed env class row '${__ocx_row}'")
  endif()
  string(TOUPPER "${CMAKE_MATCH_1}" __ocx_class)
  set_property(GLOBAL APPEND PROPERTY __OCX_ENV_${__ocx_class} "${CMAKE_MATCH_2}")
endforeach()
unset(__ocx_rows)
unset(__ocx_row)
unset(__ocx_class)

get_property(__ocx_site GLOBAL PROPERTY __OCX_ENV_SITE)
foreach(
  __ocx_var
  IN
  ITEMS
    OCX_EXECUTABLE
    OCX_INSTALL_DIST_URL
    OCX_INSTALL_MIRROR_URL
    OCX_INSTALL_VERSION
    OCX_INSTALL_CA_BUNDLE
    OCX_DEFAULT_PLATFORM
    OCX_BOOTSTRAP
    OCX_BOOTSTRAP_CACHE
    OCX_PROJECT_FILE
    OCX_ALLOW_FLOATING
    ${__ocx_site}
)
  __ocx_snapshot_env(${__ocx_var})
endforeach()
unset(__ocx_var)
unset(__ocx_site)

# The config.toml tiers that ocx reads, as paths (they may not exist), plus
# the files OCX_CONFIG, OCX_PATCH_SNAPSHOT and OCX_SIGSTORE_TRUSTED_ROOT name.
# Not listed: Windows /etc/ocx (drive-relative) and the Windows user tier
# (location undocumented).
function(__ocx_config_files out_var)
  set(files "")
  if(NOT CMAKE_HOST_WIN32)
    list(APPEND files "/etc/ocx/config.toml")
  endif()
  if(CMAKE_HOST_APPLE)
    list(APPEND files "$ENV{HOME}/Library/Application Support/ocx/config.toml")
  elseif(NOT CMAKE_HOST_WIN32)
    if(IS_ABSOLUTE "$ENV{XDG_CONFIG_HOME}")
      list(APPEND files "$ENV{XDG_CONFIG_HOME}/ocx/config.toml")
    else()
      list(APPEND files "$ENV{HOME}/.config/ocx/config.toml")
    endif()
  endif()
  if(DEFINED OCX_HOME AND NOT "${OCX_HOME}" STREQUAL "")
    set(home "${OCX_HOME}")
  elseif(CMAKE_HOST_WIN32)
    set(home "$ENV{USERPROFILE}/.ocx")
  else()
    set(home "$ENV{HOME}/.ocx")
  endif()
  list(
    APPEND files
    "${home}/config.toml"
    "${home}/state/managed-config/snapshot.json"
    "${home}/state/managed-config/config.toml"
    "$ENV{OCX_CONFIG}"
    "$ENV{OCX_PATCH_SNAPSHOT}"
    "$ENV{OCX_SIGSTORE_TRUSTED_ROOT}"
  )
  set(${out_var} "${files}" PARENT_SCOPE)
endfunction()

# Registers the config.toml tiers that exist right now, so editing one
# re-runs the configure; a file created later needs a manual reconfigure.
function(__ocx_watch_config)
  if(CMAKE_SCRIPT_MODE_FILE)
    return()
  endif()
  __ocx_config_files(files)
  foreach(file IN LISTS files)
    if(IS_ABSOLUTE "${file}" AND EXISTS "${file}" AND NOT IS_DIRECTORY "${file}")
      set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${file}")
    endif()
  endforeach()
endfunction()
__ocx_watch_config()

# Fingerprint of what the ambient configuration contributes to an ocx call:
# the translucent variables as the environment holds them, the content of the
# config files the tiers name, and the ocx_policy trust root. A change to any
# of them must not hit the memo.
function(__ocx_ambient_fingerprint out_var)
  set(fingerprint "")
  get_property(translucent GLOBAL PROPERTY __OCX_ENV_TRANSLUCENT)
  foreach(var IN LISTS translucent)
    string(APPEND fingerprint "${var}=$ENV{${var}};")
  endforeach()
  __ocx_config_files(files)
  get_property(root GLOBAL PROPERTY __OCX_POLICY_ROOT)
  list(APPEND files "${root}")
  foreach(file IN LISTS files)
    if(IS_ABSOLUTE "${file}" AND EXISTS "${file}" AND NOT IS_DIRECTORY "${file}")
      file(SHA256 "${file}" sha)
      string(APPEND fingerprint "${file}:${sha};")
    endif()
  endforeach()
  set(${out_var} "${fingerprint}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# A ';' in a path or in a site value would split the command lists this module
# builds (env entries, the exported OCX_<NAME>_RUN) into extra arguments, and
# the break would show up at build time as an unrelated ocx usage error.
function(__ocx_reject_semicolon what value)
  if("${value}" MATCHES ";")
    message(
      FATAL_ERROR
      "find_ocx: ${what} contains ';' ('${value}'), which a CMake list cannot carry\n"
      "hint: use a path without a semicolon, or a symlink to it"
    )
  endif()
endfunction()

# Appends env entries ("VAR=value" or "--unset=VAR") to the list named
# <list_var>; a later entry for a VAR replaces the earlier one.
function(__ocx_env_merge list_var)
  set(merged ${${list_var}})
  foreach(entry IN LISTS ARGN)
    if(NOT entry MATCHES "^(--unset=)?([A-Za-z_][A-Za-z0-9_]*)(=|$)")
      message(FATAL_ERROR "find_ocx: malformed env entry '${entry}'")
    endif()
    set(name "${CMAKE_MATCH_2}")
    list(FILTER merged EXCLUDE REGEX "^(--unset=)?${name}(=|$)")
    list(APPEND merged "${entry}")
  endforeach()
  set(${list_var} "${merged}" PARENT_SCOPE)
endfunction()

# The env assignments ocx_policy requested ("OCX_NO_VERIFY=1",
# "OCX_ALLOW_YANKED=1", "OCX_SIGSTORE_TRUSTED_ROOT=<path>"); empty when no
# policy was set. __ocx_env_prefix folds them into every call.
function(__ocx_policy_env out_var)
  set(env "")
  get_property(unverified GLOBAL PROPERTY __OCX_POLICY_UNVERIFIED)
  get_property(yanked GLOBAL PROPERTY __OCX_POLICY_YANKED)
  get_property(root GLOBAL PROPERTY __OCX_POLICY_ROOT)
  if(unverified)
    list(APPEND env "OCX_NO_VERIFY=1")
  endif()
  if(yanked)
    list(APPEND env "OCX_ALLOW_YANKED=1")
  endif()
  if(root)
    list(APPEND env "OCX_SIGSTORE_TRUSTED_ROOT=${root}")
  endif()
  set(${out_var} "${env}" PARENT_SCOPE)
endfunction()

# __ocx_translucent_env(<out> [CONFIG <file>] [NO_CONFIG <bool>]
#                       [PATCH_SNAPSHOT <file>])
# Env assignments for the translucent keywords, to pass as ENV to __ocx_run
# or as extra arguments to __ocx_env_prefix. Paths must be absolute; NO_CONFIG
# blanks the ambient config, patch snapshot and OCX_PATCHES unless named.
function(__ocx_translucent_env out_var)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "CONFIG;NO_CONFIG;PATCH_SNAPSHOT" "")
  if(NOT "${arg_UNPARSED_ARGUMENTS}${arg_KEYWORDS_MISSING_VALUES}" STREQUAL "")
    message(
      FATAL_ERROR
      "find_ocx: __ocx_translucent_env: bad arguments "
      "'${arg_UNPARSED_ARGUMENTS}${arg_KEYWORDS_MISSING_VALUES}'"
    )
  endif()
  set(env "")
  if(arg_NO_CONFIG)
    list(APPEND env "OCX_NO_CONFIG=1" "OCX_PATCHES=")
    if(NOT arg_CONFIG)
      list(APPEND env "OCX_CONFIG=")
    endif()
    if(NOT arg_PATCH_SNAPSHOT)
      list(APPEND env "OCX_PATCH_SNAPSHOT=")
    endif()
  endif()
  foreach(keyword IN ITEMS CONFIG PATCH_SNAPSHOT)
    if(NOT arg_${keyword})
      continue()
    endif()
    if(NOT IS_ABSOLUTE "${arg_${keyword}}")
      message(FATAL_ERROR "find_ocx: ${keyword} must be an absolute path, got '${arg_${keyword}}'")
    endif()
    list(APPEND env "OCX_${keyword}=${arg_${keyword}}")
    if(NOT CMAKE_SCRIPT_MODE_FILE AND EXISTS "${arg_${keyword}}")
      set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${arg_${keyword}}")
    endif()
  endforeach()
  set(${out_var} "${env}" PARENT_SCOPE)
endfunction()

# __ocx_env_prefix(<out> [<extra env entries>...])
# Command prefix of every ocx call (also the exported *_RUN lists): pinned
# set, site knobs, ocx_policy, then the extra entries, which win. A site
# knob cleared with -DVAR= is removed with --unset, never set empty (an
# empty OCX_INDEX makes ocx write to the current directory). Freezes policy.
function(__ocx_env_prefix out_var)
  set_property(GLOBAL PROPERTY __OCX_POLICY_FROZEN TRUE)
  __ocx_env_entries(entries ${ARGN})
  set(${out_var} "${CMAKE_COMMAND}" -E env ${entries} PARENT_SCOPE)
endfunction()

# __ocx_env_entries(<out> [<extra env entries>...])
# The env assignments behind __ocx_env_prefix, without freezing policy: for
# calls that ocx_policy cannot affect (ocx version).
function(__ocx_env_entries out_var)
  get_property(pinned GLOBAL PROPERTY __OCX_ENV_PINNED)
  get_property(site GLOBAL PROPERTY __OCX_ENV_SITE)
  get_property(explicit GLOBAL PROPERTY __OCX_ENV_EXPLICIT)
  set(entries ${pinned})
  foreach(var IN LISTS site)
    if(NOT DEFINED ${var})
      continue()
    endif()
    __ocx_reject_semicolon("${var}" "${${var}}")
    if("${${var}}" STREQUAL "")
      list(APPEND entries "--unset=${var}")
    else()
      list(APPEND entries "${var}=${${var}}")
    endif()
  endforeach()
  # www-setup hands OCX_INSTALL_CA_BUNDLE to ocx the same way: one corporate CA
  # covers the bootstrap download and every ocx call, unless the operator set
  # OCX_EXTRA_CA_CERTS (also empty, which removes it) themselves.
  __ocx_tls_cainfo(ca_unused ca_bundle)
  if(NOT DEFINED OCX_EXTRA_CA_CERTS AND NOT "${ca_bundle}" STREQUAL "")
    list(APPEND entries "OCX_EXTRA_CA_CERTS=${ca_bundle}")
  endif()
  foreach(var IN LISTS explicit)
    list(APPEND entries "--unset=${var}")
  endforeach()
  __ocx_policy_env(policy)
  __ocx_env_merge(entries ${policy} ${ARGN})
  set(${out_var} "${entries}" PARENT_SCOPE)
endfunction()

# Default hint per ocx exit code (sysexits plus the ocx-specific 79-87).
# A call site overrides it with HINTS "<code>=<text>".
function(__ocx_default_hint code out_var)
  set(hint "")
  if(code EQUAL 64)
    set(
      hint
      "usage error - ocx rejected the command line: run the tested binary with OCX_BOOTSTRAP=ALWAYS (a PATH ocx older than 0.6.0 or an old OCX_INSTALL_VERSION does not match this find_ocx), or pass one valid PLATFORM such as linux/arm64"
    )
  elseif(code EQUAL 65)
    set(
      hint
      "data error - run 'ocx lock' and commit the result if ocx.lock is stale against ocx.toml, correct a malformed reference or digest, check BINS and GROUPS, or report a layer that ocx refused to extract to the publisher"
    )
  elseif(code EQUAL 69)
    set(
      hint
      "service unavailable - the registry or index answered but not usefully, and a rerun will not help: check the name, the network, OCX_MIRRORS and OCX_AUTH_*; behind an intercepting proxy set OCX_EXTRA_CA_CERTS to its CA file"
    )
  elseif(code EQUAL 74)
    set(
      hint
      "I/O error - a local read or write failed: free disk space, fix the permissions on OCX_HOME, and check that the CA file is readable"
    )
  elseif(code EQUAL 75)
    set(
      hint
      "transient failure, retried twice where a retry is safe: rerun later, or route the registry through OCX_MIRRORS"
    )
  elseif(code EQUAL 77)
    set(
      hint
      "permission denied - make OCX_HOME writable for the current user, or point OCX_HOME at a directory that is"
    )
  elseif(code EQUAL 78)
    set(
      hint
      "configuration error - read the message: run 'ocx lock' and commit it for a missing or version 2 ocx.lock, run 'ocx config update' for a managed config that was never synced (or set OCX_NO_CONFIG=1 to skip the managed tier), fix the TOML at the printed path, add a refused registry host to trusted_hosts, or narrow GROUPS"
    )
  elseif(code EQUAL 79)
    set(
      hint
      "not found - check the name and tag, fix the CONFIG path, run 'ocx patch sync' when a required patch companion is missing, or fill the store online first under OCX_OFFLINE"
    )
  elseif(code EQUAL 80)
    set(
      hint
      "authentication required - export OCX_AUTH_<REGISTRY>_TYPE, _USER and _TOKEN or run 'ocx login <registry>', then reconfigure"
    )
  elseif(code EQUAL 81)
    set(
      hint
      "blocked by policy - OCX_FROZEN or OCX_OFFLINE refused an unpinned tag or a download: add the tag to the snapshot with ocx_index(UPDATE_COMMAND), pin a digest, or drop the flag; OCX_OFFLINE with nothing cached needs one online configure with -DOCX_PULL=ON first; a nested configure passes -DOCX_FROZEN= -DOCX_INDEX="
    )
  elseif(code EQUAL 83)
    set(
      hint
      "the Rekor transparency log was unreachable while a required signature was verified: rerun later and check access to the log; ocx_policy(ALLOW_UNVERIFIED) accepts unverified content, which weakens the build"
    )
  elseif(code EQUAL 84)
    set(
      hint
      "the registry has no OCI referrers API, so signatures and attestations cannot be attached or copied (only publishing commands raise this): use a registry or mirror that implements referrers; a rerun never helps"
    )
  elseif(code EQUAL 85)
    set(
      hint
      "the trust policy names a key backend such as awskms:// that ocx recognizes but has not implemented: point the trust configuration at a file key; a rerun never helps"
    )
  elseif(code EQUAL 86)
    set(
      hint
      "a forge lacks a capability the transport needs (only publishing commands raise this): ask an administrator of the index project to enable it"
    )
  elseif(code EQUAL 87)
    set(
      hint
      "the registry does not delete tags (only 'ocx package prune' raises this): use a registry that supports tag deletion; a rerun never helps"
    )
  endif()
  set(${out_var} "${hint}" PARENT_SCOPE)
endfunction()

# Reduces ocx's stderr to its message: the error lines only (progress lines
# drop out), each with the chain segments ocx repeats ("A: A") listed once.
# ocx writes an error as `error: <text>` or, under a launcher, as
# `<ISO timestamp> ERROR <text>`. Falls back to the whole stderr when
# neither form occurs.
function(__ocx_error_message out_var stderr)
  set(marker "(error:|[0-9][-0-9T:.Z+]* ERROR)")
  string(REPLACE "\r" "" text "${stderr}")
  # ';' and unbalanced '[' / ']' (TOML errors) would corrupt the list below.
  string(REPLACE ";" "@OCX_SEMI@" text "${text}")
  string(REPLACE "[" "@OCX_LB@" text "${text}")
  string(REPLACE "]" "@OCX_RB@" text "${text}")
  string(REGEX MATCHALL "(^|\n)${marker} [^\n]*" lines "${text}")
  if(NOT lines)
    string(STRIP "${text}" reason)
  else()
    set(messages "")
    foreach(line IN LISTS lines)
      string(REGEX REPLACE "^\n?${marker} " "" line "${line}")
      string(STRIP "${line}" line)
      string(REPLACE ": " ";" segments "${line}")
      list(REMOVE_DUPLICATES segments)
      list(JOIN segments ": " line)
      list(APPEND messages "${line}")
    endforeach()
    list(REMOVE_DUPLICATES messages)
    list(JOIN messages "\n" reason)
  endif()
  string(REPLACE "@OCX_SEMI@" ";" reason "${reason}")
  string(REPLACE "@OCX_LB@" "[" reason "${reason}")
  string(REPLACE "@OCX_RB@" "]" reason "${reason}")
  set(${out_var} "${reason}" PARENT_SCOPE)
endfunction()

# __ocx_run(WHAT <description> COMMAND <ocx args...> [OUTPUT_VARIABLE <var>]
#           [RETRIES <n>] [ENV <entries...>] [HINTS "<code>=<hint>" ...])
# Runs ocx through the env prefix (ENV: __ocx_translucent_env entries). Only
# exit 75, ocx's retry-safe code, is retried (<n> times, growing pause);
# any other failure ends the configure with ocx's message and a hint.
function(__ocx_run)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "WHAT;OUTPUT_VARIABLE;RETRIES" "COMMAND;ENV;HINTS")
  if(NOT "${arg_UNPARSED_ARGUMENTS}" STREQUAL "")
    message(FATAL_ERROR "find_ocx: __ocx_run: unexpected arguments '${arg_UNPARSED_ARGUMENTS}'")
  endif()
  __ocx_env_prefix(prefix ${arg_ENV})
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
      ENCODING UTF-8
    )
    if(rc EQUAL 0)
      if(arg_OUTPUT_VARIABLE)
        set(${arg_OUTPUT_VARIABLE} "${stdout}" PARENT_SCOPE)
      endif()
      return()
    endif()
    if(NOT rc EQUAL 75 OR attempt EQUAL attempts)
      break()
    endif()
    message(
      STATUS
      "find_ocx: ${arg_WHAT}: transient failure (exit 75), retry ${attempt}/${arg_RETRIES}"
    )
    execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep ${attempt} COMMAND_ERROR_IS_FATAL ANY)
  endforeach()
  set(hint "")
  foreach(entry IN LISTS arg_HINTS)
    if(entry MATCHES "^([0-9]+)=(.*)$" AND CMAKE_MATCH_1 EQUAL rc)
      set(hint "${CMAKE_MATCH_2}")
      break()
    endif()
  endforeach()
  if(hint STREQUAL "")
    __ocx_default_hint("${rc}" hint)
  endif()
  if(NOT hint STREQUAL "")
    set(hint "\nhint: ${hint}")
  endif()
  __ocx_error_message(reason "${stderr}")
  list(JOIN arg_COMMAND " " pretty)
  message(FATAL_ERROR "find_ocx: ${arg_WHAT} failed (exit ${rc}): ocx ${pretty}\n${reason}${hint}")
endfunction()

# TLS_CAINFO arguments for a file(DOWNLOAD) when OCX_INSTALL_CA_BUNDLE names a
# CA bundle; empty otherwise. <out_path> (optional) receives the bundle as an
# absolute path: a relative one resolves against the top-level source
# directory, because the ocx calls run from another directory. A path that is
# not a file fails here, not as an opaque TLS error from the download or from
# an ocx call.
function(__ocx_tls_cainfo out_var)
  set(${out_var} "" PARENT_SCOPE)
  if(ARGC GREATER 1)
    set(${ARGV1} "" PARENT_SCOPE)
  endif()
  if("${OCX_INSTALL_CA_BUNDLE}" STREQUAL "")
    return()
  endif()
  set(bundle "${OCX_INSTALL_CA_BUNDLE}")
  cmake_path(ABSOLUTE_PATH bundle BASE_DIRECTORY "${CMAKE_SOURCE_DIR}" NORMALIZE)
  if(NOT EXISTS "${bundle}" OR IS_DIRECTORY "${bundle}")
    message(
      FATAL_ERROR
      "find_ocx: OCX_INSTALL_CA_BUNDLE='${OCX_INSTALL_CA_BUNDLE}' is not a readable file\n"
      "hint: point it at a PEM bundle, or clear it with -DOCX_INSTALL_CA_BUNDLE="
    )
  endif()
  __ocx_reject_semicolon("OCX_INSTALL_CA_BUNDLE" "${bundle}")
  set(${out_var} TLS_CAINFO "${bundle}" PARENT_SCOPE)
  if(ARGC GREATER 1)
    set(${ARGV1} "${bundle}" PARENT_SCOPE)
  endif()
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
function(
  __ocx_select_release
  manifest
  version
  target
  out_url
  out_sha
  out_tag
  out_filename
)
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
  message(
    FATAL_ERROR
    "find_ocx: ocx ${version} for ${target} not found in the dist manifest - "
    "refresh the vendored snapshot (task dist:update) or point "
    "OCX_INSTALL_DIST_URL at a manifest that contains it"
  )
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
  # Through the pinned env: an ambient OCX_QUIET=1 would blank the output.
  # Not __ocx_env_prefix: 'ocx version' ignores policy, so it must not freeze it.
  __ocx_env_entries(entries)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env ${entries} "${OCX_EXECUTABLE}" version
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
    ENCODING UTF-8
  )
  if(NOT rc EQUAL 0)
    __ocx_error_message(reason "${err}")
    message(FATAL_ERROR "find_ocx: '${OCX_EXECUTABLE} version' failed (exit ${rc})\n${reason}")
  endif()
  string(STRIP "${out}" out)
  if(NOT out MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+")
    message(FATAL_ERROR "find_ocx: unexpected 'ocx version' output '${out}' from ${OCX_EXECUTABLE}")
  endif()
  set_property(GLOBAL PROPERTY __OCX_CLI_VERSION "${out}")
  set_property(GLOBAL PROPERTY __OCX_CLI_VERSION_PATH "${OCX_EXECUTABLE}")
  set(${out_var} "${out}" PARENT_SCOPE)
endfunction()

# OCX_BOOTSTRAP as ON, OFF or ALWAYS. Empty or unset is <default> (the entry
# points differ in it); the CMake boolean spellings map to ON and OFF, in any
# case. Any other value is an error: a typo such as 'always' would otherwise
# mean ON silently.
function(__ocx_bootstrap_mode out_var default)
  set(mode "${default}")
  if(DEFINED OCX_BOOTSTRAP AND NOT "${OCX_BOOTSTRAP}" STREQUAL "")
    string(TOUPPER "${OCX_BOOTSTRAP}" value)
    if(value STREQUAL "ALWAYS")
      set(mode ALWAYS)
    elseif(value MATCHES "^(ON|TRUE|YES|Y|1)$")
      set(mode ON)
    elseif(value MATCHES "^(OFF|FALSE|NO|N|0)$")
      set(mode OFF)
    else()
      message(
        FATAL_ERROR
        "find_ocx: OCX_BOOTSTRAP='${OCX_BOOTSTRAP}' is not ON, OFF or ALWAYS\n"
        "hint: ON bootstraps when no ocx is found, ALWAYS skips the PATH search, "
        "OFF forbids the download"
      )
    endif()
  endif()
  set(${out_var} "${mode}" PARENT_SCOPE)
endfunction()

# Ensures OCX_EXECUTABLE is usable: explicit setting, else PATH, else the
# pinned bootstrap (OCX_BOOTSTRAP: ALWAYS skips PATH, OFF forbids the
# download).
# A path this module chose itself (PATH hit or bootstrap) is remembered in
# __OCX_AUTO_EXECUTABLE and chosen again on every configure, so a changed
# OCX_INSTALL_VERSION, a new pin or OCX_BOOTSTRAP=ALWAYS reaches an existing
# build directory. Anything else in OCX_EXECUTABLE is the user's: it must
# exist, and it is never replaced. An empty value, a mistyped path of an
# earlier find_program and find_program's own NOTFOUND are not settings,
# and find_program skips a variable that is already set, so they are unset first.
function(__ocx_require_cli)
  __ocx_bootstrap_mode(mode ON)
  set(given "${OCX_EXECUTABLE}")
  if(given MATCHES "-NOTFOUND$" OR given STREQUAL "$CACHE{__OCX_AUTO_EXECUTABLE}")
    set(given "")
  endif()
  if(NOT given STREQUAL "")
    if(NOT EXISTS "${given}")
      message(
        FATAL_ERROR
        "find_ocx: OCX_EXECUTABLE='${given}' does not exist\n"
        "hint: fix the path, or clear it with -DOCX_EXECUTABLE= to search PATH"
      )
    endif()
  else()
    unset(OCX_EXECUTABLE CACHE)
    unset(OCX_EXECUTABLE)
    if(NOT mode STREQUAL "ALWAYS")
      find_program(OCX_EXECUTABLE NAMES ocx DOC "Path to the ocx CLI")
    endif()
    if(OCX_EXECUTABLE)
      message(
        STATUS
        "find_ocx: using ocx from PATH (${OCX_EXECUTABLE}) - "
        "OCX_BOOTSTRAP=ALWAYS forces the pinned bootstrap instead"
      )
    elseif(mode STREQUAL "OFF")
      message(
        FATAL_ERROR
        "find_ocx: no ocx on PATH, OCX_EXECUTABLE is not set, and implicit "
        "bootstrap is disabled (OCX_BOOTSTRAP=OFF)\n"
        "hint: install ocx on PATH or set OCX_EXECUTABLE to an ocx binary"
      )
    else()
      ocx_bootstrap()
    endif()
    set(OCX_EXECUTABLE "${OCX_EXECUTABLE}" PARENT_SCOPE)
    set(
      __OCX_AUTO_EXECUTABLE
      "${OCX_EXECUTABLE}"
      CACHE INTERNAL
      "find_ocx: ocx chosen by the module"
    )
  endif()
  __ocx_reject_semicolon("OCX_EXECUTABLE" "${OCX_EXECUTABLE}")
endfunction()

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

# Drops every result variable of NAME before a call recomputes them: a BINS
# entry or a PLATFORM that a later configure drops would otherwise survive in
# the cache, and add_test(COMMAND ${OCX_<NAME>_RUN_<BIN>}) would keep working.
# ponytail: a NAME that extends another with _RUN or _ENV_ shares its prefix; the
# result-variable scheme cannot tell them apart.
function(__ocx_clear_results name)
  get_cmake_property(cached CACHE_VARIABLES)
  foreach(var IN LISTS cached)
    if(var MATCHES "^OCX_${name}_(RUN|RUN_.+|PATHS|CONTENT|ENV_.+)$")
      unset(${var} CACHE)
    endif()
  endforeach()
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
# ocx_policy
# ---------------------------------------------------------------------------

#[=[.rst:
.. command:: ocx_policy

  Weakens the verification posture of every later ocx call in this configure, explicitly.

  .. signature::
    ocx_policy([ALLOW_UNVERIFIED] [ALLOW_YANKED]
               [SIGSTORE_TRUSTED_ROOT <file>])
    :target: ocx_policy
    :break: verbatim

    .. versionadded:: 0.4

    The policy is explicit-only.
    An ``OCX_NO_VERIFY`` or ``OCX_ALLOW_YANKED`` in the environment is removed from every ocx call.
    An inherited variable can therefore never weaken a build silently.
    Nothing is cached, so state the policy in the project listfile on every configure.
    An empty argument value is an error, because it usually means that a variable is unset.

    Call the command before the first :command:`ocx_project` or :command:`ocx_package`.
    A repeated call with identical arguments is a no-op.
    A call that differs from an earlier one is a fatal error.
    So is a call that weakens the posture after ocx has already run.

  Options
  ^^^^^^^

  ``ALLOW_UNVERIFIED``
    Accept packages that fail or lack Sigstore verification.
    The module sets ``OCX_NO_VERIFY=1`` for the ocx calls.

  ``ALLOW_YANKED``
    Resolve yanked versions.
    The module sets ``OCX_ALLOW_YANKED=1`` for the ocx calls.

  ``SIGSTORE_TRUSTED_ROOT <file>``
    Absolute path of the Sigstore trusted root to verify against.
    The module sets ``OCX_SIGSTORE_TRUSTED_ROOT`` for the ocx calls.
    A relative path is an error.

  Example
  ^^^^^^^

  The test fixture ``tests/fixtures/runtime_core/case.cmake`` runs this call.

  .. code-block:: cmake

    ocx_policy(ALLOW_YANKED)
#]=]
function(ocx_policy)
  __ocx_reject_empty_args("ocx_policy" ${ARGC} "${ARGV}")
  cmake_parse_arguments(PARSE_ARGV 0 arg "ALLOW_UNVERIFIED;ALLOW_YANKED" "SIGSTORE_TRUSTED_ROOT" "")
  if(NOT "${arg_UNPARSED_ARGUMENTS}${arg_KEYWORDS_MISSING_VALUES}" STREQUAL "")
    message(
      FATAL_ERROR
      "find_ocx: ocx_policy: bad arguments "
      "'${arg_UNPARSED_ARGUMENTS}${arg_KEYWORDS_MISSING_VALUES}'"
    )
  endif()
  if(
    NOT "${arg_SIGSTORE_TRUSTED_ROOT}" STREQUAL ""
    AND NOT IS_ABSOLUTE "${arg_SIGSTORE_TRUSTED_ROOT}"
  )
    message(
      FATAL_ERROR
      "find_ocx: ocx_policy: SIGSTORE_TRUSTED_ROOT must be an absolute path, "
      "got '${arg_SIGSTORE_TRUSTED_ROOT}'"
    )
  endif()
  __ocx_reject_semicolon("ocx_policy SIGSTORE_TRUSTED_ROOT" "${arg_SIGSTORE_TRUSTED_ROOT}")
  set(unverified 0)
  set(yanked 0)
  if(arg_ALLOW_UNVERIFIED)
    set(unverified 1)
  endif()
  if(arg_ALLOW_YANKED)
    set(yanked 1)
  endif()
  set(signature "${unverified}|${yanked}|${arg_SIGSTORE_TRUSTED_ROOT}")

  get_property(known GLOBAL PROPERTY __OCX_POLICY_SIGNATURE SET)
  if(known)
    get_property(current GLOBAL PROPERTY __OCX_POLICY_SIGNATURE)
    if(NOT signature STREQUAL current)
      message(
        FATAL_ERROR
        "find_ocx: ocx_policy: conflicting second call - the policy is "
        "'${signature}' but an earlier call set '${current}' "
        "(allow_unverified|allow_yanked|sigstore_trusted_root)"
      )
    endif()
    return()
  endif()
  get_property(frozen GLOBAL PROPERTY __OCX_POLICY_FROZEN)
  if(frozen AND NOT signature STREQUAL "0|0|")
    message(
      FATAL_ERROR
      "find_ocx: ocx_policy must be called before the first ocx_project or "
      "ocx_package - ocx has already run without it"
    )
  endif()
  set_property(GLOBAL PROPERTY __OCX_POLICY_SIGNATURE "${signature}")
  set_property(GLOBAL PROPERTY __OCX_POLICY_UNVERIFIED "${unverified}")
  set_property(GLOBAL PROPERTY __OCX_POLICY_YANKED "${yanked}")
  set_property(GLOBAL PROPERTY __OCX_POLICY_ROOT "${arg_SIGSTORE_TRUSTED_ROOT}")
endfunction()

# ---------------------------------------------------------------------------
# ocx_bootstrap
# ---------------------------------------------------------------------------

# Digest named by a dist manifest URL whose last path segment is
# <sha256>.json (the form the setup.ocx.sh installers write), else "". The
# name is the manifest's own digest, so the fetch can enforce it.
function(__ocx_manifest_sha256 url out_var)
  set(${out_var} "" PARENT_SCOPE)
  string(REGEX REPLACE "[#?].*$" "" clean "${url}")
  # CMake regexes have no {64}: match the hex run, then count it.
  if(clean MATCHES "(^|/)([0-9a-f]+)\\.json$")
    set(digest "${CMAKE_MATCH_2}")
    string(LENGTH "${digest}" len)
    if(len EQUAL 64)
      set(${out_var} "${digest}" PARENT_SCOPE)
    endif()
  endif()
endfunction()

#[=[.rst:
.. command:: ocx_bootstrap

  Downloads a pinned ocx CLI release for the host and sets ``OCX_EXECUTABLE``.

  .. signature::
    ocx_bootstrap([VERSION <version>] [TRIPLE <target-triple>]
                  [DIST_MANIFEST <dist.json>])
    :target: ocx_bootstrap
    :break: verbatim

    The call does nothing when ``OCX_EXECUTABLE`` already points at a binary of the requested version.
    The release row (URL and sha256) comes from the dist.json snapshot embedded in ``ocx.cmake``.
    :variable:`OCX_INSTALL_DIST_URL` fetches a mirrored manifest instead, and ``DIST_MANIFEST`` names a local file that wins over both.
    :variable:`OCX_INSTALL_MIRROR_URL` rewrites the artifact download to ``<mirror>/<tag>/<filename>``.

    The module verifies the archive against the sha256 of its manifest row before extraction, whichever manifest or URL served it.
    The extracted binary must report the requested version, else it is removed and the configure fails.

    Binaries land in the per-machine :variable:`OCX_BOOTSTRAP_CACHE`.
    They are downloaded once per machine and shared by all build trees.
    A warm cache needs no network access, so an air-gapped reconfigure stays offline.

    .. versionchanged:: 0.4
      Downloads verify TLS and are bounded by a timeout.
      The module probes the version of a fresh binary.

  Options
  ^^^^^^^

  An empty argument value is an error, because it usually means that a variable is unset.

  ``VERSION <version>``
    ocx CLI version to download.
    The default is :variable:`OCX_INSTALL_VERSION`, else the version pinned by this find_ocx release.

  ``TRIPLE <target-triple>``
    Release target triple.
    The default is the host triple.
    The module does not probe the version of a foreign triple, because its binary cannot run here.

  ``DIST_MANIFEST <dist.json>``
    Local release manifest that wins over the embedded snapshot and over :variable:`OCX_INSTALL_DIST_URL`.
    A relative path resolves against the directory of the calling file.
    A project configure watches the file, so editing it reconfigures.
    Script mode reads it once.

    .. versionadded:: 0.4

  Result variables
  ^^^^^^^^^^^^^^^^

  ``OCX_EXECUTABLE``
    Cache variable that holds the path of the bootstrapped binary.

  Example
  ^^^^^^^

  The fixture ``tests/fixtures/bootstrap/CMakeLists.txt`` runs these calls.

  .. code-block:: cmake

    include(ocx)

    ocx_bootstrap()
    find_package(ocx REQUIRED)
#]=]
function(ocx_bootstrap)
  __ocx_reject_empty_args("ocx_bootstrap" ${ARGC} "${ARGV}")
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "VERSION;TRIPLE;DIST_MANIFEST" "")
  if(NOT "${arg_UNPARSED_ARGUMENTS}" STREQUAL "")
    message(FATAL_ERROR "find_ocx: ocx_bootstrap: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(arg_KEYWORDS_MISSING_VALUES)
    message(FATAL_ERROR "find_ocx: ocx_bootstrap: missing value for ${arg_KEYWORDS_MISSING_VALUES}")
  endif()

  get_property(version GLOBAL PROPERTY __OCX_PIN_VERSION)
  if(DEFINED OCX_INSTALL_VERSION AND NOT "${OCX_INSTALL_VERSION}" STREQUAL "")
    set(version "${OCX_INSTALL_VERSION}")
  endif()
  if(NOT "${arg_VERSION}" STREQUAL "")
    set(version "${arg_VERSION}")
  endif()

  if(DEFINED OCX_EXECUTABLE AND EXISTS "${OCX_EXECUTABLE}")
    __ocx_cli_version(have)
    if(have VERSION_EQUAL version)
      return()
    endif()
    message(STATUS "find_ocx: OCX_EXECUTABLE is ocx ${have}, want ${version} - bootstrapping")
    set_property(GLOBAL PROPERTY __OCX_CLI_VERSION "")
  endif()

  __ocx_host_info(host_triple host_platform exe_ext)
  set(triple "${host_triple}")
  if(NOT "${arg_TRIPLE}" STREQUAL "")
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
  # A relative root would split the binary between the build directory (where
  # file(COPY) writes) and the directory the ocx calls run in.
  cmake_path(ABSOLUTE_PATH cache_root BASE_DIRECTORY "${CMAKE_SOURCE_DIR}" NORMALIZE)
  set(binary "${cache_root}/${version}/${triple}/ocx${exe_ext}")

  # Warm machine cache: no manifest work, no network - not even the
  # OCX_INSTALL_DIST_URL fetch (air-gapped reconfigures stay offline).
  # The bundle path is validated on every configure, not only on a cold download.
  __ocx_tls_cainfo(ca_args)
  # A cached binary must still run and report the version it is filed under: an
  # interrupted copy or a full disk leaves a file that exists and cannot run.
  # A foreign TRIPLE cannot run here, so it is trusted as it is.
  if(EXISTS "${binary}" AND triple STREQUAL host_triple)
    __ocx_env_entries(probe_env)
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E env ${probe_env} "${binary}" version
      RESULT_VARIABLE probe_rc
      OUTPUT_VARIABLE probe_out
      ERROR_QUIET
      ENCODING UTF-8
    )
    string(STRIP "${probe_out}" probe_out)
    if(NOT probe_rc EQUAL 0 OR NOT probe_out VERSION_EQUAL version)
      message(
        STATUS
        "find_ocx: the cached ${binary} does not report ocx ${version} "
        "(exit ${probe_rc}) - downloading it again"
      )
      file(REMOVE "${binary}")
    endif()
  endif()
  set(fresh FALSE)
  if(NOT EXISTS "${binary}")
    set(fresh TRUE)
    if(NOT "${arg_DIST_MANIFEST}" STREQUAL "")
      cmake_path(
        ABSOLUTE_PATH arg_DIST_MANIFEST
        BASE_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
        NORMALIZE
        OUTPUT_VARIABLE dist_manifest
      )
      if(NOT EXISTS "${dist_manifest}")
        message(
          FATAL_ERROR
          "find_ocx: ocx_bootstrap: DIST_MANIFEST '${arg_DIST_MANIFEST}' does not exist "
          "(looked for ${dist_manifest})"
        )
      endif()
      if(NOT CMAKE_SCRIPT_MODE_FILE)
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${dist_manifest}")
      endif()
      file(READ "${dist_manifest}" manifest)
    elseif(DEFINED OCX_INSTALL_DIST_URL AND NOT "${OCX_INSTALL_DIST_URL}" STREQUAL "")
      set(dist_file "${CMAKE_BINARY_DIR}/_ocx/dist.json")
      # A <sha256>.json name is the manifest's own digest: enforce it.
      # Any other name is fetched unverified (documented trust boundary).
      __ocx_manifest_sha256("${OCX_INSTALL_DIST_URL}" manifest_sha)
      set(manifest_hash "")
      if(NOT manifest_sha STREQUAL "")
        set(manifest_hash EXPECTED_HASH "SHA256=${manifest_sha}")
      else()
        message(
          STATUS
          "find_ocx: OCX_INSTALL_DIST_URL is not named <sha256>.json - its manifest is "
          "fetched unverified, so that host decides which archive hashes are trusted"
        )
      endif()
      file(
        DOWNLOAD "${OCX_INSTALL_DIST_URL}"
        "${dist_file}"
        ${manifest_hash}
        ${ca_args}
        TLS_VERIFY ON
        TIMEOUT 120
        INACTIVITY_TIMEOUT 30
        STATUS status
      )
      list(GET status 0 status_code)
      if(NOT status_code EQUAL 0)
        list(GET status 1 status_msg)
        message(
          FATAL_ERROR
          "find_ocx: failed to fetch the dist manifest from "
          "OCX_INSTALL_DIST_URL='${OCX_INSTALL_DIST_URL}': ${status_msg}\n"
          "hint: the mirror must allow anonymous read; a manifest named "
          "<sha256>.json must match that digest"
        )
      endif()
      file(READ "${dist_file}" manifest)
    else()
      get_property(manifest GLOBAL PROPERTY __OCX_DIST_JSON)
    endif()

    __ocx_select_release("${manifest}" "${version}" "${triple}" url sha tag filename)

    # tag and filename become path segments (the mirror url, the scratch
    # archive): a custom manifest must not walk out of either directory.
    foreach(field IN ITEMS tag filename)
      if(NOT "${${field}}" MATCHES "^[A-Za-z0-9._+-]+$" OR "${${field}}" MATCHES "^\\.\\.?$")
        message(
          FATAL_ERROR
          "find_ocx: dist manifest row for ocx ${version} (${triple}) has an unusable "
          "${field} '${${field}}' - not a single path segment"
        )
      endif()
    endforeach()

    if(DEFINED OCX_INSTALL_MIRROR_URL AND NOT "${OCX_INSTALL_MIRROR_URL}" STREQUAL "")
      string(REGEX REPLACE "/+$" "" mirror "${OCX_INSTALL_MIRROR_URL}")
      set(url "${mirror}/${tag}/${filename}")
    endif()

    set(scratch "${CMAKE_BINARY_DIR}/_ocx")
    set(archive "${scratch}/${filename}")
    message(STATUS "find_ocx: downloading ocx ${version} (${triple}) from ${url}")
    get_property(pin GLOBAL PROPERTY __OCX_PIN_VERSION)
    message(
      STATUS
      "find_ocx:   version knob: OCX_INSTALL_VERSION (pin: "
      "${pin}); cache: ${cache_root}; opt out: "
      "OCX_BOOTSTRAP=OFF + OCX_EXECUTABLE"
    )
    file(
      DOWNLOAD "${url}"
      "${archive}"
      EXPECTED_HASH SHA256=${sha}
      ${ca_args}
      TLS_VERIFY ON
      TIMEOUT 900
      INACTIVITY_TIMEOUT 60
      STATUS status
    )
    list(GET status 0 status_code)
    if(NOT status_code EQUAL 0)
      list(GET status 1 status_msg)
      message(
        FATAL_ERROR
        "find_ocx: download of ${url} failed: ${status_msg}\n"
        "hint: corporate networks - set OCX_INSTALL_MIRROR_URL (artifacts) "
        "and/or OCX_INSTALL_DIST_URL (manifest); mirrors must allow anonymous read"
      )
    endif()
    set(extract_dir "${scratch}/extract-${version}-${triple}")
    file(REMOVE_RECURSE "${extract_dir}")
    file(ARCHIVE_EXTRACT INPUT "${archive}" DESTINATION "${extract_dir}")
    # The .tar.gz holds ocx-<triple>/ocx and the .zip a flat ocx.exe: accept
    # either layout.
    set(nested "${extract_dir}/ocx-${triple}/ocx${exe_ext}")
    set(flat "${extract_dir}/ocx${exe_ext}")
    if(EXISTS "${nested}")
      set(source "${nested}")
    elseif(EXISTS "${flat}")
      set(source "${flat}")
    else()
      message(
        FATAL_ERROR
        "find_ocx: 'ocx${exe_ext}' not found in the extracted archive from ${url}"
      )
    endif()
    # Copy beside the target and rename into place: the cache is shared by all
    # build trees, and a copy that stops half way must never be taken for the
    # binary. The rename is atomic on one file system.
    string(RANDOM LENGTH 8 ALPHABET 0123456789abcdef stage_id)
    set(stage "${cache_root}/${version}/${triple}/.stage-${stage_id}")
    file(COPY "${source}" DESTINATION "${stage}")
    file(RENAME "${stage}/ocx${exe_ext}" "${binary}")
    file(REMOVE_RECURSE "${stage}")
    file(REMOVE_RECURSE "${extract_dir}")
    file(REMOVE "${archive}")
  endif()

  # ocx_bootstrap is the one writer of OCX_EXECUTABLE besides the user: a
  # binary that does not match the requested version was replaced above, and
  # this call is the sanctioned exception to "never FORCE a user knob". The
  # plain copies keep a normal variable of the same name from shadowing the
  # cache entry here and in the caller. A direct call is user intent, so it
  # also withdraws the module's own mark (see __ocx_require_cli).
  set(OCX_EXECUTABLE "${binary}" CACHE FILEPATH "Path to the ocx CLI" FORCE)
  set(OCX_EXECUTABLE "${binary}")
  set(OCX_EXECUTABLE "${binary}" PARENT_SCOPE)
  unset(__OCX_AUTO_EXECUTABLE CACHE)
  set_property(GLOBAL PROPERTY __OCX_CLI_VERSION "")
  set(reported "${version}")
  # A fresh binary must report the version the manifest row promised: a
  # mirrored manifest can pair a valid hash with the wrong release. A foreign
  # TRIPLE cannot run here, so it is not probed.
  if(fresh AND triple STREQUAL host_triple)
    __ocx_cli_version(reported)
    if(NOT reported VERSION_EQUAL version)
      file(REMOVE "${binary}")
      message(
        FATAL_ERROR
        "find_ocx: the bootstrapped ocx reports version ${reported}, expected ${version} "
        "(removed ${binary}) - check OCX_INSTALL_DIST_URL / DIST_MANIFEST"
      )
    endif()
  endif()
  message(STATUS "find_ocx: using bootstrapped ocx ${reported} (${binary})")
endfunction()

# ---------------------------------------------------------------------------
# Command helpers (shared by ocx_project and ocx_package)
# ---------------------------------------------------------------------------

# An empty argument (`INDEX "${unset_var}"`) is an error, not a missing
# optional: cmake_parse_arguments under policy 3.19 drops it silently. Pass
# the caller's ARGC and "${ARGV}".
function(__ocx_reject_empty_args caller argc argv)
  if(argc GREATER 0 AND ";${argv};" MATCHES ";;")
    message(FATAL_ERROR "find_ocx: ${caller}: empty argument in '${argv}' - is a variable unset?")
  endif()
endfunction()

# Claims NAME for one command. A repeat call with the identical command and
# arguments (CMake includes a toolchain file twice) sets <out_var> TRUE and
# changes nothing; a different one is the duplicate-NAME error.
function(__ocx_claim out_var name caller signature)
  set(${out_var} FALSE PARENT_SCOPE)
  get_property(known GLOBAL PROPERTY __OCX_SIG_${name} SET)
  if(known)
    get_property(previous GLOBAL PROPERTY __OCX_SIG_${name})
    if("${previous}" STREQUAL "${caller}|${signature}")
      set(${out_var} TRUE PARENT_SCOPE)
      return()
    endif()
  endif()
  __ocx_register_name("${name}" "${caller}")
  set_property(GLOBAL PROPERTY __OCX_SIG_${name} "${caller}|${signature}")
endfunction()

# PLATFORM (keyword, else OCX_DEFAULT_PLATFORM) is at most one ocx platform:
# `ocx -p` takes a single value, and a comma starts a +feature list, not a
# second platform.
function(__ocx_single_platform out_var caller keyword_value)
  set(platform "${keyword_value}")
  set(source "PLATFORM")
  if("${platform}" STREQUAL "" AND DEFINED OCX_DEFAULT_PLATFORM)
    set(platform "${OCX_DEFAULT_PLATFORM}")
    set(source "OCX_DEFAULT_PLATFORM")
  endif()
  list(LENGTH platform count)
  if(count GREATER 1)
    message(
      FATAL_ERROR
      "find_ocx: ${caller}: ${source} takes a single ocx platform, got "
      "'${platform}'\n"
      "hint: call ${caller} once per platform, each under its own NAME"
    )
  endif()
  set(${out_var} "${platform}" PARENT_SCOPE)
endfunction()

# CONFIG / NO_CONFIG / PATCH_SNAPSHOT -> the env assignments (<out_env>) and a
# fingerprint of the files behind them (<out_fingerprint>). Relative paths
# resolve against the calling directory; existing files retrigger the configure.
# Only given keywords reach __ocx_translucent_env: a keyword overrides its env
# var, an absent one leaves the environment alone.
function(
  __ocx_config_env
  out_env
  out_fingerprint
  config
  no_config
  patch_snapshot
)
  set(fingerprint "")
  set(translucent_args "")
  foreach(keyword IN ITEMS CONFIG PATCH_SNAPSHOT)
    string(TOLOWER "${keyword}" var)
    if(NOT "${${var}}" STREQUAL "")
      get_filename_component(path "${${var}}" ABSOLUTE)
      __ocx_reject_semicolon("${keyword}" "${path}")
      list(APPEND translucent_args ${keyword} "${path}")
      if(EXISTS "${path}" AND NOT IS_DIRECTORY "${path}")
        file(SHA256 "${path}" sha)
        string(APPEND fingerprint "${keyword}=${path}:${sha};")
        if(NOT CMAKE_SCRIPT_MODE_FILE)
          set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${path}")
        endif()
      else()
        string(APPEND fingerprint "${keyword}=${path};")
      endif()
    endif()
  endforeach()
  if(no_config)
    list(APPEND translucent_args NO_CONFIG TRUE)
  endif()
  __ocx_translucent_env(env ${translucent_args})
  __ocx_ambient_fingerprint(ambient)
  string(APPEND fingerprint "NO_CONFIG=${no_config};ENV=${env};AMBIENT=${ambient}")
  set(${out_env} "${env}" PARENT_SCOPE)
  set(${out_fingerprint} "${fingerprint}" PARENT_SCOPE)
endfunction()

# Non-fatal ocx call for the one probe whose refusal is a valid answer
# (exit 79 while offline); every other caller goes through __ocx_run.
function(__ocx_probe out_rc out_stdout)
  # gersemi: hints { COMMAND: command_line }
  cmake_parse_arguments(PARSE_ARGV 2 arg "" "" "COMMAND;ENV")
  if(NOT "${arg_UNPARSED_ARGUMENTS}" STREQUAL "")
    message(FATAL_ERROR "find_ocx: unknown arguments '${arg_UNPARSED_ARGUMENTS}'")
  endif()
  __ocx_env_prefix(prefix ${arg_ENV})
  execute_process(
    COMMAND ${prefix} "${OCX_EXECUTABLE}" ${arg_COMMAND}
    RESULT_VARIABLE rc
    OUTPUT_VARIABLE stdout
    ERROR_QUIET
    ENCODING UTF-8
  )
  set(${out_rc} "${rc}" PARENT_SCOPE)
  set(${out_stdout} "${stdout}" PARENT_SCOPE)
endfunction()

# Names a closure inspection declares: packages[].closure.surface.interface
# binaries[].name and entrypoints[].name. <out_complete> is FALSE when any
# node left its binaries undeclared (the list is then a lower bound).
function(__ocx_closure_names json out_names out_complete)
  set(names "")
  set(complete TRUE)
  string(JSON count ERROR_VARIABLE err LENGTH "${json}" packages)
  if(err)
    set(count 0)
    set(complete FALSE)
  endif()
  if(count GREATER 0)
    math(EXPR last "${count} - 1")
    foreach(i RANGE 0 ${last})
      set(
        surface
        packages
        ${i}
        closure
        surface
        interface
      )
      string(JSON flag ERROR_VARIABLE err GET "${json}" ${surface} binaries_complete)
      if(err OR NOT flag)
        set(complete FALSE)
      endif()
      foreach(kind IN ITEMS binaries entrypoints)
        string(JSON n ERROR_VARIABLE err LENGTH "${json}" ${surface} ${kind})
        if(NOT err AND n GREATER 0)
          math(EXPR n_last "${n} - 1")
          foreach(j RANGE 0 ${n_last})
            string(JSON entry GET "${json}" ${surface} ${kind} ${j} name)
            list(APPEND names "${entry}")
          endforeach()
        endif()
      endforeach()
    endforeach()
  endif()
  list(REMOVE_DUPLICATES names)
  list(SORT names)
  set(${out_names} "${names}" PARENT_SCOPE)
  set(${out_complete} "${complete}" PARENT_SCOPE)
endfunction()

# Fails the configure when a BINS name is not declared by the inspected
# closure. Runs for lazy and eager provisioning alike: the inspection fetches
# manifests only, never layers. With WIDER_COMMAND a name that exists there
# but not in COMMAND's scope is reported as a missing GROUPS entry. While
# OCX_OFFLINE, exit 79 (package not in the local store) skips the check.
function(__ocx_validate_bins)
  # gersemi: hints { COMMAND: command_line, WIDER_COMMAND: command_line }
  cmake_parse_arguments(
    PARSE_ARGV 0
    arg
    ""
    "WHAT;WIDER_HINT"
    "BINS;COMMAND;WIDER_COMMAND;ENV;HINTS"
  )
  if(NOT "${arg_UNPARSED_ARGUMENTS}" STREQUAL "")
    message(FATAL_ERROR "find_ocx: unknown arguments '${arg_UNPARSED_ARGUMENTS}'")
  endif()

  set(json "")
  set(have_json FALSE)
  if(OCX_OFFLINE)
    __ocx_probe(rc json ENV ${arg_ENV} COMMAND ${arg_COMMAND})
    if(rc EQUAL 79)
      message(
        STATUS
        "find_ocx: ${arg_WHAT}: BINS not validated (OCX_OFFLINE and the "
        "package is not in the local store)"
      )
      return()
    endif()
    if(rc EQUAL 0)
      set(have_json TRUE)
    endif()
  endif()
  if(NOT have_json)
    __ocx_run(
      WHAT "inspecting ${arg_WHAT}"
      COMMAND ${arg_COMMAND}
      ENV ${arg_ENV}
      OUTPUT_VARIABLE json
      RETRIES 2
      HINTS ${arg_HINTS}
    )
  endif()

  __ocx_closure_names("${json}" declared complete)
  set(missing "")
  foreach(bin IN LISTS arg_BINS)
    if(NOT bin IN_LIST declared)
      list(APPEND missing "${bin}")
    endif()
  endforeach()
  if("${missing}" STREQUAL "")
    return()
  endif()
  if(NOT complete)
    message(
      STATUS
      "find_ocx: ${arg_WHAT}: BINS ${missing} not validated (the package "
      "does not declare all of its binaries)"
    )
    return()
  endif()

  if(arg_WIDER_COMMAND)
    __ocx_probe(rc wider_json ENV ${arg_ENV} COMMAND ${arg_WIDER_COMMAND})
    if(rc EQUAL 0)
      __ocx_closure_names("${wider_json}" wider wider_complete)
      set(elsewhere "")
      foreach(bin IN LISTS missing)
        if(bin IN_LIST wider)
          list(APPEND elsewhere "${bin}")
        endif()
      endforeach()
      if(NOT "${elsewhere}" STREQUAL "")
        message(
          FATAL_ERROR
          "find_ocx: ${arg_WHAT}: BINS ${elsewhere}: declared only in a "
          "group that was not requested\n${arg_WIDER_HINT}"
        )
      endif()
    endif()
  endif()
  list(JOIN missing ", " missing_text)
  list(JOIN declared ", " declared_text)
  message(
    FATAL_ERROR
    "find_ocx: ${arg_WHAT}: BINS ${missing_text}: not a declared binary or "
    "entrypoint\ndeclared: ${declared_text}\n"
    "hint: BINS names are executable names, check the spelling"
  )
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
  message(
    FATAL_ERROR
    "find_ocx: no ocx.toml found searching upward from "
    "${CMAKE_CURRENT_SOURCE_DIR} - pass TOML <path>, set OCX_PROJECT_FILE, "
    "or create an ocx.toml"
  )
endfunction()

#[=[.rst:
.. command:: ocx_project

  Provisions the toolchain of a workspace ``ocx.toml`` and its ``ocx.lock``.

  .. signature::
    ocx_project([NAME <name>] [TOML <ocx.toml>] [LOCK <ocx.lock>]
                [GROUPS <group>...] [BINS <tool>...]
                [PLATFORM <ocx-platform>] [PULL]
                [CONFIG <config.toml>] [NO_CONFIG] [PATCH_SNAPSHOT <path>])
    :target: ocx_project
    :break: verbatim

    The call always runs ``ocx lock --check``, an offline staleness gate for the lock file.
    Content materializes on first execution.
    ``PULL`` or :variable:`OCX_PULL` materializes it at configure time instead.

    Calling the command again with the same ``NAME`` and identical arguments does nothing, because CMake includes a toolchain file twice.
    The same ``NAME`` with different arguments is an error.

    .. versionchanged:: 0.4
      An empty argument value is an error, because it usually means that a variable is unset.

  Options
  ^^^^^^^

  ``NAME <name>``
    Prefix of the result variables.
    The default is ``PROJECT``.
    The module upper-cases the name and reduces it to a C identifier.

  ``TOML <ocx.toml>``
    The workspace declaration.
    The default is :variable:`OCX_PROJECT_FILE`, else the nearest ``ocx.toml`` between the calling directory and the last ``project()`` source directory.
    In script mode the search walks to the filesystem root.

  ``LOCK <ocx.lock>``
    The lock file.
    The default is the ``ocx.lock`` next to the declaration.

  ``GROUPS <group>...``
    Groups that the commands see.
    The ``[tools]`` table is the group ``default``, which a ``GROUPS`` list must name itself.

  ``BINS <tool>...``
    Tools that get an ``OCX_<NAME>_RUN_<BIN>`` command.
    Entries are executable names on the composed environment, not package references, because a package may ship several tools.
    A name that no locked package declares is a configure error that lists the declared names.
    A name that only a group outside ``GROUPS`` declares says so.
    The check is skipped while ``OCX_OFFLINE`` is set and the packages are not in the local store.

    ``BINS`` is an error together with ``PLATFORM``, because content for another platform cannot run on the host.

    .. versionchanged:: 0.4
      The module checks every name against the binaries and entrypoints that ``ocx inspect --closure`` reports.

  ``PLATFORM <ocx-platform>``
    One ocx platform such as ``linux/arm64``.
    The default is :variable:`OCX_DEFAULT_PLATFORM`, else the host.
    The call pulls that platform's content from the same ``ocx.lock``.
    It exports the platform result variables instead of the command lists.
    A list of platforms is an error, so call the command once per platform under its own ``NAME``.

  ``PULL``
    Materialize the content at configure time.
    :variable:`OCX_PULL` does the same for every call.
    ``PLATFORM`` always pulls.

  ``CONFIG <config.toml>``
    An ocx config file that applies as ``OCX_CONFIG`` to every ocx call of this command and to the exported ``OCX_<NAME>_RUN``.
    A relative path resolves against the calling directory.

  ``NO_CONFIG``
    Skip the user, ``$OCX_HOME`` and managed config tiers, as ``OCX_NO_CONFIG=1`` does.

  ``PATCH_SNAPSHOT <path>``
    A patch snapshot that applies as ``OCX_PATCH_SNAPSHOT``.

  Each of the three config keywords overrides the environment variable of the same name for this command.

  .. versionadded:: 0.4
    ``CONFIG``, ``NO_CONFIG`` and ``PATCH_SNAPSHOT``.

  Result variables
  ^^^^^^^^^^^^^^^^

  The call exports these variables as global cache-internal values, usable from any directory.
  Each run removes the variables of the same ``NAME`` that an earlier configure exported.
  A dropped ``BINS`` entry therefore leaves no command behind.

  ``OCX_<NAME>_RUN``
    Command-list prefix that composes the project environment and runs any tool on it.

    .. versionchanged:: 0.4
      The prefix calls ``ocx exec``.

  ``OCX_<NAME>_RUN_<BIN>``
    Per-tool command for every name in ``BINS``.
    ``<BIN>`` is the upper-cased executable name.

  ``OCX_<NAME>_PATHS``, ``OCX_<NAME>_ENV_<KEY>``, ``OCX_<NAME>_ENV_KEYS``
    Set with ``PLATFORM`` instead of the command lists.
    They hold the ``PATH`` directories (digest paths, in environment order), the constant environment values and the list of their ``<KEY>`` names.

  Examples
  ^^^^^^^^

  The tested project ``examples/project`` builds a tool command and a test from the lazy ``OCX_TOOLS_RUN`` prefix.

  .. code-block:: cmake

    include(ocx)

    ocx_project(NAME TOOLS BINS jq)

    add_test(
      NAME data_valid
      COMMAND ${OCX_TOOLS_RUN_JQ} -e ".greeting == \"hello\"" "${CMAKE_CURRENT_SOURCE_DIR}/data.json"
    )

  The same project selects groups.
  A ``BINS`` entry from a non-default group needs that group in ``GROUPS``, and ``default`` keeps the top-level ``[tools]`` table in the environment.

  .. code-block:: cmake

    ocx_project(NAME DEV GROUPS default lint BINS jq shellcheck)
    add_test(
      NAME shellcheck_hello
      COMMAND ${OCX_DEV_RUN_SHELLCHECK} "${CMAKE_CURRENT_SOURCE_DIR}/hello.sh"
    )

  The tested project ``examples/cross_build`` provisions the ``linux/arm64`` content from a toolchain file.

  .. code-block:: cmake

    ocx_project(NAME TARGET TOML "${CMAKE_CURRENT_LIST_DIR}/ocx.toml" PLATFORM linux/arm64)

    list(APPEND CMAKE_FIND_ROOT_PATH ${OCX_TARGET_PATHS})

  The tested project ``examples/policy`` pins one ocx config file and ignores the config files of the machine.

  .. code-block:: cmake

    ocx_project(NAME TOOLS BINS jq CONFIG "${CMAKE_CURRENT_SOURCE_DIR}/ocx-config.toml" NO_CONFIG)
#]=]
function(ocx_project)
  __ocx_reject_empty_args("ocx_project" ${ARGC} "${ARGV}")
  cmake_parse_arguments(
    PARSE_ARGV 0
    arg
    "PULL;NO_CONFIG"
    "NAME;TOML;LOCK;PLATFORM;CONFIG;PATCH_SNAPSHOT"
    "GROUPS;BINS"
  )
  if(NOT "${arg_UNPARSED_ARGUMENTS}" STREQUAL "")
    set(hint "")
    if(NOT "${arg_PLATFORM}" STREQUAL "")
      set(hint " (PLATFORM takes a single ocx platform)")
    endif()
    message(
      FATAL_ERROR
      "find_ocx: ocx_project: unknown arguments '${arg_UNPARSED_ARGUMENTS}'${hint}"
    )
  endif()
  if(arg_KEYWORDS_MISSING_VALUES)
    message(FATAL_ERROR "find_ocx: ocx_project: ${arg_KEYWORDS_MISSING_VALUES} need a value")
  endif()

  if("${arg_NAME}" STREQUAL "")
    set(arg_NAME "PROJECT")
  endif()
  string(TOUPPER "${arg_NAME}" name)
  string(MAKE_C_IDENTIFIER "${name}" name)
  string(
    JOIN "|"
    signature
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${arg_NAME}"
    "${arg_TOML}"
    "${arg_LOCK}"
    "${arg_GROUPS}"
    "${arg_BINS}"
    "${arg_PLATFORM}"
    "${arg_PULL}"
    "${arg_CONFIG}"
    "${arg_NO_CONFIG}"
    "${arg_PATCH_SNAPSHOT}"
  )
  __ocx_claim(repeated "${name}" "ocx_project" "${signature}")
  if(repeated)
    message(VERBOSE "find_ocx: ${name}: identical ocx_project call, nothing to do")
    return()
  endif()

  if(NOT "${arg_TOML}" STREQUAL "")
    set(toml "${arg_TOML}")
  else()
    __ocx_default_toml(toml)
  endif()
  get_filename_component(toml "${toml}" ABSOLUTE)
  __ocx_reject_semicolon("ocx_project TOML" "${toml}")
  if(NOT EXISTS "${toml}")
    message(FATAL_ERROR "find_ocx: ocx_project: '${toml}' does not exist")
  endif()
  if(NOT "${arg_LOCK}" STREQUAL "")
    set(lock "${arg_LOCK}")
    get_filename_component(lock "${lock}" ABSOLUTE)
  else()
    get_filename_component(lock_dir "${toml}" DIRECTORY)
    set(lock "${lock_dir}/ocx.lock")
  endif()
  __ocx_reject_semicolon("ocx_project LOCK" "${lock}")

  __ocx_single_platform(platform "ocx_project" "${arg_PLATFORM}")
  if(NOT "${platform}" STREQUAL "" AND NOT "${arg_BINS}" STREQUAL "")
    message(
      FATAL_ERROR
      "find_ocx: ocx_project: PLATFORM is incompatible with BINS - foreign "
      "binaries cannot execute on this host"
    )
  endif()

  set(pull ${arg_PULL})
  if(OCX_PULL OR NOT "${platform}" STREQUAL "")
    set(pull TRUE) # foreign platforms: the pulled content IS the product
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

  __ocx_config_env(
    config_env
    config_fingerprint
    "${arg_CONFIG}"
    "${arg_NO_CONFIG}"
    "${arg_PATCH_SNAPSHOT}"
  )

  __ocx_cli_version(cli_version)
  get_property(module_version GLOBAL PROPERTY __OCX_MODULE_VERSION)
  file(SHA256 "${toml}" toml_sha)
  set(lock_sha "missing")
  if(EXISTS "${lock}")
    file(SHA256 "${lock}" lock_sha)
  endif()
  __ocx_env_prefix(prefix ${config_env})
  string(
    SHA256 fingerprint
    "project|${module_version}|${cli_version}|${OCX_EXECUTABLE}|${toml}|${toml_sha}|${lock_sha}|${arg_GROUPS}|${arg_BINS}|${platform}|${pull}|${prefix}|${config_fingerprint}"
  )
  __ocx_memo_hit("${name}" "${fingerprint}" hit)
  if(hit)
    message(STATUS "find_ocx: ${name} up to date (memoized)")
    return()
  endif()
  __ocx_clear_results("${name}")

  set(groups_args "")
  set(groups_csv "")
  if(NOT "${arg_GROUPS}" STREQUAL "")
    list(JOIN arg_GROUPS "," groups_csv)
    set(groups_args -g "${groups_csv}")
  endif()
  set(platform_args "")
  if(NOT "${platform}" STREQUAL "")
    set(platform_args -p "${platform}")
  endif()

  __ocx_run(
    WHAT "checking ${toml} against its lockfile"
    ENV ${config_env}
    COMMAND --project "${toml}" lock --check
    HINTS
      "65=run 'ocx lock' next to ${toml} and commit the updated ocx.lock"
      "78=no ocx.lock next to ${toml}, a version 2 lock, or unusable config - run 'ocx lock' and commit it, or read the message above"
  )

  if(pull)
    __ocx_run(
      WHAT "pulling packages for ${toml}"
      ENV ${config_env}
      COMMAND --project "${toml}" pull --lazy-mode never ${platform_args} ${groups_args}
      RETRIES 2
      HINTS
        "78=a tool in scope ships no '${platform}' leaf in ocx.lock - narrow GROUPS or drop the platform"
    )
  endif()

  set(guard_paths "")
  if(NOT "${platform}" STREQUAL "")
    # --pinned: digest paths. The default link paths point at whichever
    # platform pull/exec/env rendered last, so a later host exec would
    # silently turn them into host binaries.
    __ocx_run(
      WHAT "composing the ${platform} environment of ${toml}"
      ENV ${config_env}
      COMMAND
        --format
        json
        --project
        "${toml}"
        env
        --pinned
        --lazy-mode
        never
        ${platform_args}
        ${groups_args}
      OUTPUT_VARIABLE env_json
      HINTS
        "78=a tool in scope ships no '${platform}' leaf in ocx.lock - narrow GROUPS or drop the platform"
    )
    __ocx_export_env("${name}" "${env_json}")
    set(guard_paths "${OCX_${name}_PATHS}")
  else()
    set(
      run
      ${prefix}
      "${OCX_EXECUTABLE}"
      --project
      "${toml}"
      exec
      ${groups_args}
      --lazy-mode
      never
      --pinned
      --
    )
    __ocx_set_result(OCX_${name}_RUN "${run}")
    foreach(bin IN LISTS arg_BINS)
      string(TOUPPER "${bin}" bin_id)
      string(MAKE_C_IDENTIFIER "${bin_id}" bin_id)
      __ocx_set_result(OCX_${name}_RUN_${bin_id} "${run}" "${bin}")
    endforeach()
  endif()

  if(NOT "${arg_BINS}" STREQUAL "")
    set(wider_command "")
    if(NOT "${groups_csv}" MATCHES "(^|,)all(,|$)")
      set(
        wider_command
        --format
        json
        --project
        "${toml}"
        inspect
        --closure
        -g
        all
      )
    endif()
    __ocx_validate_bins(
      WHAT "ocx_project ${name} (${toml})"
      ENV ${config_env}
      BINS ${arg_BINS}
      COMMAND --format json --project "${toml}" inspect --closure ${groups_args}
      WIDER_COMMAND ${wider_command}
      WIDER_HINT
        "hint: add the group to GROUPS (the [tools] table is the group 'default'), e.g. GROUPS default <group>"
    )
  endif()

  __ocx_memo_store("${name}" "${fingerprint}" ${guard_paths})
endfunction()

# ---------------------------------------------------------------------------
# ocx_package
# ---------------------------------------------------------------------------

# True when <dir> is an index snapshot: it holds config.json or a <registry>/p
# directory. A bare `.ocx/` does not count - `ocx pull` renders its project
# toolchain (`.ocx/toolchain`) there.
function(__ocx_is_index_dir dir out_var)
  set(${out_var} FALSE PARENT_SCOPE)
  if(EXISTS "${dir}/config.json")
    set(${out_var} TRUE PARENT_SCOPE)
    return()
  endif()
  file(GLOB registries LIST_DIRECTORIES TRUE "${dir}/*")
  foreach(registry IN LISTS registries)
    if(IS_DIRECTORY "${registry}/p" OR EXISTS "${registry}/config.json")
      set(${out_var} TRUE PARENT_SCOPE)
      return()
    endif()
  endforeach()
endfunction()

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
    __ocx_is_index_dir("${dir}/.ocx" is_index)
    if(is_index)
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

  Provisions a single OCX package from an OCI registry.

  .. signature::
    ocx_package(NAME <name> PACKAGE <registry/repo[:tag][@sha256:...]>
                [INDEX <dir> | NO_INDEX] [BINS <tool>...]
                [PLATFORM <ocx-platform>] [PULL] [NO_ROOT]
                [CONFIG <config.toml>] [NO_CONFIG] [PATCH_SNAPSHOT <path>])
    :target: ocx_package
    :break: verbatim

    The call exports the same ``OCX_<NAME>_RUN`` and ``OCX_<NAME>_RUN_<BIN>`` command lists as :command:`ocx_project`.
    The lists re-enter ``ocx package exec`` and are lazy by default.
    ``PULL`` or :variable:`OCX_PULL` installs the package at configure time instead.
    A floating tag needs an index snapshot or an image index digest, as `Tag resolution`_ describes.

    Calling the command again with the same ``NAME`` and identical arguments does nothing, because CMake includes a toolchain file twice.
    The same ``NAME`` with different arguments is an error.

    .. versionchanged:: 0.4
      An empty argument value is an error, because it usually means that a variable is unset.

    .. versionchanged:: 0.4
      ``PINS`` is removed.
      Pin a floating tag with a committed index snapshot, or with the image index digest in ``PACKAGE``.

  Options
  ^^^^^^^

  ``NAME <name>``
    Prefix of the result variables.
    The module upper-cases the name and reduces it to a C identifier.
    The option is required.

  ``PACKAGE <registry/repo[:tag][@sha256:...]>``
    The package reference.
    The option is required.
    A ``@sha256:`` digest pins the package.
    An image index digest pins every platform at once, and ocx selects the leaf for the effective platform, features included.
    ``ocx package inspect <registry/repo:tag>`` prints it as ``pinned_digest``.

  ``INDEX <dir>``
    Index snapshot directory that freezes tag resolution for this package.

  ``NO_INDEX``
    Skip index resolution.
    ``INDEX`` and ``NO_INDEX`` exclude each other.

  ``BINS <tool>...``
    Tools that get an ``OCX_<NAME>_RUN_<BIN>`` command.
    Entries are executable names on the composed environment, not package references, because a package may ship several tools.
    The module checks every name against the binaries and entrypoints that ``ocx package inspect --closure`` reports.
    A typo is a configure error that lists the declared names.

    Lazy and eager provisioning both run the check.
    The check is skipped while ``OCX_OFFLINE`` is set and the package is not in the local store.

    ``BINS`` is an error together with ``PLATFORM``, because content for another platform cannot run on the host.

    .. versionchanged:: 0.4
      The module validates ``BINS``.

  ``PLATFORM <ocx-platform>``
    One ocx platform.
    The default is :variable:`OCX_DEFAULT_PLATFORM`, else the host.
    The call installs the package eagerly and exports the platform result variables instead of the command lists.
    A list of platforms is an error, so call the command once per platform under its own ``NAME``.

  ``PULL``
    Install the package at configure time.
    ``PLATFORM`` always installs.

  ``NO_ROOT``
    Do not export ``<name>_ROOT``.

  ``CONFIG <config.toml>``
    An ocx config file that applies as ``OCX_CONFIG`` to every ocx call of this command and to the exported ``OCX_<NAME>_RUN``.
    A relative path resolves against the calling directory.

  ``NO_CONFIG``
    Skip the user, ``$OCX_HOME`` and managed config tiers, as ``OCX_NO_CONFIG=1`` does.

  ``PATCH_SNAPSHOT <path>``
    A patch snapshot that applies as ``OCX_PATCH_SNAPSHOT``.

  Each of the three config keywords overrides the environment variable of the same name for this command.

  .. versionadded:: 0.4
    ``CONFIG``, ``NO_CONFIG`` and ``PATCH_SNAPSHOT``.

  Tag resolution
  ^^^^^^^^^^^^^^

  Tag resolution is frozen against the first index snapshot in effect.
  The candidates, in order, are:

  1. The explicit ``INDEX <dir>``.
  2. The :variable:`OCX_INDEX` variable.
  3. The nearest committed ``.ocx/`` directory between the calling directory and the last ``project()`` source directory.

  A ``.ocx/`` counts only when it holds a ``config.json`` or a ``<registry>/p/`` directory.
  The ``.ocx/toolchain`` that ``ocx pull`` renders does not count.
  ``NO_INDEX`` skips all three.

  A floating tag with no index in effect and no digest pin is a configure error unless :variable:`OCX_ALLOW_FLOATING` is set.
  Create and refresh a snapshot deliberately with ``ocx --index <dir> index update <package>``.
  :command:`ocx_index` composes the refresh command.

  With an index in effect, the exported launchers run ``ocx --index <dir> --frozen`` and export both settings into child processes.
  A find_ocx configure nested under such a launcher inherits the outer resolution mode.
  Pass ``-DOCX_FROZEN=`` and ``-DOCX_INDEX=`` to opt out.

  Result variables
  ^^^^^^^^^^^^^^^^

  The call exports these variables as global cache-internal values.
  Each run of a changed call removes the variables of the same ``NAME`` that an earlier configure exported, ``<name>_ROOT`` included.

  ``OCX_<NAME>_RUN``, ``OCX_<NAME>_RUN_<BIN>``
    The command lists described for :command:`ocx_project`.

  ``OCX_<NAME>_CONTENT``
    The package content directory.
    The call sets it when it installs the package.

  ``<name>_ROOT``
    The same directory under the original-case name (CMP0074).
    A following ``find_package(<name>)`` or ``find_library`` searches the OCX-provisioned content.
    ``find_program`` ignores the variable, so pass ``HINTS ${<name>_ROOT}``.
    ``NO_ROOT`` suppresses it.

    .. versionchanged:: 0.4
      A changed value also unsets ``<name>_DIR``, so ``find_package`` stops answering with the old copy.

  ``OCX_<NAME>_PATHS``, ``OCX_<NAME>_ENV_<KEY>``, ``OCX_<NAME>_ENV_KEYS``
    Set with ``PLATFORM`` instead of the command lists.
    They hold the ``PATH`` directories, the constant environment values and the list of their ``<KEY>`` names.

  Examples
  ^^^^^^^^

  The tested project ``examples/package`` pins the image index digest and keeps the package lazy.

  .. code-block:: cmake

    ocx_package(
      NAME jq_pinned
      PACKAGE ocx.sh/jqlang/jq:1.8.2@sha256:c295300441831e002c0ba54df8e6126cdd4064c63be2464bdc6b68d0012beec6
      BINS jq
      NO_ROOT
    )

  The same project resolves a floating tag from a snapshot directory, with no digest in the CMake code.

  .. code-block:: cmake

    ocx_package(
      NAME jq_frozen
      PACKAGE ocx.sh/jqlang/jq:latest
      BINS jq
      NO_ROOT
      INDEX "${CMAKE_CURRENT_SOURCE_DIR}/index"
    )

  The same project installs a floating tag eagerly and hands the content root to ``find_program``.
  ``OCX_ALLOW_FLOATING`` is the deliberate escape hatch here, and the log says how to pin the tag.

  .. code-block:: cmake

    set(OCX_ALLOW_FLOATING ON)
    ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest PULL)
    unset(OCX_ALLOW_FLOATING)
    message(STATUS "example: jq content at ${jq_ROOT}")

    find_program(JQ_EXECUTABLE NAMES jq HINTS "${jq_ROOT}" "${jq_ROOT}/bin" NO_DEFAULT_PATH NO_CACHE)
#]=]
function(ocx_package)
  __ocx_reject_empty_args("ocx_package" ${ARGC} "${ARGV}")
  cmake_parse_arguments(
    PARSE_ARGV 0
    arg
    "PULL;NO_ROOT;NO_INDEX;NO_CONFIG"
    "NAME;PACKAGE;INDEX;PLATFORM;CONFIG;PATCH_SNAPSHOT"
    "BINS"
  )
  # PINS parses as an unknown argument, or as part of BINS when it follows BINS.
  if("PINS" IN_LIST arg_UNPARSED_ARGUMENTS OR "PINS" IN_LIST arg_BINS)
    message(
      FATAL_ERROR
      "find_ocx: ocx_package: PINS was removed - commit an index snapshot, or "
      "put the image index digest in PACKAGE (PACKAGE <repo>:<tag>@sha256:<index digest>)"
    )
  endif()
  if(NOT "${arg_UNPARSED_ARGUMENTS}" STREQUAL "")
    set(hint "")
    if(NOT "${arg_PLATFORM}" STREQUAL "")
      set(hint " (PLATFORM takes a single ocx platform)")
    endif()
    message(
      FATAL_ERROR
      "find_ocx: ocx_package: unknown arguments '${arg_UNPARSED_ARGUMENTS}'${hint}"
    )
  endif()
  if(arg_KEYWORDS_MISSING_VALUES)
    message(FATAL_ERROR "find_ocx: ocx_package: ${arg_KEYWORDS_MISSING_VALUES} need a value")
  endif()
  if("${arg_NAME}" STREQUAL "" OR "${arg_PACKAGE}" STREQUAL "")
    message(FATAL_ERROR "find_ocx: ocx_package: NAME and PACKAGE are required")
  endif()
  string(TOUPPER "${arg_NAME}" name)
  string(MAKE_C_IDENTIFIER "${name}" name)
  string(
    JOIN "|"
    signature
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${arg_NAME}"
    "${arg_PACKAGE}"
    "${arg_INDEX}"
    "${arg_NO_INDEX}"
    "${arg_BINS}"
    "${arg_PLATFORM}"
    "${arg_PULL}"
    "${arg_NO_ROOT}"
    "${arg_CONFIG}"
    "${arg_NO_CONFIG}"
    "${arg_PATCH_SNAPSHOT}"
  )
  __ocx_claim(repeated "${name}" "ocx_package" "${signature}")
  if(repeated)
    message(VERBOSE "find_ocx: ${name}: identical ocx_package call, nothing to do")
    return()
  endif()

  if(NOT "${arg_INDEX}" STREQUAL "" AND arg_NO_INDEX)
    message(
      FATAL_ERROR
      "find_ocx: ocx_package ${arg_NAME}: INDEX and NO_INDEX are mutually exclusive"
    )
  endif()
  __ocx_single_platform(platform "ocx_package" "${arg_PLATFORM}")
  if(NOT "${platform}" STREQUAL "" AND NOT "${arg_BINS}" STREQUAL "")
    message(
      FATAL_ERROR
      "find_ocx: ocx_package: PLATFORM is incompatible with BINS - foreign "
      "binaries cannot execute on this host"
    )
  endif()

  __ocx_require_cli()
  __ocx_host_info(host_triple host_platform exe_ext)
  set(ref "${arg_PACKAGE}")

  # Index resolution ladder: explicit INDEX, else the OCX_INDEX knob, else
  # the nearest committed `.ocx/` snapshot; NO_INDEX skips all three. An
  # empty OCX_INDEX (-DOCX_INDEX=) neutralizes a launcher-inherited value
  # but does not veto the project's own committed snapshot.
  set(index_dir "")
  if(NOT "${arg_INDEX}" STREQUAL "")
    get_filename_component(index_dir "${arg_INDEX}" ABSOLUTE)
  elseif(NOT arg_NO_INDEX)
    if(DEFINED OCX_INDEX AND NOT "${OCX_INDEX}" STREQUAL "")
      get_filename_component(index_dir "${OCX_INDEX}" ABSOLUTE)
    else()
      __ocx_find_index(index_dir)
    endif()
  endif()

  __ocx_reject_semicolon("ocx_package INDEX" "${index_dir}")

  # Reproducible-first: a floating tag with no index in effect and no
  # digest pin would resolve differently over time - fail instead.
  if(NOT index_dir AND NOT ref MATCHES "@sha256:" AND NOT OCX_ALLOW_FLOATING)
    message(
      FATAL_ERROR
      "find_ocx: ocx_package ${arg_NAME}: '${ref}' is floating and no "
      "index snapshot is in effect - resolution is not reproducible\n"
      "fix (pick one): commit a snapshot ('ocx --index .ocx index update "
      "${arg_PACKAGE}' next to your CMakeLists, or set OCX_INDEX); pin "
      "the image index digest with @sha256:; or accept drift explicitly with "
      "-DOCX_ALLOW_FLOATING=ON"
    )
  endif()

  set(index_args "")
  set(index_leaf_sha "")
  set(index_ref "")
  if(index_dir)
    set(index_args --index "${index_dir}" --frozen)
    # repo[:tag] without @digest - what `ocx index update` expects (a tag
    # records only that tag, a bare repo every tag). Registered before the
    # memo gate: GLOBAL properties do not survive reconfigures, so
    # ocx_index(UPDATE_COMMAND) must see memoized packages too.
    string(REGEX REPLACE "@.*$" "" index_ref "${arg_PACKAGE}")
    string(REGEX REPLACE ":[^:/]*$" "" index_repo "${index_ref}")
    set_property(GLOBAL APPEND PROPERTY __OCX_INDEX_REFRESH "${index_dir}|${index_ref}")
    # The flag string alone would memoize across snapshot refreshes: hash
    # the <repo>.json leaf into the fingerprint and retrigger on edits.
    # The leaf path is <registry>/p/<repo path>.json.
    # REGEX REPLACE "^[^/]*/" would re-anchor per global match ('ocx.sh/jqlang/jq'
    # -> 'jq'), so cut at the first '/' by position.
    string(FIND "${index_repo}" "/" index_slash)
    if(index_slash EQUAL -1)
      set(index_registry "${index_repo}")
      set(index_path "")
    else()
      string(SUBSTRING "${index_repo}" 0 ${index_slash} index_registry)
      math(EXPR index_slash "${index_slash} + 1")
      string(SUBSTRING "${index_repo}" ${index_slash} -1 index_path)
    endif()
    # ocx names the registry directory with ':' written '_' (localhost:5001 -> localhost_5001).
    string(REPLACE ":" "_" index_registry_dir "${index_registry}")
    set(index_leaf "${index_dir}/${index_registry_dir}/p/${index_path}.json")
    if(EXISTS "${index_leaf}")
      file(SHA256 "${index_leaf}" index_leaf_sha)
      if(NOT CMAKE_SCRIPT_MODE_FILE)
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${index_leaf}")
      endif()
    endif()
  endif()
  set(platform_args "")
  if(NOT "${platform}" STREQUAL "")
    set(platform_args -p "${platform}")
  endif()

  set(pull ${arg_PULL})
  if(OCX_PULL OR NOT "${platform}" STREQUAL "")
    set(pull TRUE)
  endif()

  __ocx_config_env(
    config_env
    config_fingerprint
    "${arg_CONFIG}"
    "${arg_NO_CONFIG}"
    "${arg_PATCH_SNAPSHOT}"
  )

  __ocx_cli_version(cli_version)
  get_property(module_version GLOBAL PROPERTY __OCX_MODULE_VERSION)
  __ocx_env_prefix(prefix ${config_env})
  string(
    SHA256 fingerprint
    "package|${module_version}|${cli_version}|${OCX_EXECUTABLE}|${ref}|${arg_BINS}|${platform}|${index_args}|${index_leaf_sha}|${pull}|${arg_NO_ROOT}|${prefix}|${config_fingerprint}"
  )
  __ocx_memo_hit("${name}" "${fingerprint}" hit)
  if(hit)
    message(STATUS "find_ocx: ${name} up to date (memoized)")
    return()
  endif()
  __ocx_clear_results("${name}")
  # A root that an earlier configure exported stays only if this call exports it again.
  if(NOT pull OR arg_NO_ROOT)
    if(NOT "$CACHE{__OCX_R_${name}_ROOTVAR}" STREQUAL "")
      set(old_root "$CACHE{__OCX_R_${name}_ROOTVAR}")
      string(REGEX REPLACE "_ROOT$" "_DIR" old_dir "${old_root}")
      unset(${old_root} CACHE)
      unset(${old_dir} CACHE)
      unset(__OCX_R_${name}_ROOTVAR CACHE)
    endif()
  endif()

  if(index_dir)
    set(
      index_hint
      "81=package not in the committed index snapshot - refresh it with 'ocx --index ${index_dir} index update ${index_ref}'"
    )
  else()
    set(
      index_hint
      "81=frozen resolution refused the floating tag - is OCX_FROZEN set without a usable index?"
    )
  endif()

  set(guard_paths "")
  if(pull)
    __ocx_run(
      WHAT "installing ${ref}"
      ENV ${config_env}
      COMMAND ${index_args} --format json package install ${platform_args} "${ref}"
      RETRIES 2
      HINTS "${index_hint}"
    )
    if(NOT index_dir AND NOT ref MATCHES "@sha256:")
      message(
        STATUS
        "find_ocx: ${arg_NAME} resolved floating - pin it with a committed index "
        "snapshot or the image index digest (PACKAGE <repo>:<tag>@sha256:<index digest>; "
        "'ocx package inspect ${arg_PACKAGE}' prints it as pinned_digest)"
      )
    endif()
    __ocx_run(
      WHAT "locating ${ref} in the store"
      ENV ${config_env}
      COMMAND ${index_args} --format json package which ${platform_args} "${ref}"
      OUTPUT_VARIABLE which_json
      HINTS "${index_hint}"
    )
    # {"<ref>": {"path": "<package root>", "kind": "package"}}
    string(JSON member MEMBER "${which_json}" 0)
    string(JSON store_root GET "${which_json}" "${member}" path)
    # ocx prints native paths: backslashes on Windows. The cache holds CMake paths, as <name>_ROOT does.
    cmake_path(SET content NORMALIZE "${store_root}/content")
    __ocx_set_result(OCX_${name}_CONTENT "${content}")
    list(APPEND guard_paths "${content}")
    if(NOT arg_NO_ROOT)
      if(NOT "$CACHE{${arg_NAME}_ROOT}" STREQUAL "${content}")
        unset(${arg_NAME}_DIR CACHE)
      endif()
      set(
        ${arg_NAME}_ROOT
        "${content}"
        CACHE PATH
        "find_ocx: content root of ${ref} (CMP0074 search hint)"
        FORCE
      )
      __ocx_set_result(__OCX_R_${name}_ROOTVAR "${arg_NAME}_ROOT")
    endif()
  elseif(NOT ref MATCHES "@sha256:" AND NOT index_dir)
    # only reachable with OCX_ALLOW_FLOATING (the gate above fails otherwise)
    message(
      WARNING
      "find_ocx: ocx_package ${arg_NAME}: '${ref}' is lazy AND floating - "
      "the tag resolves on first execution and can drift; add an "
      "index snapshot or an @sha256: image index digest (or PULL to resolve now)"
    )
  endif()

  if(NOT "${platform}" STREQUAL "")
    __ocx_run(
      WHAT "composing the ${platform} environment of ${ref}"
      ENV ${config_env}
      COMMAND ${index_args} --format json package env --lazy-mode never ${platform_args} "${ref}"
      OUTPUT_VARIABLE env_json
      RETRIES 2
      HINTS "${index_hint}"
    )
    __ocx_export_env("${name}" "${env_json}")
    list(APPEND guard_paths ${OCX_${name}_PATHS})
  else()
    set(
      run
      ${prefix}
      "${OCX_EXECUTABLE}"
      ${index_args}
      package
      exec
      --lazy-mode
      never
      "${ref}"
      --
    )
    __ocx_set_result(OCX_${name}_RUN "${run}")
    foreach(bin IN LISTS arg_BINS)
      string(TOUPPER "${bin}" bin_id)
      string(MAKE_C_IDENTIFIER "${bin_id}" bin_id)
      __ocx_set_result(OCX_${name}_RUN_${bin_id} "${run}" "${bin}")
    endforeach()
  endif()

  if(NOT "${arg_BINS}" STREQUAL "")
    __ocx_validate_bins(
      WHAT "ocx_package ${arg_NAME} (${ref})"
      ENV ${config_env}
      BINS ${arg_BINS}
      COMMAND ${index_args} --format json package inspect --closure "${ref}"
      HINTS "${index_hint}"
    )
  endif()

  __ocx_memo_store("${name}" "${fingerprint}" ${guard_paths})
endfunction()

# ---------------------------------------------------------------------------
# ocx_index
# ---------------------------------------------------------------------------

# ocx_index(FIND [REQUIRED]): the discovery result lands in <out_var> ("" when
# none); the facade relays it into OCX_INDEX.
function(__ocx_index_find out_var)
  __ocx_reject_empty_args("ocx_index(FIND)" ${ARGC} "${ARGV}")
  cmake_parse_arguments(PARSE_ARGV 1 arg "REQUIRED" "" "")
  if(NOT "${arg_UNPARSED_ARGUMENTS}" STREQUAL "")
    message(FATAL_ERROR "find_ocx: ocx_index(FIND): unknown arguments '${arg_UNPARSED_ARGUMENTS}'")
  endif()
  set(${out_var} "" PARENT_SCOPE)
  if(CMAKE_SCRIPT_MODE_FILE)
    message(
      FATAL_ERROR
      "find_ocx: ocx_index(FIND) needs a project() search bound and "
      "script mode has none - set OCX_INDEX instead"
    )
  endif()
  __ocx_find_index(dir)
  if(NOT dir)
    if(arg_REQUIRED)
      message(
        FATAL_ERROR
        "find_ocx: ocx_index(FIND REQUIRED): no .ocx index snapshot "
        "between ${CMAKE_CURRENT_SOURCE_DIR} and ${PROJECT_SOURCE_DIR}\n"
        "hint: create one with 'ocx --index .ocx index update "
        "<package>...' and commit it"
      )
    endif()
    return()
  endif()
  message(STATUS "find_ocx: index snapshot: ${dir}")
  set(${out_var} "${dir}" PARENT_SCOPE)
endfunction()

# ocx_index(UPDATE_COMMAND <out-var> ...): composes the refresh command.
function(__ocx_index_update_command out_var)
  __ocx_reject_empty_args("ocx_index(UPDATE_COMMAND)" ${ARGC} "${ARGV}")
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "INDEX" "PACKAGES")
  if(NOT "${arg_UNPARSED_ARGUMENTS}" STREQUAL "")
    message(
      FATAL_ERROR
      "find_ocx: ocx_index(UPDATE_COMMAND): unknown arguments '${arg_UNPARSED_ARGUMENTS}'"
    )
  endif()
  if(arg_KEYWORDS_MISSING_VALUES)
    message(
      FATAL_ERROR
      "find_ocx: ocx_index(UPDATE_COMMAND): ${arg_KEYWORDS_MISSING_VALUES} need a value"
    )
  endif()

  if(NOT "${arg_INDEX}" STREQUAL "")
    get_filename_component(dir "${arg_INDEX}" ABSOLUTE)
  elseif(DEFINED OCX_INDEX AND NOT "${OCX_INDEX}" STREQUAL "")
    get_filename_component(dir "${OCX_INDEX}" ABSOLUTE)
  else()
    __ocx_find_index(dir)
  endif()
  if(NOT dir)
    message(
      FATAL_ERROR
      "find_ocx: ocx_index(UPDATE_COMMAND): no index in effect - pass "
      "INDEX <dir>, set OCX_INDEX, or commit a .ocx snapshot"
    )
  endif()

  # repo:tag records that tag only, a bare repo every tag.
  set(refs "")
  foreach(pkg IN LISTS arg_PACKAGES)
    string(REGEX REPLACE "@.*$" "" pkg "${pkg}")
    list(APPEND refs "${pkg}")
  endforeach()
  if(NOT refs)
    get_property(entries GLOBAL PROPERTY __OCX_INDEX_REFRESH)
    foreach(entry IN LISTS entries)
      string(REGEX REPLACE "^(.*)\\|([^|]+)$" "\\1" entry_dir "${entry}")
      string(REGEX REPLACE "^(.*)\\|([^|]+)$" "\\2" entry_ref "${entry}")
      if(entry_dir STREQUAL "${dir}")
        list(APPEND refs "${entry_ref}")
      endif()
    endforeach()
    list(REMOVE_DUPLICATES refs)
    if(NOT refs)
      message(
        FATAL_ERROR
        "find_ocx: ocx_index(UPDATE_COMMAND): no ocx_package call is "
        "frozen against '${dir}' - pass PACKAGES <ref>... explicitly"
      )
    endif()
  endif()

  __ocx_require_cli()
  __ocx_env_prefix(prefix)
  # `index update` refuses to run frozen (exit 81): drop a pinned
  # OCX_FROZEN and unset an inherited one.
  list(FILTER prefix EXCLUDE REGEX "^(OCX_FROZEN=.*|--unset=OCX_FROZEN)$")
  list(APPEND prefix "--unset=OCX_FROZEN")
  set(
    ${out_var}
    ${prefix}
    "${OCX_EXECUTABLE}"
    --index
    "${dir}"
    index
    update
    ${refs}
    PARENT_SCOPE
  )
endfunction()

#[=[.rst:
.. command:: ocx_index

  Operates on committed index snapshots, the reproducibility mechanism for floating tags next to ``@sha256:`` image index digests.
  The first argument selects the operation.

  .. parsed-literal::

    ocx_index(`FIND`_ [REQUIRED])
    ocx_index(`UPDATE_COMMAND`_ <out-var> [INDEX <dir>] [PACKAGES <ref>...])

  A snapshot is a directory owned by the ocx CLI.
  It holds ``<registry>/p/<repo>.json`` leaves that map tags to digests.
  Create and refresh it with ``ocx --index <dir> index update <package>...``.
  Committing one next to your ``CMakeLists.txt`` as ``.ocx/`` freezes every :command:`ocx_package` tag resolution against it.
  The discovery ladder is described under :command:`ocx_package`.

  .. versionchanged:: 0.4
    The leaves follow the layout of ocx 0.6.
    Regenerate a snapshot that an earlier CLI created with ``UPDATE_COMMAND``.

  .. signature::
    ocx_index(FIND [REQUIRED])
    :target: FIND
    :break: verbatim

    Runs the ``.ocx/`` discovery once and locks the result into :variable:`OCX_INDEX` for the current directory and below.
    The search goes upward from the calling directory and stops at the last ``project()`` source directory.
    A ``.ocx/`` counts only when it holds a ``config.json`` or a ``<registry>/p/`` directory.
    The ``.ocx/toolchain`` that ``ocx pull`` renders does not count.

    ``REQUIRED``
      Turns "no snapshot found" into a configure error.
      Use it to fail fast at the top of a ``CMakeLists.txt`` instead of once per package.
      Without it, finding nothing is a quiet no-op.

    The operation is not available in script mode, because script mode has no search bound.
    Set :variable:`OCX_INDEX` there instead.

  .. signature::
    ocx_index(UPDATE_COMMAND <out-var> [INDEX <dir>] [PACKAGES <ref>...])
    :target: UPDATE_COMMAND
    :break: verbatim

    Composes the command list that refreshes a snapshot and stores it in ``<out-var>``.
    The list runs ``ocx --index <dir> index update <ref>...`` under the composed environment of the module.
    It carries no ``OCX_FROZEN``, because ``index update`` refuses to run frozen.
    The operation works in project mode and in script mode, where ``execute_process`` can run the list.

    ``INDEX <dir>``
      The snapshot to refresh.
      The default is the index in effect, which is :variable:`OCX_INDEX`, else the ``.ocx/`` discovery.

    ``PACKAGES <ref>...``
      The references to refresh.
      The default is the references of the preceding :command:`ocx_package` calls frozen against that directory.
      A reference with a tag records only that tag, and a bare repository records every tag.
      The operation strips a ``@sha256:`` digest.

    How the command runs is the caller's choice: a build target, a test fixture or script mode.
    The module deliberately has no built-in target or ctest wiring.
    A test that rewrites a committed file would let CI paper over drift instead of failing.
    The freshness gate is the frozen configure itself, because a tag missing from the snapshot fails with the exit-81 refresh hint.
    Run the command, review the diff and commit.

  Examples
  ^^^^^^^^

  The tested project ``examples/frozen_index`` locks the discovered snapshot and resolves a floating tag from it.

  .. code-block:: cmake

    ocx_index(FIND REQUIRED)

    ocx_package(NAME jq PACKAGE ocx.sh/jqlang/jq:latest BINS jq NO_ROOT)

  The same project composes the refresh command and wraps it in a build target.

  .. code-block:: cmake

    ocx_index(UPDATE_COMMAND refresh)
    add_custom_target(
      index-update
      COMMAND ${refresh}
      COMMAND
        ${CMAKE_COMMAND} -E echo "index snapshot refreshed - review the diff and commit the result"
      VERBATIM
    )
#]=]
function(ocx_index op)
  # Forward the verb's arguments (after the <out-var> of UPDATE_COMMAND)
  # quoted, so an empty one reaches the verb's own check instead of vanishing.
  # cmake_language(EVAL) runs in this scope.
  set(first 1)
  if(op STREQUAL "UPDATE_COMMAND")
    set(first 2)
  endif()
  set(quoted "")
  if(ARGC GREATER first)
    math(EXPR last "${ARGC} - 1")
    foreach(i RANGE ${first} ${last})
      # A bracket argument ends at the first closing bracket of its own width:
      # widen it until the value cannot contain it (a path may hold ']==]').
      set(equals "==")
      while(TRUE)
        string(FIND "${ARGV${i}}" "]${equals}]" closing)
        if(closing EQUAL -1)
          break()
        endif()
        string(APPEND equals "=")
      endwhile()
      string(APPEND quoted " [${equals}[${ARGV${i}}]${equals}]")
    endforeach()
  endif()
  if(op STREQUAL "FIND")
    cmake_language(EVAL CODE "__ocx_index_find(found${quoted})")
    if(found)
      set(OCX_INDEX "${found}" PARENT_SCOPE)
    endif()
  elseif(op STREQUAL "UPDATE_COMMAND")
    if(ARGC LESS 2)
      message(FATAL_ERROR "find_ocx: ocx_index(UPDATE_COMMAND) requires an <out-var>")
    endif()
    cmake_language(EVAL CODE "__ocx_index_update_command(refresh_command${quoted})")
    set(${ARGV1} "${refresh_command}" PARENT_SCOPE)
  else()
    message(
      FATAL_ERROR
      "find_ocx: ocx_index: unknown operation '${op}' "
      "(expected FIND or UPDATE_COMMAND)"
    )
  endif()
endfunction()

# ---------------------------------------------------------------------------
# ocx_self_update (script mode)
# ---------------------------------------------------------------------------

#[=[.rst:
.. command:: ocx_self_update

  Replaces the vendored ``ocx.cmake`` and a sibling ``Findocx.cmake`` with a released find_ocx version.

  .. signature::
    ocx_self_update()
    :target: ocx_self_update

    .. versionadded:: 0.4

    The command runs in script mode only (``cmake -P``).
    A configure fails with an error, because the command rewrites files in the source tree.
    ``cmake -P ocx.cmake`` calls it, and so does a call after ``include(ocx)`` from your own script.

    :variable:`OCX_SELF_UPDATE_VERSION` names the release.
    The default is the latest release, found through the GitHub releases API.
    The files come from GitHub or from :variable:`OCX_SELF_UPDATE_URL`.

    The release ``SHA256SUMS`` file is the trust root.
    The command downloads both files and verifies them against it before either one replaces the vendored copy.
    A failed update leaves the vendored copy untouched.

  Example
  ^^^^^^^

  The check ``tests/self_update_check.cmake`` runs this form against a ``file://`` release.

  .. code-block:: sh

    cmake -DOCX_SELF_UPDATE_VERSION=v0.4.0 -P cmake/ocx.cmake
#]=]
function(ocx_self_update)
  __ocx_reject_empty_args("ocx_self_update" ${ARGC} "${ARGV}")
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "" "")
  if(NOT "${arg_UNPARSED_ARGUMENTS}" STREQUAL "")
    message(
      FATAL_ERROR
      "find_ocx: ocx_self_update: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}"
    )
  endif()
  if(NOT CMAKE_SCRIPT_MODE_FILE)
    message(
      FATAL_ERROR
      "find_ocx: ocx_self_update rewrites the vendored files and runs in script "
      "mode only\nhint: cmake [-DOCX_SELF_UPDATE_VERSION=vX.Y.Z] -P <dir>/ocx.cmake"
    )
  endif()
  get_property(module_file GLOBAL PROPERTY __OCX_MODULE_FILE)
  get_property(module_version GLOBAL PROPERTY __OCX_MODULE_VERSION)
  get_filename_component(module_dir "${module_file}" DIRECTORY)

  set(tag "")
  if(DEFINED OCX_SELF_UPDATE_VERSION AND NOT "${OCX_SELF_UPDATE_VERSION}" STREQUAL "")
    set(tag "${OCX_SELF_UPDATE_VERSION}")
    if(NOT tag MATCHES "^v")
      set(tag "v${tag}")
    endif()
  elseif(DEFINED OCX_SELF_UPDATE_URL AND NOT "${OCX_SELF_UPDATE_URL}" STREQUAL "")
    message(
      FATAL_ERROR
      "find_ocx: OCX_SELF_UPDATE_URL is set but OCX_SELF_UPDATE_VERSION is "
      "not - a mirror cannot serve the GitHub releases API, pass the tag "
      "explicitly (-DOCX_SELF_UPDATE_VERSION=vX.Y.Z)"
    )
  endif()

  __ocx_tls_cainfo(ca_args)

  # Sibling temp dir: same filesystem, so the final file(RENAME) is atomic.
  set(tmp "${module_dir}/.ocx-self-update-tmp")
  file(REMOVE_RECURSE "${tmp}")

  if(tag STREQUAL "")
    # The API only names the tag; SHA256SUMS below is what is trusted.
    file(
      DOWNLOAD "https://api.github.com/repos/ocx-sh/find_ocx/releases/latest"
      "${tmp}/latest.json"
      ${ca_args}
      TLS_VERIFY ON
      TIMEOUT 60
      INACTIVITY_TIMEOUT 30
      STATUS status
    )
    list(GET status 0 status_code)
    if(NOT status_code EQUAL 0)
      list(GET status 1 status_msg)
      file(REMOVE_RECURSE "${tmp}")
      message(
        FATAL_ERROR
        "find_ocx: failed to discover the latest release from the GitHub "
        "API: ${status_msg}\n"
        "hint: pass -DOCX_SELF_UPDATE_VERSION=vX.Y.Z (plus "
        "-DOCX_SELF_UPDATE_URL=<mirror> on restricted networks)"
      )
    endif()
    file(READ "${tmp}/latest.json" api_json)
    string(JSON tag GET "${api_json}" tag_name)
  endif()
  # The tag becomes a URL path segment.
  if(NOT tag MATCHES "^v[0-9][A-Za-z0-9._+-]*$")
    file(REMOVE_RECURSE "${tmp}")
    message(FATAL_ERROR "find_ocx: '${tag}' is not a find_ocx release tag (vX.Y.Z)")
  endif()

  set(base "https://github.com/ocx-sh/find_ocx/releases/download")
  if(DEFINED OCX_SELF_UPDATE_URL AND NOT "${OCX_SELF_UPDATE_URL}" STREQUAL "")
    string(REGEX REPLACE "/+$" "" base "${OCX_SELF_UPDATE_URL}")
  endif()

  # Trust root of the update: its hashes gate both files below.
  file(
    DOWNLOAD "${base}/${tag}/SHA256SUMS"
    "${tmp}/SHA256SUMS"
    ${ca_args}
    TLS_VERIFY ON
    TIMEOUT 60
    INACTIVITY_TIMEOUT 30
    STATUS status
  )
  list(GET status 0 status_code)
  if(NOT status_code EQUAL 0)
    list(GET status 1 status_msg)
    file(REMOVE_RECURSE "${tmp}")
    message(
      FATAL_ERROR
      "find_ocx: failed to fetch ${base}/${tag}/SHA256SUMS: ${status_msg}\n"
      "hint: a mirror must allow anonymous read"
    )
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
    message(
      FATAL_ERROR
      "find_ocx: ${base}/${tag}/SHA256SUMS lacks hashes for ocx.cmake and "
      "Findocx.cmake - not a find_ocx release?"
    )
  endif()

  # Both-or-neither: nothing is renamed until both verified downloads exist.
  set(names ocx.cmake Findocx.cmake)
  set(shas "${module_sha}" "${find_sha}")
  foreach(name sha IN ZIP_LISTS names shas)
    file(
      DOWNLOAD "${base}/${tag}/${name}"
      "${tmp}/${name}"
      EXPECTED_HASH SHA256=${sha}
      ${ca_args}
      TLS_VERIFY ON
      TIMEOUT 120
      INACTIVITY_TIMEOUT 30
      STATUS status
    )
    list(GET status 0 status_code)
    if(NOT status_code EQUAL 0)
      list(GET status 1 status_msg)
      file(REMOVE_RECURSE "${tmp}")
      message(FATAL_ERROR "find_ocx: download of ${base}/${tag}/${name} failed: ${status_msg}")
    endif()
  endforeach()

  file(READ "${tmp}/ocx.cmake" new_content)
  set(new_version "unknown")
  if(new_content MATCHES "__OCX_MODULE_VERSION \"([^\"]+)\"")
    set(new_version "${CMAKE_MATCH_1}")
  endif()
  # No downgrade refusal: an explicit version is the operator's choice
  # (rollbacks are legitimate); the direction is visible in this line.
  message(STATUS "find_ocx: ${module_version} -> ${new_version} (${tag})")

  # Replacing the running script is safe: CMake parses the whole listfile
  # before executing it.
  file(RENAME "${tmp}/ocx.cmake" "${module_file}")
  set(findocx "${module_dir}/Findocx.cmake")
  if(EXISTS "${findocx}")
    file(RENAME "${tmp}/Findocx.cmake" "${findocx}")
  else()
    message(
      STATUS
      "find_ocx: no Findocx.cmake next to this file - skipped "
      "(ocx.cmake-only vendoring is supported)"
    )
  endif()
  file(REMOVE_RECURSE "${tmp}")
endfunction()

cmake_policy(POP)

# `cmake -P ocx.cmake` runs the self-update; `include(ocx)` from another
# script keeps CMAKE_SCRIPT_MODE_FILE pointing at the outer script, so a
# plain include never triggers it.
if(CMAKE_SCRIPT_MODE_FILE AND CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
  ocx_self_update()
endif()
