find_ocx
========

CMake support for `OCX <https://ocx.sh>`_ — the OCI-backed package manager.
Two copy-and-own files bootstrap a pinned, sha256-verified ``ocx`` CLI and
provision development tools through it, as command-list launchers, content
roots for ``find_package``, or foreign-platform content.

find_ocx never re-implements OCX internals in CMake. All resolution goes
through the ``ocx`` binary; the durable contracts are ``ocx.lock`` digests
and the OCI manifests.

Quick start
-----------

Vendor ``Findocx.cmake`` and ``ocx.cmake`` (from the `GitHub release assets
<https://github.com/ocx-sh/find_ocx/releases>`_) into your repository, e.g.
under ``cmake/``:

.. code-block:: cmake

  # CMakeLists.txt
  list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
  include(ocx)

  # Workspace toolchain from ./ocx.toml + ./ocx.lock (lazy):
  ocx_project(BINS jq)
  add_custom_command(... COMMAND ${OCX_PROJECT_RUN_JQ} . in.json > out.json)

  # Ad-hoc package; PULL exports jq_ROOT for find_package/find_library:
  ocx_package(NAME jq PACKAGE ocx.sh/jq:latest PULL)

No ocx installation is required: the pinned CLI is bootstrapped on first
configure into a per-machine cache. Alternatively use the classic find
module — ``find_package(ocx REQUIRED)`` — with ``-DOCX_BOOTSTRAP=ON`` for
the same zero-setup behavior.

Requires CMake 3.19 (``Findocx.cmake`` alone works on 3.15). Script mode
(``cmake -P``) is fully supported.

Corporate mirrors
-----------------

Same knobs as the `setup.ocx.sh installer
<https://github.com/ocx-sh/setup.ocx.sh>`_ and `rules_ocx
<https://github.com/ocx-sh/rules_ocx>`_. Every variable follows the
snapshot pattern: a CMake cache variable wins; otherwise the environment
value at *first* configure is snapshotted into the cache and stays sticky
for the build directory.

===========================  ====================================================
Variable                     Effect
===========================  ====================================================
``OCX_INSTALL_DIST_URL``     Fetch the release manifest from your mirror
                             instead of the embedded snapshot.
``OCX_INSTALL_MIRROR_URL``   Rewrite the ocx binary download to
                             ``<mirror>/<tag>/<filename>``. The manifest sha256
                             is still enforced.
``OCX_MIRRORS``              JSON map ``{"ocx.sh": "https://mirror.corp/ocx"}``
                             — package pulls go to the mirror; lock digests
                             stay keyed to the upstream host.
``OCX_INSECURE_REGISTRIES``  Allow plain-HTTP mirrors (comma list).
``OCX_AUTH_<REG>_*``         Registry credentials — **environment only**,
                             never snapshotted into CMakeCache.txt.
===========================  ====================================================

Also passed through when set: ``OCX_HOME``, ``OCX_OFFLINE``, ``OCX_FROZEN``,
``OCX_REMOTE``, ``OCX_JOBS``, ``OCX_INDEX``, ``OCX_DEFAULT_REGISTRY``.

Lazy vs eager
-------------

Launchers are lazy by default: ``ocx run`` / ``ocx package exec``
materialize content on first execution, so a configure touches the network
only for what it actually needs. ``PULL`` (per call) or ``-DOCX_PULL=ON``
(global, recommended for CI) materializes at configure time and enables the
``<name>_ROOT`` export. Reconfigures are memoized: when the inputs are
unchanged, no ocx process is spawned at all (``-DOCX_REFRESH=ON`` for a
one-shot bypass).

.. toctree::
   :maxdepth: 2

   examples
   reference
