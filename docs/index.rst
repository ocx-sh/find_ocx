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

.. code-block:: console

   ocx --index .ocx index update ocx.sh/jq   # snapshot the tag resolution
   git add .ocx                              # commit it - the visible lock

.. code-block:: cmake

  # CMakeLists.txt
  list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
  include(ocx)

  # Workspace toolchain from ./ocx.toml + ./ocx.lock (lazy):
  ocx_project(BINS jq)
  add_custom_command(... COMMAND ${OCX_PROJECT_RUN_JQ} . in.json > out.json)

  # Ad-hoc package, frozen through the committed .ocx/ snapshot;
  # PULL exports jq_ROOT for find_package/find_library:
  ocx_package(NAME jq PACKAGE ocx.sh/jq:latest PULL)

No ocx installation is required: an ``ocx`` on ``PATH`` is used when
present, otherwise the pinned CLI is bootstrapped on first configure into
a per-machine cache.

Requires CMake 3.19 (``Findocx.cmake`` alone works on 3.15). Script mode
(``cmake -P``) is fully supported.

Updating the vendored files
---------------------------

The vendored pair self-updates in script mode, verified against the
release ``SHA256SUMS``:

.. code-block:: console

   cmake -P cmake/ocx.cmake                                # latest release
   cmake -DOCX_SELF_UPDATE_VERSION=v0.3.0 -P cmake/ocx.cmake
   cmake -DOCX_SELF_UPDATE_VERSION=v0.3.0 \
         -DOCX_SELF_UPDATE_URL=https://mirror.corp/find_ocx \
         -P cmake/ocx.cmake                                # corporate mirror

Two entry points
----------------

``include(ocx)`` — **the provisioner.** The include itself is passive
(definitions only); the first :command:`ocx_project` /
:command:`ocx_package` call resolves the CLI and provisions through it.

``find_package(ocx REQUIRED)`` — **the discoverer.** Classic find module:
honors ``-DOCX_EXECUTABLE``, searches ``PATH``, checks the version via
``find_package_handle_standard_args``, defines the ``ocx::ocx`` imported
target. With ``-DOCX_BOOTSTRAP=ON`` it falls back to the bootstrap when
nothing is found.

Which binary runs — first match wins, identical in both entry points:

1. The ``OCX_EXECUTABLE`` cache variable — set by you, by a previous
   ``find_package(ocx)``, or by an earlier bootstrap. Both entry points
   honor it, so they compose in either order.
2. An ``ocx`` on ``PATH``.
3. The pinned, sha256-verified bootstrap (version:
   ``OCX_INSTALL_VERSION``, default: the embedded pin) — the default
   fallback under ``include(ocx)``, the explicit ``-DOCX_BOOTSTRAP=ON``
   opt-in under ``find_package(ocx)``.

Two policy overrides: ``-DOCX_BOOTSTRAP=ALWAYS`` skips the ``PATH`` step —
every developer and CI runner executes the identical pinned binary
(hermeticity, the rules_ocx model). ``-DOCX_BOOTSTRAP=OFF`` forbids the
implicit download for policy-strict environments: the configure fails
with an actionable error unless step 1 or 2 provides a binary.

Vendoring only ``ocx.cmake`` is fully supported — ``-DOCX_EXECUTABLE`` plus
``-DOCX_BOOTSTRAP=OFF`` is the fully explicit mode. ``Findocx.cmake`` is
the optional classic front door for projects that want ``find_package``
semantics and a system ocx to win.

Index snapshots — reproducible first
------------------------------------

ocx would rather fail than compromise on reproducibility. A floating tag
(``:latest``, ``:3.31``) with no index snapshot in effect and no digest
pin is a hard configure error, not a warning — the escape hatch is the
explicit ``-DOCX_ALLOW_FLOATING=ON`` (useful transiently: the eager
install prints the digests that seed ``PINS``).

The snapshot is a CLI-owned directory of ``<registry>/<repo>.json``
leaves, committed like a lockfile:

.. code-block:: console

   ocx --index .ocx index update ocx.sh/jq ocx.sh/cmake
   git add .ocx

Every :command:`ocx_package` resolves it through a ladder — explicit
``INDEX <dir>``, else the ``OCX_INDEX`` variable, else the nearest
``.ocx/`` directory between the calling directory and the last
``project()`` source dir (a vendored subproject with its own ``project()``
gets its own bound, so snapshots never leak across projects).
``ocx_index(FIND REQUIRED)`` runs that discovery once, fails fast when
nothing is committed, and locks the result into ``OCX_INDEX``.

Snapshots are **never auto-updated**. The refresh is a deliberate act:
``ocx_index(UPDATE_COMMAND <var>)`` composes the command line, the caller
decides how it runs (build target, script, CI job that opens a PR) —
review the diff, commit. The freshness gate is the frozen configure
itself: a tag missing from the snapshot fails with an actionable refresh
hint.

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
Clearing a knob with ``-DVAR=`` actively removes it from the environment
of every ocx invocation.

.. warning::

   **Nested builds inherit the outer resolution mode.** ocx launchers —
   ``ocx run``, frozen ``package exec``, and therefore every
   ``OCX_<NAME>_RUN`` command list this module exports — export
   ``OCX_FROZEN`` and ``OCX_INDEX`` into child processes. A find_ocx
   configure running inside one (ExternalProject, ``ctest
   --build-and-test``, any superbuild) snapshots those values at its
   first configure as if you had set them, and typically fails with the
   exit-81 refresh hint because the outer index does not contain the
   inner project's packages. Pass ``-DOCX_FROZEN= -DOCX_INDEX=`` to such
   nested configures to opt out of the inheritance.

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
